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

    @Test func severityTogglesAreIndependent() {
        var filter = DebugLogFilter()
        filter.severities = [.warn, .error] // info off
        let result = filter.apply(to: sampleLines())
        #expect(filter.isActive)
        #expect(result.count == 2) // the .error and the .warn
        #expect(result.allSatisfy { $0.severity != .info })

        filter.severities = [.error] // only errors
        #expect(filter.apply(to: sampleLines()).map(\.text) == ["rssi failed"])
    }

    // MARK: - Service parsing + muting

    @Test func deviceLineParsesServiceTag() {
        let text = "0054 <2026-09-18 01:46:42.000Z> [sentinel_task_bme280_service.cpp:259]"
            + " run <info> bme280_service: sample T=+23.49 C"
        let line = DebugLogLine.fromDevice(text)
        #expect(line.service == "bme280_service")

        let rtc = DebugLogLine.fromDevice("0055 <...> [file.cpp:265] run <info> rtc_service: 2026-09-18 Fri")
        #expect(rtc.service == "rtc_service")
    }

    @Test func unparseableAndLocalLinesHaveNoService() {
        #expect(DebugLogLine.fromDevice("plain line, no service format").service == nil)
        #expect(DebugLogLine.from(BluetoothLogEvent(category: .scan, message: "Scan started")).service == nil)
    }

    @Test func mutedServiceIsHiddenButUntaggedLinesSurvive() {
        let lines = [
            DebugLogLine.fromDevice("0001 <t> [f.cpp:1] run <info> bme280_service: sample"),
            DebugLogLine.fromDevice("0002 <t> [f.cpp:2] run <info> rtc_service: tick"),
            DebugLogLine.fromDevice("no service here")
        ]
        var filter = DebugLogFilter()
        filter.mutedServices = ["bme280_service"]
        let result = filter.apply(to: lines)
        #expect(filter.isActive)
        #expect(result.count == 2) // rtc_service line + the untagged line
        #expect(!result.contains { $0.service == "bme280_service" })
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
