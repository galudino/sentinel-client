//
//  SnapshotSelectTimingFieldsView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - SnapshotSelectTimingFieldsView

/// Choose which capture-timing metrics to include in an export, grouped into raw
/// timestamps vs. derived metrics for the session's capture mode.
struct SnapshotSelectTimingFieldsView: View {
    let captureMode: SnapshotCaptureMode
    @Binding var selectedFieldIds: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var showingDescriptions = true
    @State private var showingLatencyWarning = false

    private var availableFields: [SnapshotTimingFieldConfig] {
        SnapshotTimingFieldConfig.fields(for: captureMode)
    }

    private var fieldsByCategory: [SnapshotTimingFieldCategory: [SnapshotTimingFieldConfig]] {
        SnapshotTimingFieldConfig.fieldsByCategory(for: captureMode)
    }

    private var latencyWarningMessage: String {
        """
        This metric compares timestamps from two different clocks (the device and iOS). \
        Without synchronized clocks, values may be inaccurate or negative.

        A negative value means the device clock is ahead of the iOS clock.

        Are you sure you want to include this metric?
        """
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Form {
                    if let timestampFields = fieldsByCategory[.timestamps], !timestampFields.isEmpty {
                        Section {
                            ForEach(timestampFields) { timingFieldRow($0) }
                        } header: {
                            sectionHeader(.timestamps, fields: timestampFields)
                        }
                    }
                    if let derivedFields = fieldsByCategory[.derivedMetrics], !derivedFields.isEmpty {
                        Section {
                            ForEach(derivedFields) { timingFieldRow($0) }
                        } header: {
                            sectionHeader(.derivedMetrics, fields: derivedFields)
                        }
                    }
                }
            }
            .navigationTitle("Timing Fields")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Notification Latency Warning", isPresented: $showingLatencyWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Enable") { selectedFieldIds.insert("notificationLatency") }
            } message: {
                Text(latencyWarningMessage)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Text("\(selectedFieldIds.count) of \(availableFields.count) fields selected")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 12) {
                Spacer()
                Button(action: selectAll) { Label("Select All", systemImage: "checkmark.circle.fill").font(.caption) }
                    .buttonStyle(.bordered)
                    .disabled(allFieldsSelected)
                Button(action: unselectAll) { Label("Unselect All", systemImage: "circle").font(.caption) }
                    .buttonStyle(.bordered)
                    .disabled(noFieldsSelected)
                Button(action: invertSelection) {
                    Label("Invert", systemImage: "arrow.triangle.2.circlepath").font(.caption)
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            Button(action: setDefaults) { Label("Defaults", systemImage: "arrow.uturn.backward").font(.caption) }
                .buttonStyle(.bordered)
            Toggle("Show Descriptions", isOn: $showingDescriptions).padding(.horizontal)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private func sectionHeader(
        _ category: SnapshotTimingFieldCategory,
        fields: [SnapshotTimingFieldConfig]
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                Text(category.description).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(selectedCount(fields))/\(fields.count)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func timingFieldRow(_ field: SnapshotTimingFieldConfig) -> some View {
        let isSelected = selectedFieldIds.contains(field.id)
        return Button {
            toggle(field)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.blue : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(field.displayName).font(.body)
                        if !field.unit.isEmpty {
                            Text(field.unit)
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.2)))
                        }
                    }
                    if showingDescriptions {
                        Text(field.description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        Text(field.calculation)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Selection

    private var allFieldsSelected: Bool { availableFields.allSatisfy { selectedFieldIds.contains($0.id) } }
    private var noFieldsSelected: Bool { !availableFields.contains { selectedFieldIds.contains($0.id) } }

    private func selectedCount(_ fields: [SnapshotTimingFieldConfig]) -> Int {
        fields.filter { selectedFieldIds.contains($0.id) }.count
    }

    private func toggle(_ field: SnapshotTimingFieldConfig) {
        if selectedFieldIds.contains(field.id) {
            selectedFieldIds.remove(field.id)
        } else if field.id == "notificationLatency" {
            showingLatencyWarning = true
        } else {
            selectedFieldIds.insert(field.id)
        }
    }

    private func selectAll() { selectedFieldIds = Set(availableFields.map(\.id)) }
    private func unselectAll() { selectedFieldIds.removeAll() }

    private func invertSelection() {
        selectedFieldIds.formSymmetricDifference(availableFields.map(\.id))
    }

    private func setDefaults() {
        selectedFieldIds = SnapshotTimingFieldConfig.defaultEnabledFieldIds(for: captureMode)
    }
}
