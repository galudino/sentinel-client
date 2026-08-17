//
//  MockBluetoothTransport.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// A ``BluetoothPeripheralTransport`` backed by canned bytes instead of a real
/// peripheral. Drives **testing strategy #1**: exercise a *real* `*ServiceClient`
/// against known bytes to catch decode/encode bugs, and inspect what the client
/// wrote — all with zero BLE involvement.
///
/// ```swift
/// let transport = MockBluetoothTransport()
/// transport.setReadValue(UInt32(42), for: SystemCharacteristicUUID.uptimeSeconds.cbuuid)
/// let uptime = try await SystemServiceClient(transport: transport).readUptimeSeconds()
/// #expect(uptime == 42)
/// ```
///
/// `@unchecked Sendable`: state is guarded by an internal lock so the mock is safe
/// to share across the async calls a test makes. `nonisolated` (under this
/// target's `-default-isolation=MainActor`) so the stored notification closures
/// run wherever the producer calls them, not hopped onto the main actor.
final nonisolated class MockBluetoothTransport: BluetoothPeripheralTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var readData: [CBUUID: Data] = [:]
    private var notifyEnabled: [CBUUID: Bool] = [:]
    private var notificationSinks: [CBUUID: [(Data) -> Void]] = [:]

    /// One recorded write, for assertions in tests.
    struct RecordedWrite: Equatable {
        let characteristic: CBUUID
        let service: CBUUID
        let data: Data
    }

    /// Every write the client made, in order.
    private(set) var writes: [RecordedWrite] = []

    init() {}

    // MARK: Test seams

    /// Seed the canned value a `read` of `characteristic` will decode.
    func setReadValue(_ value: some PeripheralDataConvertible, for characteristic: CBUUID) {
        lock.withLock { readData[characteristic] = value.toData() }
    }

    /// Seed raw canned bytes for a `read` of `characteristic`.
    func setReadData(_ data: Data, for characteristic: CBUUID) {
        lock.withLock { readData[characteristic] = data }
    }

    /// Whether notifications are currently enabled for `characteristic`.
    func isNotifying(_ characteristic: CBUUID) -> Bool {
        lock.withLock { notifyEnabled[characteristic] ?? false }
    }

    /// Push a notification value to any open ``notifications(for:ofService:)``
    /// streams for `characteristic`.
    func injectNotification(_ value: some PeripheralDataConvertible, for characteristic: CBUUID) {
        guard let data = value.toData() else { return }
        let sinks = lock.withLock { notificationSinks[characteristic] ?? [] }
        for sink in sinks {
            sink(data)
        }
    }

    // MARK: BluetoothPeripheralTransport

    func read<T: PeripheralDataConvertible & Sendable>(
        characteristic: CBUUID,
        ofService _: CBUUID
    ) async throws -> T? {
        guard let data = lock.withLock({ readData[characteristic] }) else { return nil }
        guard let value = T.fromData(data) else { throw MockTransportError.decodingFailed(characteristic) }
        return value
    }

    func write(
        _ value: some PeripheralDataConvertible & Sendable,
        characteristic: CBUUID,
        ofService service: CBUUID,
        type _: CBCharacteristicWriteType
    ) async throws {
        guard let data = value.toData() else { throw MockTransportError.encodingFailed(characteristic) }
        lock.withLock { writes.append(RecordedWrite(characteristic: characteristic, service: service, data: data)) }
    }

    func setNotify(
        _ enabled: Bool,
        characteristic: CBUUID,
        ofService _: CBUUID
    ) async throws {
        lock.withLock { notifyEnabled[characteristic] = enabled }
    }

    func notifications<T: PeripheralDataConvertible & Sendable>(
        for characteristic: CBUUID,
        ofService _: CBUUID
    ) -> AsyncStream<T> {
        AsyncStream { continuation in
            let sink: (Data) -> Void = { data in
                if let value = T.fromData(data) { continuation.yield(value) }
            }
            lock.withLock { notificationSinks[characteristic, default: []].append(sink) }
        }
    }
}

enum MockTransportError: Error, Equatable {
    case decodingFailed(CBUUID)
    case encodingFailed(CBUUID)
}
