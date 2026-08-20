//
//  PreviewBluetoothCentral.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/20/26.
//

#if DEBUG
    import Foundation

    /// A ``BluetoothCentral`` for SwiftUI previews: instead of touching CoreBluetooth
    /// it fakes the connect handshake and hands back a fully-seeded
    /// ``ConnectedPeer/preview(name:rssi:mtu:)``. Injected into ``AppRouter`` so a
    /// `RootView` preview can be driven end to end — tap a device in
    /// `PeripheralScanView`, watch `ConnectingView`, land in a populated
    /// `MainTabView` — all without a live BLE link.
    ///
    /// The scan **list** itself still comes from a `BluetoothManager.preview(...)`
    /// injected into the environment (that's what `PeripheralScanView` reads); this
    /// object only fulfils the router's connect intent.
    final class PreviewBluetoothCentral: BluetoothCentral, @unchecked Sendable {
        /// How long `connect` pretends to take, so `ConnectingView` is visible.
        private let connectDelay: Duration

        init(connectDelay: Duration = .seconds(1)) {
            self.connectDelay = connectDelay
        }

        func connect(peripheralID _: UUID, name: String?) async throws -> ConnectedPeer {
            try? await Task.sleep(for: connectDelay)
            return .preview(name: name ?? "Sentinel")
        }

        func reconnect(peripheralID _: UUID, name: String?) async throws -> ConnectedPeer {
            try? await Task.sleep(for: connectDelay)
            return .preview(name: name ?? "Sentinel")
        }

        func cancelConnect(peripheralID _: UUID) async {}
        func disconnect(_: ConnectedPeer) async throws {}
    }
#endif
