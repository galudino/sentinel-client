//
//  SnapshotActiveSessionRowView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - SnapshotActiveSessionRowView

/// A running session's row: status, elapsed time, entry count, live capture-timing
/// metrics (last / avg / max), a progress bar for fixed-duration sessions, and a
/// Stop control.
struct SnapshotActiveSessionRowView<Provider: SnapshotDataProvider>: View {
    let session: SnapshotLoggingSession
    @Environment(SnapshotLoggingManager<Provider>.self) private var loggingManager

    private static var pollingColumns: [String] { ["last (ms)", "avg (ms)", "max (ms)"] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.name).font(.headline)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: session.status.systemImageName)
                            .foregroundStyle(session.status == .running ? Color.green : .orange)
                        Text(session.status.displayName).font(.caption)
                    }
                    labeledCaption("Started:", SessionFormat.timestamp(session.startTime))
                    if let maxDuration = session.maxDuration {
                        labeledCaption(
                            "Ending:",
                            SessionFormat.timestamp(Date(timeInterval: maxDuration, since: session.startTime))
                        )
                    }
                }

                Spacer()

                Button("Stop") { loggingManager.stopLoggingSession(session.id) }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Duration: \(SessionFormat.clockWithMillis(session.actualDuration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(session.entryCount) entries").font(.caption).foregroundStyle(.secondary)
            }

            SessionModeChip(session: session)

            if session.captureMode == .polling {
                pollingTimingSection
            } else {
                notificationTimingSection
            }

            if let maxDuration = session.maxDuration {
                ProgressView(value: min(session.actualDuration, maxDuration), total: maxDuration)
            }
        }
        .padding(.vertical, 4)
    }

    private func labeledCaption(_ label: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(label).frame(width: 60, alignment: .leading)
            Text(value)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: Timing sections

    @ViewBuilder private var pollingTimingSection: some View {
        if let stats = pollingTimingStats(last: 10) {
            let exceeded = readEverExceededInterval
            VStack(alignment: .leading, spacing: 4) {
                timingHeader
                if exceeded { exceededWarning }
                TimingMetricsTable(
                    columnHeaders: Self.pollingColumns,
                    rows: [row(
                        "Device Timestamp Period",
                        stats.lastDevicePeriod,
                        stats.avgDevicePeriod,
                        stats.maxDevicePeriod
                    )]
                )
                Divider().padding(.vertical, 2)
                TimingMetricsTable(
                    columnHeaders: Self.pollingColumns,
                    rows: [
                        row("BLE Read Duration", stats.lastReadDuration, stats.avgReadDuration, stats.maxReadDuration),
                        row(
                            "Schedule-to-Read Latency",
                            stats.lastScheduleLatency,
                            stats.avgScheduleLatency,
                            stats.maxScheduleLatency
                        ),
                        row(
                            "Device-to-Read Latency",
                            stats.lastDeviceLatency,
                            stats.avgDeviceLatency,
                            stats.maxDeviceLatency
                        ),
                        row("Cycle Duration", stats.lastCycleDuration, stats.avgCycleDuration, stats.maxCycleDuration)
                    ],
                    highlightRow: exceeded ? "BLE Read Duration" : nil,
                    showHeader: false
                )
            }
        }
    }

    @ViewBuilder private var notificationTimingSection: some View {
        if let stats = notificationTimingStats(last: 10) {
            let selected = session.selectedTimingFieldIds
            VStack(alignment: .leading, spacing: 4) {
                timingHeader
                if selected.contains("deviceTimestampPeriod") {
                    TimingMetricsTable(
                        columnHeaders: Self.pollingColumns,
                        rows: [row(
                            "Device Timestamp Period",
                            stats.lastDevicePeriod,
                            stats.avgDevicePeriod,
                            stats.maxDevicePeriod
                        )]
                    )
                    Divider().padding(.vertical, 2)
                }
                let rows = notificationRows(stats: stats, selected: selected)
                if !rows.isEmpty {
                    TimingMetricsTable(columnHeaders: Self.pollingColumns, rows: rows, showHeader: false)
                }
            }
        }
    }

    private var timingHeader: some View {
        Text("Timing Metrics")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    private var exceededWarning: some View {
        let intervalMs = String(format: "%.0f", session.pollingInterval * 1000)
        return HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).font(.caption2)
            Text("BLE read exceeded \(intervalMs) ms interval").font(.caption2).foregroundStyle(.orange)
        }
    }

    private func row(_ label: String, _ last: String, _ avg: String, _ max: String) -> TimingMetricRow {
        TimingMetricRow(label: label, columns: [last, avg, max])
    }

    private func notificationRows(
        stats: SnapshotNotificationTimingStats,
        selected: Set<String>
    ) -> [TimingMetricRow] {
        var rows: [TimingMetricRow] = []
        if selected.contains("notificationLatency") {
            rows.append(row(
                "Notification Latency",
                stats.lastNotificationLatency, stats.avgNotificationLatency, stats.maxNotificationLatency
            ))
        }
        if selected.contains("notificationPeriod") {
            rows.append(row(
                "Notification Period",
                stats.lastNotificationPeriod, stats.avgNotificationPeriod, stats.maxNotificationPeriod
            ))
        }
        return rows
    }
}

// MARK: - Live timing computation

extension SnapshotActiveSessionRowView {
    private var readEverExceededInterval: Bool {
        session.logEntries.contains { ($0.readDurationSeconds ?? 0) > session.pollingInterval }
    }

    private func pollingTimingStats(last count: Int) -> SnapshotPollingTimingStats? {
        let all = session.logEntries
        let recent = Array(all.suffix(count))
        guard !recent.isEmpty else { return nil }

        let allPeriods = calculateDeviceTimestampPeriods(from: all)
        let recentPeriods = calculateDeviceTimestampPeriods(from: recent)
        let recentReads = recent.compactMap(\.readDurationSeconds)
        let allReads = all.compactMap(\.readDurationSeconds)
        let recentSched = recent.compactMap(\.latencySeconds)
        let allSched = all.compactMap(\.latencySeconds)
        let recentDeviceLat = recent.compactMap(\.deviceToReadLatencySeconds)
        let allDeviceLat = all.compactMap(\.deviceToReadLatencySeconds)
        let recentCycles = recent.compactMap(\.cycleDurationSeconds)
        let allCycles = all.compactMap(\.cycleDurationSeconds)

        return SnapshotPollingTimingStats(
            lastDevicePeriod: formatAsMilliseconds(allPeriods.last),
            avgDevicePeriod: formatAsMilliseconds(mean(recentPeriods)),
            minDevicePeriod: formatAsMilliseconds(allPeriods.min()),
            maxDevicePeriod: formatAsMilliseconds(allPeriods.max()),
            lastReadDuration: formatAsMilliseconds(recent.last?.readDurationSeconds),
            avgReadDuration: formatAsMilliseconds(mean(recentReads)),
            minReadDuration: formatAsMilliseconds(allReads.min()),
            maxReadDuration: formatAsMilliseconds(allReads.max()),
            lastScheduleLatency: formatAsMilliseconds(recent.last?.latencySeconds),
            avgScheduleLatency: formatAsMilliseconds(mean(recentSched)),
            minScheduleLatency: formatAsMilliseconds(allSched.min()),
            maxScheduleLatency: formatAsMilliseconds(allSched.max()),
            lastDeviceLatency: formatAsMilliseconds(recent.last?.deviceToReadLatencySeconds),
            avgDeviceLatency: formatAsMilliseconds(mean(recentDeviceLat)),
            minDeviceLatency: formatAsMilliseconds(allDeviceLat.min()),
            maxDeviceLatency: formatAsMilliseconds(allDeviceLat.max()),
            lastCycleDuration: formatAsMilliseconds(recent.last?.cycleDurationSeconds),
            avgCycleDuration: formatAsMilliseconds(mean(recentCycles)),
            minCycleDuration: formatAsMilliseconds(allCycles.min()),
            maxCycleDuration: formatAsMilliseconds(allCycles.max())
        )
    }

    private func notificationTimingStats(last count: Int) -> SnapshotNotificationTimingStats? {
        let all = session.logEntries
        let recent = Array(all.suffix(count))
        guard !recent.isEmpty else { return nil }

        let allPeriods = calculateDeviceTimestampPeriods(from: all)
        let recentPeriods = calculateDeviceTimestampPeriods(from: recent)
        let recentNotifLat = recent.compactMap(\.notificationLatencySeconds)
        let allNotifLat = all.compactMap(\.notificationLatencySeconds)
        let recentNotifPeriod = recent.compactMap(\.interNotificationInterval)
        let allNotifPeriod = all.compactMap(\.interNotificationInterval)

        return SnapshotNotificationTimingStats(
            lastDevicePeriod: formatAsMilliseconds(allPeriods.last),
            avgDevicePeriod: formatAsMilliseconds(mean(recentPeriods)),
            minDevicePeriod: formatAsMilliseconds(allPeriods.min()),
            maxDevicePeriod: formatAsMilliseconds(allPeriods.max()),
            lastNotificationLatency: formatAsMilliseconds(recent.last?.notificationLatencySeconds),
            avgNotificationLatency: formatAsMilliseconds(mean(recentNotifLat)),
            minNotificationLatency: formatAsMilliseconds(allNotifLat.min()),
            maxNotificationLatency: formatAsMilliseconds(allNotifLat.max()),
            lastNotificationPeriod: formatAsMilliseconds(recent.last?.interNotificationInterval),
            avgNotificationPeriod: formatAsMilliseconds(mean(recentNotifPeriod)),
            minNotificationPeriod: formatAsMilliseconds(allNotifPeriod.min()),
            maxNotificationPeriod: formatAsMilliseconds(allNotifPeriod.max())
        )
    }
}
