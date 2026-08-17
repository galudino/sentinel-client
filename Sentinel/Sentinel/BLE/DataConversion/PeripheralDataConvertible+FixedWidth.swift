//
//  PeripheralDataConvertible+FixedWidth.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import Foundation

// AsyncBluetooth ships `PeripheralDataConvertible` conformances for the
// platform-width `Int`/`Double`/`Float` and provides a free `fromData` for any
// `Numeric` conformer — but it does **not** conform the fixed-width integer types
// the firmware GATT contract actually uses (`UInt16` humidity, `Int16`
// temperature 0.01 °C/LSB, `UInt32` pressure Pa, …). Decoding an `Int` where the
// characteristic is 2 bytes would read past the value, so the exact widths must
// conform explicitly.
//
// `fromData` is inherited from AsyncBluetooth's `where Self: Numeric` extension;
// only `toData` needs supplying here. The witnesses are `nonisolated` so the
// conformances are usable from `Sendable`/nonisolated contexts (e.g. the
// `notifications` stream) under this target's `-default-isolation=MainActor`.

extension UInt8: @retroactive nonisolated PeripheralDataConvertible {
    public nonisolated func toData() -> Data? { withUnsafeBytes(of: self) { Data($0) } }
}

extension UInt16: @retroactive nonisolated PeripheralDataConvertible {
    public nonisolated func toData() -> Data? { withUnsafeBytes(of: self) { Data($0) } }
}

extension UInt32: @retroactive nonisolated PeripheralDataConvertible {
    public nonisolated func toData() -> Data? { withUnsafeBytes(of: self) { Data($0) } }
}

extension UInt64: @retroactive nonisolated PeripheralDataConvertible {
    public nonisolated func toData() -> Data? { withUnsafeBytes(of: self) { Data($0) } }
}

extension Int8: @retroactive nonisolated PeripheralDataConvertible {
    public nonisolated func toData() -> Data? { withUnsafeBytes(of: self) { Data($0) } }
}

extension Int16: @retroactive nonisolated PeripheralDataConvertible {
    public nonisolated func toData() -> Data? { withUnsafeBytes(of: self) { Data($0) } }
}

extension Int32: @retroactive nonisolated PeripheralDataConvertible {
    public nonisolated func toData() -> Data? { withUnsafeBytes(of: self) { Data($0) } }
}

extension Int64: @retroactive nonisolated PeripheralDataConvertible {
    public nonisolated func toData() -> Data? { withUnsafeBytes(of: self) { Data($0) } }
}
