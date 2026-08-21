//
//  SnapshotSessionChartView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Charts
import SwiftUI

// MARK: - SnapshotSessionChartView

/// Per-session dual-axis chart. Picks a left (blue) and right (orange) numeric
/// field plus any number of boolean step-lines, normalizes the two axes onto a
/// shared 0…1 range, and opens a full-screen interactive view on tap.
///
/// Entries are loaded from disk once (off the main actor); the plotted series are
/// **decimated** (``ChartDecimator``) so even a 60-minute session renders quickly
/// — full resolution is preserved for export. Generic over the snapshot type via
/// the session's stored field values, so this view itself needs no provider.
struct SnapshotSessionChartView: View {
    let session: SnapshotLoggingSession

    // Selection + loaded state — non-private so the +Data extension (separate file)
    // can drive loading and series recomputation.
    @State var leftAxisFieldKeyPath: String?
    @State var rightAxisFieldKeyPath: String?
    @State var selectedBooleanKeyPaths: Set<String> = []

    @State var loadedSession: SnapshotLoggingSession?
    @State var isLoadingEntries = false
    @State var loadError: String?

    // Cached display series (decimated); recomputed only on load / selection change.
    @State var leftDisplay: [ChartDataPoint] = []
    @State var rightDisplay: [ChartDataPoint] = []
    @State var booleanDisplay: [String: [ChartDataPoint]] = [:]

    @State private var showFullScreenChart = false
    @State private var isLoadingFullScreenChart = false

    var activeSession: SnapshotLoggingSession { loadedSession ?? session }

    var body: some View {
        ZStack {
            if isLoadingEntries {
                VStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sessionInfoSection
                        axisSelector(
                            title: "Left Y-Axis:", tint: .blue,
                            selection: $leftAxisFieldKeyPath, options: leftAxisFields
                        )
                        axisSelector(
                            title: "Right Y-Axis:", tint: .orange,
                            selection: $rightAxisFieldKeyPath, options: rightAxisFields
                        )
                        if !availableBooleanFields.isEmpty { booleanFieldsSection }
                        chartSection
                        legendSection
                    }
                    .padding()
                }
            }

            if isLoadingFullScreenChart { loadingOverlay }
        }
        .navigationTitle("Session Chart")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadEntriesIfNeeded)
        .onChange(of: leftAxisFieldKeyPath) { _, _ in recomputeAxisSeries() }
        .onChange(of: rightAxisFieldKeyPath) { _, _ in recomputeAxisSeries() }
        .onChange(of: selectedBooleanKeyPaths) { _, _ in recomputeBooleanSeries() }
        .fullScreenCover(isPresented: $showFullScreenChart) {
            SnapshotFullScreenChartView(
                session: activeSession,
                leftAxisFieldKeyPath: leftAxisFieldKeyPath,
                rightAxisFieldKeyPath: rightAxisFieldKeyPath,
                selectedBooleanKeyPaths: selectedBooleanKeyPaths,
                onViewLoaded: { isLoadingFullScreenChart = false }
            )
        }
        .alert("Load Error", isPresented: .constant(loadError != nil)) {
            Button("OK") { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    // MARK: Info

    private var sessionInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(activeSession.name).font(.headline)
            VStack(alignment: .leading, spacing: 2) {
                labeledCaption("Started:", SessionFormat.timestamp(activeSession.startTime))
                if let endTime = activeSession.endTime {
                    labeledCaption("Ended:", SessionFormat.timestamp(endTime))
                }
            }
            HStack {
                Text("Duration: \(SessionFormat.clockWithMillis(activeSession.actualDuration))")
                Spacer()
                Text("\(activeSession.logEntries.count) samples")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            SessionModeChip(session: activeSession)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func labeledCaption(_ label: String, _ value: String) -> some View {
        HStack(spacing: 0) {
            Text(label).frame(width: 60, alignment: .leading)
            Text(value)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: Selectors

    private func axisSelector(
        title: String,
        tint: Color,
        selection: Binding<String?>,
        options: [ChartableField]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(tint).frame(width: 12, height: 12)
                Text(title).font(.subheadline).fontWeight(.medium)
            }
            HStack {
                Spacer()
                Picker(title, selection: selection) {
                    Text("None").tag(nil as String?)
                    ForEach(options) { field in
                        Text("\(field.displayName) (\(field.unit))").tag(field.keyPath as String?)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private var booleanFieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "togglepower").foregroundStyle(.secondary)
                Text("Boolean Values (Step Lines):").font(.subheadline).fontWeight(.medium)
            }
            VStack(spacing: 8) {
                ForEach(Array(availableBooleanFields.enumerated()), id: \.element.keyPath) { index, field in
                    Button {
                        toggleBooleanField(keyPath: field.keyPath)
                    } label: {
                        HStack {
                            Image(
                                systemName: selectedBooleanKeyPaths.contains(field.keyPath)
                                    ? "checkmark.square.fill" : "square"
                            )
                            .foregroundStyle(colorForBooleanField(at: index))
                            Text(field.displayName).font(.subheadline).foregroundStyle(.primary)
                            Spacer()
                            Circle().fill(colorForBooleanField(at: index)).frame(width: 10, height: 10)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: Chart

    @ViewBuilder private var chartSection: some View {
        if leftAxisFieldKeyPath == nil, rightAxisFieldKeyPath == nil, selectedBooleanKeyPaths.isEmpty {
            emptyChartPlaceholder
        } else {
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "hand.tap").font(.caption2)
                    Text("Tap chart for full-screen view").font(.caption2)
                }
                .foregroundStyle(.blue)
                .padding(.bottom, 4)

                Text("Seconds Elapsed").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                dualAxisChart
                    .frame(height: 300)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isLoadingFullScreenChart = true
                        showFullScreenChart = true
                    }

                Text("Sample Number").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.largeTitle).foregroundStyle(.secondary)
            Text("Select at least one field to display the chart")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var dualAxisChart: some View {
        HStack(spacing: 0) {
            if let field = leftAxisField {
                Text(field.unit).font(.caption2).foregroundStyle(.blue)
                    .rotationEffect(.degrees(-90)).fixedSize().frame(width: 20)
            }
            chartContent
            if let field = rightAxisField {
                Text(field.unit).font(.caption2).foregroundStyle(.orange)
                    .rotationEffect(.degrees(90)).fixedSize().frame(width: 20)
            }
        }
    }

    private var chartContent: some View {
        let leftRange = ChartMath.paddedRange(leftDisplay)
        let rightRange = ChartMath.paddedRange(rightDisplay)

        return Chart {
            ForEach(leftDisplay) { point in
                LineMark(
                    x: .value("Sample", point.sampleNumber),
                    y: .value("Left", ChartMath.normalize(point.value, in: leftRange)),
                    series: .value("Series", "Left")
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(rightDisplay) { point in
                LineMark(
                    x: .value("Sample", point.sampleNumber),
                    y: .value("Right", ChartMath.normalize(point.value, in: rightRange)),
                    series: .value("Series", "Right")
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(Array(selectedBooleanKeyPaths).sorted(), id: \.self) { keyPath in
                ForEach(booleanDisplay[keyPath] ?? []) { point in
                    LineMark(
                        x: .value("Sample", point.sampleNumber),
                        y: .value("Bool", point.value),
                        series: .value("Series", "Bool_\(keyPath)")
                    )
                    .foregroundStyle(colorForBooleanField(keyPath: keyPath))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                    .interpolationMethod(.stepEnd)
                }
            }
        }
        .chartXScale(domain: fullXRange)
        .chartYScale(domain: 0.0 ... 1.0)
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine()
                AxisValueLabel { if let sample = value.as(Int.self) { Text("\(sample)").font(.caption2) } }
            }
            AxisMarks(position: .top) { value in
                AxisValueLabel {
                    if let sample = value.as(Int.self) {
                        Text(String(format: "%.1fs", Double(sample - 1) * activeSession.pollingInterval))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let normalized = value.as(Double.self), !leftDisplay.isEmpty {
                        Text(ChartMath.axisLabel(ChartMath.denormalize(normalized, in: leftRange)))
                            .font(.caption2).foregroundStyle(.blue)
                    }
                }
            }
            AxisMarks(position: .trailing) { value in
                AxisValueLabel {
                    if let normalized = value.as(Double.self), !rightDisplay.isEmpty {
                        Text(ChartMath.axisLabel(ChartMath.denormalize(normalized, in: rightRange)))
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
        .drawingGroup()
    }

    private var legendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Legend").font(.subheadline).fontWeight(.medium)
            if let field = leftAxisField { legendRow(color: .blue, text: "\(field.displayName) (\(field.unit))") }
            if let field = rightAxisField { legendRow(color: .orange, text: "\(field.displayName) (\(field.unit))") }
            ForEach(Array(selectedBooleanKeyPaths).sorted(), id: \.self) { keyPath in
                if let field = availableBooleanFields.first(where: { $0.keyPath == keyPath }) {
                    legendRow(
                        color: colorForBooleanField(keyPath: keyPath),
                        text: "\(field.displayName) (0=false, 1=true)"
                    )
                }
            }
            if leftAxisFieldKeyPath == nil, rightAxisFieldKeyPath == nil, selectedBooleanKeyPaths.isEmpty {
                Text("No fields selected").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func legendRow(color: Color, text: String) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 20, height: 3)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.5).tint(.white)
                Text("Loading…").font(.headline).foregroundStyle(.white)
            }
            .padding(24)
            .background(Color.black.opacity(0.7))
            .cornerRadius(12)
        }
    }
}
