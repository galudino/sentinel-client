//
//  SnapshotFieldSelectionRow.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - SnapshotFieldSelectionRow

/// A selectable field row in the create-config / export pickers: checkbox, name,
/// unit + data-type chips, and a description.
struct SnapshotFieldSelectionRow<S: Snapshot>: View {
    let field: SnapshotFieldConfig<S>
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isSelected)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.blue : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(field.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        if !field.unit.isEmpty {
                            Text(field.unit)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .foregroundStyle(.green)
                                .cornerRadius(4)
                        }

                        Spacer()

                        Text(field.dataType.rawValue)
                            .font(.caption2)
                            .monospaced()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(4)
                    }

                    Text(field.dataDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
