//
//  SessionBinaryFormat.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

// swiftlint:disable file_length type_body_length identifier_name

import Foundation

// MARK: - SessionBinaryFormat Constants

/// Codec for the `.sentinelsession` binary file format used to persist a capture
/// session to disk.
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

// MARK: - BinaryWriter

/// Appends primitive values to an internal little-endian `Data` buffer.
final nonisolated class BinaryWriter {
    private(set) var data: Data

    init(capacity: Int = 4096) {
        data = Data()
        data.reserveCapacity(capacity)
    }

    // MARK: Primitive writes

    func writeBytes(_ bytes: [UInt8]) { data.append(contentsOf: bytes) }
    func writeUInt8(_ value: UInt8) { data.append(value) }
    func writeBool(_ value: Bool) { writeUInt8(value ? 1 : 0) }

    func writeUInt16(_ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    func writeUInt32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    func writeUInt64(_ value: UInt64) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    func writeFloat32(_ value: Float32) { writeUInt32(value.bitPattern) }
    func writeFloat64(_ value: Float64) { writeUInt64(value.bitPattern) }

    // MARK: Compound writes

    func writeString(_ value: String) {
        let utf8 = Array(value.utf8)
        writeUInt16(UInt16(utf8.count))
        data.append(contentsOf: utf8)
    }

    func writeUUID(_ value: UUID) {
        let u = value.uuid
        data.append(contentsOf: [
            u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
            u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15
        ])
    }

    func writeDate(_ date: Date) { writeFloat64(date.timeIntervalSince1970) }

    func writeOptionalFloat64(_ value: Double?) {
        if let value {
            writeUInt8(1)
            writeFloat64(value)
        } else {
            writeUInt8(0)
        }
    }

    func writeOptionalUInt64(_ value: UInt64?) {
        if let value {
            writeUInt8(1)
            writeUInt64(value)
        } else {
            writeUInt8(0)
        }
    }

    func writeOptionalDate(_ date: Date?) { writeOptionalFloat64(date?.timeIntervalSince1970) }

    // MARK: Snapshot value

    func writeSnapshotValue(_ value: SnapshotValue) {
        switch value {
        case let .bool(v): writeUInt8(0); writeBool(v)
        case let .uint8(v): writeUInt8(1); writeUInt8(v)
        case let .uint16(v): writeUInt8(2); writeUInt16(v)
        case let .uint32(v): writeUInt8(3); writeUInt32(v)
        case let .uint64(v): writeUInt8(4); writeUInt64(v)
        case let .float32(v): writeUInt8(5); writeFloat32(v)
        case let .string(v): writeUInt8(6); writeString(v)
        case let .error(v): writeUInt8(7); writeString(v)
        }
    }
}

// MARK: - BinaryReader

/// Reads primitive values sequentially from a little-endian `Data` buffer.
final nonisolated class BinaryReader {
    private let data: Data
    var offset: Int

    var bytesRemaining: Int { data.count - offset }
    var isAtEnd: Bool { offset >= data.count }

    init(data: Data) {
        self.data = data
        offset = 0
    }

    // MARK: Primitive reads

    func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else { throw BinaryFormatError.unexpectedEndOfData }
        let value = data[data.startIndex + offset]
        offset += 1
        return value
    }

    func readBool() throws -> Bool { try readUInt8() != 0 }

    func readUInt16() throws -> UInt16 {
        guard offset + 2 <= data.count else { throw BinaryFormatError.unexpectedEndOfData }
        let b0 = UInt16(data[data.startIndex + offset])
        let b1 = UInt16(data[data.startIndex + offset + 1])
        offset += 2
        return b0 | (b1 << 8)
    }

    func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw BinaryFormatError.unexpectedEndOfData }
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1])
        let b2 = UInt32(data[data.startIndex + offset + 2])
        let b3 = UInt32(data[data.startIndex + offset + 3])
        offset += 4
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    func readUInt64() throws -> UInt64 {
        guard offset + 8 <= data.count else { throw BinaryFormatError.unexpectedEndOfData }
        var value: UInt64 = 0
        for i in 0 ..< 8 {
            value |= UInt64(data[data.startIndex + offset + i]) << (i * 8)
        }
        offset += 8
        return value
    }

    func readFloat32() throws -> Float32 { try Float32(bitPattern: readUInt32()) }
    func readFloat64() throws -> Float64 { try Float64(bitPattern: readUInt64()) }

    // MARK: Compound reads

    func readString() throws -> String {
        let length = try Int(readUInt16())
        guard offset + length <= data.count else { throw BinaryFormatError.unexpectedEndOfData }
        let slice = data[data.startIndex + offset ..< data.startIndex + offset + length]
        offset += length
        guard let string = String(data: slice, encoding: .utf8) else {
            throw BinaryFormatError.invalidString
        }
        return string
    }

    func readUUID() throws -> UUID {
        guard offset + 16 <= data.count else { throw BinaryFormatError.unexpectedEndOfData }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0 ..< 16 {
            bytes[i] = data[data.startIndex + offset + i]
        }
        offset += 16
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    func readDate() throws -> Date { try Date(timeIntervalSince1970: readFloat64()) }

    func readOptionalFloat64() throws -> Double? {
        try readUInt8() == 1 ? try readFloat64() : nil
    }

    func readOptionalUInt64() throws -> UInt64? {
        try readUInt8() == 1 ? try readUInt64() : nil
    }

    func readOptionalDate() throws -> Date? {
        guard let interval = try readOptionalFloat64() else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    // MARK: Snapshot value

    func readSnapshotValue() throws -> SnapshotValue {
        let typeTag = try readUInt8()
        switch typeTag {
        case 0: return try .bool(readBool())
        case 1: return try .uint8(readUInt8())
        case 2: return try .uint16(readUInt16())
        case 3: return try .uint32(readUInt32())
        case 4: return try .uint64(readUInt64())
        case 5: return try .float32(readFloat32())
        case 6: return try .string(readString())
        case 7: return try .error(readString())
        default: throw BinaryFormatError.invalidValueType(typeTag)
        }
    }
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

        let timingIds = Array(selectedTimingFieldIds)
        writer.writeUInt16(UInt16(timingIds.count))
        for id in timingIds {
            writer.writeString(id)
        }

        writer.writeUInt16(UInt16(fieldSchema.count))
        for field in fieldSchema {
            writer.writeString(field.keyPath)
            writer.writeString(field.displayName)
            writer.writeString(field.unit)
            writer.writeUInt8(field.dataType.binaryTag)
        }

        // Header length, written last so a reader can skip straight to entries.
        writer.writeUInt32(UInt32(writer.data.count + 4))
        return writer.data
    }
}

// MARK: - Header Decoding

nonisolated extension SessionFileHeader {
    static func decode(from reader: BinaryReader) throws -> SessionFileHeader {
        let m0 = try reader.readUInt8()
        let m1 = try reader.readUInt8()
        let m2 = try reader.readUInt8()
        let m3 = try reader.readUInt8()
        guard [m0, m1, m2, m3] == SessionBinaryFormat.magic else { throw BinaryFormatError.invalidMagic }

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

        let timingIdCount = try Int(reader.readUInt16())
        var timingIds = Set<String>()
        for _ in 0 ..< timingIdCount {
            try timingIds.insert(reader.readString())
        }

        let fieldCount = try Int(reader.readUInt16())
        var fieldSchema: [BinaryFieldSchema] = []
        for _ in 0 ..< fieldCount {
            let keyPath = try reader.readString()
            let displayName = try reader.readString()
            let unit = try reader.readString()
            let dataType = try SnapshotFieldDataType.fromBinaryTag(reader.readUInt8())
            fieldSchema.append(BinaryFieldSchema(
                keyPath: keyPath, displayName: displayName, unit: unit, dataType: dataType
            ))
        }

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

        var scheduledTick: Date?
        var actualStart: Date?
        var actualFinishRead: Date?
        var finishCycle: Date?
        var latencySeconds: Double?
        var readDurationSeconds: Double?
        var cycleDurationSeconds: Double?
        var interNotificationInterval: Double?

        if captureMode == .polling {
            scheduledTick = try reader.readOptionalDate()
            actualStart = try reader.readOptionalDate()
            actualFinishRead = try reader.readOptionalDate()
            finishCycle = try reader.readOptionalDate()
            latencySeconds = try reader.readOptionalFloat64()
            readDurationSeconds = try reader.readOptionalFloat64()
            cycleDurationSeconds = try reader.readOptionalFloat64()
        } else {
            actualStart = try reader.readOptionalDate()
            interNotificationInterval = try reader.readOptionalFloat64()
        }

        let fieldCount = try Int(reader.readUInt16())
        var fieldValues: [SnapshotFieldValue] = []
        for i in 0 ..< fieldCount {
            let value = try reader.readSnapshotValue()
            let fieldInfo = i < schema.count
                ? schema[i]
                : BinaryFieldSchema(keyPath: "unknown_\(i)", displayName: "Unknown \(i)", unit: "", dataType: .string)
            fieldValues.append(SnapshotFieldValue(
                displayName: fieldInfo.displayName,
                keyPath: fieldInfo.keyPath,
                value: value,
                unit: fieldInfo.unit,
                dataType: fieldInfo.dataType
            ))
        }

        return SnapshotLogEntry(
            id: UUID(),
            timestamp: timestamp,
            fieldValues: fieldValues,
            deviceUnixTimeMs: deviceUnixTimeMs,
            scheduledTick: scheduledTick,
            actualStart: actualStart,
            actualFinishRead: actualFinishRead,
            finishCycle: finishCycle,
            latencySeconds: latencySeconds,
            readDurationSeconds: readDurationSeconds,
            cycleDurationSeconds: cycleDurationSeconds,
            interNotificationInterval: interNotificationInterval
        )
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

// swiftlint:enable file_length type_body_length identifier_name
