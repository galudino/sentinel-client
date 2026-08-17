//
//  SnapshotHistoryService.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// Persisted snapshot history on the device's SPI flash (W25Q128) — a paged
/// record store of past `DeviceSnapshot` frames (80 B each). Mirrors firmware
/// `sentinel_gatt_paged.hpp` (SNAPSHOT_HISTORY).
///
/// Phase I (#9) walks the store as raw record blobs via ``PagedStore``; typed
/// decoding into `DeviceSnapshot` is layered on by decoder issue #10.
protocol SnapshotHistoryService {
    /// Number of snapshot frames retained on device.
    func readRecordCount() async throws -> UInt32
    /// Walk the whole store, one 80-byte record per element (decoded by #10).
    func readAllRawRecords() async throws -> [Data]
    /// Erase the on-device store.
    func clearStore() async throws
}

struct SnapshotHistoryServiceClient<Transport: BluetoothPeripheralTransport>: SnapshotHistoryService {
    let transport: Transport

    /// One `DeviceSnapshot` record is 80 bytes (firmware #36).
    static var recordSize: Int { 80 }

    private var chars: PagedStoreCharacteristics {
        PagedStoreCharacteristics(
            service: SentinelServiceUUID.snapshotHistory.cbuuid,
            recordCount: SnapshotHistoryCharacteristicUUID.recordCount.cbuuid,
            index: SnapshotHistoryCharacteristicUUID.index.cbuuid,
            recordBlock: SnapshotHistoryCharacteristicUUID.recordBlock.cbuuid,
            clearStore: SnapshotHistoryCharacteristicUUID.clearStore.cbuuid
        )
    }

    func readRecordCount() async throws -> UInt32 {
        try await transport.read(characteristic: chars.recordCount, ofService: chars.service) ?? 0
    }

    func readAllRawRecords() async throws -> [Data] {
        try await PagedStore.readAllRawRecords(
            transport: transport,
            characteristics: chars,
            recordSize: Self.recordSize
        )
    }

    func clearStore() async throws {
        try await transport.write(
            UInt8(1),
            characteristic: chars.clearStore,
            ofService: chars.service,
            type: .withResponse
        )
    }
}

struct MockSnapshotHistoryService: SnapshotHistoryService {
    var records: [Data] = [Data(repeating: 0xCD, count: 80)]

    func readRecordCount() async throws -> UInt32 { UInt32(records.count) }
    func readAllRawRecords() async throws -> [Data] { records }
    func clearStore() async throws {}
}
