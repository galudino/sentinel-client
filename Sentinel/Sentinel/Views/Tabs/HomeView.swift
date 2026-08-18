//
//  HomeView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Charts
import SwiftUI

/// The **Home** tab (#15) — the Apple-Health-`Summary`-style landing view: an
/// at-a-glance read of the device's current state plus a historical trend.
///
/// Phase I surfaces live BME280 ambient readings (`bme280`, one-shot T/H/P), the
/// DS3231 clock/temperature (`ds3231`), and the 24 h temperature trend decoded
/// from persisted `SnapshotHistoryService` frames. A conditional banner appears
/// when a firmware update is available and jumps to the Device tab.
///
/// This is a **leaf view**: it takes `any <Chip>Service` (not `ConnectedPeer`) so
/// it previews against `Mock*Service` with no BLE — the injected mock *is* the
/// preview seam. Values honor the user's `AppPreferences` unit choices.
struct HomeView: View {
    /// Advertised device name, for the nav title (falls back to "Home").
    let deviceName: String?
    let bme280: any BME280Service
    let ds3231: any DS3231Service
    let history: any SnapshotHistoryService
    /// Whether a newer firmware image is available (from #20's check). Drives the
    /// dismissable banner; tapping it jumps to the Device tab.
    var firmwareUpdateAvailable: Bool = false
    var onShowFirmwareUpdate: () -> Void = {}

    @Environment(AppPreferences.self) private var prefs

    /// Live one-shot ambient sample (BME280); `nil` until the first read/notify.
    @State private var sample: BME280Sample?
    /// Live RTC temperature (0.01 °C/LSB); `nil` until read.
    @State private var rtcTempCentiC: Int16?
    /// Device wall-clock time, from the DS3231 Unix-time characteristic.
    @State private var deviceTime: Date?
    /// Persisted snapshots for the trend chart, oldest→newest.
    @State private var snapshots: [DeviceSnapshot] = []
    /// When `sample` last changed — drives the "updated N ago" caption.
    @State private var lastUpdated: Date?
    @State private var bannerDismissed = false

    var body: some View {
        NavigationStack {
            List {
                firmwareBannerSection
                ambientSection
                timeClockSection

                if sample == nil, snapshots.isEmpty {
                    ContentUnavailableView(
                        "Waiting for Telemetry",
                        systemImage: "sensor.fill",
                        description: Text("Live BME280 readings appear as the device reports them.")
                    )
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(deviceName ?? "Home")
            .refreshable { await loadHistory() }
            // Three concurrent, view-lifetime tasks; each runs on the view's
            // MainActor context, so mutating @State from the stream loops is safe.
            .task { await loadInitial() }
            .task { await observeAmbient() }
            .task { await observeRTCTemperature() }
        }
    }

    // MARK: - Sections

    @ViewBuilder private var firmwareBannerSection: some View {
        if firmwareUpdateAvailable, !bannerDismissed, prefs.showFirmwareUpdateBanner {
            Section {
                Button(action: onShowFirmwareUpdate) {
                    Label {
                        Text("Firmware update available — tap to view")
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.orange)
                    }
                }
                .swipeActions {
                    Button("Dismiss") { bannerDismissed = true }
                }
            }
        }
    }

    @ViewBuilder private var ambientSection: some View {
        Section {
            AmbientHeroCard(sample: sample, lastUpdated: lastUpdated, prefs: prefs)

            if !trendSnapshots.isEmpty {
                TemperatureTrendChart(snapshots: trendSnapshots, prefs: prefs)
            }

            if !snapshots.isEmpty {
                NavigationLink {
                    EnvironmentalHistoryDetail(snapshots: snapshots.reversed())
                } label: {
                    Label("Show all environmental data", systemImage: "list.bullet.rectangle")
                }
            }
        } header: {
            Label("Ambient", systemImage: "thermometer.medium")
        }
    }

    @ViewBuilder private var timeClockSection: some View {
        Section {
            LabeledContent("Device time") {
                if let deviceTime {
                    Text(deviceTime, format: .dateTime.year().month().day().hour().minute().second())
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            LabeledContent("RTC temperature") {
                if let rtcTempCentiC {
                    Text(Self.temperatureText(centiC: rtcTempCentiC, prefs: prefs))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Time & Clock", systemImage: "clock")
        }
    }

    // MARK: - Derived

    /// Snapshots within 24 h of the most recent one (the device clock is the
    /// reference, not the phone's — they may differ).
    private var trendSnapshots: [DeviceSnapshot] {
        guard let latest = snapshots.last?.timestamp else { return [] }
        let cutoff = latest.addingTimeInterval(-24 * 3600)
        return snapshots.filter { $0.timestamp >= cutoff }
    }

    // MARK: - Data loading

    private func loadInitial() async {
        if sample == nil { sample = try? await bme280.readAmbientSample() }
        rtcTempCentiC = try? await ds3231.readRTCTemperature()
        if let seconds = try? await ds3231.readUnixTime() {
            deviceTime = Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        if sample != nil, lastUpdated == nil { lastUpdated = .now }
        await loadHistory()
    }

    private func loadHistory() async {
        guard let snaps = try? await history.readAllSnapshots() else { return }
        snapshots = snaps.sorted { $0.unixTimestamp < $1.unixTimestamp }
    }

    private func observeAmbient() async {
        try? await bme280.setNotifying(true)
        for await next in bme280.ambientSampleNotifications() {
            sample = next
            lastUpdated = .now
        }
    }

    private func observeRTCTemperature() async {
        try? await ds3231.setTemperatureNotifying(true)
        for await next in ds3231.rtcTemperatureNotifications() {
            rtcTempCentiC = next
        }
    }

    // MARK: - Formatting

    /// Format a centidegree-Celsius value in the user's chosen unit, 1 decimal.
    static func temperatureText(centiC: Int16, prefs: AppPreferences) -> String {
        let value = prefs.temperatureUnit.convert(celsius: Double(centiC) / 100.0)
        return value.formatted(.number.precision(.fractionLength(1))) + " " + prefs.temperatureUnit.symbol
    }
}

// MARK: - Ambient hero card

/// The large current-readings card: temperature, humidity, pressure, and a
/// live-updating "updated N ago" caption.
private struct AmbientHeroCard: View {
    let sample: BME280Sample?
    let lastUpdated: Date?
    let prefs: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                reading(
                    value: temperatureValue,
                    unit: prefs.temperatureUnit.symbol,
                    icon: "thermometer.medium",
                    tint: .orange
                )
                reading(value: humidityValue, unit: "%", icon: "humidity", tint: .blue)
                reading(value: pressureValue, unit: prefs.pressureUnit.symbol, icon: "gauge.medium", tint: .teal)
            }

            if let lastUpdated {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("updated \(lastUpdated.formatted(.relative(presentation: .numeric)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func reading(value: String, unit: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title2).fontWeight(.semibold).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var temperatureValue: String {
        guard let sample else { return "—" }
        return prefs.temperatureUnit.convert(celsius: sample.temperatureCelsius)
            .formatted(.number.precision(.fractionLength(1)))
    }

    private var humidityValue: String {
        guard let sample else { return "—" }
        return sample.humidityPercent.formatted(.number.precision(.fractionLength(1)))
    }

    private var pressureValue: String {
        guard let sample else { return "—" }
        let value = prefs.pressureUnit.convert(hectopascals: sample.pressureHectopascals)
        let fraction = prefs.pressureUnit == .inchesOfMercury ? 2 : (prefs.pressureUnit == .kilopascals ? 1 : 0)
        return value.formatted(.number.precision(.fractionLength(fraction)))
    }
}

// MARK: - Temperature trend chart

/// A 24 h temperature line chart with min / max / avg summary, in the user's unit.
private struct TemperatureTrendChart: View {
    let snapshots: [DeviceSnapshot]
    let prefs: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("24-Hour Temperature").font(.subheadline).foregroundStyle(.secondary)

            Chart(snapshots, id: \.unixTimestamp) { snap in
                LineMark(
                    x: .value("Time", snap.timestamp),
                    y: .value("Temp", prefs.temperatureUnit.convert(celsius: snap.temperatureCelsius))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.orange)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 120)

            HStack(spacing: 16) {
                stat("min", minValue)
                stat("max", maxValue)
                stat("avg", avgValue)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium).monospacedDigit()
        }
    }

    private var temps: [Double] {
        snapshots.map { prefs.temperatureUnit.convert(celsius: $0.temperatureCelsius) }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + prefs.temperatureUnit.symbol
    }

    private var minValue: String { temps.min().map(format) ?? "—" }
    private var maxValue: String { temps.max().map(format) ?? "—" }
    private var avgValue: String {
        guard !temps.isEmpty else { return "—" }
        return format(temps.reduce(0, +) / Double(temps.count))
    }
}

// MARK: - Environmental history detail ("Show all")

/// A lightweight list of every persisted snapshot's ambient readings. The rich
/// per-section historical charts are deliberately separate work (see #15); this
/// keeps the "Show all" disclosure a live control rather than a dead end.
private struct EnvironmentalHistoryDetail: View {
    let snapshots: [DeviceSnapshot]
    @Environment(AppPreferences.self) private var prefs

    var body: some View {
        List(snapshots, id: \.unixTimestamp) { snap in
            VStack(alignment: .leading, spacing: 4) {
                Text(snap.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.subheadline)
                HStack(spacing: 16) {
                    Text(HomeView.temperatureText(centiC: snap.temperatureCentiDegC, prefs: prefs))
                    Text(snap.humidityPercent.formatted(.number.precision(.fractionLength(1))) + " %")
                    Text(
                        prefs.pressureUnit.convert(hectopascals: snap.pressureHectopascals)
                            .formatted(.number.precision(.fractionLength(0))) + " " + prefs.pressureUnit.symbol
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .navigationTitle("Environmental Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#if DEBUG
    extension DeviceSnapshot {
        /// Build a 24 h ramp of snapshots for chart previews: `count` frames ending at
        /// `unixTimestamp`, temperature swinging on a diurnal-ish curve.
        static func previewSeries(count: Int = 24, endingAt end: UInt32 = 1_760_000_000) -> [DeviceSnapshot] {
            (0 ..< count).map { index in
                let time = end - UInt32((count - 1 - index) * 3600)
                let phase = Double(index) / Double(max(count - 1, 1)) * 2 * .pi
                let tempC = 21.5 + 2.5 * sin(phase) // ~19–24 °C
                return DeviceSnapshot(
                    unixTimestamp: time,
                    snapshotVersion: 1,
                    firmwareVersion: FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16),
                    temperatureCentiDegC: Int16(tempC * 100),
                    humidityCentiPct: UInt16(4500 + index * 10),
                    pressurePa: 101_325,
                    rtcTemperatureCentiDegC: 2500,
                    rtcAlarmFlags: 0,
                    eventLogRecordCount: 12,
                    snapshotLogRecordCount: UInt32(index),
                    bleConnected: true,
                    bleTxPowerDbm: 4,
                    blePeerRssiNeg: 58,
                    cpuTemperatureCentiDegC: 4200,
                    postLastStatus: 0,
                    uptimeSeconds: 3600
                )
            }
        }
    }

    #Preview("Live + history") {
        HomeView(
            deviceName: "Sentinel-A1B2",
            bme280: MockBME280Service(),
            ds3231: MockDS3231Service(),
            history: MockSnapshotHistoryService(snapshots: DeviceSnapshot.previewSeries())
        )
        .environment(AppPreferences())
    }

    #Preview("Empty history") {
        HomeView(
            deviceName: "Sentinel-A1B2",
            bme280: MockBME280Service(),
            ds3231: MockDS3231Service(),
            history: MockSnapshotHistoryService(snapshots: [])
        )
        .environment(AppPreferences())
    }

    #Preview("Firmware update") {
        HomeView(
            deviceName: "Sentinel-A1B2",
            bme280: MockBME280Service(),
            ds3231: MockDS3231Service(),
            history: MockSnapshotHistoryService(snapshots: DeviceSnapshot.previewSeries()),
            firmwareUpdateAvailable: true
        )
        .environment(AppPreferences())
    }

    #Preview("Fahrenheit · inHg") {
        let prefs = AppPreferences()
        prefs.temperatureUnit = .fahrenheit
        prefs.pressureUnit = .inchesOfMercury
        return HomeView(
            deviceName: "Sentinel-A1B2",
            bme280: MockBME280Service(),
            ds3231: MockDS3231Service(),
            history: MockSnapshotHistoryService(snapshots: DeviceSnapshot.previewSeries())
        )
        .environment(prefs)
    }
#endif
