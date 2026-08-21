//
//  SnapshotActiveSessionRowView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// TODO(#17): live entry count, elapsed time, timing stats, stop control.
struct SnapshotActiveSessionRowView<Provider: SnapshotDataProvider>: View {
    let session: SnapshotLoggingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.name).font(.headline)
            Text("Running…").font(.caption).foregroundStyle(.secondary)
        }
    }
}
