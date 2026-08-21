//
//  HomeSupportingViews.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/20/26.
//

import SwiftUI

// MARK: - ClimateHeroCard

/// The large current-readings card: temperature, humidity, and air pressure.
/// Tapping it (from ``HomeView``) navigates to ``ClimateHistoryDetail``.
struct ClimateHeroCard: View {
    let sample: BME280Sample?
    let lastUpdated: Date?
    let prefs: AppPreferences

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                reading(
                    value: temperatureValue,
                    unit: prefs.temperatureUnit.symbol,
                    icon: "thermometer.medium",
                    tint: .orange
                )
                Spacer()
                reading(value: humidityValue, unit: "%", icon: "humidity", tint: .blue)
                Spacer()
                reading(value: pressureValue, unit: prefs.pressureUnit.symbol, icon: "gauge.medium", tint: .teal)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func reading(value: String, unit: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title2).fontWeight(.semibold).monospacedDigit()
                Text(unit).font(.footnote).foregroundStyle(.secondary)
            }
        }
        Spacer()
    }

    private var temperatureValue: String {
        guard let sample else {
            return "—"
        }
        return prefs.temperatureUnit.convert(celsius: sample.temperatureCelsius)
            .formatted(.number.precision(.fractionLength(1)))
    }

    private var humidityValue: String {
        guard let sample else {
            return "—"
        }
        return sample.humidityPercent.formatted(.number.precision(.fractionLength(1)))
    }

    private var pressureValue: String {
        guard let sample else {
            return "—"
        }
        let value = prefs.pressureUnit.convert(hectopascals: sample.pressureHectopascals)
        return value.formatted(.number.precision(.fractionLength(prefs.pressureUnit.displayFractionDigits)))
    }
}

// MARK: - ClimateTrendMetric

/// The metrics the Climate-Trends swipe pages between. This is the thin mapping
/// from a `DeviceSnapshot` field to ``TrendChart`` inputs (title / unit / tint /
/// precision) — one generic chart, many metrics, no per-metric chart types.
/// Phase II sensors (CO₂, TVOC, …) become new cases here for free.
enum ClimateTrendMetric: String, CaseIterable, Identifiable {
    case temperature
    case humidity
    case pressure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temperature: "24-Hour Temperature"
        case .humidity: "24-Hour Humidity"
        case .pressure: "24-Hour Air Pressure"
        }
    }

    var tint: Color {
        switch self {
        case .temperature: .orange
        case .humidity: .blue
        case .pressure: .teal
        }
    }

    func unitSymbol(_ prefs: AppPreferences) -> String {
        switch self {
        case .temperature: prefs.temperatureUnit.symbol
        case .humidity: "%"
        case .pressure: prefs.pressureUnit.symbol
        }
    }

    func fractionDigits(_ prefs: AppPreferences) -> Int {
        switch self {
        case .temperature, .humidity: 1
        case .pressure: prefs.pressureUnit.displayFractionDigits
        }
    }

    /// Extract this metric's value from each snapshot, converted to the user's unit.
    func points(from snapshots: [DeviceSnapshot], prefs: AppPreferences) -> [TrendPoint] {
        snapshots.map { snap in
            let value: Double = switch self {
            case .temperature: prefs.temperatureUnit.convert(celsius: snap.temperatureCelsius)
            case .humidity: snap.humidityPercent
            case .pressure: prefs.pressureUnit.convert(hectopascals: snap.pressureHectopascals)
            }
            return TrendPoint(date: snap.timestamp, value: value)
        }
    }
}

// MARK: - ClimateHistoryDetail

/// A lightweight list of every persisted snapshot's climate readings — reached by
/// tapping the Climate hero card (Apple-Health style).
struct ClimateHistoryDetail: View {
    let snapshots: [DeviceSnapshot]
    @Environment(AppPreferences.self) private var prefs

    var body: some View {
        List(snapshots, id: \.unixTimestamp) { snap in
            VStack(alignment: .leading, spacing: 4) {
                Text(snap.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.subheadline)
                HStack(spacing: 16) {
                    Text(HomeView.temperatureText(centiC: snap.temperatureCentiDegC, prefs: prefs))
                    Text(snap.humidityPercent.formatted(.number.precision(.fractionLength(1))) + " %")
                    Text(
                        prefs.pressureUnit.convert(hectopascals: snap.pressureHectopascals)
                            .formatted(.number.precision(.fractionLength(prefs.pressureUnit.displayFractionDigits)))
                            + " " + prefs.pressureUnit.symbol
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .navigationTitle("Climate History Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - RealTimeClockHistoryDetail

/// A per-snapshot listing of the device's real-time-clock state — device time,
/// component (RTC on-die) temperature, and the OSF status flag. Parity with
/// ``ClimateHistoryDetail``, reached by tapping the Real Time Clock card.
struct RealTimeClockHistoryDetail: View {
    let snapshots: [DeviceSnapshot]
    @Environment(AppPreferences.self) private var prefs

    var body: some View {
        List(snapshots, id: \.unixTimestamp) { snap in
            VStack(alignment: .leading, spacing: 4) {
                Text(snap.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.subheadline)
                HStack(spacing: 16) {
                    Label(
                        HomeView.temperatureText(centiC: snap.rtcTemperatureCentiDegC, prefs: prefs),
                        systemImage: "thermometer.medium"
                    )
                    if snap.rtcAlarmFlags & 0x80 != 0 {
                        Label("OSF", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .navigationTitle("Real Time Clock History")
        .navigationBarTitleDisplayMode(.inline)
    }
}
