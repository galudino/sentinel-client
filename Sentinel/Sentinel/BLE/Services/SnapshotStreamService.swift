//
//  SnapshotStreamService.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The live device-snapshot stream (firmware lane-2, firmware #46): the device
/// pushes packed `DeviceSnapshot` frames at a cadence. Aggregate service.
///
/// Phase I moves the raw frame bytes; decoding into `DeviceSnapshot` is owned by
/// decoder issue #10.
protocol SnapshotStreamService {
    /// Read the most recent snapshot frame on demand.
    func readLatest() async throws -> Data
    func setNotifying(_ enabled: Bool) async throws
    /// Live snapshot frames as the device emits them.
    func snapshotNotifications() -> AsyncStream<Data>
}

struct SnapshotStreamServiceClient<Transport: BluetoothPeripheralTransport>: SnapshotStreamService {
    let transport: Transport

    private var service: CBUUID { SnapshotStreamServiceUUID.snapshotStream.cbuuid }
    private var snapshot: CBUUID { SnapshotStreamCharacteristicUUID.snapshot.cbuuid }

    func readLatest() async throws -> Data {
        try await transport.read(characteristic: snapshot, ofService: service) ?? Data()
    }

    func setNotifying(_ enabled: Bool) async throws {
        try await transport.setNotify(enabled, characteristic: snapshot, ofService: service)
    }

    func snapshotNotifications() -> AsyncStream<Data> {
        transport.notifications(for: snapshot, ofService: service)
    }
}

struct MockSnapshotStreamService: SnapshotStreamService {
    var frame = Data(repeating: 0xAB, count: 16)

    func readLatest() async throws -> Data { frame }
    func setNotifying(_: Bool) async throws {}
    func snapshotNotifications() -> AsyncStream<Data> { .init { $0.yield(frame); $0.finish() } }
}
