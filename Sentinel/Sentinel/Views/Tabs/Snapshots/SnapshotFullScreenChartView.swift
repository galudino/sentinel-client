//
//  SnapshotFullScreenChartView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Charts
import SwiftUI

// MARK: - SnapshotFullScreenChartView

/// The interactive full-screen chart. Pinch to zoom the X axis, drag to pan,
/// tap to scrub a sample (with a draggable metadata popup).
///
/// This is where the long-session performance work pays off: the full-resolution
/// series is extracted once, and on every zoom/pan the **visible window** is
/// sliced and re-decimated (``ChartDecimator``) to a bounded point count —
/// debounced so a fast pinch stays at ~60fps. The plot is a `.drawingGroup()`.
struct SnapshotFullScreenChartView: View {
    let session: SnapshotLoggingSession
    let leftAxisFieldKeyPath: String?
    let rightAxisFieldKeyPath: String?
    let selectedBooleanKeyPaths: Set<String>
    var onViewLoaded: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    // Full-resolution series, extracted once.
    @State var fullLeft: [ChartDataPoint] = []
    @State var fullRight: [ChartDataPoint] = []
    @State var fullBooleans: [String: [ChartDataPoint]] = [:]

    // Decimated series for the current viewport.
    @State var leftViewport: [ChartDataPoint] = []
    @State var rightViewport: [ChartDataPoint] = []
    @State var booleanViewport: [String: [ChartDataPoint]] = [:]

    // Zoom / pan (X only; Y stays normalized 0…1).
    @State var xZoomScale: CGFloat = 1.0
    @State var lastXZoomScale: CGFloat = 1.0
    @State var xOffsetSamples: Double = 0
    @State var lastXOffsetSamples: Double = 0

    // Scrub + metadata popup.
    @State var selectedSampleIndex: Int?
    @State private var showMetadataEnabled = false
    @State private var isPopupExpanded = true
    @State private var popupPosition = CGPoint(x: 16, y: 80)

    @State var redecimateTask: Task<Void, Never>?

    let minZoom: CGFloat = 1.0
    let maxZoom: CGFloat = 40.0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    chartSection(geometry: geometry)
                    if showMetadataPopup, let entry = selectedLogEntry {
                        metadataPopupView(entry: entry, geometry: geometry)
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("Full-Screen Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear {
            extractFullResolutionSeries()
            recomputeViewport()
            onViewLoaded()
        }
    }

    var showMetadataPopup: Bool { showMetadataEnabled && selectedSampleIndex != nil }

    var selectedLogEntry: SnapshotLogEntry? {
        guard let index = selectedSampleIndex, index >= 0, index < session.logEntries.count else { return nil }
        return session.logEntries[index]
    }

    // MARK: Chart

    @ViewBuilder
    private func chartSection(geometry: GeometryProxy) -> some View {
        if leftAxisFieldKeyPath == nil, rightAxisFieldKeyPath == nil, selectedBooleanKeyPaths.isEmpty {
            emptyChartPlaceholder
        } else {
            VStack(spacing: 4) {
                Text("Seconds Elapsed").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                scrubberControls
                chart(height: max(200, geometry.size.height - 150))
                Text("Sample Number").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                if xZoomScale > 1.0 { zoomIndicator }
                legendSection
            }
            .padding()
        }
    }

    private var scrubberControls: some View {
        HStack(spacing: 12) {
            if let index = selectedSampleIndex {
                Text("Sample #\(index + 1)").font(.caption2).fontWeight(.medium)
            } else {
                Text("Tap chart to scrub · pinch to zoom · drag to pan")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if xZoomScale > 1.0 {
                Button("Reset Zoom") { resetZoom() }.font(.caption2)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showMetadataEnabled.toggle() }
            } label: {
                Label("Details", systemImage: showMetadataEnabled ? "info.circle.fill" : "info.circle")
                    .font(.caption2)
                    .foregroundStyle(showMetadataEnabled ? .blue : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 2)
    }

    private func chart(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            if let field = leftAxisField {
                Text(field.unit).font(.caption2).foregroundStyle(.blue)
                    .rotationEffect(.degrees(-90)).fixedSize().frame(width: 20)
            }
            chartContent
                .frame(height: height)
                .chartOverlay { proxy in
                    GeometryReader { chartGeometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(zoomGesture)
                            .simultaneousGesture(panGesture(geometry: chartGeometry))
                            .simultaneousGesture(
                                SpatialTapGesture().onEnded { event in scrub(at: event.location, proxy: proxy) }
                            )
                    }
                }
            if let field = rightAxisField {
                Text(field.unit).font(.caption2).foregroundStyle(.orange)
                    .rotationEffect(.degrees(90)).fixedSize().frame(width: 20)
            }
        }
    }

    private var chartContent: some View {
        let leftRange = ChartMath.paddedRange(leftViewport)
        let rightRange = ChartMath.paddedRange(rightViewport)

        return Chart {
            if let selectedIndex = selectedSampleIndex {
                RuleMark(x: .value("Selected", selectedIndex + 1))
                    .foregroundStyle(.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
            }
            ForEach(leftViewport) { point in
                LineMark(
                    x: .value("Sample", point.sampleNumber),
                    y: .value("Left", ChartMath.normalize(point.value, in: leftRange)),
                    series: .value("Series", "Left")
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(rightViewport) { point in
                LineMark(
                    x: .value("Sample", point.sampleNumber),
                    y: .value("Right", ChartMath.normalize(point.value, in: rightRange)),
                    series: .value("Series", "Right")
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(Array(selectedBooleanKeyPaths).sorted(), id: \.self) { keyPath in
                ForEach(booleanViewport[keyPath] ?? []) { point in
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
        .chartXScale(domain: visibleXRange)
        .chartYScale(domain: 0.0 ... 1.0)
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine()
                AxisValueLabel { if let sample = value.as(Int.self) { Text("\(sample)").font(.caption2) } }
            }
            AxisMarks(position: .top) { value in
                AxisValueLabel {
                    if let sample = value.as(Int.self) {
                        Text(String(format: "%.1fs", Double(sample - 1) * session.pollingInterval)).font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let normalized = value.as(Double.self), !leftViewport.isEmpty {
                        Text(ChartMath.axisLabel(ChartMath.denormalize(normalized, in: leftRange)))
                            .font(.caption2).foregroundStyle(.blue)
                    }
                }
            }
            AxisMarks(position: .trailing) { value in
                AxisValueLabel {
                    if let normalized = value.as(Double.self), !rightViewport.isEmpty {
                        Text(ChartMath.axisLabel(ChartMath.denormalize(normalized, in: rightRange)))
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
        .drawingGroup()
    }

    // MARK: Metadata popup

    private func metadataPopupView(entry: SnapshotLogEntry, geometry: GeometryProxy) -> some View {
        let popupWidth: CGFloat = 280
        let popupHeight: CGFloat = isPopupExpanded ? 320 : 110
        let safeX = min(max(popupPosition.x, 8), geometry.size.width - popupWidth - 8)
        let safeY = min(max(popupPosition.y, 8), geometry.size.height - popupHeight - 8)

        return VStack(alignment: .leading, spacing: 8) {
            popupHeader(geometry: geometry, popupWidth: popupWidth, popupHeight: popupHeight)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Timing").font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
                    timingMetrics(for: entry)
                    Divider().padding(.vertical, 4)
                    Text("Field Values").font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
                    ForEach(entry.fieldValues) { fieldValue in
                        metadataRow(label: fieldValue.displayName, value: formatFieldValue(fieldValue))
                    }
                }
            }
        }
        .padding(12)
        .frame(width: popupWidth, height: popupHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
        .position(x: safeX + popupWidth / 2, y: safeY + popupHeight / 2)
        .animation(.easeInOut(duration: 0.2), value: isPopupExpanded)
    }

    private func popupHeader(geometry: GeometryProxy, popupWidth: CGFloat, popupHeight: CGFloat) -> some View {
        HStack {
            Image(systemName: "line.3.horizontal").font(.caption).foregroundStyle(.tertiary)
            Text("Sample #\((selectedSampleIndex ?? 0) + 1)").font(.headline)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isPopupExpanded.toggle() }
            } label: {
                Image(systemName: isPopupExpanded ? "chevron.up.circle" : "chevron.down.circle")
                    .foregroundStyle(.secondary)
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showMetadataEnabled = false }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    popupPosition = CGPoint(
                        x: popupPosition.x + value.translation.width,
                        y: popupPosition.y + value.translation.height
                    )
                }
                .onEnded { _ in
                    popupPosition = CGPoint(
                        x: min(max(popupPosition.x, 8), geometry.size.width - popupWidth - 8),
                        y: min(max(popupPosition.y, 8), geometry.size.height - popupHeight - 8)
                    )
                }
        )
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.medium).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - LegendItem

struct LegendItem: Identifiable {
    let id: String
    let color: Color
    let name: String
    let isDashed: Bool
}

extension SnapshotFullScreenChartView {
    var legendItems: [LegendItem] {
        var items: [LegendItem] = []
        if let field = leftAxisField {
            items.append(LegendItem(id: "left", color: .blue, name: legendName(field), isDashed: false))
        }
        if let field = rightAxisField {
            items.append(LegendItem(id: "right", color: .orange, name: legendName(field), isDashed: false))
        }
        for keyPath in selectedBooleanKeyPaths.sorted() {
            if let field = availableBooleanFields.first(where: { $0.keyPath == keyPath }) {
                items.append(LegendItem(
                    id: keyPath, color: colorForBooleanField(keyPath: keyPath), name: field.displayName, isDashed: true
                ))
            }
        }
        return items
    }

    private func legendName(_ field: ChartableField) -> String {
        field.unit.isEmpty ? field.displayName : "\(field.displayName) (\(field.unit))"
    }
}

// MARK: - Rendering (overlays + legend)

private extension SnapshotFullScreenChartView {
    var zoomIndicator: some View {
        HStack {
            Text("Zoom \(String(format: "%.1f", xZoomScale))×").font(.caption2).foregroundStyle(.secondary)
            Text("•").foregroundStyle(.secondary)
            Text("Samples \(visibleXRange.lowerBound)–\(visibleXRange.upperBound)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    var emptyChartPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.largeTitle).foregroundStyle(.secondary)
            Text("No fields selected to display").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Legend

    var legendSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(legendItems) { item in legendChip(item: item) }
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, 8)
    }

    func legendChip(item: LegendItem) -> some View {
        HStack(spacing: 6) {
            if item.isDashed {
                HStack(spacing: 2) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1).fill(item.color).frame(width: 4, height: 3)
                    }
                }
                .frame(width: 16)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 16, height: 3)
            }
            Text(item.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
    }
}
