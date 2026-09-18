//
//  TimingMetricsTable.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - TimingMetricsTable

/// A small aligned table of timing metrics: a label column plus one trailing
/// column per header (e.g. last / avg / max, or avg / min / max). Shared by the
/// active and completed session rows.
struct TimingMetricsTable: View {
    let columnHeaders: [String]
    let rows: [TimingMetricRow]
    var highlightRow: String?
    var showHeader = true

    private let labelWidth: CGFloat = 150
    private let columnWidth: CGFloat = 66

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showHeader {
                HStack(spacing: 0) {
                    Text("").frame(width: labelWidth, alignment: .leading)
                    ForEach(columnHeaders, id: \.self) { header in
                        Text(header).frame(width: columnWidth, alignment: .trailing)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            ForEach(rows) { row in
                let isHighlighted = row.label == highlightRow
                HStack(spacing: 0) {
                    Text(row.label).frame(width: labelWidth, alignment: .leading)
                    ForEach(Array(row.columns.enumerated()), id: \.offset) { _, value in
                        Text(value).frame(width: columnWidth, alignment: .trailing)
                    }
                }
                .font(.caption2)
                .fontWeight(isHighlighted ? .bold : .regular)
                .foregroundStyle(isHighlighted ? Color.orange : .secondary)
            }
        }
    }
}

// MARK: - Shared row bits

/// The capture-mode chip shown on session rows.
struct SessionModeChip: View {
    let session: SnapshotLoggingSession

    var body: some View {
        HStack(spacing: 6) {
            Label(session.captureMode.displayName, systemImage: session.captureMode.systemImageName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint.opacity(0.1))
                .foregroundStyle(tint)
                .cornerRadius(4)

            if session.captureMode == .polling {
                Text("\(String(format: "%.2f", session.pollingInterval))s interval")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tint: Color { session.captureMode == .polling ? .blue : .purple }
}

// MARK: - Formatting helpers

enum SessionFormat {
    static func clockWithMillis(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        let millis = Int(duration.truncatingRemainder(dividingBy: 1) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
