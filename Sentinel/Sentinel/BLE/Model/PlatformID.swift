//
//  PlatformID.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation

/// The device's machine-stable platform identity, read from the System service's
/// Platform ID characteristic. Mirrors firmware `sentinel::platform_id`
/// (`Sentinel/src/utilities/sentinel_platform_id.hpp`).
///
/// Firmware-selection and (Phase IV) the cloud `target` switch on **this**, never
/// on the human-readable Model Number string.
enum PlatformID: UInt8, CaseIterable, Sendable {
    case unknown = 0x00
    case cyble416045 = 0x01
    case rpi5 = 0x02
    case nrf5340 = 0x03

    /// Human-readable model name (display only — never a selection key).
    var modelName: String {
        switch self {
        case .unknown: "Unknown"
        case .cyble416045: "CYBLE-416045-EVAL"
        case .rpi5: "Raspberry Pi 5"
        case .nrf5340: "nRF5340"
        }
    }

    var vendor: VendorID {
        switch self {
        case .cyble416045: .infineon
        case .rpi5: .raspberryPiLtd
        case .nrf5340: .nordicSemiconductor
        case .unknown: .unknown
        }
    }
}

/// Vendor identity, mirrors firmware `sentinel::vendor_id`. Feeds the DIS
/// Manufacturer Name + PnP ID.
enum VendorID: UInt8, CaseIterable, Sendable {
    case unknown = 0x00
    case infineon = 0x01
    case raspberryPiLtd = 0x02
    case nordicSemiconductor = 0x03

    var manufacturerName: String {
        switch self {
        case .unknown: "Unknown"
        case .infineon: "Infineon Technologies"
        case .raspberryPiLtd: "Raspberry Pi Ltd"
        case .nordicSemiconductor: "Nordic Semiconductor"
        }
    }
}
