//
//  BinaryCoding.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - BinaryWriter

/// Appends primitive values to an internal little-endian `Data` buffer. The
/// low-level half of the `.sentinelsession` codec (see ``SessionBinaryFormat``).
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

    /// A length-prefixed array of strings.
    func writeStrings(_ strings: [String]) {
        writeUInt16(UInt16(strings.count))
        for string in strings {
            writeString(string)
        }
    }

    func writeUUID(_ value: UUID) {
        let uuid = value.uuid
        data.append(contentsOf: [
            uuid.0, uuid.1, uuid.2, uuid.3, uuid.4, uuid.5, uuid.6, uuid.7,
            uuid.8, uuid.9, uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15
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

    /// The header field-schema block: count followed by each descriptor.
    func writeFieldSchema(_ schema: [BinaryFieldSchema]) {
        writeUInt16(UInt16(schema.count))
        for field in schema {
            writeString(field.keyPath)
            writeString(field.displayName)
            writeString(field.unit)
            writeUInt8(field.dataType.binaryTag)
        }
    }

    func writeSnapshotValue(_ value: SnapshotValue) {
        switch value {
        case let .bool(raw): writeUInt8(0); writeBool(raw)
        case let .uint8(raw): writeUInt8(1); writeUInt8(raw)
        case let .uint16(raw): writeUInt8(2); writeUInt16(raw)
        case let .uint32(raw): writeUInt8(3); writeUInt32(raw)
        case let .uint64(raw): writeUInt8(4); writeUInt64(raw)
        case let .float32(raw): writeUInt8(5); writeFloat32(raw)
        case let .string(raw): writeUInt8(6); writeString(raw)
        case let .error(raw): writeUInt8(7); writeString(raw)
        }
    }
}

// MARK: - BinaryReader

/// Reads primitive values sequentially from a little-endian `Data` buffer. The
/// decoding half of the `.sentinelsession` codec (see ``SessionBinaryFormat``).
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
        let byte0 = UInt16(data[data.startIndex + offset])
        let byte1 = UInt16(data[data.startIndex + offset + 1])
        offset += 2
        return byte0 | (byte1 << 8)
    }

    func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw BinaryFormatError.unexpectedEndOfData }
        let byte0 = UInt32(data[data.startIndex + offset])
        let byte1 = UInt32(data[data.startIndex + offset + 1])
        let byte2 = UInt32(data[data.startIndex + offset + 2])
        let byte3 = UInt32(data[data.startIndex + offset + 3])
        offset += 4
        return byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24)
    }

    func readUInt64() throws -> UInt64 {
        guard offset + 8 <= data.count else { throw BinaryFormatError.unexpectedEndOfData }
        var value: UInt64 = 0
        for index in 0 ..< 8 {
            value |= UInt64(data[data.startIndex + offset + index]) << (index * 8)
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

    /// A length-prefixed array of strings.
    func readStrings() throws -> [String] {
        let count = try Int(readUInt16())
        return try (0 ..< count).map { _ in try readString() }
    }

    func readUUID() throws -> UUID {
        guard offset + 16 <= data.count else { throw BinaryFormatError.unexpectedEndOfData }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0 ..< 16 {
            bytes[index] = data[data.startIndex + offset + index]
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

    /// The 4-byte file magic.
    func readMagic() throws -> [UInt8] {
        try (0 ..< 4).map { _ in try readUInt8() }
    }

    /// The header field-schema block written by ``BinaryWriter/writeFieldSchema(_:)``.
    func readFieldSchema() throws -> [BinaryFieldSchema] {
        let count = try Int(readUInt16())
        return try (0 ..< count).map { _ in
            let keyPath = try readString()
            let displayName = try readString()
            let unit = try readString()
            let dataType = try SnapshotFieldDataType.fromBinaryTag(readUInt8())
            return BinaryFieldSchema(keyPath: keyPath, displayName: displayName, unit: unit, dataType: dataType)
        }
    }

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
