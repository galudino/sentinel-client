//
//  DeviceSnapshot.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import AsyncBluetooth
import Foundation

/// A decoded `device_snapshot` — the firmware's periodic all-subsystem telemetry
/// record. Mirrors firmware `sentinel::telemetry::device_snapshot`
/// (`sentinel_device_snapshot.hpp`, firmware #36): an **80-byte**, packed,
/// little-endian, fixed-point wire record whose field offsets are locked by
/// `static_assert`s on the firmware side.
///
/// Decoded by explicit little-endian offset reads (see the `firmware:` offset on
/// each field) rather than a raw struct copy — the record has 30 fields with
/// reserved padding, so offset decoding mirrors the firmware `offsetof`
/// assertions exactly and stays independent of Swift's struct layout. Reserved
/// regions are intentionally not surfaced.
struct DeviceSnapshot: Equatable, Sendable {
    /// `SNAPSHOT_TRAILER_MAGIC` — written last by firmware, validated on decode.
    nonisolated static let trailerMagic: UInt16 = 0xA5C3
    /// The wire record is exactly this many bytes.
    nonisolated static let wireSize = 80

    // Header (offset 0)
    let unixTimestamp: UInt32 // firmware @0
    let snapshotVersion: UInt8 // firmware @4
    let firmwareVersion: FirmwareVersion // firmware @5 (major/minor/patch) + @8 (build u16)

    // Environment (offset 16)
    let temperatureCentiDegC: Int16 // firmware @16, 0.01 °C
    let humidityCentiPct: UInt16 // firmware @18, 0.01 %RH
    let pressurePa: UInt32 // firmware @20

    // RTC (offset 24)
    let rtcTemperatureCentiDegC: Int16 // firmware @24, 0.01 °C
    let rtcAlarmFlags: UInt8 // firmware @26 (bit0 A1F, bit1 A2F, bit7 OSF)

    // Storage (offset 32)
    let eventLogRecordCount: UInt32 // firmware @32
    let snapshotLogRecordCount: UInt32 // firmware @36

    // BLE (offset 48)
    let bleConnected: Bool // firmware @48
    let bleTxPowerDbm: UInt8 // firmware @49
    /// -RSSI in dBm (wire stores the negated value; 0 when disconnected).
    let blePeerRssiNeg: UInt8 // firmware @50

    // Health (offset 56)
    let cpuTemperatureCentiDegC: UInt16 // firmware @56, 0.01 °C
    let postLastStatus: UInt8 // firmware @58 (0 = pass, else subsystem id)
    let uptimeSeconds: UInt32 // firmware @60

    /// Decode the packed 80-byte wire record. Returns `nil` if the buffer is short
    /// or the trailer magic is wrong (a torn / partially written record).
    nonisolated static func decode(_ data: Data) -> DeviceSnapshot? {
        guard data.count >= wireSize else { return nil }
        guard data.u16le(at: 78) == trailerMagic else { return nil }
        return DeviceSnapshot(
            unixTimestamp: data.u32le(at: 0),
            snapshotVersion: data.u8(at: 4),
            firmwareVersion: FirmwareVersion(
                major: data.u8(at: 5),
                minor: data.u8(at: 6),
                patch: data.u8(at: 7),
                build: data.u16le(at: 8)
            ),
            temperatureCentiDegC: data.i16le(at: 16),
            humidityCentiPct: data.u16le(at: 18),
            pressurePa: data.u32le(at: 20),
            rtcTemperatureCentiDegC: data.i16le(at: 24),
            rtcAlarmFlags: data.u8(at: 26),
            eventLogRecordCount: data.u32le(at: 32),
            snapshotLogRecordCount: data.u32le(at: 36),
            bleConnected: data.u8(at: 48) != 0,
            bleTxPowerDbm: data.u8(at: 49),
            blePeerRssiNeg: data.u8(at: 50),
            cpuTemperatureCentiDegC: data.u16le(at: 56),
            postLastStatus: data.u8(at: 58),
            uptimeSeconds: data.u32le(at: 60)
        )
    }
}

// MARK: PeripheralDataConvertible — read a snapshot straight off a characteristic

extension DeviceSnapshot: nonisolated PeripheralDataConvertible {
    nonisolated static func fromData(_ data: Data) -> DeviceSnapshot? { decode(data) }
    /// Encode is only needed for tests/mocks; produces a valid 80-byte record.
    nonisolated func toData() -> Data? { Self.encode(self) }
}

// MARK: Derived values for views (recomputed, never cached)

extension DeviceSnapshot {
    var timestamp: Date { Date(timeIntervalSince1970: TimeInterval(unixTimestamp)) }
    var temperatureCelsius: Double { Double(temperatureCentiDegC) / 100.0 }
    var humidityPercent: Double { Double(humidityCentiPct) / 100.0 }
    var pressureHectopascals: Double { Double(pressurePa) / 100.0 }
    var rtcTemperatureCelsius: Double { Double(rtcTemperatureCentiDegC) / 100.0 }
    var cpuTemperatureCelsius: Double { Double(cpuTemperatureCentiDegC) / 100.0 }
    /// Signed peer RSSI in dBm (0 when disconnected).
    var blePeerRssiDbm: Int { bleConnected ? -Int(blePeerRssiNeg) : 0 }
    var uptime: Duration { .seconds(uptimeSeconds) }
    var postPassed: Bool { postLastStatus == 0 }
}

// MARK: Sample (previews / mocks)

extension DeviceSnapshot {
    /// A representative snapshot for previews and mock services.
    static let sample = DeviceSnapshot(
        unixTimestamp: 1_760_000_000,
        snapshotVersion: 1,
        firmwareVersion: FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16),
        temperatureCentiDegC: 2345,
        humidityCentiPct: 4567,
        pressurePa: 101_325,
        rtcTemperatureCentiDegC: 2500,
        rtcAlarmFlags: 0,
        eventLogRecordCount: 12,
        snapshotLogRecordCount: 34,
        bleConnected: true,
        bleTxPowerDbm: 4,
        blePeerRssiNeg: 58,
        cpuTemperatureCentiDegC: 4200,
        postLastStatus: 0,
        uptimeSeconds: 3600
    )
}

// MARK: Encode (test/mock support)

extension DeviceSnapshot {
    /// Encode a valid 80-byte wire record (reserved regions zero-filled, trailer
    /// magic set). Inverse of ``decode(_:)`` for the surfaced fields.
    nonisolated static func encode(_ snapshot: DeviceSnapshot) -> Data {
        var bytes = [UInt8](repeating: 0, count: wireSize)
        func put32(_ value: UInt32, _ offset: Int) {
            bytes[offset] = UInt8(value & 0xFF)
            bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
            bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
            bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
        }
        func put16(_ value: UInt16, _ offset: Int) {
            bytes[offset] = UInt8(value & 0xFF)
            bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        }
        put32(snapshot.unixTimestamp, 0)
        bytes[4] = snapshot.snapshotVersion
        bytes[5] = snapshot.firmwareVersion.major
        bytes[6] = snapshot.firmwareVersion.minor
        bytes[7] = snapshot.firmwareVersion.patch
        put16(snapshot.firmwareVersion.build, 8)
        put16(UInt16(bitPattern: snapshot.temperatureCentiDegC), 16)
        put16(snapshot.humidityCentiPct, 18)
        put32(snapshot.pressurePa, 20)
        put16(UInt16(bitPattern: snapshot.rtcTemperatureCentiDegC), 24)
        bytes[26] = snapshot.rtcAlarmFlags
        put32(snapshot.eventLogRecordCount, 32)
        put32(snapshot.snapshotLogRecordCount, 36)
        bytes[48] = snapshot.bleConnected ? 1 : 0
        bytes[49] = snapshot.bleTxPowerDbm
        bytes[50] = snapshot.blePeerRssiNeg
        put16(snapshot.cpuTemperatureCentiDegC, 56)
        bytes[58] = snapshot.postLastStatus
        put32(snapshot.uptimeSeconds, 60)
        put16(trailerMagic, 78)
        return Data(bytes)
    }
}
