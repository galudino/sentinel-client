//
//  SnapshotCompletedSessionRowView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - SnapshotCompletedSessionRowView

/// A completed session's row: summary, capture-timing metrics (avg / min / max,
/// from the loaded entries or the persisted aggregates), and actions to open the
/// chart, rename, or export.
struct SnapshotCompletedSessionRowView<Provider: SnapshotDataProvider>: View {
    // swiftlint:disable:next type_name
    typealias S = Provider.S

    let session: SnapshotLoggingSession
    @Environment(SnapshotLoggingManager<Provider>.self) private var loggingManager

    @State private var showingExportSheet = false
    @State private var showingRenameSheet = false
    @State private var loadedSession: SnapshotLoggingSession?
    @State private var isLoadingEntries = false
    @State private var loadError: String?

    private static var columns: [String] { ["avg (ms)", "min (ms)", "max (ms)"] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.name).font(.headline).lineLimit(1).truncationMode(.tail)

            HStack(alignment: .top) {
                timestampsView
                Spacer()
                actionButtons
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
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingExportSheet) {
            if let loaded = loadedSession {
                SnapshotExportSessionView<Provider>(session: loaded)
            }
        }
        .sheet(isPresented: $showingRenameSheet) {
            SnapshotRenameSessionView<Provider>(session: session).presentationDetents([.medium])
        }
        .alert("Load Error", isPresented: .constant(loadError != nil)) {
            Button("OK") { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button { showingRenameSheet = true } label: { Image(systemName: "pencil") }
                .buttonStyle(.bordered)

            NavigationLink(value: S.chartRoute(for: session)) {
                Image(systemName: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.bordered)

            Button(action: loadEntriesAndExport) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Export")
            .disabled(isLoadingEntries)
        }
    }

    private var timestampsView: some View {
        VStack(alignment: .leading, spacing: 2) {
            labeledCaption("Started:", SessionFormat.timestamp(session.startTime))
            if let endTime = session.endTime {
                labeledCaption("Ended:", SessionFormat.timestamp(endTime))
            }
        }
    }

    private func labeledCaption(_ label: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(label).frame(width: 60, alignment: .leading)
            Text(value)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func loadEntriesAndExport() {
        isLoadingEntries = true
        Task {
            do {
                loadedSession = try await loggingManager.loadSessionWithEntries(session.id)
                isLoadingEntries = false
                showingExportSheet = true
            } catch {
                loadError = "Failed to load session entries: \(error.localizedDescription)"
                isLoadingEntries = false
            }
        }
    }

    // MARK: Timing sections

    @ViewBuilder private var pollingTimingSection: some View {
        let rows = pollingRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                timingHeader
                if readEverExceededInterval { exceededWarning }
                TimingMetricsTable(columnHeaders: Self.columns, rows: [rows[0]])
                if rows.count > 1 {
                    Divider().padding(.vertical, 2)
                    TimingMetricsTable(
                        columnHeaders: Self.columns,
                        rows: Array(rows.dropFirst()),
                        highlightRow: readEverExceededInterval ? "BLE Read Duration" : nil,
                        showHeader: false
                    )
                }
            }
        }
    }

    @ViewBuilder private var notificationTimingSection: some View {
        let rows = notificationRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                timingHeader
                if rows.first?.label == "Device Timestamp Period" {
                    TimingMetricsTable(columnHeaders: Self.columns, rows: [rows[0]])
                    if rows.count > 1 {
                        Divider().padding(.vertical, 2)
                        TimingMetricsTable(
                            columnHeaders: Self.columns,
                            rows: Array(rows.dropFirst()),
                            showHeader: false
                        )
                    }
                } else {
                    TimingMetricsTable(columnHeaders: Self.columns, rows: rows, showHeader: false)
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

    private var readEverExceededInterval: Bool {
        if !session.logEntries.isEmpty {
            return session.logEntries.contains { ($0.readDurationSeconds ?? 0) > session.pollingInterval }
        }
        return loggingManager.aggregates(for: session.id)?.readEverExceededInterval ?? false
    }
}

// MARK: - Completed-session timing rows

extension SnapshotCompletedSessionRowView {
    /// Polling rows from loaded entries when available, else persisted aggregates.
    private var pollingRows: [TimingMetricRow] {
        if !session.logEntries.isEmpty {
            let all = session.logEntries
            return [
                statRow("Device Timestamp Period", calculateDeviceTimestampPeriods(from: all)),
                statRow("BLE Read Duration", all.compactMap(\.readDurationSeconds)),
                statRow("Schedule-to-Read Latency", all.compactMap(\.latencySeconds)),
                statRow("Device-to-Read Latency", all.compactMap(\.deviceToReadLatencySeconds)),
                statRow("Cycle Duration", all.compactMap(\.cycleDurationSeconds))
            ]
        }
        guard let agg = loggingManager.aggregates(for: session.id) else { return [] }
        return [
            aggregateRow("Device Timestamp Period", agg.deviceTimestampPeriod),
            aggregateRow("BLE Read Duration", agg.bleReadDuration),
            aggregateRow("Schedule-to-Read Latency", agg.scheduleToReadLatency),
            aggregateRow("Device-to-Read Latency", agg.deviceToReadLatency),
            aggregateRow("Cycle Duration", agg.cycleDuration)
        ]
    }

    /// Notification rows filtered by the session's selected timing fields.
    private var notificationRows: [TimingMetricRow] {
        let selected = session.selectedTimingFieldIds
        if !session.logEntries.isEmpty {
            let all = session.logEntries
            var rows: [TimingMetricRow] = []
            if selected.contains("deviceTimestampPeriod") {
                rows.append(statRow("Device Timestamp Period", calculateDeviceTimestampPeriods(from: all)))
            }
            if selected.contains("notificationLatency") {
                rows.append(statRow("Notification Latency", all.compactMap(\.notificationLatencySeconds)))
            }
            if selected.contains("notificationPeriod") {
                rows.append(statRow("Notification Period", all.compactMap(\.interNotificationInterval)))
            }
            return rows
        }
        guard let agg = loggingManager.aggregates(for: session.id) else { return [] }
        var rows: [TimingMetricRow] = []
        if selected.contains("deviceTimestampPeriod") {
            rows.append(aggregateRow("Device Timestamp Period", agg.deviceTimestampPeriod))
        }
        if selected.contains("notificationLatency") {
            rows.append(aggregateRow("Notification Latency", agg.notificationLatency))
        }
        if selected.contains("notificationPeriod") {
            rows.append(aggregateRow("Notification Period", agg.notificationPeriod))
        }
        return rows
    }

    private func statRow(_ label: String, _ values: [Double]) -> TimingMetricRow {
        TimingMetricRow(label: label, columns: [
            formatAsMilliseconds(mean(values)),
            formatAsMilliseconds(values.min()),
            formatAsMilliseconds(values.max())
        ])
    }

    private func aggregateRow(_ label: String, _ stats: RunningStatistics) -> TimingMetricRow {
        guard stats.count > 0 else { return TimingMetricRow(label: label, columns: ["-", "-", "-"]) }
        return TimingMetricRow(label: label, columns: [
            String(format: "%.3f", stats.avg * 1000),
            String(format: "%.3f", (stats.min ?? 0) * 1000),
            String(format: "%.3f", (stats.max ?? 0) * 1000)
        ])
    }
}
