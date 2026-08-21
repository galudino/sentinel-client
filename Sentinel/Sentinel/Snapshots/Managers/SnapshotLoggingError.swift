//
//  SnapshotLoggingError.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - SnapshotLoggingError

nonisolated enum SnapshotLoggingError: LocalizedError {
    case notConnected
    case noEnabledFields
    case sessionNotFound
    case exportFailed
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to a device"
        case .noEnabledFields: "No fields are enabled for logging"
        case .sessionNotFound: "Logging session not found"
        case .exportFailed: "Failed to export logging data"
        case let .importFailed(reason): "Failed to import session: \(reason)"
        }
    }
}
