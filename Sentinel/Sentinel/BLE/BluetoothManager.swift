//
//  BluetoothManager.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation
import Observation

/// The BLE *central*: scans, connects, and tracks connection state. One per app,
/// injected app-wide (no singletons). Does **not** do characteristic I/O and does
/// **not** retain the connected peripheral — `connect()` *returns* a
/// ``ConnectedPeer`` that owns the active connection.
///
/// **Seed for #7 (navigation state machine).** Only the surface the router needs
/// is present: a `connect()` that vends a ``ConnectedPeer`` and a `disconnect()`.
/// Issue #8 builds the real central on top of `AsyncBluetooth` — scanning,
/// discovered-peripheral list, service/characteristic discovery, MTU negotiation,
/// and the structured BLE event stream (`DebugOutputStreamView`, #25). See
/// `docs/architecture/architecture.md`.
///
/// `@unchecked Sendable` is an intentional Phase I concession; strict-concurrency
/// hardening is tracked in #24.
@Observable
final class BluetoothManager: @unchecked Sendable {
    /// High-level connection lifecycle, surfaced for UI. The router derives
    /// ``AppState`` from user intent; this enum is the central's own view of the
    /// link and will grow in #8.
    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting(peripheralID: UUID)
        case connected(peripheralID: UUID)
        case disconnecting
    }

    private(set) var connectionState: ConnectionState = .disconnected

    init() {}

    /// Connect to a peripheral (by identity, for now), discover its services, and
    /// return the active ``ConnectedPeer``.
    ///
    /// - Note: Seed implementation — synthesizes a ``ConnectedPeer`` so the
    ///   navigation flow is exercisable end to end. #8 replaces this with the real
    ///   `AsyncBluetooth` connect + service discovery and takes an actual
    ///   `Peripheral`.
    func connect(peripheralID: UUID, name: String? = nil) async throws -> ConnectedPeer {
        connectionState = .connecting(peripheralID: peripheralID)
        let peer = ConnectedPeer(id: peripheralID, name: name)
        connectionState = .connected(peripheralID: peripheralID)
        return peer
    }

    /// Tear down the active connection and release the peer.
    ///
    /// - Note: Seed implementation. #8 performs the real `AsyncBluetooth`
    ///   disconnect.
    func disconnect(_ peer: ConnectedPeer) async throws {
        connectionState = .disconnecting
        connectionState = .disconnected
    }
}
