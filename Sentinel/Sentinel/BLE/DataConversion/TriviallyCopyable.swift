//
//  TriviallyCopyable.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import Foundation

/// Opt-in for **packed, fixed-layout POD structs** that decode byte-for-byte from
/// a characteristic's `Data` (and back). Conform a `@frozen`/C-layout struct to
/// get ``AsyncBluetooth/PeripheralDataConvertible`` for free, so it can flow
/// through ``BluetoothPeripheralTransport`` exactly like a primitive:
///
/// ```swift
/// struct FirmwareVersion: TriviallyCopyable { let major, minor, patch: UInt8; let build: UInt16 }
/// let v: FirmwareVersion? = try await transport.read(characteristic: …, ofService: …)
/// ```
///
/// The concrete Phase I wire structs (`DeviceSnapshot`, `SystemEventRecordRaw`,
/// `FirmwareVersion`) are defined and conformed by the decoder issues (#10 / #11)
/// against the firmware byte layout (firmware #34 / #36). This file supplies only
/// the mechanism.
///
/// - Important: Only safe for types with **no padding, no references, and a
///   layout that matches the wire format exactly** — i.e. genuine C-style PODs.
///   The wire is little-endian; these run only on little-endian Apple silicon,
///   so a raw byte copy is correct without swapping.
protocol TriviallyCopyable: PeripheralDataConvertible {}

extension TriviallyCopyable {
    // `nonisolated` so conforming structs are usable from `Sendable`/nonisolated
    // contexts under this target's `-default-isolation=MainActor`.
    nonisolated static func fromData(_ data: Data) -> Self? {
        guard data.count >= MemoryLayout<Self>.size else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Self.self) }
    }

    nonisolated func toData() -> Data? {
        withUnsafeBytes(of: self) { Data($0) }
    }
}
