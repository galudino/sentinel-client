//
//  CRC32.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/18/26.
//

import Foundation

/// Standard zlib/PNG CRC-32 (reflected polynomial `0xEDB88320`, init
/// `0xFFFFFFFF`, final XOR `0xFFFFFFFF`), computed incrementally so the OTA
/// uploader (#22) can fold each chunk in as it streams rather than buffering the
/// whole image. This is the exact CRC the firmware's `ota-update` library expects
/// in the `Verify` control-point command — round-tripping it is what proves the
/// upload landed intact.
///
/// `nonisolated` (and a value type) so it is usable from any isolation domain
/// under this target's `-default-isolation=MainActor`.
nonisolated struct CRC32: Sendable {
    /// The reflected-polynomial lookup table, built once.
    private static let table: [UInt32] = (0 ..< 256).map { index -> UInt32 in
        var crc = UInt32(index)
        for _ in 0 ..< 8 {
            crc = (crc & 1) != 0 ? (0xEDB8_8320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    private var state: UInt32 = 0xFFFF_FFFF

    init() {}

    /// Fold `data` into the running checksum.
    mutating func update(_ data: Data) {
        for byte in data {
            let index = Int((state ^ UInt32(byte)) & 0xFF)
            state = (state >> 8) ^ Self.table[index]
        }
    }

    /// The finalized checksum (final XOR applied). Reading this does not mutate the
    /// accumulator, so `update` may continue afterward.
    var checksum: UInt32 { state ^ 0xFFFF_FFFF }

    /// One-shot convenience for a complete buffer.
    static func checksum(of data: Data) -> UInt32 {
        var crc = CRC32()
        crc.update(data)
        return crc.checksum
    }
}
