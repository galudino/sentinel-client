//
//  SessionBinaryFormatTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation
import Testing

@testable import Sentinel

/// The `.sentinelsession` binary format is the on-disk persistence for capture
/// sessions and the basis for lazy disk paging, so header/entry/footer must
/// round-trip byte-for-byte and reject corrupt input.
struct SessionBinaryFormatTests {
    private func sampleHeader(mode: SnapshotCaptureMode) -> SessionFileHeader {
        SessionFileHeader(
            formatVersion: SessionBinaryFormat.currentVersion,
            snapshotType: 0,
            captureMode: mode,
            sessionId: UUID(),
            configurationId: UUID(),
            sessionName: "Session ☂ 1",
            startTime: Date(timeIntervalSince1970: 1_760_000_000.25),
            pollingInterval: 0.1,
            maxDuration: 300,
            stopOnDisconnect: true,
            serialNumber: 0xABCD,
            firmwareVersion: "1.0.1",
            selectedTimingFieldIds: ["deviceTimestamp", "bleReadDuration"],
            fieldSchema: [
                BinaryFieldSchema(keyPath: "temperatureCelsius", displayName: "Temp", unit: "°C", dataType: .float32),
                BinaryFieldSchema(keyPath: "bleConnected", displayName: "BLE", unit: "T/F", dataType: .bool)
            ],
            autoSaveInterval: 300
        )
    }

    @Test func headerRoundTrips() throws {
        let header = sampleHeader(mode: .polling)
        let decoded = try SessionFileHeader.decode(from: BinaryReader(data: header.encode()))

        #expect(decoded.sessionId == header.sessionId)
        #expect(decoded.configurationId == header.configurationId)
        #expect(decoded.sessionName == header.sessionName)
        #expect(decoded.captureMode == .polling)
        #expect(decoded.serialNumber == header.serialNumber)
        #expect(decoded.firmwareVersion == header.firmwareVersion)
        #expect(decoded.selectedTimingFieldIds == header.selectedTimingFieldIds)
        #expect(decoded.fieldSchema.count == 2)
        #expect(decoded.fieldSchema[0].keyPath == "temperatureCelsius")
        #expect(decoded.fieldSchema[1].dataType == .bool)
        #expect(decoded.autoSaveInterval == 300)
    }

    @Test func pollingEntryRoundTrips() throws {
        let entry = SnapshotLogEntry(
            fieldValues: [
                SnapshotFieldValue(
                    displayName: "Temp",
                    keyPath: "temperatureCelsius",
                    value: .float32(22.5),
                    unit: "°C",
                    dataType: .float32
                ),
                SnapshotFieldValue(
                    displayName: "BLE",
                    keyPath: "bleConnected",
                    value: .bool(true),
                    unit: "T/F",
                    dataType: .bool
                )
            ],
            deviceUnixTimeMs: 1_760_000_000_000,
            scheduledTick: Date(timeIntervalSince1970: 100),
            actualStart: Date(timeIntervalSince1970: 100.01),
            actualFinishRead: Date(timeIntervalSince1970: 100.02),
            finishCycle: Date(timeIntervalSince1970: 100.1),
            latencySeconds: 0.01,
            readDurationSeconds: 0.01,
            cycleDurationSeconds: 0.1
        )
        let schema = sampleHeader(mode: .polling).fieldSchema
        let data = SessionBinaryFormat.encodeEntry(entry, captureMode: .polling)
        let decoded = try SessionBinaryFormat.decodeEntry(
            from: BinaryReader(data: data),
            captureMode: .polling,
            schema: schema
        )

        #expect(decoded.deviceUnixTimeMs == 1_760_000_000_000)
        #expect(decoded.readDurationSeconds == 0.01)
        #expect(decoded.fieldValues.count == 2)
        #expect(decoded.fieldValues[0].value == .float32(22.5))
        #expect(decoded.fieldValues[0].keyPath == "temperatureCelsius")
        #expect(decoded.fieldValues[1].value == .bool(true))
    }

    @Test func notificationEntryRoundTripsWithInterval() throws {
        let entry = SnapshotLogEntry(
            fieldValues: [SnapshotFieldValue(
                displayName: "Temp",
                keyPath: "temperatureCelsius",
                value: .float32(19.0),
                unit: "°C",
                dataType: .float32
            )],
            deviceUnixTimeMs: 42,
            actualStart: Date(timeIntervalSince1970: 5),
            interNotificationInterval: 0.25
        )
        let schema = [BinaryFieldSchema(
            keyPath: "temperatureCelsius",
            displayName: "Temp",
            unit: "°C",
            dataType: .float32
        )]
        let data = SessionBinaryFormat.encodeEntry(entry, captureMode: .notifications)
        let decoded = try SessionBinaryFormat.decodeEntry(
            from: BinaryReader(data: data), captureMode: .notifications, schema: schema
        )

        #expect(decoded.deviceUnixTimeMs == 42)
        #expect(decoded.interNotificationInterval == 0.25)
        #expect(decoded.fieldValues[0].value == .float32(19.0))
    }

    @Test func footerRoundTrips() throws {
        let footer = SessionFileFooter(
            endTime: Date(timeIntervalSince1970: 200),
            duration: 100,
            status: .completed,
            entryCount: 1234
        )
        let decoded = try SessionFileFooter.decode(from: BinaryReader(data: footer.encode()))
        #expect(decoded.status == .completed)
        #expect(decoded.entryCount == 1234)
        #expect(decoded.duration == 100)
    }

    @Test func rejectsWrongMagic() {
        let reader = BinaryReader(data: Data([0x00, 0x01, 0x02, 0x03, 0x04]))
        #expect(throws: BinaryFormatError.self) {
            _ = try SessionFileHeader.decode(from: reader)
        }
    }
}
