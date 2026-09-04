//
//  SnapshotTimingStats.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - Timing stat value models

/// Formatted polling-mode timing statistics for a session's live/summary view.
/// Every value is a preformatted millisecond string ("-" when unavailable).
struct SnapshotPollingTimingStats {
    let lastDevicePeriod, avgDevicePeriod, minDevicePeriod, maxDevicePeriod: String
    let lastReadDuration, avgReadDuration, minReadDuration, maxReadDuration: String
    let lastScheduleLatency, avgScheduleLatency, minScheduleLatency, maxScheduleLatency: String
    let lastDeviceLatency, avgDeviceLatency, minDeviceLatency, maxDeviceLatency: String
    let lastCycleDuration, avgCycleDuration, minCycleDuration, maxCycleDuration: String
}

/// Formatted notification-mode timing statistics for a session's live/summary view.
struct SnapshotNotificationTimingStats {
    let lastDevicePeriod, avgDevicePeriod, minDevicePeriod, maxDevicePeriod: String
    let lastNotificationLatency, avgNotificationLatency, minNotificationLatency, maxNotificationLatency: String
    let lastNotificationPeriod, avgNotificationPeriod, minNotificationPeriod, maxNotificationPeriod: String
}

/// One row in a timing-metrics table (label + last/avg/max or avg/min/max columns).
struct TimingMetricRow: Identifiable {
    let label: String
    let columns: [String]
    var id: String { label }
}

// MARK: - Helpers

/// Format a seconds value as a millisecond string, or "-" when absent.
func formatAsMilliseconds(_ seconds: Double?) -> String {
    guard let seconds else { return "-" }
    return String(format: "%.3f", seconds * 1000.0)
}

/// The gaps (in seconds) between consecutive device timestamps across `entries`.
func calculateDeviceTimestampPeriods(from entries: [SnapshotLogEntry]) -> [Double] {
    var periods: [Double] = []
    var previous: UInt64?
    for entry in entries {
        if let current = entry.deviceUnixTimeMs {
            if let previous {
                periods.append((Double(current) - Double(previous)) / 1000.0)
            }
            previous = current
        }
    }
    return periods
}

/// Mean of a non-empty sequence, or `nil` for an empty one.
func mean(_ values: [Double]) -> Double? {
    values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
}
