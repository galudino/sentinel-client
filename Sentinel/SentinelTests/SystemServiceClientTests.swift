//
//  SystemServiceClientTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation
import Testing

@testable import Sentinel

/// Testing strategy #1: mock the transport, exercise the *real* client. Catches
/// byte-format bugs in the reference `SystemService` trio, now against the real
/// GATT contract (#9): serial (UInt32), firmware version (5-byte packed), platform
/// id (UInt8 → enum), CPU temperature (UInt16).
@MainActor
struct SystemServiceClientTests {
    @Test func readsSystemCharacteristicsFromCannedBytes() async throws {
        let transport = MockBluetoothTransport()
        transport.setReadValue(UInt32(0x0000_ABCD), for: SystemCharacteristicUUID.serialNumber.cbuuid)
        transport.setReadValue(
            FirmwareVersion(major: 1, minor: 4, patch: 2, build: 1801),
            for: SystemCharacteristicUUID.firmwareVersion.cbuuid
        )
        transport.setReadValue(PlatformID.cyble416045.rawValue, for: SystemCharacteristicUUID.platformID.cbuuid)
        transport.setReadValue(UInt16(4200), for: SystemCharacteristicUUID.cpuTemperature.cbuuid)

        let system = SystemServiceClient(transport: transport)

        #expect(try await system.readSerialNumber() == 0x0000_ABCD)
        #expect(try await system.readFirmwareVersion() == FirmwareVersion(major: 1, minor: 4, patch: 2, build: 1801))
        #expect(try await system.readPlatformID() == .cyble416045)
        #expect(try await system.readCPUTemperature() == 4200)
    }

    @Test func firmwareVersionDecodesFromPacked5ByteWire() {
        // major=1, minor=4, patch=2, build=0x0709 (1801) little-endian.
        let wire = Data([0x01, 0x04, 0x02, 0x09, 0x07])
        let decoded = FirmwareVersion.fromData(wire)
        #expect(decoded == FirmwareVersion(major: 1, minor: 4, patch: 2, build: 1801))
        #expect(decoded?.description == "1.4.2.1801")
        #expect(decoded?.toData() == wire)
    }

    @Test func requestBootloaderModeWritesToTheRightCharacteristic() async throws {
        let transport = MockBluetoothTransport()
        try await SystemServiceClient(transport: transport).requestBootloaderMode()
        #expect(transport.writes.count == 1)
        #expect(transport.writes.first?.characteristic == SystemCharacteristicUUID.requestBootloaderMode.cbuuid)
    }

    @Test func mockServiceStandsInForPreviews() async throws {
        let mock = MockSystemService(platformID: .rpi5)
        #expect(try await mock.readPlatformID() == .rpi5)
        #expect(try await mock.readPlatformID().modelName == "Raspberry Pi 5")
    }
}
