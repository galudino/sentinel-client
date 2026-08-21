//
//  SnapshotCompletedSessionRowView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import SwiftUI

// TODO(#17): summary, chart navigation, export, rename.
struct SnapshotCompletedSessionRowView<Provider: SnapshotDataProvider>: View {
    let session: SnapshotLoggingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.name).font(.headline)
            Text("\(session.entryCount) entries").font(.caption).foregroundStyle(.secondary)
        }
    }
}
