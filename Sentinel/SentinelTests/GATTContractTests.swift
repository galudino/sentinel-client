//
//  GATTContractTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/17/26.
//

import CoreBluetooth
import Testing

@testable import Sentinel

/// The client-side half of the #9 contract check: the client UUID constants are
/// pinned to the values firmware #6 assigned (transcribed from
/// `sentinel-firmware/Sentinel/src/GeneratedSource/cycfg_gatt_db.h`). If a
/// firmware characteristic changes or is added, mirroring it here is what makes
/// this test pass again — so drift fails loudly.
@MainActor
struct GATTContractTests {
    @Test func everyPhaseIServiceIsListedWithFirmwareUUID() {
        let expected: [SentinelServiceUUID: String] = [
            .bme280: "5C3F249D-1AB4-423A-9DA7-2CD67E526C45",
            .ds3231: "3E28CA68-D66B-4FF1-ADA0-79225F3076F2",
            .system: "11A3488D-B5D5-4145-A322-8EC8E819F166",
            .snapshotStream: "8935D83C-FAE8-439E-ADCF-F38B67AF7F55",
            .snapshotHistory: "55E2C813-F552-40CB-BB26-4694451DBD0A",
            .systemEventLog: "09A79D7A-7C5A-4D0D-AB42-BEEFA1ABA947",
            .ota: "AE5D1E47-5C13-43A0-8635-82AD38A1381F",
            .debugStream: "6847AEEA-E7F5-42DE-8DAF-10D7FB344EF7"
        ]
        // Every case is pinned, and nothing was added without a pin.
        #expect(Set(SentinelServiceUUID.allCases) == Set(expected.keys))
        for (service, uuid) in expected {
            #expect(service.rawValue == uuid)
            #expect(service.cbuuid == CBUUID(string: uuid))
        }
        #expect(SentinelServiceUUID.cbuuids.count == 8)
    }

    @Test func characteristicUUIDsMatchFirmware() {
        #expect(BME280CharacteristicUUID.ambientSample.rawValue == "11AC7ECD-3752-4300-A600-7790721AD4C5")

        #expect(DS3231CharacteristicUUID.unixTime.rawValue == "2021C969-6F28-4A17-9347-ABEE83337EE1")
        #expect(DS3231CharacteristicUUID.rtcTemperature.rawValue == "64E51871-745E-42ED-A382-33D670F16ED1")
        #expect(DS3231CharacteristicUUID.alarmFlags.rawValue == "BD627112-6AF2-40CF-9C9C-AA0BFD3E7003")

        #expect(SystemCharacteristicUUID.serialNumber.rawValue == "49666C6D-2A24-4978-B4E5-A3C3D5B18B93")
        #expect(SystemCharacteristicUUID.firmwareVersion.rawValue == "D4EE3C16-5EEC-469E-910A-51C95C9DFE83")
        #expect(SystemCharacteristicUUID.requestBootloaderMode.rawValue == "9EA19980-36C2-49CD-A348-CCD803820915")
        #expect(SystemCharacteristicUUID.platformID.rawValue == "EC5DBBC3-B5D1-40D3-8022-D4531CDD227C")
        #expect(SystemCharacteristicUUID.cpuTemperature.rawValue == "098FA125-5909-4442-B691-7041807581D0")
        #expect(SystemCharacteristicUUID.deviceReadiness.rawValue == "D3E542A5-3476-4A48-B4F5-1D0D0699DB28")

        #expect(
            SnapshotStreamCharacteristicUUID.currentDeviceSnapshot
                .rawValue == "B1D01D8B-32EB-491B-943D-E24C2527FCA0"
        )
        #expect(SnapshotHistoryCharacteristicUUID.recordBlock.rawValue == "4B85F62B-EDAA-48B1-B7D7-70067B6B2D3E")
        #expect(SystemEventLogCharacteristicUUID.recordBlock.rawValue == "ECD7927C-6DB4-4FD2-A8AE-DE104DB0BAA2")

        #expect(OTACharacteristicUUID.controlPoint.rawValue == "A3DD50BF-F7A7-4E99-838E-570A086C661B")
        #expect(OTACharacteristicUUID.data.rawValue == "A2E86C7A-D961-4091-B74F-2409E72EFE26")

        #expect(DebugStreamCharacteristicUUID.outputStream.rawValue == "83F4C70C-D09E-4C0C-8835-3B8CFA2202D9")
    }

    @Test func deviceInformationUsesStandardSIGShortUUIDs() {
        #expect(StandardServiceUUID.deviceInformation.cbuuid == CBUUID(string: "180A"))
        #expect(DeviceInformationCharacteristicUUID.manufacturerName.cbuuid == CBUUID(string: "2A29"))
        #expect(DeviceInformationCharacteristicUUID.pnpID.cbuuid == CBUUID(string: "2A50"))
    }

    @Test func platformIDMirrorsFirmwareEnum() {
        #expect(PlatformID.unknown.rawValue == 0x00)
        #expect(PlatformID.cyble416045.rawValue == 0x01)
        #expect(PlatformID.rpi5.rawValue == 0x02)
        #expect(PlatformID.nrf5340.rawValue == 0x03)
        #expect(PlatformID.cyble416045.vendor == .infineon)
    }
}
