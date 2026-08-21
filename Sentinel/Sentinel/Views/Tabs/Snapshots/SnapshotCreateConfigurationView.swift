//
//  SnapshotCreateConfigurationView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - SnapshotCreateConfigurationView

/// Create a named logging configuration: pick a capture mode (and interval for
/// polling) and choose which fields to log, grouped by category with
/// select-all / invert helpers and search.
struct SnapshotCreateConfigurationView<Provider: SnapshotDataProvider>: View {
    typealias SnapshotType = Provider.SnapshotType

    @Environment(SnapshotLoggingManager<Provider>.self) private var loggingManager
    @Environment(\.dismiss) private var dismiss

    @State private var configurationName = ""
    @State private var selectedFields: [SnapshotFieldConfig<SnapshotType>] = []
    @State private var captureMode: SnapshotCaptureMode = .notifications
    @State private var pollingInterval: Double = 0.3
    @State private var searchText = ""
    @State private var expandedCategories: Set<SnapshotType.Category> = []
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                detailsHeader
                fieldSelectionHeader
                fieldsList
            }
            .navigationTitle("New Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveConfiguration)
                        .disabled(configurationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Validation Error", isPresented: .constant(validationMessage != nil)) {
                Button("OK") { validationMessage = nil }
            } message: {
                Text(validationMessage ?? "")
            }
        }
    }

    // MARK: Header sections

    private var detailsHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Configuration Name").font(.headline)
                TextField("Enter configuration name", text: $configurationName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Capture Mode").font(.headline)
                Picker("Capture Mode", selection: $captureMode) {
                    ForEach(SnapshotCaptureMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if captureMode == .polling {
                    HStack {
                        Text("Interval")
                        Spacer()
                        Text("\(String(format: "%.1f", pollingInterval)) s").foregroundStyle(.secondary)
                    }
                    Slider(value: $pollingInterval, in: 0.1 ... 5.0, step: 0.1)
                }

                Text(captureMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private var fieldSelectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                let count = selectedFields.count
                Text("\(count) \(count == 1 ? "field" : "fields") selected").foregroundStyle(.secondary)
                Spacer()
            }

            SnapshotSearchBar(text: $searchText)

            HStack(spacing: 12) {
                Button(action: selectAllFilteredFields) {
                    Label("Select All", systemImage: "checkmark.circle.fill").font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(filteredFields.isEmpty || allFilteredFieldsSelected)

                Button(action: unselectAllFilteredFields) {
                    Label("Unselect All", systemImage: "circle").font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(filteredFields.isEmpty || noFilteredFieldsSelected)

                Button(action: invertFilteredSelection) {
                    Label("Invert", systemImage: "arrow.triangle.2.circlepath").font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(filteredFields.isEmpty)

                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private var fieldsList: some View {
        List {
            ForEach(categoriesInOrder) { category in
                if let fields = filteredFieldsByCategory[category] {
                    DisclosureGroup(isExpanded: expansionBinding(for: category)) {
                        ForEach(fields) { field in
                            SnapshotFieldSelectionRow(
                                field: field,
                                isSelected: isSelected(field),
                                onToggle: { setSelected($0, field: field) }
                            )
                        }
                    } label: {
                        categoryLabel(category, fields: fields)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func categoryLabel(
        _ category: SnapshotType.Category,
        fields: [SnapshotFieldConfig<SnapshotType>]
    ) -> some View {
        HStack {
            Button {
                toggleCategory(fields: fields)
            } label: {
                Image(systemName: categorySelectionState(fields: fields))
                    .foregroundStyle(isCategoryFullySelected(fields) ? Color.blue : .secondary)
            }
            .buttonStyle(.plain)

            Text(category.displayName).font(.headline)
            Spacer()
            Text("\(selectedFieldsCount(fields))/\(fields.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func expansionBinding(for category: SnapshotType.Category) -> Binding<Bool> {
        Binding(
            get: { expandedCategories.contains(category) },
            set: { isExpanded in
                if isExpanded { expandedCategories.insert(category) } else { expandedCategories.remove(category) }
            }
        )
    }
}

// MARK: - Field grouping + selection

extension SnapshotCreateConfigurationView {
    private var filteredFieldsByCategory: [SnapshotType.Category: [SnapshotFieldConfig<SnapshotType>]] {
        let all = SnapshotType.availableFields()
        let filtered = searchText.isEmpty ? all : all.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.dataDescription.localizedCaseInsensitiveContains(searchText)
                || $0.category.displayName.localizedCaseInsensitiveContains(searchText)
        }
        return Dictionary(grouping: filtered, by: \.category)
    }

    private var categoriesInOrder: [SnapshotType.Category] {
        SnapshotType.Category.allCases.filter { filteredFieldsByCategory[$0] != nil }
    }

    private var filteredFields: [SnapshotFieldConfig<SnapshotType>] {
        filteredFieldsByCategory.values.flatMap { $0 }
    }

    private var allFilteredFieldsSelected: Bool {
        let filtered = filteredFields
        guard !filtered.isEmpty else { return true }
        return filtered.allSatisfy(isSelected)
    }

    private var noFilteredFieldsSelected: Bool {
        !filteredFields.contains(where: isSelected)
    }

    private func isSelected(_ field: SnapshotFieldConfig<SnapshotType>) -> Bool {
        selectedFields.contains { $0.keyPath == field.keyPath }
    }

    private func setSelected(_ selected: Bool, field: SnapshotFieldConfig<SnapshotType>) {
        if selected {
            if !isSelected(field) { selectedFields.append(field) }
        } else {
            selectedFields.removeAll { $0.keyPath == field.keyPath }
        }
    }

    private func selectAllFilteredFields() {
        for field in filteredFields where !isSelected(field) {
            selectedFields.append(field)
        }
    }

    private func unselectAllFilteredFields() {
        let keyPaths = Set(filteredFields.map(\.keyPath))
        selectedFields.removeAll { keyPaths.contains($0.keyPath) }
    }

    private func invertFilteredSelection() {
        for field in filteredFields {
            setSelected(!isSelected(field), field: field)
        }
    }

    private func toggleCategory(fields: [SnapshotFieldConfig<SnapshotType>]) {
        if isCategoryFullySelected(fields) {
            for field in fields {
                selectedFields.removeAll { $0.keyPath == field.keyPath }
            }
        } else {
            for field in fields where !isSelected(field) {
                selectedFields.append(field)
            }
        }
    }

    private func isCategoryFullySelected(_ fields: [SnapshotFieldConfig<SnapshotType>]) -> Bool {
        fields.allSatisfy(isSelected)
    }

    private func selectedFieldsCount(_ fields: [SnapshotFieldConfig<SnapshotType>]) -> Int {
        fields.filter(isSelected).count
    }

    private func categorySelectionState(fields: [SnapshotFieldConfig<SnapshotType>]) -> String {
        let selected = selectedFieldsCount(fields)
        if selected == fields.count { return "checkmark.circle.fill" }
        if selected > 0 { return "minus.circle.fill" }
        return "circle"
    }

    private func saveConfiguration() {
        let trimmedName = configurationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Please enter a configuration name."
            return
        }
        guard !selectedFields.isEmpty else {
            validationMessage = "Please select at least one field to log."
            return
        }
        loggingManager.saveConfiguration(SnapshotLoggingConfiguration(
            name: trimmedName,
            selectedFields: selectedFields,
            pollingInterval: pollingInterval,
            captureMode: captureMode
        ))
        dismiss()
    }
}
