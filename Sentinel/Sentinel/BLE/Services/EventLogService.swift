//
//  EventLogService.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The on-device system event log — a retrievable ring of records the firmware
/// appends on notable events. Aggregate (cross-cutting) service.
///
/// Phase I surfaces the raw record blob + a live "new record" stream. Decoding
/// the blob into `SystemEventRecord` values (the packed `SystemEventRecordRaw`
/// wire struct) is owned by decoder issue #11; this service moves the bytes.
protocol EventLogService {
    /// Number of records currently held on the device.
    func readRecordCount() async throws -> UInt32
    /// The full record blob (decoded by #11).
    func readRecords() async throws -> Data
    func setNotifying(_ enabled: Bool) async throws
    /// Newly appended records, pushed as they occur.
    func recordNotifications() -> AsyncStream<Data>
}

struct EventLogServiceClient<Transport: BluetoothPeripheralTransport>: EventLogService {
    let transport: Transport

    private var service: CBUUID { EventLogServiceUUID.eventLog.cbuuid }
    private var records: CBUUID { EventLogCharacteristicUUID.records.cbuuid }

    func readRecordCount() async throws -> UInt32 {
        // Count is derived from the record blob length in #11; Phase I reads a
        // dedicated count characteristic when firmware #6 assigns one. For now
        // this reuses the records characteristic's presence as a stand-in.
        let data: Data = try await transport.read(characteristic: records, ofService: service) ?? Data()
        return UInt32(data.count)
    }

    func readRecords() async throws -> Data {
        try await transport.read(characteristic: records, ofService: service) ?? Data()
    }

    func setNotifying(_ enabled: Bool) async throws {
        try await transport.setNotify(enabled, characteristic: records, ofService: service)
    }

    func recordNotifications() -> AsyncStream<Data> {
        transport.notifications(for: records, ofService: service)
    }
}

struct MockEventLogService: EventLogService {
    var records = Data([0x01, 0x02, 0x03, 0x04])

    func readRecordCount() async throws -> UInt32 { UInt32(records.count) }
    func readRecords() async throws -> Data { records }
    func setNotifying(_: Bool) async throws {}
    func recordNotifications() -> AsyncStream<Data> { .init { $0.yield(records); $0.finish() } }
}
