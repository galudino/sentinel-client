//
//  AppPreferences.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation
import Observation
import SwiftUI

/// App-side preferences (theme, units, notification + debug toggles), persisted to
/// UserDefaults under the versioned `v1.prefs.*` keys. `@Observable`, **no
/// singleton** — created in `SentinelApp.init()` and injected. Device-side concerns
/// live in the Device tab, not here.
@Observable
final class AppPreferences {
    var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: Key.temperatureUnit) }
    }

    var pressureUnit: PressureUnit { didSet { defaults.set(pressureUnit.rawValue, forKey: Key.pressureUnit) } }
    var showFirmwareUpdateBanner: Bool { didSet { defaults.set(
        showFirmwareUpdateBanner,
        forKey: Key.showFirmwareUpdateBanner
    ) } }
    var debugModeEnabled: Bool { didSet { defaults.set(debugModeEnabled, forKey: Key.debugModeEnabled) } }

    private let defaults: UserDefaults

    private enum Key {
        static let theme = "v1.prefs.theme"
        static let temperatureUnit = "v1.prefs.temperatureUnit"
        static let pressureUnit = "v1.prefs.pressureUnit"
        static let showFirmwareUpdateBanner = "v1.prefs.showFirmwareUpdateBanner"
        static let debugModeEnabled = "v1.prefs.debugModeEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: Key.theme).flatMap(Theme.init) ?? .system
        temperatureUnit = defaults.string(forKey: Key.temperatureUnit).flatMap(TemperatureUnit.init) ?? .celsius
        pressureUnit = defaults.string(forKey: Key.pressureUnit).flatMap(PressureUnit.init) ?? .hectopascals
        // Bool defaults: absent key reads as false, so store the intended default.
        showFirmwareUpdateBanner = defaults.object(forKey: Key.showFirmwareUpdateBanner) as? Bool ?? true
        debugModeEnabled = defaults.bool(forKey: Key.debugModeEnabled)
    }
}

enum Theme: String, CaseIterable, Sendable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The SwiftUI override, or `nil` to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum TemperatureUnit: String, CaseIterable, Sendable {
    case celsius, fahrenheit

    var symbol: String { self == .celsius ? "°C" : "°F" }

    /// Convert a Celsius value into this unit.
    func convert(celsius value: Double) -> Double {
        self == .celsius ? value : value * 9 / 5 + 32
    }
}

enum PressureUnit: String, CaseIterable, Sendable {
    case hectopascals, kilopascals, inchesOfMercury

    var symbol: String {
        switch self {
        case .hectopascals: "hPa"
        case .kilopascals: "kPa"
        case .inchesOfMercury: "inHg"
        }
    }

    /// Convert a hectopascal value into this unit.
    func convert(hectopascals value: Double) -> Double {
        switch self {
        case .hectopascals: value
        case .kilopascals: value / 10
        case .inchesOfMercury: value * 0.029529983
        }
    }
}
