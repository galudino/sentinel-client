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
/// the device pushes packed ``DeviceSnapshot`` frames (80 B) at a cadence. Frames
/// are decoded by the ``DeviceSnapshot`` decoder (#10) as they arrive.
protocol SnapshotStreamService {
    /// Read + decode the most recent snapshot on demand (`nil` on a torn record).
    func readCurrentSnapshot() async throws -> DeviceSnapshot?
    func setNotifying(_ enabled: Bool) async throws
    /// Live snapshots as the device emits them (torn frames are dropped).
    func snapshotNotifications() -> AsyncStream<DeviceSnapshot>
}

struct SnapshotStreamServiceClient<Transport: BluetoothPeripheralTransport>: SnapshotStreamService {
    let transport: Transport

    private var service: CBUUID { SentinelServiceUUID.snapshotStream.cbuuid }
    private var current: CBUUID { SnapshotStreamCharacteristicUUID.currentDeviceSnapshot.cbuuid }

    func readCurrentSnapshot() async throws -> DeviceSnapshot? {
        try await transport.read(characteristic: current, ofService: service)
    }

    /// The firmware gates the stream behind a separate notify-enable flag that must
    /// be armed **before** the CCCD subscribe (and cleared **after** unsubscribe),
    /// so the two writes are ordered symmetrically here.
    func setNotifying(_ enabled: Bool) async throws {
        if enabled {
            try await streamNotifyEnable(true)
            try await transport.setNotify(true, characteristic: current, ofService: service)
        } else {
            try await transport.setNotify(false, characteristic: current, ofService: service)
            try await streamNotifyEnable(false)
        }
    }

    func snapshotNotifications() -> AsyncStream<DeviceSnapshot> {
        transport.notifications(for: current, ofService: service)
    }

    private func streamNotifyEnable(_ enabled: Bool) async throws {
        try await transport.write(
            UInt8(enabled ? 1 : 0),
            characteristic: SnapshotStreamCharacteristicUUID.snapshotNotifyEnable.cbuuid,
            ofService: service,
            type: .withResponse
        )
    }
}

struct MockSnapshotStreamService: SnapshotStreamService {
    var snapshot: DeviceSnapshot = .sample

    func readCurrentSnapshot() async throws -> DeviceSnapshot? { snapshot }
    func setNotifying(_: Bool) async throws {}
    func snapshotNotifications() -> AsyncStream<DeviceSnapshot> {
        .init { $0.yield(snapshot); $0.finish() }
    }
}
