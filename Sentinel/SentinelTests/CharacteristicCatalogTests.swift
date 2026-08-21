//
//  CharacteristicCatalogTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/19/26.
//

import CoreBluetooth
import Foundation
import Testing

@testable import Sentinel

/// The GATT Explorer (#18) is catalog-driven, so the catalog must stay in lockstep
/// with the #9 characteristic contract. These tests fail the build if a
/// characteristic is added to ``GATTContract`` without a ``CharacteristicCatalog``
/// descriptor (or vice-versa), and spot-check the utilitarian decoder.
@MainActor
struct CharacteristicCatalogTests {
    /// Every characteristic UUID enum case, paired with the service it belongs to.
    private static let allContractCharacteristics: [(SentinelServiceUUID, CBUUID)] =
        BME280CharacteristicUUID.allCases.map { (.bme280, $0.cbuuid) }
            + DS3231CharacteristicUUID.allCases.map { (.ds3231, $0.cbuuid) }
            + SystemCharacteristicUUID.allCases.map { (.system, $0.cbuuid) }
            + SnapshotStreamCharacteristicUUID.allCases.map { (.snapshotStream, $0.cbuuid) }
            + SnapshotHistoryCharacteristicUUID.allCases.map { (.snapshotHistory, $0.cbuuid) }
            + SystemEventLogCharacteristicUUID.allCases.map { (.systemEventLog, $0.cbuuid) }
            + OTACharacteristicUUID.allCases.map { (.ota, $0.cbuuid) }
            + DebugStreamCharacteristicUUID.allCases.map { (.debugStream, $0.cbuuid) }

    @Test func everyContractCharacteristicHasADescriptor() {
        for (service, cbuuid) in Self.allContractCharacteristics {
            let descriptor = CharacteristicCatalog.descriptor(for: cbuuid)
            #expect(descriptor != nil, "Missing catalog descriptor for \(service.displayName) \(cbuuid)")
            #expect(descriptor?.service == service)
        }
    }

    @Test func noOrphanOrDuplicateDescriptors() {
        let contractUUIDs = Set(Self.allContractCharacteristics.map(\.1))
        let catalogUUIDs = CharacteristicCatalog.all.map(\.characteristicCBUUID)

        // No descriptor points at a characteristic outside the contract.
        for uuid in catalogUUIDs {
            #expect(contractUUIDs.contains(uuid), "Orphan catalog descriptor for \(uuid)")
        }
        // One descriptor per characteristic — and the counts line up exactly.
        #expect(Set(catalogUUIDs).count == catalogUUIDs.count, "Duplicate catalog descriptor")
        #expect(catalogUUIDs.count == contractUUIDs.count)
    }

    @Test func everyServiceIsRepresented() {
        for service in SentinelServiceUUID.allCases {
            #expect(
                !CharacteristicCatalog.descriptors(for: service).isEmpty,
                "\(service.displayName) has no characteristics in the catalog"
            )
        }
    }

    // MARK: - Decoder spot-checks

    @Test func decodesScaledSignedTemperature() {
        // 0.01 °C / LSB, signed. 2537 → 25.37 °C.
        let data = withUnsafeBytes(of: Int16(2537).littleEndian) { Data($0) }
        let interpreted = GATTDataType.int16.interpreted(data, lsbUnit: "0.01 °C")
        #expect(interpreted.contains("25.37"))
        #expect(interpreted.contains("°C"))
    }

    @Test func decodesNegativeTemperature() {
        let data = withUnsafeBytes(of: Int16(-512).littleEndian) { Data($0) }
        let interpreted = GATTDataType.int16.interpreted(data, lsbUnit: "0.01 °C")
        #expect(interpreted.contains("-5.12"))
        #expect(GATTDataType.int16.signedScalar(data) == -512)
    }

    @Test func decodesUnsignedScalarForFormatForms() {
        let data = withUnsafeBytes(of: UInt32(0x0000_ABCD).littleEndian) { Data($0) }
        #expect(GATTDataType.uint32.unsignedScalar(data) == 0xABCD)
        #expect(GATTByteFormat.hex.renderInteger(0xABCD) == "0xABCD")
        #expect(GATTByteFormat.dec.renderInteger(0xABCD) == "43981")
        #expect(GATTByteFormat.oct.renderInteger(0xABCD) == "0o125715")
    }

    @Test func decodesPlatformID() {
        let data = Data([PlatformID.cyble416045.rawValue])
        let interpreted = GATTDataType.platformID.interpreted(data, lsbUnit: nil)
        #expect(interpreted.contains("CYBLE-416045"))
    }

    @Test func rendersBytesInEachFormat() {
        let data = Data([0xAB, 0xCD])
        #expect(GATTByteFormat.hex.renderBytes(data) == "AB CD")
        #expect(GATTByteFormat.dec.renderBytes(data) == "171 205")
        #expect(GATTByteFormat.raw.renderBytes(data) == "ABCD")
    }

    @Test func parsesScaledUnitHint() {
        let (scale, unit) = GATTDataType.parseUnit("0.01 °C")
        #expect(scale == 0.01)
        #expect(unit == "°C")
        let (plainScale, plainUnit) = GATTDataType.parseUnit("s")
        #expect(plainScale == 1)
        #expect(plainUnit == "s")
    }
}
