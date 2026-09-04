//
//  SnapshotSessionChartView+Data.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - Field discovery + data loading

extension SnapshotSessionChartView {
    /// Numeric (chartable) fields present in the session's samples.
    var availableFields: [ChartableField] {
        chartableFields { $0.dataType.isNumeric }
    }

    /// Boolean fields present in the session's samples.
    var availableBooleanFields: [ChartableField] {
        chartableFields(unitOverride: "bool") { $0.dataType == .bool }
    }

    private func chartableFields(
        unitOverride: String? = nil,
        where predicate: (SnapshotFieldValue) -> Bool
    ) -> [ChartableField] {
        guard let first = activeSession.logEntries.first else { return [] }
        return first.fieldValues.compactMap { fieldValue in
            guard predicate(fieldValue) else { return nil }
            return ChartableField(
                keyPath: fieldValue.keyPath,
                displayName: fieldValue.displayName,
                unit: unitOverride ?? fieldValue.unit,
                dataType: fieldValue.dataType
            )
        }
    }

    var leftAxisFields: [ChartableField] { availableFields.filter { $0.keyPath != rightAxisFieldKeyPath } }
    var rightAxisFields: [ChartableField] { availableFields.filter { $0.keyPath != leftAxisFieldKeyPath } }
    var leftAxisField: ChartableField? { availableFields.first { $0.keyPath == leftAxisFieldKeyPath } }
    var rightAxisField: ChartableField? { availableFields.first { $0.keyPath == rightAxisFieldKeyPath } }

    var fullXRange: ClosedRange<Int> {
        let count = activeSession.logEntries.count
        return count > 0 ? 1 ... count : 1 ... 1
    }

    func colorForBooleanField(at index: Int) -> Color {
        let palette: [Color] = [.green, .purple, .red, .cyan, .pink, .mint, .indigo, .teal]
        return palette[index % palette.count]
    }

    func colorForBooleanField(keyPath: String) -> Color {
        guard let index = availableBooleanFields.firstIndex(where: { $0.keyPath == keyPath }) else { return .gray }
        return colorForBooleanField(at: index)
    }

    func toggleBooleanField(keyPath: String) {
        if selectedBooleanKeyPaths.contains(keyPath) {
            selectedBooleanKeyPaths.remove(keyPath)
        } else {
            selectedBooleanKeyPaths.insert(keyPath)
        }
    }

    // MARK: Loading

    func loadEntriesIfNeeded() {
        guard loadedSession == nil else {
            initializeDefaultSelections()
            recomputeAxisSeries()
            recomputeBooleanSeries()
            return
        }
        // Entries already present (e.g. a still-active session passed in-memory).
        if !session.logEntries.isEmpty {
            initializeDefaultSelections()
            recomputeAxisSeries()
            recomputeBooleanSeries()
            return
        }

        isLoadingEntries = true
        let sessionId = session.id
        Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try SessionFileManager.shared.loadEntries(for: sessionId)
                }.value
                var loaded = session
                loaded.logEntries = result.entries
                loaded.entryCount = result.entries.count
                if let footer = result.footer {
                    if loaded.endTime == nil { loaded.endTime = footer.endTime }
                    if loaded.duration == nil { loaded.duration = footer.duration }
                }
                loadedSession = loaded
                isLoadingEntries = false
                initializeDefaultSelections()
                recomputeAxisSeries()
                recomputeBooleanSeries()
            } catch {
                loadError = "Failed to load session entries: \(error.localizedDescription)"
                isLoadingEntries = false
            }
        }
    }

    func initializeDefaultSelections() {
        let fields = availableFields
        if leftAxisFieldKeyPath == nil, let first = fields.first { leftAxisFieldKeyPath = first.keyPath }
        if rightAxisFieldKeyPath == nil, fields.count >= 2 { rightAxisFieldKeyPath = fields[1].keyPath }
    }

    // MARK: Series extraction + decimation (cached)

    func recomputeAxisSeries() {
        leftDisplay = decimatedNumericSeries(for: leftAxisFieldKeyPath)
        rightDisplay = decimatedNumericSeries(for: rightAxisFieldKeyPath)
    }

    func recomputeBooleanSeries() {
        var series: [String: [ChartDataPoint]] = [:]
        for keyPath in selectedBooleanKeyPaths {
            series[keyPath] = ChartDecimator.transitionsOnly(booleanPoints(for: keyPath))
        }
        booleanDisplay = series
    }

    private func decimatedNumericSeries(for keyPath: String?) -> [ChartDataPoint] {
        guard let keyPath else { return [] }
        return ChartDecimator.minMaxDecimated(
            numericPoints(for: keyPath),
            targetPoints: ChartDecimator.inlineTargetPoints
        )
    }

    private func numericPoints(for keyPath: String) -> [ChartDataPoint] {
        activeSession.logEntries.enumerated().compactMap { index, entry in
            guard let fieldValue = entry.fieldValues.first(where: { $0.keyPath == keyPath }),
                  let value = fieldValue.value.numericValue else { return nil }
            return ChartDataPoint(
                sampleNumber: index + 1,
                secondsElapsed: entry.timestamp.timeIntervalSince(activeSession.startTime),
                value: value
            )
        }
    }

    private func booleanPoints(for keyPath: String) -> [ChartDataPoint] {
        activeSession.logEntries.enumerated().compactMap { index, entry in
            guard let fieldValue = entry.fieldValues.first(where: { $0.keyPath == keyPath }),
                  let boolValue = fieldValue.value.boolValue else { return nil }
            return ChartDataPoint(
                sampleNumber: index + 1,
                secondsElapsed: entry.timestamp.timeIntervalSince(activeSession.startTime),
                value: boolValue ? 1.0 : 0.0
            )
        }
    }
}
