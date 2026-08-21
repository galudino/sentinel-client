//
//  SnapshotStartSessionView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// TODO(#17): full start-session flow (name, mode, duration, autosave).
struct SnapshotStartSessionView<Provider: SnapshotDataProvider>: View {
    typealias S = Provider.S

    let configuration: SnapshotLoggingConfiguration<S>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Start Session", systemImage: "play.circle")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
