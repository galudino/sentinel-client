//
//  RootView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import SwiftUI

/// The app root: renders exactly one screen for the current ``AppState``.
///
/// There is deliberately **no single outer `NavigationStack`** wrapping the
/// whole switch. A nav stack belongs around the scan/connect screens (so
/// `PeripheralScanView` can push, e.g. the Debug stream, #25) but must **not**
/// wrap `MainTabView` — the tab bar's tabs own their own stacks (#14). So each
/// branch supplies the navigation container that fits it:
///
/// - `.scanning` / `.connecting` → their own `NavigationStack`
/// - `.connected` → `MainTabView` (a `TabView`; no outer stack)
/// - `.updatingFirmware` → a bare full-screen escape hatch (no tab bar)
///
/// `ConnectedPeer` is injected via `.environment(_:)` into the connected
/// branches **only**, so views under `MainTabView` / `FirmwareUpdateView` can
/// `@Environment(ConnectedPeer.self)` and trust it exists, while scanning /
/// connecting views structurally cannot reach a peer. "The connection exists
/// only while connected" is enforced by the view tree, not by optionals.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PairedPeerStore.self) private var pairedPeerStore

    var body: some View {
        ZStack {
            switch router.state {
            case .scanning:
                NavigationStack {
                    PeripheralScanView()
                }
                .transition(.opacity)

            case .connecting, .connectFailed:
                ConnectingView()
                    .transition(.opacity)

            case let .connected(peer):
                MainTabView()
                    .environment(peer) // ConnectedPeer visible only here
                    .transition(.opacity)
                    // Register-on-connect: a successful connection trusts the peer
                    // so it surfaces in PeripheralScanView (#12) + SettingsView (#19).
                    .task(id: peer.id) {
                        pairedPeerStore.register(id: peer.id, name: peer.name)
                    }

            case let .updatingFirmware(peer, image):
                FirmwareUpdateView(image: image)
                    .environment(peer)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: router.state)
    }
}

#Preview {
    RootView()
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
        .environment(PairedPeerStore.preview(peers: []))
}
