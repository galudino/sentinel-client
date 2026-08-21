//
//  SnapshotTimingMetricsExplanationsView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - SnapshotTimingMetricsExplanationsView

/// Reference sheet explaining every capture-timing metric, grouped into raw
/// timestamps vs. derived metrics. Generated directly from
/// ``SnapshotTimingFieldConfig`` so the copy never drifts from the fields that
/// actually appear in exports.
struct SnapshotTimingMetricsExplanationsView: View {
    @Environment(\.dismiss) private var dismiss

    private var fieldsByCategory: [SnapshotTimingFieldCategory: [SnapshotTimingFieldConfig]] {
        Dictionary(grouping: SnapshotTimingFieldConfig.allFields, by: \.category)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(SnapshotTimingFieldCategory.allCases) { category in
                    if let fields = fieldsByCategory[category] {
                        Section {
                            ForEach(fields) { field in explanationRow(field) }
                        } header: {
                            Text(category.displayName)
                        } footer: {
                            Text(category.description)
                        }
                    }
                }
            }
            .navigationTitle("Timing Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func explanationRow(_ field: SnapshotTimingFieldConfig) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(field.displayName).font(.subheadline).fontWeight(.semibold)
                if !field.unit.isEmpty {
                    Text(field.unit)
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.2)))
                }
                Spacer()
                modesBadge(field.applicableModes)
            }
            Text(field.description).font(.caption).foregroundStyle(.secondary)
            Text(field.calculation)
                .font(.caption2)
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }

    private func modesBadge(_ modes: Set<SnapshotCaptureMode>) -> some View {
        let label = modes.count == SnapshotCaptureMode.allCases.count
            ? "Both"
            : modes.map(\.displayName).sorted().joined(separator: ", ")
        return Text(label).font(.caption2).foregroundStyle(.tertiary)
    }
}
