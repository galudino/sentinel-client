//
//  ConnectedPeer.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation
import Observation

/// One *active* BLE connection — the transport + service namespace for a peer
/// that is currently connected.
///
/// **Seed for #7 (navigation state machine).** This is the minimal shape the
/// router needs: a stable identity and a display name. Issue #8 expands it into
/// the real active-connection type described in `docs/architecture/architecture.md`
/// — owning the AsyncBluetooth `Peripheral`, conforming to
/// `BluetoothPeripheralTransport`, holding live per-connection state (RSSI/MTU),
/// and vending the per-service clients (`bme280`, `ds3231`, `snapshotStream`, …).
/// The router carries a `ConnectedPeer` in `.connected` / `.updatingFirmware`
/// and `RootView` injects it into the connected subtree only, so "this
/// connection exists only while connected" is a structural invariant, not an
/// optional guard.
@Observable
final class ConnectedPeer: Identifiable {
    /// The peripheral's stable identifier (`CBPeripheral.identifier`). Matches
    /// the `peripheralID` carried through `.connecting`.
    let id: UUID

    /// Advertised / GAP name, when known. Display-only.
    let name: String?

    init(id: UUID = UUID(), name: String? = nil) {
        self.id = id
        self.name = name
    }
}

// MARK: Equatable (identity)

extension ConnectedPeer: Equatable {
    /// A connection is defined by object identity: two references are the same
    /// connection iff they are the same instance. This is what lets `AppState`
    /// be `Equatable` (see `AppRouter`).
    static func == (lhs: ConnectedPeer, rhs: ConnectedPeer) -> Bool {
        lhs === rhs
    }
}
