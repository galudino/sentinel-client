//
//  DebugLogTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 9/17/26.
//

import Foundation
import Testing

@testable import Sentinel

/// Covers the pure-logic core of `DebugOutputStreamView` (#25): source→line
/// mapping (including device-side severity parsing) and the merged-buffer filter.
struct DebugLogTests {
    // MARK: - Local event mapping

    @Test func localEventMapsToInfoUnlessError() {
        let info = DebugLogLine.from(BluetoothLogEvent(category: .connection, message: "Connected"))
        #expect(info.source == .local)
        #expect(info.severity == .info)
        #expect(info.text == "Connected")

        let error = DebugLogLine.from(BluetoothLogEvent(category: .error, message: "RSSI read failed"))
        #expect(error.severity == .error)
    }

    @Test func localEventPreservesIdAndTimestamp() {
        let event = BluetoothLogEvent(category: .scan, message: "Scan started")
        let line = DebugLogLine.from(event)
        #expect(line.id == event.id)
        #expect(line.timestamp == event.timestamp)
    }

    // MARK: - Device line parsing

    @Test func deviceLineDefaultsToInfo() {
        let line = DebugLogLine.fromDevice("bme280 sample: T=22.05")
        #expect(line.source == .device)
        #expect(line.severity == .info)
        #expect(line.text == "bme280 sample: T=22.05")
    }

    @Test func deviceLineParsesAndStripsSeverityMarkers() {
        let warn = DebugLogLine.fromDevice("[WARN] store 80% full")
        #expect(warn.severity == .warn)
        #expect(warn.text == "store 80% full")

        let error = DebugLogLine.fromDevice("[ERROR] i2c timeout")
        #expect(error.severity == .error)
        #expect(error.text == "i2c timeout")
    }

    @Test func deviceSeverityMarkerIsCaseInsensitiveAndTrimmed() {
        let line = DebugLogLine.fromDevice("  [error]  disk lost  ")
        #expect(line.severity == .error)
        #expect(line.text == "disk lost")
    }

    // MARK: - Filter

    private func sampleLines() -> [DebugLogLine] {
        [
            DebugLogLine(timestamp: .now, source: .local, severity: .info, text: "scan started"),
            DebugLogLine(timestamp: .now, source: .local, severity: .error, text: "rssi failed"),
            DebugLogLine(timestamp: .now, source: .device, severity: .info, text: "POST pass"),
            DebugLogLine(timestamp: .now, source: .device, severity: .warn, text: "store nearly full")
        ]
    }

    @Test func defaultFilterKeepsEverythingAndIsInactive() {
        let filter = DebugLogFilter()
        #expect(!filter.isActive)
        #expect(filter.apply(to: sampleLines()).count == 4)
    }

    @Test func sourceTogglesHideThatSource() {
        var filter = DebugLogFilter()
        filter.showDevice = false
        let result = filter.apply(to: sampleLines())
        #expect(filter.isActive)
        #expect(result.allSatisfy { $0.source == .local })
        #expect(result.count == 2)
    }

    @Test func severityThresholdFiltersBelowMinimum() {
        var filter = DebugLogFilter()
        filter.minimumSeverity = .warn
        let result = filter.apply(to: sampleLines())
        #expect(result.count == 2) // the .error and the .warn
        #expect(result.allSatisfy { $0.severity >= .warn })
    }

    @Test func searchIsCaseInsensitiveSubstringAndIgnoresBlank() {
        var filter = DebugLogFilter()
        filter.searchText = "STORE"
        #expect(filter.apply(to: sampleLines()).map(\.text) == ["store nearly full"])

        filter.searchText = "   "
        #expect(!filter.isActive)
        #expect(filter.apply(to: sampleLines()).count == 4)
    }
}
