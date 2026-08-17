//
//  AppRouter.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation
import Observation

/// The app-level navigation state — four states driven by the BLE connection
/// lifecycle. This is the single source of truth for *which root screen* is on
/// screen; `RootView` renders exactly one branch per case.
///
/// ```
/// .scanning         → PeripheralScanView   (entry — "log in")
/// .connecting       → ConnectingView       (connect + service discovery)
/// .connected        → MainTabView          (live operating mode — tabbed)
/// .updatingFirmware → FirmwareUpdateView   (single-view escape hatch; DFU)
/// ```
///
/// `ConnectedPeer` is carried in `.connected` / `.updatingFirmware` and is the
/// single owner of the active connection — there is no duplicate peripheral box
/// on ``BluetoothManager``.
enum AppState: Equatable {
    case scanning
    case connecting(peripheralID: UUID)
    case connected(peer: ConnectedPeer)
    case updatingFirmware(peer: ConnectedPeer, payload: FirmwareImage)
}

/// The five tabs of `MainTabView` (#14). The *selection* lives here on the
/// router rather than in `MainTabView`'s local `@State` so it survives the view
/// being torn down and rebuilt — e.g. a DFU round-trip (`.connected` →
/// `.updatingFirmware` → `.connected`) or a disconnect/reconnect within a
/// session. `MainTabView` binds to ``AppRouter/selectedTab``.
enum MainTab: String, CaseIterable, Identifiable {
    case home
    case logs
    case snapshots
    case device
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .logs: "Logs"
        case .snapshots: "Snapshots"
        case .device: "Device"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .logs: "list.bullet.rectangle"
        case .snapshots: "camera.viewfinder"
        case .device: "cpu.fill"
        case .settings: "gearshape.fill"
        }
    }
}

/// The app-level state machine. `@Observable`, created once in `SentinelApp`,
/// injected app-wide, and read by `RootView`.
///
/// **Views never mutate `state` directly** — they call the intent methods here
/// (`beginConnect`, `didDisconnect`, `startFirmwareUpdate`, …). Every transition
/// is guarded so illegal moves are no-ops rather than invalid states.
@MainActor
@Observable
final class AppRouter {
    /// The BLE central (#8). The router owns the *intent* to connect; the central
    /// performs it and returns a ``ConnectedPeer``. Held behind the
    /// ``BluetoothCentral`` protocol so the state machine stays free of any
    /// `AsyncBluetooth` type and is unit-testable against a mock central.
    let bluetoothManager: any BluetoothCentral

    /// The current root state. Externally read-only — mutated only through the
    /// intent methods below.
    private(set) var state: AppState = .scanning

    /// Selected `MainTabView` tab. Lives on the router (not the tab view) so it
    /// persists across reconnects within a session. Reset only happens on a fresh
    /// app launch (a new `AppRouter`).
    var selectedTab: MainTab = .home

    init(bluetoothManager: any BluetoothCentral) {
        self.bluetoothManager = bluetoothManager
    }

    // MARK: Intents

    /// User picked a peripheral in `PeripheralScanView` (#12): enter
    /// `.connecting`, then connect + discover services off the main actor. On
    /// success advance to `.connected`; on failure fall back to `.scanning`.
    ///
    /// - Note: Takes a peripheral identifier for now; #8 wires the real
    ///   `AsyncBluetooth` `Peripheral` from the scan list through here.
    func beginConnect(peripheralID: UUID, name: String? = nil) {
        guard case .scanning = state else { return }
        state = .connecting(peripheralID: peripheralID)

        Task {
            do {
                let peer = try await bluetoothManager.connect(peripheralID: peripheralID, name: name)
                // Guard against a cancel/disconnect that moved us on while awaiting.
                guard case let .connecting(id) = state, id == peripheralID else { return }
                state = .connected(peer: peer)
            } catch {
                connectFailed()
            }
        }
    }

    /// Connection attempt failed — return to the scan screen.
    func connectFailed() {
        guard case .connecting = state else { return }
        state = .scanning
    }

    /// The link dropped (from any non-scanning state) — return to `.scanning`,
    /// releasing the ``ConnectedPeer``. Deliberately does **not** reset
    /// ``selectedTab``, so a reconnect lands the user back on the same tab.
    func didDisconnect() {
        guard state != .scanning else { return }
        state = .scanning
    }

    /// Leave `MainTabView` for the DFU escape hatch, carrying the live peer +
    /// the chosen payload. Only valid while `.connected`.
    func startFirmwareUpdate(_ image: FirmwareImage) {
        guard case let .connected(peer) = state else { return }
        state = .updatingFirmware(peer: peer, payload: image)
    }

    /// User cancelled DFU *before the point of no return* — back to `.connected`
    /// with the **same** peer (not `.scanning`). Cancel is a no-op once the
    /// upload reaches validation; that guard lives in the DFU flow (#21/#22).
    func cancelFirmwareUpdate() {
        guard case let .updatingFirmware(peer, _) = state else { return }
        state = .connected(peer: peer)
    }

    /// DFU finished — return to `.connected`.
    ///
    /// - Note: Seed behavior reuses the same peer. The real success path (#22)
    ///   involves the device self-resetting and disconnecting, then a reconnect;
    ///   this method will be refined to route through that handshake. Because
    ///   ``selectedTab`` lives on the router, the tab is preserved across that
    ///   round-trip regardless.
    func firmwareUpdateCompleted() {
        guard case let .updatingFirmware(peer, _) = state else { return }
        state = .connected(peer: peer)
    }
}
