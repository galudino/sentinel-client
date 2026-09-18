//
//  SnapshotSearchBar.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - SnapshotSearchBar

/// A compact inline search field used to filter long field lists in the
/// create-config and export-field pickers.
struct SnapshotSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search fields", text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button("Clear") { text = "" }
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    SnapshotSearchBar(text: .constant("temp"))
        .padding()
}
