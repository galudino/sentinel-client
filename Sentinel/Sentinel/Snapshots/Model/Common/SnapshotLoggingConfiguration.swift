//
//  SnapshotLoggingConfiguration.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - SnapshotLoggingConfiguration

/// A named, reusable capture recipe: which fields of snapshot type `S` to log, at
/// what cadence, in which ``SnapshotCaptureMode``. Persisted (small) in
/// UserDefaults by ``SnapshotLoggingManager``.
nonisolated struct SnapshotLoggingConfiguration<S: Snapshot>: Codable, Identifiable {
    let id: UUID
    var name: String
    var selectedFields: [SnapshotFieldConfig<S>]
    /// Interval between reads, in seconds — only meaningful in `.polling` mode.
    var pollingInterval: TimeInterval
    var captureMode: SnapshotCaptureMode
    var createdAt: Date
    var modifiedAt: Date

    init(
        name: String,
        selectedFields: [SnapshotFieldConfig<S>] = [],
        pollingInterval: TimeInterval = 0.1,
        captureMode: SnapshotCaptureMode = .polling
    ) {
        id = UUID()
        self.name = name
        self.selectedFields = selectedFields
        self.pollingInterval = pollingInterval
        self.captureMode = captureMode
        createdAt = Date()
        modifiedAt = Date()
    }

    mutating func updateModifiedDate() {
        modifiedAt = Date()
    }

    var enabledFields: [SnapshotFieldConfig<S>] {
        selectedFields.filter(\.isEnabled)
    }
}
