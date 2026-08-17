//
//  ConnectingView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import SwiftUI

/// Transient screen shown while the central connects and discovers services.
/// The router advances to `.connected` on success or falls back to `.scanning`
/// on failure — this view only reflects progress and offers a cancel.
///
/// **Stub for #7.** Real connection-phase detail (service-discovery progress,
/// timeout, retry) lands in **#13**.
struct ConnectingView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting…")
                .font(.headline)
            Button("Cancel", role: .cancel) {
                router.connectFailed()
            }
        }
        .padding()
    }
}

#Preview {
    ConnectingView()
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
}
