//
//  HomeView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Charts
import SwiftUI

// MARK: - HomeView

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
    /// Device-minus-phone clock offset (seconds), from the DS3231 Unix-time
    /// characteristic; drives the live-ticking analog clock + date/time text so
    /// the face advances against *device* time without re-reading each second.
    @State private var deviceClockOffset: TimeInterval?
    /// Persisted snapshots for the trend chart, oldest→newest.
    @State private var snapshots: [DeviceSnapshot] = []
    /// When `sample` last changed — drives the "updated N ago" caption.
    @State private var lastUpdated: Date?
    @State private var bannerDismissed = false
    /// Which climate-trend page is showing — bound to the paged `TabView` and the
    /// custom page indicator rendered in the section footer.
    @State private var selectedTrend: ClimateTrendMetric = .temperature

    var body: some View {
        NavigationStack {
            List {
                firmwareBannerSection

                if sample == nil, snapshots.isEmpty {
                    ContentUnavailableView(
                        "Waiting for Environmental Sensor (BME280)",
                        systemImage: "thermometer.medium",
                        description: Text("Live BME280 readings appear as the device reports them.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    climateSection
                    climateTrendsSection
                }

                if deviceClockOffset == nil, snapshots.isEmpty {
                    ContentUnavailableView(
                        "Waiting for Real Time Clock (DS3231)",
                        systemImage: "clock",
                        description: Text("Live DS3231 readings appear as the device reports them.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    timeClockSection
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

    @ViewBuilder private var climateSection: some View {
        Section {
            NavigationLink(destination: {
                if !snapshots.isEmpty {
                    ClimateHistoryDetail(snapshots: snapshots)
                }
            }, label: {
                ClimateHeroCard(sample: sample, lastUpdated: lastUpdated, prefs: prefs)
                    .listRowSeparator(.hidden)
            })
        } header: {
            Label("Climate Readings", systemImage: "thermometer.medium")
        } footer: {
            if let lastUpdated {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("updated \(lastUpdated.formatted(.relative(presentation: .numeric)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var climateTrendsSection: some View {
        Section {
            if trendSnapshots.isEmpty {
                ContentUnavailableView(
                    "No Trends Yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Trends appear here as the device records its periodic snapshots.")
                )
            } else {
                // One reusable TrendChart per metric, paged so the user swipes
                // between temperature / humidity / air pressure. A single chart type
                // (not per-metric subclasses) — the metrics differ only in which
                // field, unit, tint, and precision they pull from each snapshot. The
                // built-in page dots are hidden; the indicator lives in the section
                // footer so it sits on the List background, not inside the card.
                TabView(selection: $selectedTrend) {
                    ForEach(ClimateTrendMetric.allCases) { metric in
                        TrendChart(
                            title: metric.title,
                            points: metric.points(from: trendSnapshots, prefs: prefs),
                            unitSymbol: metric.unitSymbol(prefs),
                            tint: metric.tint,
                            fractionDigits: metric.fractionDigits(prefs)
                        )
                        .tag(metric)
                    }
                }
                .frame(height: 190)
                .tabViewStyle(.page(indexDisplayMode: .never))
                .listRowSeparator(.hidden)
            }
        } header: {
            Label("Climate Trends", systemImage: "chart.xyaxis.line")
        } footer: {
            if !trendSnapshots.isEmpty {
                trendPageIndicator
            }
        }
    }

    /// Page dots for the climate-trend swipe, rendered in the section footer so
    /// they sit on the List's background beneath the card (à la swipeable cards in
    /// other apps). Tappable as a shortcut to each page.
    private var trendPageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(ClimateTrendMetric.allCases) { metric in
                Circle()
                    .fill(metric == selectedTrend ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .onTapGesture { withAnimation { selectedTrend = metric } }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    @ViewBuilder private var timeClockSection: some View {
        Section {
            clockRow
            LabeledContent("Component Temperature") {
                if let rtcTempCentiC {
                    Text(Self.temperatureText(centiC: rtcTempCentiC, prefs: prefs))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            if !componentTemperaturePoints.isEmpty {
                TrendChart(
                    title: "24-Hour Component Temperature",
                    points: componentTemperaturePoints,
                    unitSymbol: prefs.temperatureUnit.symbol,
                    tint: .pink
                )
                .listRowSeparator(.hidden)
            }
        } header: {
            Label("Real Time Clock", systemImage: "clock")
        }
    }

    /// The tappable clock card — parity with the Climate hero card: it navigates to
    /// ``RealTimeClockHistoryDetail`` (the per-snapshot RTC listing).
    private var clockRow: some View {
        NavigationLink {
            if !snapshots.isEmpty {
                RealTimeClockHistoryDetail(snapshots: snapshots)
            }
        } label: {
            clockRowLabel
        }
    }

    /// Live-ticking analog clock + full device date/time. One `TimelineView` drives
    /// both the face and the text so they stay in lockstep; the device clock offset
    /// keeps the face on *device* time, not the phone's.
    @ViewBuilder private var clockRowLabel: some View {
        if let deviceClockOffset {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let shown = context.date.addingTimeInterval(deviceClockOffset)
                HStack(spacing: 16) {
                    AnalogClockView(date: shown)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shown, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                            .font(.headline)
                        Text(shown, format: .dateTime.hour().minute().second())
                            .font(.title3).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        } else {
            LabeledContent("Date & Time") { Text("—").foregroundStyle(.secondary) }
        }
    }

    // MARK: - Derived

    /// Snapshots within 24 h of the most recent one (the device clock is the
    /// reference, not the phone's — they may differ).
    private var trendSnapshots: [DeviceSnapshot] {
        guard let latest = snapshots.last?.timestamp else {
            return []
        }
        let cutoff = latest.addingTimeInterval(-24 * 3600)
        return snapshots.filter { $0.timestamp >= cutoff }
    }

    /// Component (DS3231 on-die) temperature over the trend window, in the user's
    /// unit — feeds the Real-Time-Clock section's trend chart.
    private var componentTemperaturePoints: [TrendPoint] {
        trendSnapshots.map {
            TrendPoint(date: $0.timestamp, value: prefs.temperatureUnit.convert(celsius: $0.rtcTemperatureCelsius))
        }
    }

    // MARK: - Data loading

    private func loadInitial() async {
        if sample == nil {
            sample = try? await bme280.readAmbientSample()
        }
        rtcTempCentiC = try? await ds3231.readRTCTemperature()
        if let seconds = try? await ds3231.readUnixTime() {
            deviceClockOffset = TimeInterval(seconds) - Date().timeIntervalSince1970
        }
        if sample != nil, lastUpdated == nil {
            lastUpdated = .now
        }
        await loadHistory()
    }

    private func loadHistory() async {
        guard let snaps = try? await history.readAllSnapshots() else {
            return
        }
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

// MARK: - Previews

#if DEBUG
    #Preview("Live + history") {
        HomeView(
            deviceName: "Sentinel",
            bme280: MockBME280Service(),
            ds3231: MockDS3231Service(),
            history: MockSnapshotHistoryService(snapshots: DeviceSnapshot.previewSeries())
        )
        .environment(AppPreferences())
    }

    #Preview("Empty history") {
        HomeView(
            deviceName: "Sentinel",
            bme280: MockBME280Service(),
            ds3231: MockDS3231Service(),
            history: MockSnapshotHistoryService(snapshots: [])
        )
        .environment(AppPreferences())
    }

    #Preview("Firmware update") {
        HomeView(
            deviceName: "Sentinel",
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
            deviceName: "Sentinel",
            bme280: MockBME280Service(),
            ds3231: MockDS3231Service(),
            history: MockSnapshotHistoryService(snapshots: DeviceSnapshot.previewSeries())
        )
        .environment(prefs)
    }

    // Every service read fails → the BME280 + DS3231 "waiting" ContentUnavailableViews
    // show (the freshly-connected-but-no-data state the empty-state cards handle).
    #Preview("Awaiting telemetry") {
        HomeView(
            deviceName: "Sentinel",
            bme280: UnavailablePreviewService(),
            ds3231: UnavailablePreviewService(),
            history: UnavailablePreviewService()
        )
        .environment(AppPreferences())
    }

    /// A single preview double that conforms to the three Home services and fails
    /// every read, so Home renders its "awaiting telemetry" empty states.
    private struct UnavailablePreviewService: BME280Service, DS3231Service, SnapshotHistoryService {
        struct Unavailable: Error {}

        // BME280
        func readAmbientSample() async throws -> BME280Sample { throw Unavailable() }
        func ambientSampleNotifications() -> AsyncStream<BME280Sample> { .init { $0.finish() } }

        // DS3231
        func readUnixTime() async throws -> UInt32 { throw Unavailable() }
        func writeUnixTime(_: UInt32) async throws {}
        func readRTCTemperature() async throws -> Int16 { throw Unavailable() }
        func readAlarmFlags() async throws -> UInt8 { throw Unavailable() }
        func setTemperatureNotifying(_: Bool) async throws {}
        func rtcTemperatureNotifications() -> AsyncStream<Int16> { .init { $0.finish() } }

        // SnapshotHistory
        func readRecordCount() async throws -> UInt32 { 0 }
        func readAllSnapshots() async throws -> [DeviceSnapshot] { [] }
        func clearStore() async throws {}

        // setNotifying is required by BME280Service.
        func setNotifying(_: Bool) async throws {}
    }
#endif
