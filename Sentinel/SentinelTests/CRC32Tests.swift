//
//  CRC32Tests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/18/26.
//

import Foundation
import Testing

@testable import Sentinel

/// Pins the CRC-32 implementation against the standard zlib/PNG check values —
/// the same algorithm the firmware `ota-update` library uses for `Verify` (#22).
struct CRC32Tests {
    @Test func emptyIsZero() {
        #expect(CRC32.checksum(of: Data()) == 0)
    }

    @Test func standardCheckVector() {
        // The canonical CRC-32 "check" value for the ASCII string "123456789".
        let data = Data("123456789".utf8)
        #expect(CRC32.checksum(of: data) == 0xCBF4_3926)
    }

    @Test func quickBrownFox() {
        let data = Data("The quick brown fox jumps over the lazy dog".utf8)
        #expect(CRC32.checksum(of: data) == 0x414F_A339)
    }

    @Test func incrementalMatchesOneShot() {
        let whole = Data((0 ..< 5000).map { UInt8($0 & 0xFF) })
        var incremental = CRC32()
        for slice in stride(from: 0, to: whole.count, by: 244) {
            let end = min(slice + 244, whole.count)
            incremental.update(whole.subdata(in: slice ..< end))
        }
        #expect(incremental.checksum == CRC32.checksum(of: whole))
    }

    @Test func checksumIsStableAcrossReads() {
        var crc = CRC32()
        crc.update(Data("123456789".utf8))
        let first = crc.checksum
        let second = crc.checksum // reading must not mutate the accumulator
        #expect(first == second)
    }
}
