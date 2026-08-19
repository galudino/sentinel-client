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
    /// A connect attempt errored or timed out. Carries the peer id (so the user
    /// can retry the same device) and a display message. `ConnectingView` (#13)
    /// renders this branch as an error with Retry / Back-to-scan.
    case connectFailed(peripheralID: UUID, message: String)
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
        case .home: "sensor.fill"
        case .logs: "list.bullet.indent"
        case .snapshots: "square.stack.3d.down.right.fill"
        case .device: "info.circle.fill"
        case .settings: "gearshape.2.fill"
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

    /// The running connect attempt, retained so ``cancelConnect()`` can abort it.
    private var connectTask: Task<Void, Never>?

    /// Whole-sequence connect budget (#13). Exceeding it surfaces a timeout error.
    private let connectTimeout: Duration = .seconds(15)

    // MARK: Intents

    /// User picked a peripheral in `PeripheralScanView` (#12): enter `.connecting`
    /// and run the connect off the main actor. On success advance to `.connected`;
    /// on error/timeout advance to `.connectFailed` (so `ConnectingView` can show
    /// it); on user cancel we're already back at `.scanning`.
    func beginConnect(peripheralID: UUID, name: String? = nil) {
        guard case .scanning = state else { return }
        startConnect(peripheralID: peripheralID, name: name)
    }

    /// Retry the same device after a failure — valid only from `.connectFailed`.
    func retryConnect() {
        guard case let .connectFailed(peripheralID, _) = state else { return }
        startConnect(peripheralID: peripheralID, name: nil)
    }

    private func startConnect(peripheralID: UUID, name: String?) {
        state = .connecting(peripheralID: peripheralID)
        connectTask?.cancel()

        let central = bluetoothManager
        let timeout = connectTimeout
        connectTask = Task {
            do {
                let peer = try await withThrowingTimeout(timeout) {
                    try await central.connect(peripheralID: peripheralID, name: name)
                }
                // Guard against a cancel/disconnect that moved us on while awaiting.
                guard case let .connecting(id) = state, id == peripheralID else { return }
                state = .connected(peer: peer)
            } catch is CancellationError {
                // User cancelled — `cancelConnect()` already returned us to scanning.
            } catch {
                await central.cancelConnect(peripheralID: peripheralID) // tear down any half-open link
                guard case let .connecting(id) = state, id == peripheralID else { return }
                state = .connectFailed(peripheralID: peripheralID, message: Self.message(for: error))
            }
        }
    }

    /// Cancel an in-flight connect: abort the BLE work and return to scanning
    /// immediately. Valid only while `.connecting`.
    func cancelConnect() {
        guard case let .connecting(peripheralID) = state else { return }
        connectTask?.cancel()
        connectTask = nil
        let central = bluetoothManager
        Task { await central.cancelConnect(peripheralID: peripheralID) }
        state = .scanning
    }

    /// Acknowledge a `.connectFailed` error and return to the scan screen.
    func dismissConnectError() {
        guard case .connectFailed = state else { return }
        state = .scanning
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// The link dropped (from any non-scanning state) — return to `.scanning`,
    /// releasing the ``ConnectedPeer``. Deliberately does **not** reset
    /// ``selectedTab``, so a reconnect lands the user back on the same tab.
    ///
    /// Use this for an *involuntary* drop (the device went away). For a
    /// user-initiated disconnect that should also tear down the BLE link, use
    /// ``disconnect()``.
    func didDisconnect() {
        guard state != .scanning else { return }
        state = .scanning
    }

    /// User-initiated disconnect (Settings / Device tab): actively tear down the
    /// BLE link, then return to `.scanning`. Only valid while `.connected`.
    func disconnect() {
        guard case let .connected(peer) = state else { return }
        let central = bluetoothManager
        Task { try? await central.disconnect(peer) }
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

    /// DFU finished but no *fresh* connection was handed back (previews / the
    /// no-reconnector path) — fall back to the existing peer. Production completes
    /// through ``firmwareUpdateReconnected(peer:)`` with the post-reboot peer.
    /// Because ``selectedTab`` lives on the router, the tab is preserved across the
    /// round-trip regardless.
    func firmwareUpdateCompleted() {
        guard case let .updatingFirmware(peer, _) = state else { return }
        state = .connected(peer: peer)
    }

    /// DFU finished and the uploader (#22) reconnected to the device after its
    /// self-reset — land `.connected` on the **new** `ConnectedPeer` (the old one's
    /// link is gone), so the tabs bind to the live connection and read back the new
    /// firmware version. Only valid while `.updatingFirmware`.
    func firmwareUpdateReconnected(peer: ConnectedPeer) {
        guard case .updatingFirmware = state else { return }
        state = .connected(peer: peer)
    }
}

// MARK: - Timeout

/// Thrown by ``withThrowingTimeout(_:_:)`` when the operation exceeds its budget.
struct TimeoutError: LocalizedError {
    var errorDescription: String? { "The connection timed out. Move closer to the device and try again." }
}

/// Run `operation`, throwing ``TimeoutError`` if it doesn't finish within
/// `duration`. Whichever finishes first wins; the other child task is cancelled.
func withThrowingTimeout<T: Sendable>(
    _ duration: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw TimeoutError() }
        return result
    }
}
