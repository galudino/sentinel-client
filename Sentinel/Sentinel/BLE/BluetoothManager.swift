//
//  BluetoothManager.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation
import Observation

/// The BLE *central*: scans, connects, and tracks connection state. One per app,
/// injected app-wide (no singletons). It does **not** do characteristic I/O and
/// does **not** retain the connected peripheral — `connect()` *returns* a
/// ``ConnectedPeer`` that owns the active connection. The manager keeps only the
/// discovered scan list and a high-level ``ConnectionState`` for the UI.
///
/// Built on `AsyncBluetooth`'s `CentralManager` (async/await + `AsyncStream` over
/// CoreBluetooth). Conforms to ``BluetoothCentral`` so `AppRouter` depends on the
/// small connect/disconnect surface (and can be tested against a mock central).
///
/// `@unchecked Sendable` is an intentional Phase I concession — the scan list and
/// connection state are mutated from the scan/connect tasks while observed on the
/// main actor; Swift 6 strict-concurrency hardening is tracked in #24.
@Observable
final class BluetoothManager: BluetoothCentral, @unchecked Sendable {
    /// The current discovered peripherals, newest signal first. Driven by
    /// ``scanForPeripherals()``; consumed by `PeripheralScanView` (#12).
    private(set) var discoveredPeripherals: [PeripheralScanItem] = []

    /// High-level connection lifecycle, surfaced for UI. The router derives
    /// `AppState` from user intent; this is the central's own view of the link.
    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting(peripheralID: UUID)
        case discoveringServices(peripheralID: UUID)
        case connected(peripheralID: UUID)
        case disconnecting
    }

    private(set) var connectionState: ConnectionState = .disconnected

    private let central = CentralManager()

    /// The running scan-consumer task, retained so ``stopScan()`` can cancel it.
    private var scanTask: Task<Void, Never>?

    /// Ignore duplicate advertisements for a peripheral seen within this window,
    /// to tame `CBCentralManagerScanOptionAllowDuplicatesKey` churn.
    private let scanThrottle: TimeInterval = 0.5

    /// Fan-out for ``bluetoothEventStream()`` subscribers.
    private let eventBroadcaster = BluetoothEventBroadcaster()

    init() {}

    // MARK: Scanning

    /// Start scanning for sentinel peripherals, filtered to the known service
    /// UUIDs. Idempotent: a second call replaces the running scan.
    func scanForPeripherals() async throws {
        try await central.waitUntilReady()
        stopScanTask()
        discoveredPeripherals.removeAll()
        connectionState = .scanning
        emit(.scan, "Scan started")

        let stream = try await central.scanForPeripherals(
            withServices: SentinelServiceUUID.cbuuids
        )
        scanTask = Task { [weak self] in
            for await scanData in stream {
                self?.ingest(scanData)
            }
        }
    }

    /// Stop scanning. Leaves the discovered list intact so the UI can still act on
    /// the last results.
    func stopScan() async throws {
        stopScanTask()
        await central.stopScan()
        if case .scanning = connectionState { connectionState = .disconnected }
        emit(.scan, "Scan stopped")
    }

    private func stopScanTask() {
        scanTask?.cancel()
        scanTask = nil
    }

    /// Upsert a discovered peripheral, throttling repeat advertisements.
    private func ingest(_ scanData: ScanData) {
        let id = scanData.peripheral.identifier
        let rssi = scanData.rssi.intValue
        let now = Date.now

        if let index = discoveredPeripherals.firstIndex(where: { $0.id == id }) {
            guard now.timeIntervalSince(discoveredPeripherals[index].lastUpdated) >= scanThrottle
            else { return }
            discoveredPeripherals[index].rssi = rssi
            discoveredPeripherals[index].lastUpdated = now
        } else {
            discoveredPeripherals.append(
                PeripheralScanItem(peripheral: scanData.peripheral, rssi: rssi, lastUpdated: now)
            )
            emit(.scan, "Discovered \(scanData.peripheral.name ?? "unnamed")", peripheralID: id)
        }
    }

    // MARK: Connecting

    /// Connect to a discovered peripheral by identity, discover its services, and
    /// return the active ``ConnectedPeer``.
    ///
    /// The router speaks in `UUID`s; the manager resolves the identity to a live
    /// `Peripheral` from the scan list (falling back to CoreBluetooth's retained
    /// set), so `AppRouter` never touches an `AsyncBluetooth` type.
    func connect(peripheralID: UUID, name: String? = nil) async throws -> ConnectedPeer {
        let peripheral = try resolvePeripheral(peripheralID)
        stopScanTask()

        connectionState = .connecting(peripheralID: peripheralID)
        emit(.connection, "Connecting to \(peripheral.name ?? name ?? "peer")", peripheralID: peripheralID)
        try await central.connect(peripheral)

        connectionState = .discoveringServices(peripheralID: peripheralID)
        emit(.discovery, "Discovering services", peripheralID: peripheralID)
        try await peripheral.discoverServices(SentinelServiceUUID.cbuuids)

        let peer = ConnectedPeer(peripheral: peripheral, central: central)
        peer.refreshMTU()
        await peer.refreshSignal()

        connectionState = .connected(peripheralID: peripheralID)
        emit(.connection, "Connected (MTU \(peer.negotiatedMTU))", peripheralID: peripheralID)
        return peer
    }

    /// Tear down the active connection and release the peer. Does not retain the
    /// peripheral — it is re-resolved from CoreBluetooth's retained set by id.
    func disconnect(_ peer: ConnectedPeer) async throws {
        connectionState = .disconnecting
        emit(.connection, "Disconnecting", peripheralID: peer.id)
        if let peripheral = central.retrievePeripherals(withIdentifiers: [peer.id]).first {
            try await central.cancelPeripheralConnection(peripheral)
        }
        connectionState = .disconnected
        emit(.connection, "Disconnected", peripheralID: peer.id)
    }

    private func resolvePeripheral(_ id: UUID) throws -> Peripheral {
        if let item = discoveredPeripherals.first(where: { $0.id == id }) {
            return item.peripheral
        }
        if let retrieved = central.retrievePeripherals(withIdentifiers: [id]).first {
            return retrieved
        }
        throw BluetoothManagerError.unknownPeripheral(id)
    }

    // MARK: Event stream (#25)

    /// A structured stream of local BLE activity for `DebugOutputStreamView` (#25).
    /// Each subscriber gets its own stream; new events fan out to all of them.
    func bluetoothEventStream() -> AsyncStream<BluetoothLogEvent> {
        eventBroadcaster.subscribe()
    }

    private func emit(_ category: BluetoothLogEvent.Category, _ message: String, peripheralID: UUID? = nil) {
        eventBroadcaster.emit(
            BluetoothLogEvent(category: category, message: message, peripheralID: peripheralID)
        )
    }
}

// MARK: - Errors

enum BluetoothManagerError: Error, Equatable {
    /// `connect` was asked for a peripheral that is neither in the scan list nor
    /// retained by CoreBluetooth.
    case unknownPeripheral(UUID)
}

// MARK: - Event fan-out

/// Thread-safe fan-out of ``BluetoothLogEvent``s to any number of `AsyncStream`
/// subscribers. Minimal by design — #25 owns the richer merged-timeline model.
/// `nonisolated` so its lock-guarded storage is reachable from the streams'
/// `@Sendable` `onTermination` handlers under `-default-isolation=MainActor`.
private final nonisolated class BluetoothEventBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<BluetoothLogEvent>.Continuation] = [:]

    func subscribe() -> AsyncStream<BluetoothLogEvent> {
        let key = UUID()
        return AsyncStream { continuation in
            lock.withLock { continuations[key] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { _ = self?.continuations.removeValue(forKey: key) }
            }
        }
    }

    func emit(_ event: BluetoothLogEvent) {
        let targets = lock.withLock { Array(continuations.values) }
        for continuation in targets {
            continuation.yield(event)
        }
    }
}
