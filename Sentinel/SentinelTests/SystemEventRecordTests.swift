//
//  SystemEventRecordTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation
import Testing

@testable import Sentinel

/// Round-trip decode of 36-byte `system_event_record`s against the firmware's
/// typed-record layouts (`sentinel_system_event.hpp`, firmware #34).
@MainActor
struct SystemEventRecordTests {
    /// Assemble a 36-byte record: header (timestamp @0, event @4) + body bytes at
    /// their in-record offsets.
    private func record(
        event: SystemEvent,
        timestamp: UInt32 = 1_760_000_000,
        body: [Int: UInt8] = [:]
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 36)
        for index in 0 ..< 4 {
            bytes[index] = UInt8((timestamp >> (8 * index)) & 0xFF)
        }
        bytes[4] = event.rawValue
        for (offset, value) in body {
            bytes[offset] = value
        }
        return Data(bytes)
    }

    private func put32(_ value: UInt32, at offset: Int, into body: inout [Int: UInt8]) {
        for index in 0 ..< 4 {
            body[offset + index] = UInt8((value >> (8 * index)) & 0xFF)
        }
    }

    @Test func bootCompleteDecodesToBootLifecycle() throws {
        var body: [Int: UInt8] = [8: 1, 9: 4, 10: 2, 11: 9] // fw 1.4.2 build-low 9
        put32(42, at: 12, into: &body) // boot_count
        put32(0, at: 16, into: &body) // uptime_at_event
        let decoded = try #require(SystemEventRecord.decode(record(event: .bootComplete, body: body)))
        guard case let .bootLifecycle(header, boot) = decoded else {
            Issue.record("expected .bootLifecycle, got \(decoded)"); return
        }
        #expect(header.eventType == .bootComplete)
        #expect(header.unixTimestamp == 1_760_000_000)
        #expect(boot.firmwareVersion == FirmwareVersion(major: 1, minor: 4, patch: 2, build: 9))
        #expect(boot.bootCount == 42)
    }

    @Test func firmwareUpdateDecodesBothVersions() throws {
        var body: [Int: UInt8] = [8: 1, 9: 0, 10: 0, 11: 16, 12: 1, 13: 1, 14: 0, 15: 20]
        put32(0, at: 16, into: &body)
        let decoded = try #require(SystemEventRecord.decode(record(event: .firmwareUpdateCompleted, body: body)))
        guard case let .firmwareUpdate(_, update) = decoded else {
            Issue.record("expected .firmwareUpdate"); return
        }
        #expect(update.fromVersion == FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16))
        #expect(update.toVersion == FirmwareVersion(major: 1, minor: 1, patch: 0, build: 20))
        #expect(decoded.displaySubtitle == "v1.0.0 → v1.1.0")
    }

    @Test func bleConnectionDecodesPeerAddressAndMTU() throws {
        var body: [Int: UInt8] = [8: 0x11, 9: 0x22, 10: 0x33, 11: 0x44, 12: 0x55, 13: 0x66, 14: 0, 15: 0]
        body[16] = 0x18; body[17] = 0x00 // conn interval 24
        body[18] = 0xF7; body[19] = 0x00 // MTU 247
        let decoded = try #require(SystemEventRecord.decode(record(event: .blePeripheralConnected, body: body)))
        guard case let .bleConnection(_, ble) = decoded else { Issue.record("expected .bleConnection"); return }
        #expect(ble.peerAddress == [0x11, 0x22, 0x33, 0x44, 0x55, 0x66])
        #expect(ble.peerAddressString == "66:55:44:33:22:11")
        #expect(ble.peerMTU == 247)
    }

    @Test func faultAndModeAndPostAndSnapshotVariantsDecode() throws {
        guard case .fault = try #require(SystemEventRecord.decode(record(event: .faultRaised, body: [8: 5, 9: 3])))
        else {
            Issue.record("expected .fault"); return
        }
        guard case .modeChange = try #require(
            SystemEventRecord
                .decode(record(event: .modeChanged, body: [8: 1, 9: 2]))
        ) else {
            Issue.record("expected .modeChange"); return
        }
        guard case .post = try #require(SystemEventRecord.decode(record(event: .postPassed))) else {
            Issue.record("expected .post"); return
        }
        guard case .snapshot = try #require(SystemEventRecord.decode(record(event: .snapshotPersisted, body: [12: 1])))
        else {
            Issue.record("expected .snapshot"); return
        }
    }

    @Test func recognizedEventWithoutTypedBodyDecodesToOther() throws {
        let decoded = try #require(SystemEventRecord.decode(record(event: .rtcSetFromBLE)))
        guard case .other = decoded else { Issue.record("expected .other"); return }
        #expect(decoded.event == .rtcSetFromBLE)
    }

    @Test func unknownEventTypeDecodesToUnknownWithRawIntact() throws {
        var bytes = [UInt8](repeating: 0, count: 36)
        bytes[4] = 0xAA
        let data = Data(bytes)
        let decoded = try #require(SystemEventRecord.decode(data))
        guard case let .unknown(header, raw) = decoded else { Issue.record("expected .unknown"); return }
        #expect(header.eventTypeRaw == 0xAA)
        #expect(header.eventType == nil)
        #expect(raw == data)
        #expect(decoded.displayTitle == "Unknown event 0xAA")
    }

    @Test func shortBufferFailsToDecode() {
        #expect(SystemEventRecord.decode(Data(repeating: 0, count: 35)) == nil)
    }

    @Test func serviceDecodesConcatenatedRecords() async throws {
        let transport = MockBluetoothTransport()
        let block = record(event: .bootComplete) + record(event: .faultRaised, body: [8: 1])
        transport.setReadValue(UInt32(2), for: SystemEventLogCharacteristicUUID.recordCount.cbuuid)
        transport.setReadData(block, for: SystemEventLogCharacteristicUUID.recordBlock.cbuuid)

        let records = try await SystemEventLogServiceClient(transport: transport).readAllRecords()
        #expect(records.count == 2)
        #expect(records.first?.event == .bootComplete)
        #expect(records.last?.event == .faultRaised)
    }
}
