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
                FirmwareUpdateView(peer: peer, image: image)
                    .environment(peer)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: router.state)
    }
}

#if DEBUG
    /// The full app flow, drivable in the preview canvas: starts at
    /// `PeripheralScanView` with a seeded "Sentinel" in range → tap it → `ConnectingView`
    /// → a populated `MainTabView`. The router's central is a ``PreviewBluetoothCentral``
    /// (fakes connect → `ConnectedPeer.preview()`); the scan list comes from a
    /// `BluetoothManager.preview(...)`. All app-wide environment objects are injected
    /// so every branch of the tree can render.
    #Preview("Full flow") {
        RootView()
            .environment(AppRouter(bluetoothManager: PreviewBluetoothCentral()))
            .environment(BluetoothManager.preview(discovered: [
                PeripheralScanItem(previewName: "Sentinel", rssi: -47, lastUpdated: .now.addingTimeInterval(-1))
            ]))
            .environment(AppPreferences())
            .environment(PairedPeerStore.preview(peers: []))
            .environment(ImportedFirmwareStore())
    }

    /// Straight into the connected tabs — a populated `MainTabView` reached through
    /// `RootView` (zero-delay fake connect, so it lands on the tabs immediately).
    #Preview("Connected (populated)") {
        @Previewable @State var router = AppRouter(bluetoothManager: PreviewBluetoothCentral(connectDelay: .zero))
        RootView()
            .environment(router)
            .environment(BluetoothManager.preview(discovered: []))
            .environment(AppPreferences())
            .environment(PairedPeerStore.preview(peers: []))
            .environment(ImportedFirmwareStore())
            .task { router.beginConnect(peripheralID: UUID(), name: "Sentinel") }
    }
#endif
