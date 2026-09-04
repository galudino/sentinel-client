//
//  SnapshotLoggingStatus.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

// MARK: - SnapshotLoggingStatus

/// Lifecycle state of a ``SnapshotLoggingSession``.
nonisolated enum SnapshotLoggingStatus: String, Codable, CaseIterable {
    case pending
    case running
    case stopped
    case completed
    case error

    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .running: "Running"
        case .stopped: "Stopped"
        case .completed: "Completed"
        case .error: "Error"
        }
    }

    var systemImageName: String {
        switch self {
        case .pending: "clock"
        case .running: "play.circle.fill"
        case .stopped: "stop.circle"
        case .completed: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    // MARK: - Binary Format Support

    /// Tag byte used in the `.sentinelsession` binary format.
    var binaryTag: UInt8 {
        switch self {
        case .pending: 0
        case .running: 1
        case .stopped: 2
        case .completed: 3
        case .error: 4
        }
    }

    /// Reconstruct a `SnapshotLoggingStatus` from a binary tag byte.
    static func fromBinaryTag(_ tag: UInt8) -> SnapshotLoggingStatus {
        switch tag {
        case 0: .pending
        case 1: .running
        case 2: .stopped
        case 3: .completed
        case 4: .error
        default: .error
        }
    }
}
