//
//  FirmwareUpdateView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import SwiftUI

/// The OTA DFU escape hatch — a single full-screen view that deliberately leaves
/// `MainTabView` (no tab bar) while firmware uploads. Driven by the OTA uploader
/// (#22). Cancel returns to `.connected` (same peer); a completed update also
/// returns to `.connected`.
///
/// **Stub for #7.** The real progress UI, CRC/verify, point-of-no-return cancel
/// gating, and the device-reset→reconnect handshake land in **#21** (+ #22).
struct FirmwareUpdateView: View {
    /// The payload being flashed — carried into `.updatingFirmware` by the router.
    let image: FirmwareImage

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.up.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .foregroundStyle(.tint)

            Text("Updating Firmware")
                .font(.title2.bold())
            Text("Version \(image.version)")
                .foregroundStyle(.secondary)

            ProgressView()
                .controlSize(.large)
                .padding(.vertical, 8)

            // Seed controls. #21 gates cancel after the point of no return and
            // drives completion from the uploader (#22), not a button.
            HStack(spacing: 16) {
                Button("Cancel", role: .cancel) {
                    router.cancelFirmwareUpdate()
                }
                Button("Simulate Completion") {
                    router.firmwareUpdateCompleted()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

#Preview {
    FirmwareUpdateView(image: FirmwareImage(version: "1.1.0"))
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
        .environment(ConnectedPeer(name: "Sentinel"))
}
