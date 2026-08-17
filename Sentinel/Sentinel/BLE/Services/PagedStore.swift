//
//  PagedStore.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import CoreBluetooth
import Foundation

/// The four characteristics of a firmware paged record store
/// (`sentinel_gatt_paged.hpp`): Record Count, Index (cursor), Record Block,
/// Clear Store. Used by ``SnapshotHistoryService`` and ``SystemEventLogService``.
struct PagedStoreCharacteristics {
    let service: CBUUID
    let recordCount: CBUUID
    let index: CBUUID
    let recordBlock: CBUUID
    let clearStore: CBUUID
}

/// The #9 chunking convention for walking a paged store: read Record Count →
/// write Index (cursor) → read Record Block (`floor(MTU / recordSize)` records) →
/// repeat. On-device stores are circular buffers (firmware #33) so the client is
/// the durable record; this reads a full snapshot of what's currently retained.
enum PagedStore {
    /// Walk the whole store, returning each record's raw `recordSize` bytes in
    /// order. Typed decoding is layered on top (#10 / #11).
    static func readAllRawRecords(
        transport: some BluetoothPeripheralTransport,
        characteristics chars: PagedStoreCharacteristics,
        recordSize: Int
    ) async throws -> [Data] {
        let count: UInt32 = try await transport.read(characteristic: chars.recordCount, ofService: chars.service) ?? 0
        var records: [Data] = []
        var cursor: UInt32 = 0
        while cursor < count {
            try await transport.write(
                cursor,
                characteristic: chars.index,
                ofService: chars.service,
                type: .withResponse
            )
            let block: Data = try await transport
                .read(characteristic: chars.recordBlock, ofService: chars.service) ?? Data()
            let recordsInBlock = block.count / recordSize
            if recordsInBlock == 0 { break } // device returned nothing further — avoid a spin
            for offset in 0 ..< recordsInBlock {
                let start = block.startIndex + offset * recordSize
                records.append(block.subdata(in: start ..< (start + recordSize)))
            }
            cursor += UInt32(recordsInBlock)
        }
        return records
    }
}
