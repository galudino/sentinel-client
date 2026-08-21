//
//  TimeAndDateView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/19/26.
//

import SwiftUI

/// **Time & Date** (#18) — reads the DS3231 real-time clock (Unix time, on-die
/// temperature, alarm/status flags) and offers **Sync from iPhone**: write the
/// phone's current epoch to the Unix Time characteristic, then re-read to confirm.
///
/// The write depends on firmware #6 wiring the set-time handler; the re-read is
/// what distinguishes "device accepted it" from a silent no-op — the UI reports
/// the confirmed device time, never assumes success.
struct TimeAndDateView: View {
    let ds3231: any DS3231Service

    @State private var deviceUnixTime: UInt32?
    @State private var rtcTemperatureCentiC: Int16?
    @State private var alarmFlags: UInt8?
    @State private var isSyncing = false
    @State private var syncResult: SyncResult?

    private enum SyncResult { case confirmed, mismatch, failed(String) }

    var body: some View {
        List {
            Section("Device Clock") {
                LabeledContent("Device time", value: deviceTimeText)
                LabeledContent("RTC temperature", value: rtcTemperatureText)
            }

            Section {
                LabeledContent("Oscillator (OSF)", value: osfText)
                LabeledContent("Alarm 1 (A1F)", value: flag(bit: 0))
                LabeledContent("Alarm 2 (A2F)", value: flag(bit: 1))
            } header: {
                Text("Status Flags")
            } footer: {
                if alarmFlags.map({ $0 & 0x80 != 0 }) == true {
                    Text(
                        "OSF set — the oscillator has stopped since it was last cleared; "
                            + "the clock may be inaccurate until re-synced."
                    )
                }
            }

            Section {
                Button {
                    Task { await syncFromPhone() }
                } label: {
                    Label("Sync from iPhone", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isSyncing)

                if let syncResult {
                    switch syncResult {
                    case .confirmed:
                        Label("Synced — device time confirmed.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    case .mismatch:
                        Label(
                            "Wrote time, but the device read back a different value.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    case let .failed(message):
                        Label(message, systemImage: "xmark.circle").foregroundStyle(.red)
                    }
                }
            } footer: {
                Text("Writes this iPhone's current UTC time to the device clock, then re-reads to confirm.")
            }
        }
        .navigationTitle("Time & Date")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isSyncing { ProgressView().controlSize(.large) } }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Derived text

    private var deviceTimeText: String {
        guard let deviceUnixTime, deviceUnixTime != 0 else { return "—" }
        return Date(timeIntervalSince1970: TimeInterval(deviceUnixTime))
            .formatted(date: .abbreviated, time: .standard)
    }

    private var rtcTemperatureText: String {
        guard let rtcTemperatureCentiC else { return "—" }
        // DS3231 on-die temp is ±3 °C / 0.25 °C steps — 1 dp avoids false precision.
        return (Double(rtcTemperatureCentiC) / 100.0)
            .formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    private var osfText: String { flag(bit: 7, setLabel: "Stopped", clearLabel: "Running") }

    private func flag(bit: UInt8, setLabel: String = "Set", clearLabel: String = "Clear") -> String {
        guard let alarmFlags else { return "—" }
        return (alarmFlags & (1 << bit)) != 0 ? setLabel : clearLabel
    }

    // MARK: - Actions

    private func load() async {
        deviceUnixTime = try? await ds3231.readUnixTime()
        rtcTemperatureCentiC = try? await ds3231.readRTCTemperature()
        alarmFlags = try? await ds3231.readAlarmFlags()
    }

    private func syncFromPhone() async {
        isSyncing = true
        syncResult = nil
        defer { isSyncing = false }
        let now = UInt32(Date().timeIntervalSince1970)
        do {
            try await ds3231.writeUnixTime(now)
            let confirmed = try await ds3231.readUnixTime()
            deviceUnixTime = confirmed
            // Allow a couple seconds of drift between write and read-back.
            syncResult = abs(Int64(confirmed) - Int64(now)) <= 2 ? .confirmed : .mismatch
        } catch {
            syncResult = .failed("Sync failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("Running clock") {
        NavigationStack {
            TimeAndDateView(ds3231: MockDS3231Service())
        }
    }

    #Preview("OSF set") {
        NavigationStack {
            TimeAndDateView(ds3231: MockDS3231Service(alarmFlags: 0x80))
        }
    }
#endif
