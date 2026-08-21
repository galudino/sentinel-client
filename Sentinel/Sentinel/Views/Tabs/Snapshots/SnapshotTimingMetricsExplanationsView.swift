//
//  SnapshotTimingMetricsExplanationsView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// TODO(#17): grouped explanations of every capture-timing metric.
struct SnapshotTimingMetricsExplanationsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Timing Metrics", systemImage: "info.circle")
                .navigationTitle("Timing Metrics")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
