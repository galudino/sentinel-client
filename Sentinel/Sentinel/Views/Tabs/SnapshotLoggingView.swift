//
//  SnapshotLoggingView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import SwiftUI

/// The **Snapshots** tab — snapshot history + live capture session.
///
/// **Stub for #14.** The real snapshot browser (history via `peer.snapshotHistory`
/// + live stream via `peer.snapshotStream`, decoded to `DeviceSnapshot` from #10)
/// lands in **#17**.
struct SnapshotLoggingView: View {
    let peer: ConnectedPeer

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Device Snapshots",
                systemImage: "camera.aperture",
                description: Text("Persisted snapshot history and live capture arrive in #17.")
            )
            .navigationTitle("Snapshots")
        }
    }
}

#Preview {
    SnapshotLoggingView(peer: ConnectedPeer(name: "Sentinel"))
}
