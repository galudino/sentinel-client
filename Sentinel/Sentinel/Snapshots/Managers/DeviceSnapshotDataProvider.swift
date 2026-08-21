//
//  DeviceSnapshotDataProvider.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - DeviceSnapshotDataProvider

/// ``SnapshotDataProvider`` for ``DeviceSnapshot``. Wraps the live connection's
/// ``SnapshotStreamService`` for BLE I/O and extracts derived engineering-unit
/// values by keyPath (matching ``SnapshotFieldConfig`` field catalog).
struct DeviceSnapshotDataProvider: SnapshotDataProvider {
    typealias S = DeviceSnapshot

    /// The live snapshot stream (read on demand for polling; notifications for
    /// streaming). Supplied by the connected peer's `snapshotStream` client.
    let stream: any SnapshotStreamService

    // MARK: Identification / storage keys

    var configurationsStorageKey: String { "SnapshotLoggingConfigurations" }
    var completedSessionsStorageKey: String { "SnapshotLoggingCompletedSessions" }
    var snapshotTypeIdentifier: String { "deviceSnapshot" }
    var sortingPreferencesStorageKey: String { "DeviceSnapshotSortingPreferences" }

    // MARK: BLE operations

    func readSnapshot() async throws -> DeviceSnapshot {
        guard let snapshot = try await stream.readCurrentSnapshot() else {
            throw SnapshotLoggingError.notConnected
        }
        return snapshot
    }

    func setStreaming(_ enabled: Bool) async throws {
        try await stream.setNotifying(enabled)
    }

    func snapshotStream() -> AsyncStream<DeviceSnapshot> {
        stream.snapshotNotifications()
    }

    // MARK: Field extraction

    // swiftlint:disable:next cyclomatic_complexity
    func extractValue(from snapshot: DeviceSnapshot, keyPath: String) -> SnapshotValue {
        switch keyPath {
        // Environment
        case "temperatureCelsius": .float32(Float32(snapshot.temperatureCelsius))
        case "humidityPercent": .float32(Float32(snapshot.humidityPercent))
        case "pressureHectopascals": .float32(Float32(snapshot.pressureHectopascals))
        // Real-Time Clock
        case "rtcTemperatureCelsius": .float32(Float32(snapshot.rtcTemperatureCelsius))
        case "rtcAlarm1Fired": .bool(snapshot.rtcAlarmFlags & 0x01 != 0)
        case "rtcAlarm2Fired": .bool(snapshot.rtcAlarmFlags & 0x02 != 0)
        case "rtcOscillatorStopped": .bool(snapshot.rtcAlarmFlags & 0x80 != 0)
        // Storage
        case "eventLogRecordCount": .uint32(snapshot.eventLogRecordCount)
        case "snapshotLogRecordCount": .uint32(snapshot.snapshotLogRecordCount)
        // Bluetooth
        case "bleConnected": .bool(snapshot.bleConnected)
        case "bleTxPowerDbm": .uint8(snapshot.bleTxPowerDbm)
        case "blePeerRssiDbm": .float32(Float32(snapshot.blePeerRssiDbm))
        // Health
        case "cpuTemperatureCelsius": .float32(Float32(snapshot.cpuTemperatureCelsius))
        case "uptimeSeconds": .uint32(snapshot.uptimeSeconds)
        case "postPassed": .bool(snapshot.postPassed)
        case "postLastStatus": .uint8(snapshot.postLastStatus)
        default: .error("Unknown keyPath: \(keyPath)")
        }
    }
}
