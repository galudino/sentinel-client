//
//  SnapshotFieldDataType.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

// MARK: - SnapshotFieldDataType

/// The scalar type of a ``Snapshot`` field. Mirrors the case set of
/// ``SnapshotValue`` and gates chartability (``isNumeric``) and the binary
/// session encoding (``binaryTag``).
nonisolated enum SnapshotFieldDataType: String, Codable, CaseIterable, CustomStringConvertible {
    case bool = "Bool"
    case uint8 = "UInt8"
    case uint16 = "UInt16"
    case uint32 = "UInt32"
    case uint64 = "UInt64"
    case float32 = "Float32"
    case string = "String"

    var description: String {
        switch self {
        case .bool: "Boolean value (true/false)"
        case .uint8: "8-bit unsigned integer"
        case .uint16: "16-bit unsigned integer"
        case .uint32: "32-bit unsigned integer"
        case .uint64: "64-bit unsigned integer"
        case .float32: "Single-precision floating point number"
        case .string: "String value"
        }
    }

    /// Whether a field of this type can be plotted (numeric).
    var isNumeric: Bool {
        switch self {
        case .bool, .string: false
        case .uint8, .uint16, .uint32, .uint64, .float32: true
        }
    }

    // MARK: - Binary Format Support

    /// Tag byte used in the `.sentinelsession` binary format.
    var binaryTag: UInt8 {
        switch self {
        case .bool: 0
        case .uint8: 1
        case .uint16: 2
        case .uint32: 3
        case .uint64: 4
        case .float32: 5
        case .string: 6
        }
    }

    /// Reconstruct a `SnapshotFieldDataType` from a binary tag byte.
    static func fromBinaryTag(_ tag: UInt8) -> SnapshotFieldDataType {
        switch tag {
        case 0: .bool
        case 1: .uint8
        case 2: .uint16
        case 3: .uint32
        case 4: .uint64
        case 5: .float32
        case 6: .string
        default: .string
        }
    }
}
