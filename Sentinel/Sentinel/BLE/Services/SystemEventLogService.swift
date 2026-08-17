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
/// Walks the store via ``PagedStore`` and decodes each 36-byte record with the
/// ``SystemEventRecord`` decoder (#11).
protocol SystemEventLogService {
    /// Number of event records currently retained on device.
    func readRecordCount() async throws -> UInt32
    /// Walk + decode the whole store (short records are dropped; unknown event
    /// types decode to `.unknown`).
    func readAllRecords() async throws -> [SystemEventRecord]
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

    func readAllRecords() async throws -> [SystemEventRecord] {
        let raw = try await PagedStore.readAllRawRecords(
            transport: transport,
            characteristics: chars,
            recordSize: Self.recordSize
        )
        return raw.compactMap(SystemEventRecord.decode)
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
    var records: [SystemEventRecord] = [
        .bootLifecycle(
            SystemEventRecordHeader(unixTimestamp: 1_760_000_000, eventTypeRaw: SystemEvent.bootComplete.rawValue),
            BootLifecycleBody(
                firmwareVersion: FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16),
                bootCount: 7,
                uptimeAtEvent: 0
            )
        )
    ]

    func readRecordCount() async throws -> UInt32 { UInt32(records.count) }
    func readAllRecords() async throws -> [SystemEventRecord] { records }
    func clearStore() async throws {}
}
