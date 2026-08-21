//
//  TrendChart.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/20/26.
//

import Charts
import SwiftUI

/// One plotted sample on a ``TrendChart`` — a timestamp paired with a value that
/// has **already** been converted to the display unit (the chart is unit-agnostic;
/// the caller owns unit conversion).
struct TrendPoint: Identifiable {
    let date: Date
    let value: Double

    /// Stable identity from the timestamp, so re-decimation / unit changes don't
    /// churn the chart's element identity.
    var id: TimeInterval { date.timeIntervalSince1970 }
}

/// A compact recent-history line chart with a min / max / avg readout — the
/// **shared** trend chart used across the app (Home's climate swipe + component
/// temperature today; reusable wherever a single metric's recent history is
/// shown). Domain-agnostic: callers pass converted ``TrendPoint``s plus the
/// display chrome (title, unit, tint). Rich decimation/zoom is #17's concern; this
/// stays deliberately lightweight.
struct TrendChart: View {
    let title: String
    let points: [TrendPoint]
    let unitSymbol: String
    var tint: Color = .accentColor
    var fractionDigits: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart(points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value(title, point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 120)

            HStack(spacing: 16) {
                stat("min", minValue)
                stat("max", maxValue)
                stat("avg", avgValue)
            }
            .font(.caption)
        }
    }

    @ViewBuilder private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium).monospacedDigit()
        }
    }

    // MARK: - Summary statistics

    private var values: [Double] { points.map(\.value) }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits))) + " " + unitSymbol
    }

    private var minValue: String { values.min().map(format) ?? "—" }
    private var maxValue: String { values.max().map(format) ?? "—" }
    private var avgValue: String {
        guard !values.isEmpty else { return "—" }
        return format(values.reduce(0, +) / Double(values.count))
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("Temperature trend") {
        let start = Date()
        let points = (0 ..< 24).map { hour in
            TrendPoint(
                date: start.addingTimeInterval(Double(hour) * 3600),
                value: 21.5 + 2.5 * sin(Double(hour) / 24 * 2 * .pi)
            )
        }
        return List {
            Section("Climate Trends") {
                TrendChart(title: "24-Hour Temperature", points: points, unitSymbol: "°C", tint: .orange)
            }
        }
    }
#endif
