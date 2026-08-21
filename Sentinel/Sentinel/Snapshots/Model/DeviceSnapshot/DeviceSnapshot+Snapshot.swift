//
//  DeviceSnapshot+Snapshot.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

// MARK: - DeviceSnapshot + Snapshot

/// Makes ``DeviceSnapshot`` (firmware #36) the Phase I conformer of the generic
/// ``Snapshot`` protocol, so the snapshot-logging subsystem can capture, chart,
/// and export it without any type-specific code.
nonisolated extension DeviceSnapshot: Snapshot {
    typealias Category = DeviceSnapshotCategory

    /// Device capture time in Unix milliseconds. The wire record carries seconds
    /// (`unixTimestamp`); the logging subsystem works in milliseconds.
    var unixTimeMs: UInt64 { UInt64(unixTimestamp) * 1000 }

    // MARK: Display metadata

    static var displayName: String { "Device Snapshot" }
    static var shortName: String { "Device" }
    static var emptyStateIconName: String { "square.stack.3d.down.right.fill" }
    static var exportFilePrefix: String { "device_snapshot" }

    static var pollingIntervalDescription: String {
        "How often to read the device snapshot from the device."
    }

    static var noConfigurationsText: String {
        "Create a configuration to start logging device-snapshot data."
    }

    static var noCompletedSessionsText: String {
        "Completed logging sessions will appear here."
    }

    static var createConfigurationPrompt: String {
        "Create and manage configurations to define which fields to log."
    }

    static var captureNavigationTitle: String { "Device Snapshot Capture" }

    static func chartRoute(for session: SnapshotLoggingSession) -> SnapshotRoute {
        .deviceSnapshotSessionChart(session: session)
    }

    static func availableFields() -> [SnapshotFieldConfig<DeviceSnapshot>] {
        SnapshotFieldConfig<DeviceSnapshot>.availableFields()
    }
}
