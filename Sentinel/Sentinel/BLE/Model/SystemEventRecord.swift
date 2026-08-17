//
//  SystemEventRecord.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation

/// The common 8-byte header of every `system_event_record` (firmware
/// `sentinel_system_event.hpp`): `unix_timestamp` (u32 @0) + `event_type`
/// (u8 @4) + 3 reserved bytes.
struct SystemEventRecordHeader: Equatable, Sendable {
    let unixTimestamp: UInt32
    let eventTypeRaw: UInt8

    nonisolated static let wireSize = 8

    nonisolated var eventType: SystemEvent? { SystemEvent(rawValue: eventTypeRaw) }
    nonisolated var timestamp: Date { Date(timeIntervalSince1970: TimeInterval(unixTimestamp)) }

    nonisolated static func decode(_ data: Data) -> SystemEventRecordHeader? {
        guard data.count >= wireSize else { return nil }
        return SystemEventRecordHeader(unixTimestamp: data.u32le(at: 0), eventTypeRaw: data.u8(at: 4))
    }
}

// MARK: - Typed bodies (each occupies the 28 bytes after the header)

struct BootLifecycleBody: Equatable, Sendable {
    let firmwareVersion: FirmwareVersion // @8 major/minor/patch, @11 build (low 8 bits)
    let bootCount: UInt32 // @12
    let uptimeAtEvent: UInt32 // @16
    nonisolated static func decode(_ data: Data) -> BootLifecycleBody {
        BootLifecycleBody(
            firmwareVersion: .compact(data, at: 8),
            bootCount: data.u32le(at: 12),
            uptimeAtEvent: data.u32le(at: 16)
        )
    }
}

struct FirmwareUpdateBody: Equatable, Sendable {
    let fromVersion: FirmwareVersion // @8
    let toVersion: FirmwareVersion // @12
    let mcubootResult: UInt32 // @16
    nonisolated static func decode(_ data: Data) -> FirmwareUpdateBody {
        FirmwareUpdateBody(
            fromVersion: .compact(data, at: 8),
            toVersion: .compact(data, at: 12),
            mcubootResult: data.u32le(at: 16)
        )
    }
}

struct BLEConnectionBody: Equatable, Sendable {
    let peerAddress: [UInt8] // @8..13 (BD_ADDR, 6 bytes)
    let addressType: UInt8 // @14
    let disconnectReason: UInt8 // @15 (0 for connected events)
    let connectionInterval125us: UInt16 // @16
    let peerMTU: UInt16 // @18
    /// Colon-separated BD_ADDR, MSB first (display convention).
    var peerAddressString: String { peerAddress.reversed().map { String(format: "%02X", $0) }.joined(separator: ":") }
    nonisolated static func decode(_ data: Data) -> BLEConnectionBody {
        BLEConnectionBody(
            peerAddress: (8 ..< 14).map { data.u8(at: $0) },
            addressType: data.u8(at: 14),
            disconnectReason: data.u8(at: 15),
            connectionInterval125us: data.u16le(at: 16),
            peerMTU: data.u16le(at: 18)
        )
    }
}

struct FaultBody: Equatable, Sendable {
    let faultID: UInt8 // @8
    let severity: UInt8 // @9 (0=info 1=warn 2=error 3=crit)
    let subsystemID: UInt8 // @10
    let context: [UInt32] // @12..35 (6 × u32)
    nonisolated static func decode(_ data: Data) -> FaultBody {
        FaultBody(
            faultID: data.u8(at: 8), severity: data.u8(at: 9), subsystemID: data.u8(at: 10),
            context: (0 ..< 6).map { data.u32le(at: 12 + $0 * 4) }
        )
    }
}

struct ModeChangeBody: Equatable, Sendable {
    let fromMode: UInt8 // @8
    let toMode: UInt8 // @9
    let trigger: UInt8 // @10
    nonisolated static func decode(_ data: Data) -> ModeChangeBody {
        ModeChangeBody(fromMode: data.u8(at: 8), toMode: data.u8(at: 9), trigger: data.u8(at: 10))
    }
}

struct POSTResultBody: Equatable, Sendable {
    let subsystemID: UInt8 // @8 (0 for post_passed)
    let result: UInt8 // @9
    let detail: UInt8 // @10
    nonisolated static func decode(_ data: Data) -> POSTResultBody {
        POSTResultBody(subsystemID: data.u8(at: 8), result: data.u8(at: 9), detail: data.u8(at: 10))
    }
}

struct SnapshotEventBody: Equatable, Sendable {
    let snapshotCount: UInt32 // @8
    let reason: UInt8 // @12 (0=periodic, 1=pre-fault)
    nonisolated static func decode(_ data: Data) -> SnapshotEventBody {
        SnapshotEventBody(snapshotCount: data.u32le(at: 8), reason: data.u8(at: 12))
    }
}

// MARK: - High-level record — what views consume

/// A decoded 36-byte `system_event_record`, dispatched on `header.event_type` into
/// a typed body. Mirrors firmware #34. Views render via ``displayTitle`` /
/// ``displaySubtitle`` / ``iconSystemName`` and only reach into the typed bodies
/// for a detail view.
enum SystemEventRecord: Equatable, Sendable {
    case bootLifecycle(SystemEventRecordHeader, BootLifecycleBody)
    case firmwareUpdate(SystemEventRecordHeader, FirmwareUpdateBody)
    case bleConnection(SystemEventRecordHeader, BLEConnectionBody)
    case modeChange(SystemEventRecordHeader, ModeChangeBody)
    case fault(SystemEventRecordHeader, FaultBody)
    case post(SystemEventRecordHeader, POSTResultBody)
    case snapshot(SystemEventRecordHeader, SnapshotEventBody)
    /// A recognized event with no dedicated typed body (config / rtc / pairing /
    /// user-input / sensor-threshold / Phase II fan events).
    case other(SystemEventRecordHeader)
    /// An unrecognized `event_type` — the header + full raw record are preserved.
    case unknown(SystemEventRecordHeader, raw: Data)

    nonisolated static let wireSize = 36

    /// Decode one 36-byte record. Returns `nil` only for a short buffer.
    nonisolated static func decode(_ data: Data) -> SystemEventRecord? {
        guard data.count >= wireSize, let header = SystemEventRecordHeader.decode(data) else { return nil }
        guard let event = header.eventType else { return .unknown(header, raw: data) }
        switch event {
        case .bootComplete, .shutdownClean, .shutdownUnexpected:
            return .bootLifecycle(header, .decode(data))
        case .firmwareUpdateAttempted, .firmwareUpdateCompleted, .firmwareUpdateFailed, .firmwareReverted:
            return .firmwareUpdate(header, .decode(data))
        case .blePeripheralConnected, .blePeripheralDisconnected:
            return .bleConnection(header, .decode(data))
        case .modeChanged:
            return .modeChange(header, .decode(data))
        case .faultRaised, .faultCleared:
            return .fault(header, .decode(data))
        case .postPassed, .postSubsystemFailed:
            return .post(header, .decode(data))
        case .snapshotPersisted, .preFaultSnapshotCaptured:
            return .snapshot(header, .decode(data))
        default:
            return .other(header)
        }
    }

    var header: SystemEventRecordHeader {
        switch self {
        case let .bootLifecycle(header, _), let .firmwareUpdate(header, _), let .bleConnection(header, _),
             let .modeChange(header, _), let .fault(header, _), let .post(header, _),
             let .snapshot(header, _), let .other(header), let .unknown(header, _):
            header
        }
    }

    var timestamp: Date { header.timestamp }
    var event: SystemEvent? { header.eventType }
}
