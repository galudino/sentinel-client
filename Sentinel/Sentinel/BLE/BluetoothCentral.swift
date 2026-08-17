//
//  BluetoothCentral.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation

/// The *central*'s connect/disconnect surface, as seen by ``AppRouter``.
///
/// `AppRouter` drives the navigation state machine off the outcome of a connect;
/// it does not need — and should not import — the `AsyncBluetooth` `Peripheral`
/// type. Keeping the router behind this protocol does two things:
///
/// 1. **Keeps the state machine pure.** The router speaks in `UUID`s (the peer
///    identity carried through `.connecting`); ``BluetoothManager`` resolves the
///    `UUID` to a live `Peripheral` from its own scan list and performs the real
///    connect.
/// 2. **Keeps the router unit-testable.** A real BLE connect can never reach
///    `.connected` in a unit test (no hardware, no constructible `Peripheral`).
///    Tests inject a `MockBluetoothCentral` that returns a detached
///    ``ConnectedPeer``, so every transition stays exercisable off-device.
///
/// Production injects the real ``BluetoothManager``; both conform.
///
/// `Sendable` so the `any BluetoothCentral` existential can be called from
/// `AppRouter`'s `@MainActor` connect task into the central's nonisolated async
/// `connect` (conformers are `@unchecked Sendable` for Phase I; see #24).
protocol BluetoothCentral: AnyObject, Sendable {
    /// Connect to the peripheral with the given identity (resolved from the
    /// discovered scan list), discover its services, and return the active
    /// ``ConnectedPeer``. Throws if no such peripheral is known or the link fails.
    func connect(peripheralID: UUID, name: String?) async throws -> ConnectedPeer

    /// Abort an in-flight connect to the given peripheral (user cancel / timeout),
    /// tearing down any half-open link. Safe to call even if nothing is pending.
    func cancelConnect(peripheralID: UUID) async

    /// Tear down the active connection and release the peer.
    func disconnect(_ peer: ConnectedPeer) async throws
}
