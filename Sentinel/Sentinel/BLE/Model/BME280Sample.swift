//
//  BME280Sample.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import AsyncBluetooth
import Foundation

/// The BME280 Ambient Sample characteristic — one packed, little-endian **8-byte**
/// combined sample (the one-shot-sample rule: the driver returns T/H/P in a single
/// read, so the contract is one characteristic, not three). Mirrors firmware
/// `sentinel::gatt::bme280::bme280_sample` (`sentinel_gatt_bme280.hpp`).
///
/// All fields are naturally aligned (`Int16`@0 · `UInt16`@2 · `UInt32`@4 = 8 B),
/// so this decodes byte-exact via ``TriviallyCopyable`` (declaration-order layout,
/// guarded by the wire-order round-trip test in `BluetoothTransportTests`).
struct BME280Sample: Equatable, Sendable {
    /// Temperature, 0.01 °C / LSB (e.g. 2345 = 23.45 °C).
    let temperatureCentiDegC: Int16
    /// Relative humidity, 0.01 %RH / LSB.
    let humidityCentiPct: UInt16
    /// Barometric pressure, Pa.
    let pressurePa: UInt32
}

extension BME280Sample: TriviallyCopyable {}

// MARK: Derived values for views (recomputed, never cached)

extension BME280Sample {
    var temperatureCelsius: Double { Double(temperatureCentiDegC) / 100.0 }
    var humidityPercent: Double { Double(humidityCentiPct) / 100.0 }
    var pressureHectopascals: Double { Double(pressurePa) / 100.0 }
}
