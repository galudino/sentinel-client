//
//  SnapshotValue.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - SnapshotValue

/// A type-erased scalar value pulled out of a ``Snapshot`` field.
///
/// The snapshot-logging subsystem is generic over the snapshot type; this is the
/// common currency every field decodes to, so charting, export, and the binary
/// session format can work without knowing the concrete snapshot. The case set is
/// deliberately small — it matches the wire scalars the firmware emits.
nonisolated enum SnapshotValue: Codable, Hashable {
    case bool(Bool)
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)
    case float32(Float32)
    case string(String)
    case error(String)

    var stringValue: String {
        switch self {
        case let .bool(value): value ? "true" : "false"
        case let .uint8(value): "\(value)"
        case let .uint16(value): "\(value)"
        case let .uint32(value): "\(value)"
        case let .uint64(value): "\(value)"
        case let .float32(value): String(format: "%.3f", value)
        case let .string(value): value
        case let .error(message): "Error: \(message)"
        }
    }

    var jsonValue: Any {
        switch self {
        case let .bool(value): value
        case let .uint8(value): value
        case let .uint16(value): value
        case let .uint32(value): value
        case let .uint64(value): value
        case let .float32(value): value
        case let .string(value): value
        case let .error(message): ["error": message]
        }
    }

    /// The value as a `Double` for charting, or `nil` for non-chartable cases
    /// (bool / string / error).
    var numericValue: Double? {
        switch self {
        case .bool, .string, .error: nil
        case let .uint8(value): Double(value)
        case let .uint16(value): Double(value)
        case let .uint32(value): Double(value)
        case let .uint64(value): Double(value)
        case let .float32(value): Double(value)
        }
    }

    var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }
}
