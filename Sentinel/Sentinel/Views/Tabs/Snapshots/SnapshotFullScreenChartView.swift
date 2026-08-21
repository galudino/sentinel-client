//
//  SnapshotFullScreenChartView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// TODO(#17): interactive full-screen chart with viewport-aware re-decimation,
// debounced scrub/zoom, and rolling live window.
struct SnapshotFullScreenChartView: View {
    let session: SnapshotLoggingSession
    let leftAxisFieldKeyPath: String?
    let rightAxisFieldKeyPath: String?
    let selectedBooleanKeyPaths: Set<String>
    var onViewLoaded: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Full-Screen Chart", systemImage: "chart.xyaxis.line")
                .navigationTitle(session.name)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear(perform: onViewLoaded)
    }
}
