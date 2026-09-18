//
//  DebugOutputStreamView+ConnectHeader.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 9/17/26.
//

import SwiftUI

// MARK: - Pinned connect header

/// The debug console's pinned header (#25): discovered peripherals with a per-row
/// Connect / Cancel / Retry control that's a pure function of ``AppRouter/state``,
/// collapsing to a compact strip once connected. Pinned above the scrolling log so
/// the control never scrolls out of reach while lines stream.
extension DebugOutputStreamView {
    @ViewBuilder var connectHeader: some View {
        switch router.state {
        case let .connected(peer), let .updatingFirmware(peer, _):
            connectedStrip(peer)
        default:
            discoveredTargets
        }
    }

    private var discoveredTargets: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Discovered", systemImage: "dot.radiowaves.left.and.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if bluetoothManager.isScanning {
                    ProgressView().controlSize(.mini)
                }
            }
            if bluetoothManager.discoveredPeripherals.isEmpty {
                Text("Searching for devices…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bluetoothManager.discoveredPeripherals) { item in
                    targetRow(item)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func targetRow(_ item: PeripheralScanItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name ?? "Unknown Device")
                    .font(.subheadline.weight(.medium))
                Text("\(item.rssi) dBm")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            targetControl(for: item)
        }
    }

    /// The trailing control for a discovered row — a pure function of the router's
    /// connection state. Only the peripheral being connected is actionable; the
    /// others are disabled (the router guards `beginConnect` to `.scanning`, so a
    /// tap would no-op — disabling makes that truthful).
    @ViewBuilder private func targetControl(for item: PeripheralScanItem) -> some View {
        switch router.state {
        case .scanning:
            connectButton(item)

        case let .connecting(id):
            if id == item.id {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Button(role: .destructive) {
                        router.cancelConnect()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                connectButton(item, disabled: true)
            }

        case let .connectFailed(id, message):
            if id == item.id {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(message)
                    Button {
                        router.retryConnect()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button {
                        router.dismissConnectError()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("Dismiss error")
                }
            } else {
                connectButton(item, disabled: true)
            }

        case .connected, .updatingFirmware:
            EmptyView()
        }
    }

    private func connectButton(_ item: PeripheralScanItem, disabled: Bool = false) -> some View {
        Button {
            router.beginConnect(peripheralID: item.id, name: item.name)
        } label: {
            Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(disabled)
        .accessibilityLabel("Connect to \(item.name ?? "device")")
    }

    /// Compact strip shown once connected: identity + link metric, the device-output
    /// streaming toggle (same persisted flag as Settings), and a Disconnect button.
    private func connectedStrip(_ peer: ConnectedPeer) -> some View {
        @Bindable var prefs = prefs
        return HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Connected — \(peer.name ?? "Sentinel")")
                    .font(.subheadline.weight(.medium))
                Text("MTU \(peer.negotiatedMTU)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle(isOn: $prefs.debugModeEnabled) {
                Text("Device output").font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .fixedSize()
            Button(role: .destructive) {
                router.disconnect()
            } label: {
                Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .labelStyle(.iconOnly)
            .tint(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}
