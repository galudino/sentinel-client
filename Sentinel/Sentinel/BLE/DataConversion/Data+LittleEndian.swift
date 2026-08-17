//
//  Data+LittleEndian.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation

/// Little-endian scalar reads at a byte offset, for decoding packed firmware wire
/// records (`DeviceSnapshot` #10, `SystemEventRecord` #11) by their locked
/// offsets. Reading at explicit offsets mirrors the firmware `offsetof`
/// `static_assert`s directly and avoids coupling to Swift's struct layout.
///
/// All accessors are offset-relative to `startIndex` (so they work on `Data`
/// slices) and return `nil`-free values only when the caller has bounds-checked
/// the length; each is `precondition`-guarded against overrun.
extension Data {
    private nonisolated func byte(_ offset: Int) -> UInt8 {
        self[startIndex + offset]
    }

    nonisolated func u8(at offset: Int) -> UInt8 {
        precondition(offset + 1 <= count, "u8 read out of bounds")
        return byte(offset)
    }

    nonisolated func i8(at offset: Int) -> Int8 {
        Int8(bitPattern: u8(at: offset))
    }

    nonisolated func u16le(at offset: Int) -> UInt16 {
        precondition(offset + 2 <= count, "u16 read out of bounds")
        return UInt16(byte(offset)) | (UInt16(byte(offset + 1)) << 8)
    }

    nonisolated func i16le(at offset: Int) -> Int16 {
        Int16(bitPattern: u16le(at: offset))
    }

    nonisolated func u32le(at offset: Int) -> UInt32 {
        precondition(offset + 4 <= count, "u32 read out of bounds")
        return UInt32(byte(offset))
            | (UInt32(byte(offset + 1)) << 8)
            | (UInt32(byte(offset + 2)) << 16)
            | (UInt32(byte(offset + 3)) << 24)
    }
}
