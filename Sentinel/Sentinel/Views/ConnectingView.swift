//
//  ConnectingView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import SwiftUI

/// Shown while a BLE connection is in flight (`.connecting`) and when it fails
/// (`.connectFailed`). Purely presentational: the **router** owns the connect
/// sequence (`AppRouter.beginConnect` → `BluetoothManager.connect`, with a 15 s
/// timeout), so this view only reflects progress and offers Cancel / Retry.
///
/// Progress text tracks the central's live ``BluetoothManager/ConnectionState``
/// (Connecting → Discovering services). There is no separate "subscribing to
/// telemetry" phase: notification subscription is lazy, done per-view when a
/// telemetry screen opens — so it isn't part of the connect handshake.
struct ConnectingView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BluetoothManager.self) private var bluetoothManager

    var body: some View {
        Group {
            if case let .connectFailed(_, message) = router.state {
                ConnectingFailureContent(
                    message: message,
                    onRetry: { router.retryConnect() },
                    onBackToScan: { router.dismissConnectError() }
                )
            } else {
                ConnectingProgressContent(
                    statusText: statusText,
                    onCancel: { router.cancelConnect() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: String {
        switch bluetoothManager.connectionState {
        case .discoveringServices: "Discovering services…"
        case .connected: "Connected"
        default: "Connecting to \(deviceName)…"
        }
    }

    /// The name of the peripheral being connected, resolved from the scan list.
    private var deviceName: String {
        guard case let .connecting(peripheralID) = router.state,
              let item = bluetoothManager.discoveredPeripherals.first(where: { $0.id == peripheralID })
        else { return "device" }
        return item.name ?? "device"
    }
}

/// In-flight progress: spinner + phase text + Cancel. Standalone so it previews
/// with any status string.
private struct ConnectingProgressContent: View {
    let statusText: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(statusText)
                .font(.headline)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
        }
        .padding()
    }
}

/// Failure state: message + Try Again + Back to Scan. Standalone so it previews
/// with any message.
private struct ConnectingFailureContent: View {
    let message: String
    let onRetry: () -> Void
    let onBackToScan: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text("Couldn't Connect")
                    .font(.title3.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again", systemImage: "arrow.clockwise", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
            Spacer()
            Button("Back to Scan", role: .cancel, action: onBackToScan)
        }
        .padding()
    }
}

#Preview("Connecting") {
    ConnectingProgressContent(statusText: "Connecting to Sentinel…", onCancel: {})
}

#Preview("Discovering") {
    ConnectingProgressContent(statusText: "Discovering services…", onCancel: {})
}

#Preview("Failed") {
    ConnectingFailureContent(
        message: "The connection timed out. Move closer to the device and try again.",
        onRetry: {},
        onBackToScan: {}
    )
}
