//
//  SnapshotStreamService.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The live device-snapshot stream (firmware lane-2, `sentinel_gatt_snapshot_stream.hpp`):
/// the device pushes packed `DeviceSnapshot` frames (80 B) at a cadence.
///
/// Phase I (#9) moves the raw frame bytes; typed decoding into `DeviceSnapshot`
/// is layered on by decoder issue #10.
protocol SnapshotStreamService {
    /// Read the most recent snapshot frame on demand.
    func readLatest() async throws -> Data
    func setNotifying(_ enabled: Bool) async throws
    /// Live snapshot frames as the device emits them.
    func snapshotNotifications() -> AsyncStream<Data>
}

struct SnapshotStreamServiceClient<Transport: BluetoothPeripheralTransport>: SnapshotStreamService {
    let transport: Transport

    private var service: CBUUID { SentinelServiceUUID.snapshotStream.cbuuid }
    private var current: CBUUID { SnapshotStreamCharacteristicUUID.currentDeviceSnapshot.cbuuid }

    func readLatest() async throws -> Data {
        try await transport.read(characteristic: current, ofService: service) ?? Data()
    }

    func setNotifying(_ enabled: Bool) async throws {
        try await transport.setNotify(enabled, characteristic: current, ofService: service)
    }

    func snapshotNotifications() -> AsyncStream<Data> {
        transport.notifications(for: current, ofService: service)
    }
}

struct MockSnapshotStreamService: SnapshotStreamService {
    var frame = Data(repeating: 0xAB, count: 80)

    func readLatest() async throws -> Data { frame }
    func setNotifying(_: Bool) async throws {}
    func snapshotNotifications() -> AsyncStream<Data> { .init { $0.yield(frame); $0.finish() } }
}
