//
//  SnapshotSessionChartView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// TODO(#17): per-session multi-field chart with viewport-aware decimation.
struct SnapshotSessionChartView<Provider: SnapshotDataProvider>: View {
    let session: SnapshotLoggingSession

    var body: some View {
        ContentUnavailableView("Session Chart", systemImage: "chart.xyaxis.line")
            .navigationTitle(session.name)
    }
}
