//
//  CharacteristicCatalog.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/19/26.
//

import CoreBluetooth
import Foundation

// ============================================================================
// The characteristic catalog — the single source of truth that drives the GATT
// Explorer (#18). One ``CharacteristicDescriptor`` per characteristic in the #9
// contract (``GATTContract.swift``): display name, catalogued data type, LSB
// unit, and BLE properties. A unit test asserts every characteristic enum case
// has a descriptor, so a new firmware characteristic can't be added without one.
//
// The Explorer is deliberately utilitarian: this decoder handles the scalar and
// a few structured types well enough to *inspect* a characteristic; the polished
// per-chip views own rich decoding.
// ============================================================================

/// How a characteristic's raw bytes should be interpreted for display.
enum GATTDataType: Sendable {
    case uint8, uint16, uint32, uint64
    case int8, int16, int32
    case float32
    case unixTimeSeconds // UInt32 epoch seconds → Date
    case firmwareVersion // 5-byte packed FirmwareVersion
    case platformID // UInt8 → PlatformID.modelName
    case utf8 // UTF-8 text
    case bme280Sample // packed 8-byte BME280Sample
    case deviceSnapshot // packed 80-byte DeviceSnapshot
    case deviceSnapshotBlock // N × DeviceSnapshot
    case eventRecordBlock // N × 36-byte event record
    case deviceReadiness // 2-byte [state, failedSubsystem] (#69)
    case bytes // opaque

    /// Fixed byte width for the fixed-width scalar types; `nil` for variable.
    var byteWidth: Int? {
        switch self {
        case .uint8, .int8, .platformID: 1
        case .uint16, .int16: 2
        case .uint32, .int32, .float32, .unixTimeSeconds: 4
        case .uint64: 8
        case .firmwareVersion: 5
        default: nil
        }
    }

    /// Whether the type is a plain integer that has meaningful dec/hex/oct forms.
    var isScalarInteger: Bool {
        switch self {
        case .uint8, .uint16, .uint32, .uint64, .int8, .int16, .int32,
             .unixTimeSeconds, .platformID:
            true
        default:
            false
        }
    }

    /// The little-endian value as an unsigned integer, for the dec/hex/oct forms.
    /// `nil` for non-scalar or short data.
    func unsignedScalar(_ data: Data) -> UInt64? {
        guard isScalarInteger, let width = byteWidth, data.count >= width else { return nil }
        var value: UInt64 = 0
        for offset in 0 ..< width {
            value |= UInt64(data[data.startIndex + offset]) << (8 * offset)
        }
        return value
    }

    /// The little-endian value as a signed integer (sign-extended by width).
    func signedScalar(_ data: Data) -> Int64? {
        guard let raw = unsignedScalar(data), let width = byteWidth else { return nil }
        let bits = width * 8
        if bits < 64, (raw & (1 << (bits - 1))) != 0 {
            return Int64(bitPattern: raw | (~UInt64(0) << bits))
        }
        return Int64(bitPattern: raw)
    }

    /// The human-readable "decoded value" — unit-applied where the LSB unit
    /// encodes a scale (e.g. `"0.01 °C"`).
    func interpreted(_ data: Data, lsbUnit: String?) -> String {
        guard !data.isEmpty else { return "(empty)" }
        switch self {
        case .uint8, .uint16, .uint32, .uint64:
            return scaledScalar(unsignedScalar(data).map(Double.init), lsbUnit: lsbUnit)
        case .int8, .int16, .int32:
            return scaledScalar(signedScalar(data).map(Double.init), lsbUnit: lsbUnit)
        case .float32:
            return interpretedFloat(data, lsbUnit: lsbUnit)
        case .unixTimeSeconds:
            guard let secs = unsignedScalar(data) else { return "(short)" }
            return Date(timeIntervalSince1970: TimeInterval(secs))
                .formatted(date: .abbreviated, time: .standard)
        case .firmwareVersion:
            guard data.count >= 5 else { return "(short)" }
            return FirmwareVersion.compact(data, at: data.startIndex).description
        case .platformID:
            let raw = data[data.startIndex]
            return (PlatformID(rawValue: raw)?.modelName ?? "Unknown").appending(" (0x\(hex(raw)))")
        default:
            return structuredSummary(data)
        }
    }

    /// Decode the 2-byte Device Readiness value into an explorer-friendly string.
    private func interpretedReadiness(_ data: Data) -> String {
        guard let readiness = DeviceReadiness.fromData(data) else { return "(short)" }
        switch readiness.state {
        case .booting: return "Booting"
        case .postRunning: return "Running self-test"
        case .ready: return "Ready"
        case .degraded:
            let subsystem = readiness.failedSubsystem?.displayName
                ?? "subsystem 0x\(hex(readiness.failedSubsystemID))"
            return "Degraded — \(subsystem) failed"
        }
    }

    /// A byte-count summary for the non-scalar structured / opaque / text types.
    private func structuredSummary(_ data: Data) -> String {
        switch self {
        case .utf8: String(bytes: data, encoding: .utf8) ?? "(non-UTF-8, \(data.count) B)"
        case .bme280Sample: "BME280 sample — \(data.count) B"
        case .deviceSnapshot: "Device snapshot — \(data.count) B"
        case .deviceSnapshotBlock: "\(data.count / 80) snapshot(s) — \(data.count) B"
        case .eventRecordBlock: "\(data.count / 36) record(s) — \(data.count) B"
        case .deviceReadiness: interpretedReadiness(data)
        default: "\(data.count) B opaque"
        }
    }

    private func interpretedFloat(_ data: Data, lsbUnit: String?) -> String {
        guard data.count >= 4 else { return "(short)" }
        // Assemble the 4 bytes little-endian (byte 0 = LSB) into the host-order
        // bit pattern; iOS is little-endian so this is the wire value.
        var bits: UInt32 = 0
        for offset in 0 ..< 4 {
            bits |= UInt32(data[data.startIndex + offset]) << (8 * offset)
        }
        let floatValue = Float(bitPattern: bits)
        return floatValue.formatted(.number.precision(.fractionLength(0 ... 3))) + unitSuffix(lsbUnit)
    }

    // MARK: - Helpers

    private func scaledScalar(_ value: Double?, lsbUnit: String?) -> String {
        guard let value else { return "(short)" }
        let (scale, unit) = Self.parseUnit(lsbUnit)
        let scaled = value * scale
        let text = scale == 1
            ? String(format: "%.0f", value)
            : scaled.formatted(.number.precision(.fractionLength(0 ... 2)))
        return unit.isEmpty ? text : "\(text) \(unit)"
    }

    private func unitSuffix(_ lsbUnit: String?) -> String {
        let (_, unit) = Self.parseUnit(lsbUnit)
        return unit.isEmpty ? "" : " \(unit)"
    }

    private func hex(_ byte: UInt8) -> String { String(format: "%02X", byte) }

    /// Splits `"0.01 °C"` into `(0.01, "°C")`; a non-numeric prefix means scale 1.
    static func parseUnit(_ lsbUnit: String?) -> (scale: Double, unit: String) {
        guard let lsbUnit, !lsbUnit.isEmpty else { return (1, "") }
        let parts = lsbUnit.split(separator: " ", maxSplits: 1).map(String.init)
        if let first = parts.first, let scale = Double(first) {
            return (scale, parts.count > 1 ? parts[1] : "")
        }
        return (1, lsbUnit)
    }
}

/// A single characteristic's catalog entry — drives the GATT Explorer detail view.
struct CharacteristicDescriptor: Identifiable, Sendable {
    let service: SentinelServiceUUID
    let characteristicCBUUID: CBUUID
    let displayName: String
    let dataType: GATTDataType
    /// e.g. `"0.01 °C"`, `"s"`; `nil` when the value carries no unit.
    let lsbUnit: String?
    let properties: CBCharacteristicProperties

    var id: String { characteristicCBUUID.uuidString }
}

/// The catalog: one descriptor per characteristic in ``GATTContract.swift``.
/// Enforced complete by `CharacteristicCatalogTests`.
enum CharacteristicCatalog {
    static let all: [CharacteristicDescriptor] = [
        // BME280 ---------------------------------------------------------------
        .init(
            service: .bme280,
            characteristicCBUUID: BME280CharacteristicUUID.ambientSample.cbuuid,
            displayName: "Ambient Sample",
            dataType: .bme280Sample,
            lsbUnit: nil,
            properties: [.read, .notify]
        ),

        // DS3231 ---------------------------------------------------------------
        .init(
            service: .ds3231,
            characteristicCBUUID: DS3231CharacteristicUUID.unixTime.cbuuid,
            displayName: "Unix Time",
            dataType: .unixTimeSeconds,
            lsbUnit: "s",
            properties: [.read, .write]
        ),
        .init(
            service: .ds3231,
            characteristicCBUUID: DS3231CharacteristicUUID.rtcTemperature.cbuuid,
            displayName: "RTC Temperature",
            dataType: .int16,
            lsbUnit: "0.01 °C",
            properties: [.read, .notify]
        ),
        .init(
            service: .ds3231,
            characteristicCBUUID: DS3231CharacteristicUUID.alarmFlags.cbuuid,
            displayName: "Alarm Flags",
            dataType: .uint8,
            lsbUnit: nil,
            properties: [.read]
        ),

        // System ---------------------------------------------------------------
        .init(
            service: .system,
            characteristicCBUUID: SystemCharacteristicUUID.serialNumber.cbuuid,
            displayName: "Serial Number",
            dataType: .uint32,
            lsbUnit: nil,
            properties: [.read, .write]
        ),
        .init(
            service: .system,
            characteristicCBUUID: SystemCharacteristicUUID.firmwareVersion.cbuuid,
            displayName: "Firmware Version",
            dataType: .firmwareVersion,
            lsbUnit: nil,
            properties: [.read]
        ),
        .init(
            service: .system,
            characteristicCBUUID: SystemCharacteristicUUID.platformID.cbuuid,
            displayName: "Platform ID",
            dataType: .platformID,
            lsbUnit: nil,
            properties: [.read]
        ),
        .init(
            service: .system,
            characteristicCBUUID: SystemCharacteristicUUID.cpuTemperature.cbuuid,
            displayName: "CPU Temperature",
            dataType: .uint16,
            lsbUnit: "0.01 °C",
            properties: [.read, .notify]
        ),
        .init(
            service: .system,
            characteristicCBUUID: SystemCharacteristicUUID.deviceReadiness.cbuuid,
            displayName: "Device Readiness",
            dataType: .deviceReadiness,
            lsbUnit: nil,
            properties: [.read, .notify]
        ),

        // Snapshot stream ------------------------------------------------------
        .init(
            service: .snapshotStream,
            characteristicCBUUID: SnapshotStreamCharacteristicUUID.currentDeviceSnapshot.cbuuid,
            displayName: "Current Device Snapshot",
            dataType: .deviceSnapshot,
            lsbUnit: nil,
            properties: [.read, .notify]
        ),
        .init(
            service: .snapshotStream,
            characteristicCBUUID: SnapshotStreamCharacteristicUUID.snapshotNotifyEnable.cbuuid,
            displayName: "Snapshot Notify Enable",
            dataType: .uint8,
            lsbUnit: nil,
            properties: [.read, .write]
        ),

        // Snapshot history -----------------------------------------------------
        .init(
            service: .snapshotHistory,
            characteristicCBUUID: SnapshotHistoryCharacteristicUUID.recordCount.cbuuid,
            displayName: "Record Count",
            dataType: .uint32,
            lsbUnit: nil,
            properties: [.read]
        ),
        .init(
            service: .snapshotHistory,
            characteristicCBUUID: SnapshotHistoryCharacteristicUUID.index.cbuuid,
            displayName: "Read Index",
            dataType: .uint32,
            lsbUnit: nil,
            properties: [.read, .write]
        ),
        .init(
            service: .snapshotHistory,
            characteristicCBUUID: SnapshotHistoryCharacteristicUUID.recordBlock.cbuuid,
            displayName: "Record Block",
            dataType: .deviceSnapshotBlock,
            lsbUnit: nil,
            properties: [.read]
        ),
        .init(
            service: .snapshotHistory,
            characteristicCBUUID: SnapshotHistoryCharacteristicUUID.clearStore.cbuuid,
            displayName: "Clear Store",
            dataType: .uint8,
            lsbUnit: nil,
            properties: [.read, .write]
        ),

        // System event log -----------------------------------------------------
        .init(
            service: .systemEventLog,
            characteristicCBUUID: SystemEventLogCharacteristicUUID.recordCount.cbuuid,
            displayName: "Record Count",
            dataType: .uint32,
            lsbUnit: nil,
            properties: [.read]
        ),
        .init(
            service: .systemEventLog,
            characteristicCBUUID: SystemEventLogCharacteristicUUID.index.cbuuid,
            displayName: "Read Index",
            dataType: .uint32,
            lsbUnit: nil,
            properties: [.read, .write]
        ),
        .init(
            service: .systemEventLog,
            characteristicCBUUID: SystemEventLogCharacteristicUUID.recordBlock.cbuuid,
            displayName: "Record Block",
            dataType: .eventRecordBlock,
            lsbUnit: nil,
            properties: [.read]
        ),
        .init(
            service: .systemEventLog,
            characteristicCBUUID: SystemEventLogCharacteristicUUID.clearStore.cbuuid,
            displayName: "Clear Store",
            dataType: .uint8,
            lsbUnit: nil,
            properties: [.read, .write]
        ),

        // OTA FW Upgrade -------------------------------------------------------
        .init(
            service: .ota,
            characteristicCBUUID: OTACharacteristicUUID.controlPoint.cbuuid,
            displayName: "OTA Control Point",
            dataType: .bytes,
            lsbUnit: nil,
            properties: [.write, .notify, .indicate]
        ),
        .init(
            service: .ota,
            characteristicCBUUID: OTACharacteristicUUID.data.cbuuid,
            displayName: "OTA Data",
            dataType: .bytes,
            lsbUnit: nil,
            properties: [.write]
        ),

        // Debug stream ---------------------------------------------------------
        .init(
            service: .debugStream,
            characteristicCBUUID: DebugStreamCharacteristicUUID.outputStream.cbuuid,
            displayName: "Output Stream",
            dataType: .utf8,
            lsbUnit: nil,
            properties: [.read, .notify]
        ),
        .init(
            service: .debugStream,
            characteristicCBUUID: DebugStreamCharacteristicUUID.notifyEnable.cbuuid,
            displayName: "Notify Enable",
            dataType: .uint8,
            lsbUnit: nil,
            properties: [.read, .write]
        )
    ]

    /// Descriptors for one service, in catalog order.
    static func descriptors(for service: SentinelServiceUUID) -> [CharacteristicDescriptor] {
        all.filter { $0.service == service }
    }

    static func descriptor(for cbuuid: CBUUID) -> CharacteristicDescriptor? {
        all.first { $0.characteristicCBUUID == cbuuid }
    }
}

extension SentinelServiceUUID {
    /// Human-readable service name for the GATT Explorer list.
    var displayName: String {
        switch self {
        case .bme280: "BME280"
        case .ds3231: "DS3231 RTC"
        case .system: "System"
        case .snapshotStream: "Snapshot Stream"
        case .snapshotHistory: "Snapshot History"
        case .systemEventLog: "System Event Log"
        case .ota: "OTA FW Upgrade"
        case .debugStream: "Debug Stream"
        }
    }
}
