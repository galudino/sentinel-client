//
//  LogsView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import SwiftUI

/// The **Logs** tab — System Event Log retrieval.
///
/// **Stub for #14.** The real event-log browser (paged retrieval + the
/// `SystemEventRecord` display API from #11) lands in **#16**, built against
/// `peer.systemEventLog`.
struct LogsView: View {
    let peer: ConnectedPeer

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "System Event Log",
                systemImage: "list.bullet.rectangle",
                description: Text("Retrieved device events (boot, faults, BLE, firmware updates) arrive in #16.")
            )
            .navigationTitle("Logs")
        }
    }
}

#Preview {
    LogsView(peer: ConnectedPeer(name: "Sentinel"))
}
