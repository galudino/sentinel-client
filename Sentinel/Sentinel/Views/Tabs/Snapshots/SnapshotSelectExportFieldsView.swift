//
//  SnapshotSelectExportFieldsView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - SnapshotSelectExportFieldsView

/// Choose which data fields to include in an export, grouped by category with
/// search and select-all / invert helpers. Reuses ``SnapshotFieldSelectionRow``.
struct SnapshotSelectExportFieldsView<S: Snapshot>: View {
    let availableFieldKeyPaths: [String]
    @Binding var selectedFieldKeyPaths: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var expandedCategories: Set<S.Category> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                SnapshotSearchBar(text: $searchText).padding(.horizontal)
                fieldsList
            }
            .navigationTitle("Select Export Fields")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Text("\(selectedFieldKeyPaths.count) of \(availableFieldKeyPaths.count) fields selected")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 12) {
                Spacer()
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
                                isSelected: selectedFieldKeyPaths.contains(field.keyPath),
                                onToggle: { setSelected($0, keyPath: field.keyPath) }
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

    private func categoryLabel(_ category: S.Category, fields: [SnapshotFieldConfig<S>]) -> some View {
        HStack {
            Button { toggleCategory(fields: fields) } label: {
                Image(systemName: categorySelectionState(fields: fields))
                    .foregroundStyle(isCategoryFullySelected(fields) ? Color.blue : .secondary)
            }
            .buttonStyle(.plain)
            Text(category.displayName).font(.headline)
            Spacer()
            Text("\(selectedCount(fields))/\(fields.count)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func expansionBinding(for category: S.Category) -> Binding<Bool> {
        Binding(
            get: { expandedCategories.contains(category) },
            set: { isExpanded in
                if isExpanded { expandedCategories.insert(category) } else { expandedCategories.remove(category) }
            }
        )
    }
}

// MARK: - Fields + selection

extension SnapshotSelectExportFieldsView {
    private var availableFields: [SnapshotFieldConfig<S>] {
        S.availableFields().filter { availableFieldKeyPaths.contains($0.keyPath) }
    }

    private var filteredFieldsByCategory: [S.Category: [SnapshotFieldConfig<S>]] {
        let filtered = searchText.isEmpty ? availableFields : availableFields.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.dataDescription.localizedCaseInsensitiveContains(searchText)
                || $0.category.displayName.localizedCaseInsensitiveContains(searchText)
        }
        return Dictionary(grouping: filtered, by: \.category)
    }

    private var categoriesInOrder: [S.Category] {
        S.Category.allCases.filter { filteredFieldsByCategory[$0] != nil }
    }

    private var filteredFields: [SnapshotFieldConfig<S>] { filteredFieldsByCategory.values.flatMap { $0 } }

    private var allFilteredFieldsSelected: Bool {
        let filtered = filteredFields
        guard !filtered.isEmpty else { return true }
        return filtered.allSatisfy { selectedFieldKeyPaths.contains($0.keyPath) }
    }

    private var noFilteredFieldsSelected: Bool {
        !filteredFields.contains { selectedFieldKeyPaths.contains($0.keyPath) }
    }

    private func setSelected(_ selected: Bool, keyPath: String) {
        if selected { selectedFieldKeyPaths.insert(keyPath) } else { selectedFieldKeyPaths.remove(keyPath) }
    }

    private func selectAllFilteredFields() {
        for field in filteredFields {
            selectedFieldKeyPaths.insert(field.keyPath)
        }
    }

    private func unselectAllFilteredFields() {
        selectedFieldKeyPaths.subtract(Set(filteredFields.map(\.keyPath)))
    }

    private func invertFilteredSelection() {
        for field in filteredFields {
            setSelected(!selectedFieldKeyPaths.contains(field.keyPath), keyPath: field.keyPath)
        }
    }

    private func toggleCategory(fields: [SnapshotFieldConfig<S>]) {
        if isCategoryFullySelected(fields) {
            for field in fields {
                selectedFieldKeyPaths.remove(field.keyPath)
            }
        } else {
            for field in fields {
                selectedFieldKeyPaths.insert(field.keyPath)
            }
        }
    }

    private func isCategoryFullySelected(_ fields: [SnapshotFieldConfig<S>]) -> Bool {
        fields.allSatisfy { selectedFieldKeyPaths.contains($0.keyPath) }
    }

    private func selectedCount(_ fields: [SnapshotFieldConfig<S>]) -> Int {
        fields.filter { selectedFieldKeyPaths.contains($0.keyPath) }.count
    }

    private func categorySelectionState(fields: [SnapshotFieldConfig<S>]) -> String {
        let selected = selectedCount(fields)
        if selected == fields.count { return "checkmark.circle.fill" }
        if selected > 0 { return "minus.circle.fill" }
        return "circle"
    }
}
