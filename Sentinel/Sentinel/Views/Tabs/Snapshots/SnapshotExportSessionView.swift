//
//  SnapshotExportSessionView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// TODO(#17): full export flow (format, field/timing selection, preview, share).
struct SnapshotExportSessionView<Provider: SnapshotDataProvider>: View {
    let session: SnapshotLoggingSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Export Session", systemImage: "square.and.arrow.up")
                .navigationTitle(session.name)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
