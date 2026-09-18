//
//  DeviceSnapshotCategory.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

// MARK: - DeviceSnapshotCategory

/// Field groupings for ``DeviceSnapshot``, mirroring the firmware record's
/// subsystem sections (environment, RTC, storage, BLE, health).
nonisolated enum DeviceSnapshotCategory: String, SnapshotCategory {
    case environment = "Environment"
    case rtc = "Real-Time Clock"
    case storage = "Storage"
    case bluetooth = "Bluetooth"
    case health = "Health"

    nonisolated var id: Self { self }
    nonisolated var displayName: String { rawValue }
}
