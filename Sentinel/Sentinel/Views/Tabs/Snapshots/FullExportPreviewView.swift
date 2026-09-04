//
//  FullExportPreviewView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// MARK: - FullExportPreviewView

/// A full, scrollable preview of an export's text output, rendered with the
/// lazy ``LargeTextView`` so even a very large CSV/JSON stays smooth. Offers a
/// copy-to-clipboard action.
struct FullExportPreviewView: View {
    let text: String
    let title: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LargeTextView(text: text)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            UIPasteboard.general.string = text
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel("Copy")
                    }
                }
        }
    }
}
