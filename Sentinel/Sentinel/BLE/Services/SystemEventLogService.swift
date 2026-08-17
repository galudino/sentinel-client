//
//  SystemEventLogService.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The on-device System Event Log — a paged record store the firmware appends on
/// notable events (36-byte records). Mirrors firmware `sentinel_gatt_paged.hpp`
/// (SYSTEM_EVENT_LOG); the service is named **SystemEventLog** to match the
/// contract 1:1 (not the shorter "EventLog" the #8 scaffold used).
///
/// Phase I (#9) walks the store as raw 36-byte record blobs via ``PagedStore``;
/// typed decoding into `SystemEventRecord` is layered on by decoder issue #11.
protocol SystemEventLogService {
    /// Number of event records currently retained on device.
    func readRecordCount() async throws -> UInt32
    /// Walk the whole store, one 36-byte record per element (decoded by #11).
    func readAllRawRecords() async throws -> [Data]
    /// Erase the on-device store.
    func clearStore() async throws
}

struct SystemEventLogServiceClient<Transport: BluetoothPeripheralTransport>: SystemEventLogService {
    let transport: Transport

    /// One `system_event_record` is 36 bytes (firmware #34).
    static var recordSize: Int { 36 }

    private var chars: PagedStoreCharacteristics {
        PagedStoreCharacteristics(
            service: SentinelServiceUUID.systemEventLog.cbuuid,
            recordCount: SystemEventLogCharacteristicUUID.recordCount.cbuuid,
            index: SystemEventLogCharacteristicUUID.index.cbuuid,
            recordBlock: SystemEventLogCharacteristicUUID.recordBlock.cbuuid,
            clearStore: SystemEventLogCharacteristicUUID.clearStore.cbuuid
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

struct MockSystemEventLogService: SystemEventLogService {
    var records: [Data] = [Data(repeating: 0x01, count: 36)]

    func readRecordCount() async throws -> UInt32 { UInt32(records.count) }
    func readAllRawRecords() async throws -> [Data] { records }
    func clearStore() async throws {}
}
