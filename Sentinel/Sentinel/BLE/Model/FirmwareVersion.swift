//
//  FirmwareVersion.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import AsyncBluetooth
import Foundation

/// The System service's Firmware Version characteristic — a **5-byte packed**
/// wire value: `major`/`minor`/`patch` (`UInt8`) + `build` (`UInt16`, LE).
/// Mirrors firmware `sentinel_gatt_system.hpp::set_firmware_version` (5-byte buf).
///
/// - Note: Decoded **by hand**, not via ``TriviallyCopyable`` — a Swift struct of
///   `UInt8 · UInt8 · UInt8 · UInt16` pads `build` to a 2-byte boundary (6 bytes),
///   which would not match the packed 5-byte wire layout.
struct FirmwareVersion: Equatable, Sendable, CustomStringConvertible {
    let major: UInt8
    let minor: UInt8
    let patch: UInt8
    let build: UInt16

    var description: String { "\(major).\(minor).\(patch).\(build)" }
    /// Display form without the build number, e.g. `"1.2.3"`.
    var shortVersion: String { "\(major).\(minor).\(patch)" }
}

extension FirmwareVersion {
    /// Decode the **4-byte** `firmware_version_compact` used inside event-log
    /// records (firmware `sentinel_system_event.hpp`): major/minor/patch + build's
    /// **low 8 bits only** (the wire drops the high byte here). Reads at `offset`
    /// within `data`.
    nonisolated static func compact(_ data: Data, at offset: Int) -> FirmwareVersion {
        FirmwareVersion(
            major: data.u8(at: offset),
            minor: data.u8(at: offset + 1),
            patch: data.u8(at: offset + 2),
            build: UInt16(data.u8(at: offset + 3))
        )
    }
}

extension FirmwareVersion: nonisolated PeripheralDataConvertible {
    nonisolated static func fromData(_ data: Data) -> Self? {
        let bytes = [UInt8](data)
        guard bytes.count >= 5 else { return nil }
        let build = UInt16(bytes[3]) | (UInt16(bytes[4]) << 8)
        return FirmwareVersion(major: bytes[0], minor: bytes[1], patch: bytes[2], build: build)
    }

    nonisolated func toData() -> Data? {
        Data([major, minor, patch, UInt8(build & 0xFF), UInt8(build >> 8)])
    }
}
