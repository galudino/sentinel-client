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

    /// Device readiness (boot/POST state, #69), refreshed by
    /// ``startReadinessMonitoring()``. `.booting` until the first read; MainTabView
    /// gates the sensor-dependent UI on this so a central that connects mid-boot
    /// never renders stale/zero sensor values as if real.
    private(set) var readiness = DeviceReadiness(state: .booting, failedSubsystemID: 0)

    /// The owned peripheral, or `nil` for a detached (preview/test) peer.
    private let peripheral: Peripheral?
    private let central: CentralManager?

    /// Preview-only canned transport. `nil` in production and for plain detached
    /// peers (whose service reads throw ``ConnectedPeerError/detached``); when a
    /// peer is built via ``preview(name:rssi:mtu:)`` its service reads resolve
    /// against this instead, so **container** previews (MainTabView, RootView) show
    /// populated tabs without BLE. Leaf views still prefer `Mock*Service` directly.
    @ObservationIgnored private var previewTransport: MockBluetoothTransport?

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

    /// Read device readiness once, then subscribe for transitions — so a central
    /// that connected mid-POST observes `→ ready` (or `→ degraded`) without
    /// polling. Updates ``readiness`` and returns once a terminal state
    /// (ready/degraded) is reached. Safe no-op on a plain detached peer.
    /// `@MainActor` so the ``readiness`` mutations drive SwiftUI observation and
    /// the `SystemService` reads resolve on the actor the UI calls them from.
    @MainActor
    func startReadinessMonitoring() async {
        let system = system
        if let value = try? await system.readDeviceReadiness() {
            readiness = value
        }
        guard readiness.isInitializing else { return } // already ready/degraded
        try? await system.setDeviceReadinessNotifying(true)
        for await value in system.deviceReadinessNotifications() {
            readiness = value
            if !value.isInitializing { break } // reached ready / degraded
        }
    }

    // MARK: BluetoothPeripheralTransport

    func read<T: PeripheralDataConvertible & Sendable>(
        characteristic: CBUUID,
        ofService service: CBUUID
    ) async throws -> T? {
        guard let peripheral else {
            if let previewTransport {
                return try await previewTransport.read(characteristic: characteristic, ofService: service)
            }
            throw ConnectedPeerError.detached
        }
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
        guard let peripheral else {
            if let previewTransport {
                try await previewTransport.write(value, characteristic: characteristic, ofService: service, type: type)
                return
            }
            throw ConnectedPeerError.detached
        }
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
        guard let peripheral else {
            if let previewTransport {
                try await previewTransport.setNotify(enabled, characteristic: characteristic, ofService: service)
            }
            return
        }
        try await peripheral.setNotifyValue(
            enabled,
            forCharacteristicWithCBUUID: characteristic,
            ofServiceWithCBUUID: service
        )
    }

    func notifications<T: PeripheralDataConvertible & Sendable>(
        for characteristic: CBUUID,
        ofService service: CBUUID
    ) -> AsyncStream<T> {
        guard let peripheral else {
            if let previewTransport {
                return previewTransport.notifications(for: characteristic, ofService: service)
            }
            return AsyncStream { $0.finish() }
        }
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

// MARK: - Preview seam

#if DEBUG
    extension ConnectedPeer {
        /// A detached peer whose **service reads return canned data**, for SwiftUI
        /// previews of connected-subtree *containers* (MainTabView, RootView) — so
        /// their tabs show populated content without a live BLE link. One-shot reads
        /// (BME280 / DS3231 / System) **and** the paged **snapshot history** are
        /// seeded, so Home's trends + Climate History populate exactly as when
        /// HomeView is previewed on its own. The event log has no byte encoder yet,
        /// so LogsView still shows its empty state here. Leaf views should still
        /// preview with `Mock*Service` directly.
        static func preview(
            name: String? = "Sentinel",
            rssi: Int = -58,
            mtu: Int = 247,
            readiness: DeviceReadiness = .ready
        ) -> ConnectedPeer {
            let peer = ConnectedPeer(name: name)
            let transport = MockBluetoothTransport()

            // BME280 — one-shot ambient sample.
            transport.setReadValue(
                BME280Sample(temperatureCentiDegC: 2205, humidityCentiPct: 4780, pressurePa: 101_300),
                for: BME280CharacteristicUUID.ambientSample.cbuuid
            )
            // DS3231 — clock + on-die temperature + alarm flags.
            transport.setReadValue(
                UInt32(Date().timeIntervalSince1970),
                for: DS3231CharacteristicUUID.unixTime.cbuuid
            )
            transport.setReadValue(Int16(2500), for: DS3231CharacteristicUUID.rtcTemperature.cbuuid)
            transport.setReadValue(UInt8(0), for: DS3231CharacteristicUUID.alarmFlags.cbuuid)
            // System — identity + health.
            transport.setReadValue(
                FirmwareVersion(major: 1, minor: 0, patch: 1, build: 17),
                for: SystemCharacteristicUUID.firmwareVersion.cbuuid
            )
            transport.setReadValue(PlatformID.cyble416045.rawValue, for: SystemCharacteristicUUID.platformID.cbuuid)
            transport.setReadValue(UInt32(0x0000_ABCD), for: SystemCharacteristicUUID.serialNumber.cbuuid)
            transport.setReadValue(UInt16(4200), for: SystemCharacteristicUUID.cpuTemperature.cbuuid)
            transport.setReadValue(readiness, for: SystemCharacteristicUUID.deviceReadiness.cbuuid)

            // Snapshot history (paged store) — the mock transport returns the same
            // block per read, so a record count matching a single seeded block
            // resolves the whole store in one page (PagedStore.readAllRawRecords).
            // This is what makes Home's trends + Climate History populate in the
            // container previews exactly as in HomeView's own previews.
            let historyCount = 24
            transport.setReadValue(UInt32(historyCount), for: SnapshotHistoryCharacteristicUUID.recordCount.cbuuid)
            transport.setReadData(
                DeviceSnapshot.previewHistoryBlock(count: historyCount),
                for: SnapshotHistoryCharacteristicUUID.recordBlock.cbuuid
            )
            // Live snapshot stream — a single current frame for any reader.
            transport.setReadData(
                DeviceSnapshot.encode(.previewFrame),
                for: SnapshotStreamCharacteristicUUID.currentDeviceSnapshot.cbuuid
            )

            peer.previewTransport = transport
            peer.rssi = rssi
            peer.negotiatedMTU = mtu
            peer.readiness = readiness // reflect the state without running the monitor task
            return peer
        }
    }
#endif

/// A `Sendable` holder for an `AnyCancellable`, so a Combine subscription can be
/// captured into an `AsyncStream`'s `@Sendable` termination handler. `nonisolated`
/// so its storage is reachable from that closure under `-default-isolation=MainActor`.
private final nonisolated class CancellableBox: @unchecked Sendable {
    var cancellable: AnyCancellable?
}
