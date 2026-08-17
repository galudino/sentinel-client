//
//  ConnectedPeer.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import Combine
import CoreBluetooth
import Foundation
import Observation

/// One *active* BLE connection: the transport + service namespace for a peer that
/// is currently connected.
///
/// `ConnectedPeer` owns the `AsyncBluetooth` `Peripheral`, conforms to
/// ``BluetoothPeripheralTransport`` (so read/write/notify live here — they cannot
/// exist without a peripheral), holds live per-connection state (RSSI/MTU), and
/// vends the per-service clients (`bme280`, `ds3231`, `system`, …). It is created
/// by ``BluetoothManager/connect(peripheralID:name:)`` and carried in the
/// router's `.connected` / `.updatingFirmware` states; `RootView` injects it into
/// the connected subtree **only**, so "this connection exists only while
/// connected" is a structural invariant, not an optional guard.
///
/// ### Detached peers (previews / tests)
/// The peripheral-backed ``init(peripheral:central:)`` is the production path. A
/// second, *detached* ``init(id:name:)`` builds a peer with no peripheral for
/// SwiftUI previews of connected-subtree containers and for `AppRouter` state-
/// machine tests; its transport methods throw ``ConnectedPeerError/detached``.
/// Leaf views never need this — they take `any <Chip>Service` and preview with a
/// `Mock*Service` instead.
///
/// `@unchecked Sendable` is an intentional Phase I concession (live RSSI/MTU are
/// mutated off the main actor while observed on it); Swift 6 strict-concurrency
/// hardening is tracked in #24.
@Observable
final nonisolated class ConnectedPeer: BluetoothPeripheralTransport, Identifiable, @unchecked Sendable {
    /// The peripheral's stable identifier (`CBPeripheral.identifier`). Matches the
    /// `peripheralID` carried through `.connecting`.
    let id: UUID

    /// Advertised / GAP name, when known. Display-only.
    let name: String?

    /// Live signal strength (dBm), refreshed via ``refreshSignal()``. `0` until
    /// the first read.
    private(set) var rssi: Int = 0

    /// Negotiated ATT MTU (bytes). Defaults to the BLE minimum of 23 until the
    /// link reports otherwise. OTA chunking (#22) sizes writes from this — never
    /// a hardcoded 244.
    private(set) var negotiatedMTU: Int = 23

    /// The owned peripheral, or `nil` for a detached (preview/test) peer.
    private let peripheral: Peripheral?
    private let central: CentralManager?

    /// Production: own a live, connected peripheral.
    init(peripheral: Peripheral, central: CentralManager) {
        self.peripheral = peripheral
        self.central = central
        id = peripheral.identifier
        name = peripheral.name
    }

    /// Detached: no peripheral. Previews of connected-subtree containers and
    /// `AppRouter` tests only — transport calls throw ``ConnectedPeerError/detached``.
    init(id: UUID = UUID(), name: String? = nil) {
        peripheral = nil
        central = nil
        self.id = id
        self.name = name
    }

    // MARK: Link metrics

    /// Refresh ``negotiatedMTU`` from the peripheral. Called right after a
    /// successful connect. Safe no-op on a detached peer.
    func refreshMTU() {
        guard let peripheral else { return }
        // ATT MTU = write-without-response payload + the 3-byte ATT header.
        negotiatedMTU = peripheral.maximumWriteValueLength(for: .withoutResponse) + 3
    }

    /// Refresh ``rssi`` from the peripheral. Safe no-op on a detached peer.
    func refreshSignal() async {
        guard let peripheral else { return }
        if let value = try? await peripheral.readRSSI() {
            rssi = value.intValue
        }
    }

    // MARK: BluetoothPeripheralTransport

    func read<T: PeripheralDataConvertible & Sendable>(
        characteristic: CBUUID,
        ofService service: CBUUID
    ) async throws -> T? {
        guard let peripheral else { throw ConnectedPeerError.detached }
        return try await peripheral.readValue(
            forCharacteristicWithCBUUID: characteristic,
            ofServiceWithCBUUID: service
        )
    }

    func write(
        _ value: some PeripheralDataConvertible & Sendable,
        characteristic: CBUUID,
        ofService service: CBUUID,
        type: CBCharacteristicWriteType
    ) async throws {
        guard let peripheral else { throw ConnectedPeerError.detached }
        try await peripheral.writeValue(
            value,
            forCharacteristicWithCBUUID: characteristic,
            ofServiceWithCBUUID: service,
            type: type
        )
    }

    func setNotify(
        _ enabled: Bool,
        characteristic: CBUUID,
        ofService service: CBUUID
    ) async throws {
        guard let peripheral else { throw ConnectedPeerError.detached }
        try await peripheral.setNotifyValue(
            enabled,
            forCharacteristicWithCBUUID: characteristic,
            ofServiceWithCBUUID: service
        )
    }

    func notifications<T: PeripheralDataConvertible & Sendable>(
        for characteristic: CBUUID,
        ofService _: CBUUID
    ) -> AsyncStream<T> {
        guard let peripheral else { return AsyncStream { $0.finish() } }
        return AsyncStream { continuation in
            // AsyncBluetooth surfaces value updates as a Combine publisher; bridge
            // it to the stream, filtered to this characteristic and decoded to `T`.
            // The cancellable lives in a Sendable box so it can be torn down from
            // the stream's `onTermination` under strict concurrency.
            let bridge = CancellableBox()
            bridge.cancellable = peripheral.characteristicValueUpdatedPublisher
                .filter { $0.characteristic.uuid == characteristic }
                .sink { event in
                    guard let value: T = try? event.parsedValue() else { return }
                    continuation.yield(value)
                }
            continuation.onTermination = { [bridge] _ in bridge.cancellable?.cancel() }
        }
    }

    // MARK: Service namespace — scoped to a live connection

    var bme280: BME280ServiceClient<ConnectedPeer> { .init(transport: self) }
    var ds3231: DS3231ServiceClient<ConnectedPeer> { .init(transport: self) }
    var system: SystemServiceClient<ConnectedPeer> { .init(transport: self) }
    var systemEventLog: SystemEventLogServiceClient<ConnectedPeer> { .init(transport: self) }
    var snapshotStream: SnapshotStreamServiceClient<ConnectedPeer> { .init(transport: self) }
    var snapshotHistory: SnapshotHistoryServiceClient<ConnectedPeer> { .init(transport: self) }
    var ota: OTAServiceClient<ConnectedPeer> { .init(transport: self) }
    var debugStream: DebugStreamServiceClient<ConnectedPeer> { .init(transport: self) }
    // Phase II adds .scd41, .sgp30, .tmp117, … via the same pattern (umbrella #27).
}

// MARK: - Equatable (identity)

extension ConnectedPeer: Equatable {
    /// A connection is defined by object identity: two references are the same
    /// connection iff they are the same instance. This is what lets `AppState`
    /// be `Equatable` (see `AppRouter`).
    static func == (lhs: ConnectedPeer, rhs: ConnectedPeer) -> Bool {
        lhs === rhs
    }
}

// MARK: - Errors

enum ConnectedPeerError: Error {
    /// A transport operation was attempted on a detached (preview/test) peer that
    /// has no backing peripheral.
    case detached
}

/// A `Sendable` holder for an `AnyCancellable`, so a Combine subscription can be
/// captured into an `AsyncStream`'s `@Sendable` termination handler. `nonisolated`
/// so its storage is reachable from that closure under `-default-isolation=MainActor`.
private final nonisolated class CancellableBox: @unchecked Sendable {
    var cancellable: AnyCancellable?
}
