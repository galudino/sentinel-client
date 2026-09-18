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

    private let sampleDeviceLine =
        "0056 <2026-09-18 01:47:27.000Z> [sentinel_task_cpu_die_temp_service.cpp:143]"
            + " run <warn> cpu_die_temp: die=+30 C"

    @Test func deviceLineKeepsFullTextAndParsesSeverityFromLevel() {
        let line = DebugLogLine.fromDevice(sampleDeviceLine)
        #expect(line.source == .device)
        #expect(line.text == sampleDeviceLine) // full line preserved, nothing stripped
        #expect(line.severity == .warn) // from <warn>, not a leading marker

        let err = DebugLogLine.fromDevice("0057 <t> [f.cpp:9] run <error> x: boom")
        #expect(err.severity == .error)
        let info = DebugLogLine.fromDevice("0058 <t> [f.cpp:9] init <info> y: ok")
        #expect(info.severity == .info)
    }

    @Test func deviceLineParsesFileAndFunction() {
        let line = DebugLogLine.fromDevice(sampleDeviceLine)
        #expect(line.file == "sentinel_task_cpu_die_temp_service.cpp")
        #expect(line.function == "run")
    }

    @Test func unstructuredDeviceLineIsInfoWithNoFacets() {
        let line = DebugLogLine.fromDevice("bme280 sample: T=22.05")
        #expect(line.severity == .info)
        #expect(line.service == nil)
        #expect(line.file == nil)
    }

    @Test func leadingMarkerFallbackSetsSeverityWithoutLevel() {
        // No <level> present → fall back to a leading [WARN]/[ERROR] marker.
        #expect(DebugLogLine.fromDevice("[ERROR] i2c timeout").severity == .error)
        #expect(DebugLogLine.fromDevice("[WARN] store 80% full").severity == .warn)
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

        // Service parses regardless of the emitting function (not just `run`).
        let boot = DebugLogLine.fromDevice("0001 <t> [boot.cpp:12] init <info> boot_orchestrator: POST pass")
        #expect(boot.service == "boot_orchestrator")
        #expect(boot.function == "init")
    }

    @Test func filterRoundTripsThroughRawValue() {
        var filter = DebugLogFilter()
        filter.severities = [.error]
        filter.mutedServices = ["bme280_service"]
        filter.showLocal = false
        filter.searchText = "boom"
        #expect(DebugLogFilter(rawValue: filter.rawValue) == filter)
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
