//
//  ServiceUUIDs.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import CoreBluetooth
import Foundation

// ============================================================================
// PLACEHOLDER UUIDs — finalized in #9 against the firmware #6 GATT contract.
// ----------------------------------------------------------------------------
// These values are deliberately synthetic (the `5E271E10…` base is a marker, not
// a real assigned UUID). They exist so the Phase I service clients compile and so
// the `MockBluetoothTransport` tests can run (the mock keys canned bytes by
// characteristic, so the concrete UUID value is irrelevant to correctness). The
// only place a *real* value matters is against a live device — and that path is
// gated on firmware #6 assigning the GATT contract, then #9 transcribing it here.
//
// Convention (mirrors the firmware, mirrors architecture.md's naming table):
//   <Chip>ServiceUUID          — chip-named sensor services (BME280, DS3231)
//   <Function>ServiceUUID      — aggregate / cross-cutting services
//   <Name>CharacteristicUUID   — the characteristics within each service
// ============================================================================

/// All service-level UUIDs the central scans for / discovers. `allCBUUIDs` is the
/// scan filter (`BluetoothManager.scanForPeripherals`).
enum SentinelServiceUUID {
    nonisolated static var allCBUUIDs: [CBUUID] {
        [
            BME280ServiceUUID.bme280.cbuuid,
            DS3231ServiceUUID.ds3231.cbuuid,
            SystemServiceUUID.system.cbuuid,
            EventLogServiceUUID.eventLog.cbuuid,
            SnapshotStreamServiceUUID.snapshotStream.cbuuid,
            SnapshotHistoryServiceUUID.snapshotHistory.cbuuid,
            OTAServiceUUID.ota.cbuuid,
            DebugStreamServiceUUID.debugStream.cbuuid
        ]
    }
}

// MARK: - Chip-named sensor services

enum BME280ServiceUUID: String {
    case bme280 = "5E271E10-0000-4000-8000-000000000010"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum BME280CharacteristicUUID: String {
    case temperature = "5E271E10-0000-4000-8000-000000000011"
    case humidity = "5E271E10-0000-4000-8000-000000000012"
    case pressure = "5E271E10-0000-4000-8000-000000000013"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum DS3231ServiceUUID: String {
    case ds3231 = "5E271E10-0000-4000-8000-000000000020"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum DS3231CharacteristicUUID: String {
    case time = "5E271E10-0000-4000-8000-000000000021"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

// MARK: - Aggregate / cross-cutting services

enum SystemServiceUUID: String {
    case system = "5E271E10-0000-4000-8000-000000000030"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum SystemCharacteristicUUID: String {
    case firmwareVersion = "5E271E10-0000-4000-8000-000000000031"
    case uptimeSeconds = "5E271E10-0000-4000-8000-000000000032"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum EventLogServiceUUID: String {
    case eventLog = "5E271E10-0000-4000-8000-000000000040"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum EventLogCharacteristicUUID: String {
    case records = "5E271E10-0000-4000-8000-000000000041"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum SnapshotStreamServiceUUID: String {
    case snapshotStream = "5E271E10-0000-4000-8000-000000000050"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum SnapshotStreamCharacteristicUUID: String {
    case snapshot = "5E271E10-0000-4000-8000-000000000051"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum SnapshotHistoryServiceUUID: String {
    case snapshotHistory = "5E271E10-0000-4000-8000-000000000060"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum SnapshotHistoryCharacteristicUUID: String {
    case history = "5E271E10-0000-4000-8000-000000000061"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum OTAServiceUUID: String {
    case ota = "5E271E10-0000-4000-8000-000000000070"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum OTACharacteristicUUID: String {
    case control = "5E271E10-0000-4000-8000-000000000071"
    case data = "5E271E10-0000-4000-8000-000000000072"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum DebugStreamServiceUUID: String {
    case debugStream = "5E271E10-0000-4000-8000-000000000080"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum DebugStreamCharacteristicUUID: String {
    case output = "5E271E10-0000-4000-8000-000000000081"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}
