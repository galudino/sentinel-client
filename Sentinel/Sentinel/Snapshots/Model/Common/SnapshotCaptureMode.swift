//
//  SnapshotCaptureMode.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

// MARK: - SnapshotCaptureMode

/// How a logging session pulls snapshots off the device.
nonisolated enum SnapshotCaptureMode: String, Codable, CaseIterable, Identifiable {
    /// The client reads the snapshot characteristic at a fixed interval.
    case polling
    /// The device pushes snapshots to the client over BLE notifications.
    case notifications

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .polling: "Polling"
        case .notifications: "Notifications"
        }
    }

    var description: String {
        switch self {
        case .polling: "Client reads the snapshot characteristic at a fixed interval"
        case .notifications: "Device pushes snapshots to the client over BLE notifications"
        }
    }

    var systemImageName: String {
        switch self {
        case .polling: "arrow.clockwise.circle"
        case .notifications: "bell.badge"
        }
    }
}
