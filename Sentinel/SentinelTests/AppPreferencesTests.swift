//
//  AppPreferencesTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation
import Testing

@testable import Sentinel

/// UserDefaults-backed app preferences (#23): defaults, persistence, versioned
/// keys, and unit conversions.
@MainActor
struct AppPreferencesTests {
    private func makeSuite() -> (suite: UserDefaults, name: String) {
        let name = "test.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func defaultsWhenNothingStored() {
        let (suite, name) = makeSuite()
        defer { suite.removePersistentDomain(forName: name) }
        let prefs = AppPreferences(defaults: suite)
        #expect(prefs.theme == .system)
        #expect(prefs.temperatureUnit == .celsius)
        #expect(prefs.pressureUnit == .hectopascals)
        #expect(prefs.showFirmwareUpdateBanner) // true by default, not false
        #expect(!prefs.debugModeEnabled)
    }

    @Test func changesPersistAcrossReload() {
        let (suite, name) = makeSuite()
        defer { suite.removePersistentDomain(forName: name) }
        let prefs = AppPreferences(defaults: suite)
        prefs.theme = .dark
        prefs.temperatureUnit = .fahrenheit
        prefs.showFirmwareUpdateBanner = false

        let reloaded = AppPreferences(defaults: suite)
        #expect(reloaded.theme == .dark)
        #expect(reloaded.temperatureUnit == .fahrenheit)
        #expect(!reloaded.showFirmwareUpdateBanner)
    }

    @Test func versionedKeysAreUsed() {
        let (suite, name) = makeSuite()
        defer { suite.removePersistentDomain(forName: name) }
        let prefs = AppPreferences(defaults: suite)
        prefs.theme = .light
        #expect(suite.string(forKey: "v1.prefs.theme") == "light")
    }

    @Test func unitConversions() {
        #expect(TemperatureUnit.fahrenheit.convert(celsius: 100) == 212)
        #expect(TemperatureUnit.celsius.convert(celsius: 20) == 20)
        #expect(PressureUnit.kilopascals.convert(hectopascals: 1013.25) == 101.325)
    }
}
