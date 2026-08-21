//
//  SnapshotLogEntry.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - SnapshotLogEntry

/// One captured sample in a session: the decoded field values plus timing
/// diagnostics about how/when the client obtained it. The device-side capture
/// time is `deviceUnixTimeMs`; the remaining timestamps are client-side and
/// mode-dependent (polling vs. notifications).
nonisolated struct SnapshotLogEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let fieldValues: [SnapshotFieldValue]

    /// Device-side capture time (from the snapshot's `unixTimeMs`).
    let deviceUnixTimeMs: UInt64?

    // MARK: Polling-mode timing diagnostics

    /// When this cycle was scheduled to start.
    let scheduledTick: Date?
    /// When the read actually began.
    let actualStart: Date?
    /// When the read finished.
    let actualFinishRead: Date?
    /// After the post-read sleep.
    let finishCycle: Date?
    /// `actualStart − scheduledTick` (positive = late).
    let latencySeconds: Double?
    /// Duration of the BLE read.
    let readDurationSeconds: Double?
    /// Total cycle time (read + append + overhead).
    let cycleDurationSeconds: Double?

    // MARK: Notification-mode timing diagnostics

    /// Time since the previous notification was received.
    let interNotificationInterval: Double?

    // MARK: Computed timing

    /// Device timestamp as a `Date`.
    var deviceTimestamp: Date? {
        guard let millis = deviceUnixTimeMs else { return nil }
        return Date(timeIntervalSince1970: Double(millis) / 1000.0)
    }

    /// Device-to-read latency (polling): read start − device capture time.
    var deviceToReadLatencySeconds: Double? {
        guard let deviceDate = deviceTimestamp, let start = actualStart else { return nil }
        return start.timeIntervalSince(deviceDate)
    }

    /// Notification latency: notification receipt − device capture time.
    /// In notification mode `actualStart` is the receipt time.
    var notificationLatencySeconds: Double? {
        guard let deviceDate = deviceTimestamp, let received = actualStart else { return nil }
        return received.timeIntervalSince(deviceDate)
    }

    // MARK: Initializers

    /// Standard initializer for a freshly captured entry. `timestamp` is the
    /// creation time of this object, unrelated to `scheduledTick`/`actualStart`.
    init(
        fieldValues: [SnapshotFieldValue],
        deviceUnixTimeMs: UInt64? = nil,
        scheduledTick: Date? = nil,
        actualStart: Date? = nil,
        actualFinishRead: Date? = nil,
        finishCycle: Date? = nil,
        latencySeconds: Double? = nil,
        readDurationSeconds: Double? = nil,
        cycleDurationSeconds: Double? = nil,
        interNotificationInterval: Double? = nil
    ) {
        id = UUID()
        timestamp = Date()
        self.fieldValues = fieldValues
        self.deviceUnixTimeMs = deviceUnixTimeMs
        self.scheduledTick = scheduledTick
        self.actualStart = actualStart
        self.actualFinishRead = actualFinishRead
        self.finishCycle = finishCycle
        self.latencySeconds = latencySeconds
        self.readDurationSeconds = readDurationSeconds
        self.cycleDurationSeconds = cycleDurationSeconds
        self.interNotificationInterval = interNotificationInterval
    }

    /// Full initializer for reconstructing an entry from JSON/binary.
    init(
        id: UUID,
        timestamp: Date,
        fieldValues: [SnapshotFieldValue],
        deviceUnixTimeMs: UInt64? = nil,
        scheduledTick: Date? = nil,
        actualStart: Date? = nil,
        actualFinishRead: Date? = nil,
        finishCycle: Date? = nil,
        latencySeconds: Double? = nil,
        readDurationSeconds: Double? = nil,
        cycleDurationSeconds: Double? = nil,
        interNotificationInterval: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.fieldValues = fieldValues
        self.deviceUnixTimeMs = deviceUnixTimeMs
        self.scheduledTick = scheduledTick
        self.actualStart = actualStart
        self.actualFinishRead = actualFinishRead
        self.finishCycle = finishCycle
        self.latencySeconds = latencySeconds
        self.readDurationSeconds = readDurationSeconds
        self.cycleDurationSeconds = cycleDurationSeconds
        self.interNotificationInterval = interNotificationInterval
    }
}
