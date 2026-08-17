//
//  SnapshotHistoryService.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// Persisted snapshot history stored on the device's SPI flash (W25Q128): a
/// retrievable log of past `DeviceSnapshot` frames. Aggregate service.
///
/// Phase I moves the raw history blob; decoding is owned by decoder issue #10.
protocol SnapshotHistoryService {
    /// Number of snapshot frames retained on device.
    func readFrameCount() async throws -> UInt32
    /// The full history blob (decoded by #10).
    func readHistory() async throws -> Data
}

struct SnapshotHistoryServiceClient<Transport: BluetoothPeripheralTransport>: SnapshotHistoryService {
    let transport: Transport

    private var service: CBUUID { SnapshotHistoryServiceUUID.snapshotHistory.cbuuid }
    private var history: CBUUID { SnapshotHistoryCharacteristicUUID.history.cbuuid }

    func readFrameCount() async throws -> UInt32 {
        let data: Data = try await transport.read(characteristic: history, ofService: service) ?? Data()
        return UInt32(data.count)
    }

    func readHistory() async throws -> Data {
        try await transport.read(characteristic: history, ofService: service) ?? Data()
    }
}

struct MockSnapshotHistoryService: SnapshotHistoryService {
    var history = Data(repeating: 0xCD, count: 32)

    func readFrameCount() async throws -> UInt32 { UInt32(history.count) }
    func readHistory() async throws -> Data { history }
}
