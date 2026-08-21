//
//  SnapshotExportSessionView+Logic.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - Data + export logic

extension SnapshotExportSessionView {
    var availableFieldKeyPaths: [String] {
        session.logEntries.first?.fieldValues.map(\.keyPath) ?? []
    }

    var availablePreviewCounts: [PreviewEntryCount] {
        selectedFormat == .json ? PreviewEntryCount.jsonAllowedCases : PreviewEntryCount.csvAllowedCases
    }

    // MARK: Timing summary

    var timingRows: [TimingMetricRow] {
        let entries = session.logEntries
        guard !entries.isEmpty else { return [] }
        if session.captureMode == .polling {
            return [
                statRow("Device Timestamp Period", calculateDeviceTimestampPeriods(from: entries)),
                statRow("BLE Read Duration", entries.compactMap(\.readDurationSeconds)),
                statRow("Schedule-to-Read Latency", entries.compactMap(\.latencySeconds)),
                statRow("Device-to-Read Latency", entries.compactMap(\.deviceToReadLatencySeconds)),
                statRow("Cycle Duration", entries.compactMap(\.cycleDurationSeconds))
            ]
        }
        let selected = session.selectedTimingFieldIds
        var rows: [TimingMetricRow] = []
        if selected.contains("deviceTimestampPeriod") {
            rows.append(statRow("Device Timestamp Period", calculateDeviceTimestampPeriods(from: entries)))
        }
        if selected.contains("notificationLatency") {
            rows.append(statRow("Notification Latency", entries.compactMap(\.notificationLatencySeconds)))
        }
        if selected.contains("notificationPeriod") {
            rows.append(statRow("Notification Period", entries.compactMap(\.interNotificationInterval)))
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

    // MARK: Preview (reuses the real exporter on a truncated copy)

    var sampleOutputPreview: String {
        previewText(entryLimit: previewEntryCount.rawValue)
    }

    var fullPreviewText: String {
        previewText(entryLimit: nil)
    }

    private func previewText(entryLimit: Int?) -> String {
        let source = entryLimit.map(truncatedSession) ?? session
        guard let data = loggingManager.exportSession(
            source,
            format: selectedFormat,
            selectedFieldKeyPaths: selectedExportFieldKeyPaths,
            selectedTimingFieldIds: selectedTimingFieldIds
        ), let text = String(data: data, encoding: .utf8) else {
            return "No preview available."
        }
        return text
    }

    private func truncatedSession(_ count: Int) -> SnapshotLoggingSession {
        var copy = session
        copy.logEntries = Array(session.logEntries.prefix(count))
        copy.entryCount = copy.logEntries.count
        return copy
    }

    // MARK: Lifecycle

    func seedDefaults() {
        if selectedExportFieldKeyPaths.isEmpty { selectedExportFieldKeyPaths = Set(availableFieldKeyPaths) }
        if selectedTimingFieldIds.isEmpty {
            selectedTimingFieldIds = SnapshotTimingFieldConfig.defaultEnabledFieldIds(for: session.captureMode)
        }
        if exportFileName.isEmpty { exportFileName = SessionNameValidator.sanitizeForFilename(session.name) }
        clampPreviewEntryCount()
    }

    func clampPreviewEntryCount() {
        guard let first = availablePreviewCounts.first else { return }
        if !availablePreviewCounts.contains(previewEntryCount) { previewEntryCount = first }
    }

    // MARK: Export

    func exportSession() {
        guard let data = loggingManager.exportSession(
            session,
            format: selectedFormat,
            selectedFieldKeyPaths: selectedExportFieldKeyPaths,
            selectedTimingFieldIds: selectedTimingFieldIds
        ) else {
            errorMessage = "Failed to export session data."
            return
        }

        let sanitized = SessionNameValidator.sanitizeForFilename(exportFileName)
        let fileName = "\(sanitized).\(selectedFormat.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            exportedFileURL = url
            showingShareSheet = true
        } catch {
            errorMessage = "Failed to save export file: \(error.localizedDescription)"
        }
    }
}
