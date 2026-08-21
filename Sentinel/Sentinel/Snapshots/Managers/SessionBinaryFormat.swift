//
//  SessionBinaryFormat.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - SessionBinaryFormat Constants

/// Codec for the `.sentinelsession` binary file format used to persist a capture
/// session to disk. The low-level byte reader/writer live in `BinaryCoding.swift`.
///
/// ```
/// [Header]  — session metadata + field schema (written once at session start)
/// [Entry]…  — raw field values per entry (appended during capture)
/// [Footer]  — end time, status, entry count (written when the session ends)
/// ```
///
/// Little-endian throughout; the field schema is stored once in the header so
/// entries carry only raw values. A per-entry marker byte enables crash-recovery
/// scanning, and the format is dramatically smaller than JSON — which is what
/// makes lazy disk paging of long completed sessions cheap.
nonisolated enum SessionBinaryFormat {
    /// Magic bytes identifying a session file: "SNTL".
    static let magic: [UInt8] = [0x53, 0x4E, 0x54, 0x4C]

    /// Current binary format version.
    static let currentVersion: UInt16 = 1

    /// Marker byte at the start of each entry record.
    static let entryMarker: UInt8 = 0xAA

    /// Marker byte at the start of the session footer.
    static let footerMarker: UInt8 = 0xFF

    /// On-disk file extension (without the dot).
    static let fileExtension = "sentinelsession"
}

// MARK: - BinaryFormatError

nonisolated enum BinaryFormatError: LocalizedError {
    case invalidMagic
    case unsupportedVersion(UInt16)
    case unexpectedEndOfData
    case invalidString
    case invalidValueType(UInt8)
    case invalidEntryMarker
    case invalidFooterMarker
    case corruptedEntry
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .invalidMagic: "Invalid file format — not a .sentinelsession file"
        case let .unsupportedVersion(version): "Unsupported format version: \(version)"
        case .unexpectedEndOfData: "Unexpected end of data"
        case .invalidString: "Invalid UTF-8 string encoding"
        case let .invalidValueType(tag): "Invalid snapshot value type tag: \(tag)"
        case .invalidEntryMarker: "Invalid entry marker byte"
        case .invalidFooterMarker: "Invalid footer marker byte"
        case .corruptedEntry: "Corrupted entry detected"
        case .fileNotFound: "Session file not found"
        }
    }
}

// MARK: - BinaryFieldSchema

/// Field descriptor stored once in the file header. Entries carry only the raw
/// value in this order — no repeated metadata.
nonisolated struct BinaryFieldSchema: Codable {
    let keyPath: String
    let displayName: String
    let unit: String
    let dataType: SnapshotFieldDataType
}

// MARK: - SessionFileHeader

/// Metadata written once at the start of a `.sentinelsession` file.
nonisolated struct SessionFileHeader {
    let formatVersion: UInt16
    /// Snapshot type discriminator (0 = DeviceSnapshot; reserved for Phase II types).
    let snapshotType: UInt8
    let captureMode: SnapshotCaptureMode
    let sessionId: UUID
    let configurationId: UUID
    var sessionName: String
    let startTime: Date
    let pollingInterval: TimeInterval
    let maxDuration: TimeInterval?
    let stopOnDisconnect: Bool
    let serialNumber: UInt32
    let firmwareVersion: String
    let selectedTimingFieldIds: Set<String>
    let fieldSchema: [BinaryFieldSchema]
    let autoSaveInterval: TimeInterval?
}

// MARK: - SessionFileFooter

/// Written at the end of a `.sentinelsession` file when the session concludes.
nonisolated struct SessionFileFooter {
    let endTime: Date
    let duration: TimeInterval
    let status: SnapshotLoggingStatus
    let entryCount: UInt32
}

// MARK: - Header Encoding

nonisolated extension SessionFileHeader {
    func encode() -> Data {
        let writer = BinaryWriter(capacity: 1024)
        writer.writeBytes(SessionBinaryFormat.magic)
        writer.writeUInt16(formatVersion)
        writer.writeUInt8(snapshotType)
        writer.writeUInt8(captureMode == .polling ? 0 : 1)
        writer.writeUUID(sessionId)
        writer.writeUUID(configurationId)
        writer.writeString(sessionName)
        writer.writeDate(startTime)
        writer.writeFloat64(pollingInterval)
        writer.writeOptionalFloat64(maxDuration)
        writer.writeBool(stopOnDisconnect)
        writer.writeUInt32(serialNumber)
        writer.writeString(firmwareVersion)
        writer.writeOptionalFloat64(autoSaveInterval)
        writer.writeStrings(Array(selectedTimingFieldIds))
        writer.writeFieldSchema(fieldSchema)

        // Header length, written last so a reader can skip straight to entries.
        writer.writeUInt32(UInt32(writer.data.count + 4))
        return writer.data
    }
}

// MARK: - Header Decoding

nonisolated extension SessionFileHeader {
    static func decode(from reader: BinaryReader) throws -> SessionFileHeader {
        guard try reader.readMagic() == SessionBinaryFormat.magic else { throw BinaryFormatError.invalidMagic }

        let version = try reader.readUInt16()
        guard version == SessionBinaryFormat.currentVersion else {
            throw BinaryFormatError.unsupportedVersion(version)
        }

        let snapshotType = try reader.readUInt8()
        let captureMode: SnapshotCaptureMode = try reader.readUInt8() == 0 ? .polling : .notifications
        let sessionId = try reader.readUUID()
        let configurationId = try reader.readUUID()
        let sessionName = try reader.readString()
        let startTime = try reader.readDate()
        let pollingInterval = try reader.readFloat64()
        let maxDuration = try reader.readOptionalFloat64()
        let stopOnDisconnect = try reader.readBool()
        let serialNumber = try reader.readUInt32()
        let firmwareVersion = try reader.readString()
        let autoSaveInterval = try reader.readOptionalFloat64()
        let timingIds = try Set(reader.readStrings())
        let fieldSchema = try reader.readFieldSchema()
        _ = try reader.readUInt32() // header length — consumed, not needed

        return SessionFileHeader(
            formatVersion: version,
            snapshotType: snapshotType,
            captureMode: captureMode,
            sessionId: sessionId,
            configurationId: configurationId,
            sessionName: sessionName,
            startTime: startTime,
            pollingInterval: pollingInterval,
            maxDuration: maxDuration,
            stopOnDisconnect: stopOnDisconnect,
            serialNumber: serialNumber,
            firmwareVersion: firmwareVersion,
            selectedTimingFieldIds: timingIds,
            fieldSchema: fieldSchema,
            autoSaveInterval: autoSaveInterval
        )
    }
}

// MARK: - Entry Encoding

nonisolated extension SessionBinaryFormat {
    /// Encode one log entry. Field values are written in schema order — the reader
    /// pairs them back with the header schema to rebuild `SnapshotFieldValue`s.
    static func encodeEntry(_ entry: SnapshotLogEntry, captureMode: SnapshotCaptureMode) -> Data {
        let writer = BinaryWriter(capacity: 256)
        writer.writeUInt8(entryMarker)
        writer.writeDate(entry.timestamp)
        writer.writeOptionalUInt64(entry.deviceUnixTimeMs)

        if captureMode == .polling {
            writer.writeOptionalDate(entry.scheduledTick)
            writer.writeOptionalDate(entry.actualStart)
            writer.writeOptionalDate(entry.actualFinishRead)
            writer.writeOptionalDate(entry.finishCycle)
            writer.writeOptionalFloat64(entry.latencySeconds)
            writer.writeOptionalFloat64(entry.readDurationSeconds)
            writer.writeOptionalFloat64(entry.cycleDurationSeconds)
        } else {
            writer.writeOptionalDate(entry.actualStart)
            writer.writeOptionalFloat64(entry.interNotificationInterval)
        }

        writer.writeUInt16(UInt16(entry.fieldValues.count))
        for fieldValue in entry.fieldValues {
            writer.writeSnapshotValue(fieldValue.value)
        }
        return writer.data
    }
}

// MARK: - Entry Decoding

nonisolated extension SessionBinaryFormat {
    /// Decode one log entry, using the header field schema to rebuild each
    /// `SnapshotFieldValue`'s display metadata.
    static func decodeEntry(
        from reader: BinaryReader,
        captureMode: SnapshotCaptureMode,
        schema: [BinaryFieldSchema]
    ) throws -> SnapshotLogEntry {
        let marker = try reader.readUInt8()
        guard marker == entryMarker else { throw BinaryFormatError.invalidEntryMarker }

        let timestamp = try reader.readDate()
        let deviceUnixTimeMs = try reader.readOptionalUInt64()
        let timing = try decodeTiming(from: reader, captureMode: captureMode)
        let fieldValues = try decodeFieldValues(from: reader, schema: schema)

        return SnapshotLogEntry(
            id: UUID(),
            timestamp: timestamp,
            fieldValues: fieldValues,
            deviceUnixTimeMs: deviceUnixTimeMs,
            scheduledTick: timing.scheduledTick,
            actualStart: timing.actualStart,
            actualFinishRead: timing.actualFinishRead,
            finishCycle: timing.finishCycle,
            latencySeconds: timing.latencySeconds,
            readDurationSeconds: timing.readDurationSeconds,
            cycleDurationSeconds: timing.cycleDurationSeconds,
            interNotificationInterval: timing.interNotificationInterval
        )
    }

    /// The per-entry timing diagnostics, whose layout depends on the capture mode.
    private struct EntryTiming {
        var scheduledTick: Date?
        var actualStart: Date?
        var actualFinishRead: Date?
        var finishCycle: Date?
        var latencySeconds: Double?
        var readDurationSeconds: Double?
        var cycleDurationSeconds: Double?
        var interNotificationInterval: Double?
    }

    private static func decodeTiming(
        from reader: BinaryReader,
        captureMode: SnapshotCaptureMode
    ) throws -> EntryTiming {
        var timing = EntryTiming()
        if captureMode == .polling {
            timing.scheduledTick = try reader.readOptionalDate()
            timing.actualStart = try reader.readOptionalDate()
            timing.actualFinishRead = try reader.readOptionalDate()
            timing.finishCycle = try reader.readOptionalDate()
            timing.latencySeconds = try reader.readOptionalFloat64()
            timing.readDurationSeconds = try reader.readOptionalFloat64()
            timing.cycleDurationSeconds = try reader.readOptionalFloat64()
        } else {
            timing.actualStart = try reader.readOptionalDate()
            timing.interNotificationInterval = try reader.readOptionalFloat64()
        }
        return timing
    }

    private static func decodeFieldValues(
        from reader: BinaryReader,
        schema: [BinaryFieldSchema]
    ) throws -> [SnapshotFieldValue] {
        let fieldCount = try Int(reader.readUInt16())
        return try (0 ..< fieldCount).map { index in
            let value = try reader.readSnapshotValue()
            let info = index < schema.count
                ? schema[index]
                : BinaryFieldSchema(
                    keyPath: "unknown_\(index)", displayName: "Unknown \(index)", unit: "", dataType: .string
                )
            return SnapshotFieldValue(
                displayName: info.displayName,
                keyPath: info.keyPath,
                value: value,
                unit: info.unit,
                dataType: info.dataType
            )
        }
    }
}

// MARK: - Footer Encoding

nonisolated extension SessionFileFooter {
    func encode() -> Data {
        let writer = BinaryWriter(capacity: 32)
        writer.writeUInt8(SessionBinaryFormat.footerMarker)
        writer.writeDate(endTime)
        writer.writeFloat64(duration)
        writer.writeUInt8(status.binaryTag)
        writer.writeUInt32(entryCount)
        return writer.data
    }
}

// MARK: - Footer Decoding

nonisolated extension SessionFileFooter {
    static func decode(from reader: BinaryReader) throws -> SessionFileFooter {
        let marker = try reader.readUInt8()
        guard marker == SessionBinaryFormat.footerMarker else { throw BinaryFormatError.invalidFooterMarker }
        let endTime = try reader.readDate()
        let duration = try reader.readFloat64()
        let status = try SnapshotLoggingStatus.fromBinaryTag(reader.readUInt8())
        let entryCount = try reader.readUInt32()
        return SessionFileFooter(endTime: endTime, duration: duration, status: status, entryCount: entryCount)
    }
}
