//
//  DeviceCategory.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/19/26.
//

import Foundation

/// The rows of the **Device** tab hub (#18). `DeviceView` is a navigation list,
/// not one inline screen: this enum is the single place that defines the hub —
/// adding a subview = adding a case here + a branch in `DeviceView.detailView`.
/// Mirrors the proven control-panel-hub pattern.
///
/// `availableInPhaseI` gates the Phase II sensor-config rows: they appear in the
/// list but disabled with a "Coming in Phase II" subtitle until their firmware
/// characteristics land (expansion umbrella #27).
enum DeviceCategory: Int, CaseIterable, Identifiable, Hashable {
    case deviceInfo // About: name, serial, firmware, CPU temp, RSSI, MTU
    case firmware // → FirmwareSelectionView (#20)
    case timeAndDate // RTC read + "Sync from iPhone" (#18 write)
    case storage // clear event log / clear snapshot history
    case debugStream // → DebugOutputStreamView (#25)
    case gattExplorer // diagnostic services → characteristics browser

    // Phase II — one configuration subview per configurable chip (umbrella #27).
    case bme280Config
    case ds3231Config

    var id: Self { self }

    var title: String {
        switch self {
        case .deviceInfo: "Device Info"
        case .firmware: "Firmware"
        case .timeAndDate: "Time & Date"
        case .storage: "Storage"
        case .debugStream: "Debug Output"
        case .gattExplorer: "GATT Explorer"
        case .bme280Config: "BME280 Configuration"
        case .ds3231Config: "DS3231 Configuration"
        }
    }

    var systemImage: String {
        switch self {
        case .deviceInfo: "info.circle"
        case .firmware: "cpu"
        case .timeAndDate: "calendar.badge.clock"
        case .storage: "internaldrive"
        case .debugStream: "terminal"
        case .gattExplorer: "list.bullet.rectangle"
        case .bme280Config: "thermometer.medium"
        case .ds3231Config: "clock.circle"
        }
    }

    /// Phase II rows are shown disabled with a "Coming in Phase II" subtitle until
    /// their firmware characteristics exist.
    var availableInPhaseI: Bool {
        switch self {
        case .bme280Config, .ds3231Config: false
        default: true
        }
    }

    /// The Phase I rows, in list order.
    static var phaseIRows: [DeviceCategory] { allCases.filter(\.availableInPhaseI) }

    /// The Phase II (disabled) rows, in list order.
    static var phaseIIRows: [DeviceCategory] { allCases.filter { !$0.availableInPhaseI } }
}
