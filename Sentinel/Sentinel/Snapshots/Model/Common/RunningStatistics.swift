//
//  RunningStatistics.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - RunningStatistics

/// O(1) running statistics accumulator — count, sum, min, max without retaining
/// individual values. Lets live and completed session views show avg/min/max
/// timing without an O(n) pass over every entry.
nonisolated struct RunningStatistics: Hashable {
    private(set) var count: Int = 0
    private(set) var sum: Double = 0
    private(set) var min: Double?
    private(set) var max: Double?

    // swiftlint:disable:next empty_count
    var isEmpty: Bool { count == 0 }

    var avg: Double { !isEmpty ? sum / Double(count) : 0 }

    /// Add a value. Non-finite values are ignored to keep JSON encoding safe.
    mutating func add(_ value: Double) {
        guard value.isFinite else { return }
        min = min.map { Swift.min($0, value) } ?? value
        max = max.map { Swift.max($0, value) } ?? value
        sum += value
        count += 1
    }

    mutating func reset() {
        count = 0
        sum = 0
        min = nil
        max = nil
    }
}

// MARK: - Codable (sanitizing non-finite values)

nonisolated extension RunningStatistics: Codable {
    private enum CodingKeys: String, CodingKey {
        case count, sum, min, max
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decode(Int.self, forKey: .count)
        sum = try container.decode(Double.self, forKey: .sum)
        min = try container.decodeIfPresent(Double.self, forKey: .min)
        max = try container.decodeIfPresent(Double.self, forKey: .max)

        if let value = min, !value.isFinite { min = nil }
        if let value = max, !value.isFinite { max = nil }
        if !sum.isFinite { sum = 0 }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(count, forKey: .count)
        try container.encode(sum.isFinite ? sum : 0, forKey: .sum)

        if let value = min, value.isFinite {
            try container.encode(value, forKey: .min)
        } else {
            try container.encodeNil(forKey: .min)
        }
        if let value = max, value.isFinite {
            try container.encode(value, forKey: .max)
        } else {
            try container.encodeNil(forKey: .max)
        }
    }
}

// MARK: - SessionRunningAggregates

/// Running aggregates for every timing metric of a session, maintained O(1) per
/// entry during capture and persisted in the session index for completed
/// sessions.
nonisolated struct SessionRunningAggregates: Codable, Hashable {
    // MARK: Device timestamp period

    var deviceTimestampPeriod = RunningStatistics()
    var lastDeviceTimestampMs: UInt64?

    // MARK: Polling-mode metrics

    var bleReadDuration = RunningStatistics()
    var scheduleToReadLatency = RunningStatistics()
    var deviceToReadLatency = RunningStatistics()
    var cycleDuration = RunningStatistics()

    // MARK: Notification-mode metrics

    var notificationLatency = RunningStatistics()
    var notificationPeriod = RunningStatistics()

    // MARK: Flags

    var readEverExceededInterval = false
    var totalEntryCount = 0

    /// Fold a new entry into the aggregates.
    mutating func update(with entry: SnapshotLogEntry, pollingInterval: TimeInterval? = nil) {
        totalEntryCount += 1

        if let currentMs = entry.deviceUnixTimeMs {
            if let prevMs = lastDeviceTimestampMs {
                let difference = Int64(bitPattern: currentMs) - Int64(bitPattern: prevMs)
                deviceTimestampPeriod.add(Double(difference) / 1000.0)
            }
            lastDeviceTimestampMs = currentMs
        }

        if let readDuration = entry.readDurationSeconds {
            bleReadDuration.add(readDuration)
            if let interval = pollingInterval, readDuration > interval {
                readEverExceededInterval = true
            }
        }
        if let latency = entry.latencySeconds { scheduleToReadLatency.add(latency) }
        if let deviceLatency = entry.deviceToReadLatencySeconds { deviceToReadLatency.add(deviceLatency) }
        if let cycle = entry.cycleDurationSeconds { cycleDuration.add(cycle) }

        if let notifLatency = entry.notificationLatencySeconds { notificationLatency.add(notifLatency) }
        if let notifPeriod = entry.interNotificationInterval { notificationPeriod.add(notifPeriod) }
    }
}
