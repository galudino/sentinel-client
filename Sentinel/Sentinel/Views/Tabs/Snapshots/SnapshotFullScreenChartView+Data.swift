//
//  SnapshotFullScreenChartView+Data.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Charts
import SwiftUI

// MARK: - Fields

extension SnapshotFullScreenChartView {
    var availableFields: [ChartableField] {
        chartableFields { $0.dataType.isNumeric }
    }

    var availableBooleanFields: [ChartableField] {
        chartableFields(unitOverride: "bool") { $0.dataType == .bool }
    }

    private func chartableFields(
        unitOverride: String? = nil,
        where predicate: (SnapshotFieldValue) -> Bool
    ) -> [ChartableField] {
        guard let first = session.logEntries.first else { return [] }
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

    var leftAxisField: ChartableField? { availableFields.first { $0.keyPath == leftAxisFieldKeyPath } }
    var rightAxisField: ChartableField? { availableFields.first { $0.keyPath == rightAxisFieldKeyPath } }

    func colorForBooleanField(keyPath: String) -> Color {
        let palette: [Color] = [.green, .purple, .red, .cyan, .pink, .mint, .indigo, .teal]
        guard let index = availableBooleanFields.firstIndex(where: { $0.keyPath == keyPath }) else { return .gray }
        return palette[index % palette.count]
    }
}

// MARK: - Viewport

extension SnapshotFullScreenChartView {
    /// The visible sample window, derived from zoom scale + pan offset.
    var visibleXRange: ClosedRange<Int> {
        let total = session.logEntries.count
        guard total > 0 else { return 1 ... 1 }
        let visibleWidth = Double(total) / Double(xZoomScale)
        let clampedOffset = max(0, min(xOffsetSamples, Double(total) - visibleWidth))
        let start = max(1, Int(clampedOffset) + 1)
        let end = min(total, Int(clampedOffset + visibleWidth) + 1)
        return start ... max(start, end)
    }

    func clampOffset() {
        let total = Double(session.logEntries.count)
        let visibleWidth = total / Double(xZoomScale)
        xOffsetSamples = max(0, min(xOffsetSamples, max(0, total - visibleWidth)))
    }

    func resetZoom() {
        xZoomScale = 1.0
        lastXZoomScale = 1.0
        xOffsetSamples = 0
        lastXOffsetSamples = 0
        recomputeViewport()
    }

    /// Extract the full-resolution series once (used to slice viewports from).
    func extractFullResolutionSeries() {
        fullLeft = leftAxisFieldKeyPath.map(numericPoints(for:)) ?? []
        fullRight = rightAxisFieldKeyPath.map(numericPoints(for:)) ?? []
        var booleans: [String: [ChartDataPoint]] = [:]
        for keyPath in selectedBooleanKeyPaths {
            booleans[keyPath] = booleanPoints(for: keyPath)
        }
        fullBooleans = booleans
    }

    /// Slice the full series to the visible window and re-decimate it. Bounded
    /// point count keeps the plot smooth no matter how long the session is.
    func recomputeViewport() {
        let range = visibleXRange
        leftViewport = decimatedSlice(fullLeft, in: range)
        rightViewport = decimatedSlice(fullRight, in: range)
        var booleans: [String: [ChartDataPoint]] = [:]
        for (keyPath, points) in fullBooleans {
            booleans[keyPath] = ChartDecimator.transitionsOnly(ChartDecimator.slice(points, in: range))
        }
        booleanViewport = booleans
    }

    /// Debounced re-decimation for rapid pinch/pan; the final `onEnded` calls
    /// ``recomputeViewport()`` directly.
    func scheduleRedecimate() {
        redecimateTask?.cancel()
        redecimateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            if Task.isCancelled { return }
            recomputeViewport()
        }
    }

    private func decimatedSlice(_ points: [ChartDataPoint], in range: ClosedRange<Int>) -> [ChartDataPoint] {
        ChartDecimator.minMaxDecimated(
            ChartDecimator.slice(points, in: range),
            targetPoints: ChartDecimator.fullScreenTargetPoints
        )
    }

    private func numericPoints(for keyPath: String) -> [ChartDataPoint] {
        session.logEntries.enumerated().compactMap { index, entry in
            guard let fieldValue = entry.fieldValues.first(where: { $0.keyPath == keyPath }),
                  let value = fieldValue.value.numericValue else { return nil }
            return ChartDataPoint(
                sampleNumber: index + 1,
                secondsElapsed: entry.timestamp.timeIntervalSince(session.startTime),
                value: value
            )
        }
    }

    private func booleanPoints(for keyPath: String) -> [ChartDataPoint] {
        session.logEntries.enumerated().compactMap { index, entry in
            guard let fieldValue = entry.fieldValues.first(where: { $0.keyPath == keyPath }),
                  let boolValue = fieldValue.value.boolValue else { return nil }
            return ChartDataPoint(
                sampleNumber: index + 1,
                secondsElapsed: entry.timestamp.timeIntervalSince(session.startTime),
                value: boolValue ? 1.0 : 0.0
            )
        }
    }
}

// MARK: - Gestures

extension SnapshotFullScreenChartView {
    var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                isZooming = true
                xZoomScale = min(max(lastXZoomScale * scale, minZoom), maxZoom)
                clampOffset()
                scheduleRedecimate()
            }
            .onEnded { _ in
                lastXZoomScale = xZoomScale
                lastXOffsetSamples = xOffsetSamples
                recomputeViewport()
                isZooming = false
            }
    }

    /// One-finger drag scrubs the vertical sample line (a zero-distance drag is a
    /// tap, so tapping an exact point still works). Suppressed while pinching so it
    /// never fights the zoom.
    func scrubGesture(proxy: ChartProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isZooming else { return }
                scrub(at: value.location, proxy: proxy)
            }
    }

    func scrub(at location: CGPoint, proxy: ChartProxy) {
        guard let sample: Int = proxy.value(atX: location.x) else { return }
        let clamped = max(1, min(sample, session.logEntries.count))
        selectedSampleIndex = clamped - 1
        autoPan(towardSample: clamped)
    }

    /// When zoomed, scrubbing to the edge of the visible window nudges the window
    /// so a zoomed chart stays navigable with the same one-finger gesture.
    private func autoPan(towardSample sample: Int) {
        guard xZoomScale > 1 else { return }
        let range = visibleXRange
        let window = Double(range.upperBound - range.lowerBound)
        let margin = max(1.0, window * 0.08)
        if Double(sample) <= Double(range.lowerBound) + margin {
            xOffsetSamples -= margin
        } else if Double(sample) >= Double(range.upperBound) - margin {
            xOffsetSamples += margin
        } else {
            return
        }
        clampOffset()
        lastXOffsetSamples = xOffsetSamples
        scheduleRedecimate()
    }
}

// MARK: - Metadata popup content

extension SnapshotFullScreenChartView {
    @ViewBuilder
    func timingMetrics(for entry: SnapshotLogEntry) -> some View {
        if session.captureMode == .polling {
            pollingModeTimingMetrics(for: entry)
        } else {
            notificationModeTimingMetrics(for: entry)
        }
    }

    @ViewBuilder
    private func pollingModeTimingMetrics(for entry: SnapshotLogEntry) -> some View {
        if let millis = entry.deviceUnixTimeMs {
            popupRow("Device Timestamp", formatTime(Date(timeIntervalSince1970: Double(millis) / 1000)))
        }
        if let value = entry.scheduledTick { popupRow("Scheduled Start Cycle", formatTime(value)) }
        if let value = entry.actualStart { popupRow("Actual Start Read", formatTime(value)) }
        if let value = entry.actualFinishRead { popupRow("Actual Finish Read", formatTime(value)) }
        if let value = entry.finishCycle { popupRow("Finish Cycle", formatTime(value)) }
        Divider().padding(.vertical, 2)
        if let value = entry.readDurationSeconds { popupRow("BLE Read Duration", millisText(value)) }
        if let value = entry.latencySeconds { popupRow("Schedule-to-Read Latency", millisText(value)) }
        if let value = entry.deviceToReadLatencySeconds { popupRow("Device-to-Read Latency", millisText(value)) }
        if let value = entry.cycleDurationSeconds { popupRow("Cycle Duration", millisText(value)) }
        if let index = selectedSampleIndex {
            popupRow("Time Sample", String(format: "%.0f ms", Double(index) * session.pollingInterval * 1000))
        }
    }

    @ViewBuilder
    private func notificationModeTimingMetrics(for entry: SnapshotLogEntry) -> some View {
        let selected = session.selectedTimingFieldIds
        if selected.contains("deviceTimestamp"), let millis = entry.deviceUnixTimeMs {
            popupRow("Device Timestamp", formatTime(Date(timeIntervalSince1970: Double(millis) / 1000)))
        }
        if selected.contains("notificationReceived"), let value = entry.actualStart {
            popupRow("Notification Received", formatTime(value))
        }
        Divider().padding(.vertical, 2)
        if selected.contains("deviceTimestampPeriod"), let text = deviceTimestampPeriodText {
            popupRow("Device Timestamp Period", text)
        }
        if selected.contains("notificationLatency"), let value = entry.notificationLatencySeconds {
            popupRow("Notification Latency", millisText(value))
        }
        if selected.contains("notificationPeriod"), let value = entry.interNotificationInterval {
            popupRow("Notification Period", millisText(value))
        }
    }

    /// The device-timestamp period (ms) at the selected sample, if computable.
    private var deviceTimestampPeriodText: String? {
        guard let index = selectedSampleIndex, index > 0,
              let current = session.logEntries[index].deviceUnixTimeMs,
              let previous = session.logEntries[index - 1].deviceUnixTimeMs else { return nil }
        let periodMs = Double(Int64(bitPattern: current) - Int64(bitPattern: previous))
        return String(format: "%.0f ms", periodMs)
    }

    private func popupRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.medium).multilineTextAlignment(.trailing)
        }
    }

    func formatFieldValue(_ fieldValue: SnapshotFieldValue) -> String {
        if fieldValue.dataType == .bool || fieldValue.unit.isEmpty {
            return fieldValue.value.stringValue
        }
        return "\(fieldValue.value.stringValue) \(fieldValue.unit)"
    }

    private func millisText(_ seconds: Double) -> String { String(format: "%.3f ms", seconds * 1000) }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
