//
//  LogsView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import SwiftUI

/// The **Logs** tab (#16) — browse the device's flash-backed System Event Log
/// (firmware #34). Records are decoded to the typed ``SystemEventRecord`` (#11)
/// and rendered via its `displayTitle` / `displaySubtitle` / `iconSystemName`
/// API; tapping a row pushes the full typed body.
///
/// Leaf view: takes `any SystemEventLogService` so it previews against
/// `MockSystemEventLogService` with no BLE.
struct LogsView: View {
    let eventLog: any SystemEventLogService

    @State private var entries: [EventEntry] = []
    @State private var filter: EventFilter = .all
    @State private var isLoading = false
    @State private var lastSync: Date?
    /// Diagnostics so an empty list distinguishes read-failure vs 0-records vs
    /// records-present-but-undecodable (firmware issue vs client issue).
    @State private var loadError: String?
    @State private var deviceRecordCount: UInt32?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EventFilterBar(selection: $filter)
                    .padding(.vertical, 8)

                List {
                    ForEach(sections, id: \.day) { section in
                        Section(section.day.formatted(date: .abbreviated, time: .omitted)) {
                            ForEach(section.entries) { entry in
                                NavigationLink {
                                    EventDetailView(record: entry.record)
                                } label: {
                                    EventRow(record: entry.record)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .overlay { if entries.isEmpty { emptyState } }
                .refreshable { await load() }
            }
            .navigationTitle("Logs")
            .task { await load() }
        }
    }

    // MARK: - Sections (day-grouped, most recent first)

    private var sections: [(day: Date, entries: [EventEntry])] {
        let filtered = filter.apply(to: entries)
        let groups = Dictionary(grouping: filtered) {
            Calendar.current.startOfDay(for: $0.record.timestamp)
        }
        return groups
            .map { (day: $0.key, entries: $0.value.sorted { $0.record.timestamp > $1.record.timestamp }) }
            .sorted { $0.day > $1.day }
    }

    @ViewBuilder private var emptyState: some View {
        if isLoading {
            ProgressView("Reading event log…")
        } else {
            ContentUnavailableView {
                Label("No Events", systemImage: "list.bullet.indent")
            } description: {
                if let loadError {
                    Text("Couldn't read the event log: \(loadError)")
                } else if let deviceRecordCount, deviceRecordCount > 0 {
                    Text("The device reports \(deviceRecordCount) record(s), but none decoded (format mismatch).")
                } else if lastSync != nil {
                    Text("The device reports 0 events. Pull to refresh.")
                } else {
                    Text("The device hasn't logged any events yet.")
                }
            }
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Read the count separately so we can tell "0 on device" (firmware
            // hasn't logged / empty) from "N on device but none decoded" (client).
            deviceRecordCount = try await eventLog.readRecordCount()
            let records = try await eventLog.readAllRecords()
            let sorted = records.sorted { $0.timestamp > $1.timestamp }
            entries = sorted.enumerated().map { EventEntry(id: $0.offset, record: $0.element) }
            loadError = nil
            lastSync = .now
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// A stable identity for a decoded record within the current listing (device
/// records carry no id; reassigned on each reload).
struct EventEntry: Identifiable {
    let id: Int
    let record: SystemEventRecord
}

// MARK: - Filter

enum EventFilter: CaseIterable, Hashable {
    case all, boot, firmware, ble, faults, post, other

    var title: String {
        switch self {
        case .all: "All"
        case .boot: "Boot"
        case .firmware: "Firmware"
        case .ble: "BLE"
        case .faults: "Faults"
        case .post: "POST"
        case .other: "Other"
        }
    }

    func matches(_ record: SystemEventRecord) -> Bool {
        switch (self, record) {
        case (.all, _): true
        case (.boot, .bootLifecycle): true
        case (.firmware, .firmwareUpdate): true
        case (.ble, .bleConnection): true
        case (.faults, .fault): true
        case (.post, .post): true
        case (.other, .modeChange), (.other, .snapshot), (.other, .other), (.other, .unknown): true
        default: false
        }
    }

    func apply(to entries: [EventEntry]) -> [EventEntry] {
        self == .all ? entries : entries.filter { matches($0.record) }
    }
}

/// Horizontally scrollable filter chips.
struct EventFilterBar: View {
    @Binding var selection: EventFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EventFilter.allCases, id: \.self) { option in
                    let isSelected = option == selection
                    Button {
                        selection = option
                    } label: {
                        Text(option.title)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.thinMaterial),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Row

struct EventRow: View {
    let record: SystemEventRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.iconSystemName)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayTitle).font(.subheadline).fontWeight(.medium)
                if let subtitle = record.displaySubtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(record.timestamp, format: .relative(presentation: .numeric))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch record {
        case .fault: .red
        case .firmwareUpdate: .orange
        case .bleConnection: .blue
        case .post: record.event == .postPassed ? .green : .red
        case .bootLifecycle: .purple
        default: .secondary
        }
    }
}

// MARK: - Detail

/// The full typed body of a record. The rich-charts / cross-record correlation is
/// out of scope for #16; this surfaces every decoded field plus the raw record
/// (when preserved, i.e. for unrecognized events).
struct EventDetailView: View {
    let record: SystemEventRecord

    var body: some View {
        List {
            Section {
                LabeledContent("Type", value: record.displayTitle)
                LabeledContent("Timestamp") {
                    Text(record.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                        .monospacedDigit()
                }
                if let event = record.event {
                    LabeledContent("Event code", value: "0x\(String(event.rawValue, radix: 16, uppercase: true))")
                }
            }

            bodySection
        }
        .navigationTitle("Event Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var bodySection: some View {
        switch record {
        case let .bootLifecycle(_, body):
            Section("Boot") {
                LabeledContent("Firmware", value: "v\(body.firmwareVersion.shortVersion)")
                LabeledContent("Boot count", value: body.bootCount.formatted())
                LabeledContent("Uptime at event", value: "\(body.uptimeAtEvent) s")
            }
        case let .firmwareUpdate(_, body):
            Section("Firmware Update") {
                LabeledContent("From", value: "v\(body.fromVersion.shortVersion)")
                LabeledContent("To", value: "v\(body.toVersion.shortVersion)")
                LabeledContent("MCUboot result", value: "0x\(String(body.mcubootResult, radix: 16, uppercase: true))")
            }
        case let .bleConnection(_, body):
            Section("BLE") {
                LabeledContent("Peer", value: body.peerAddressString)
                LabeledContent("Address type", value: body.addressType.formatted())
                LabeledContent("Disconnect reason", value: body.disconnectReason.formatted())
                LabeledContent("Interval", value: "\(Double(body.connectionInterval125us) * 0.125) ms")
                LabeledContent("Peer MTU", value: body.peerMTU.formatted())
            }
        case let .fault(_, body):
            Section("Fault") {
                LabeledContent("Fault ID", value: body.faultID.formatted())
                LabeledContent("Severity", value: severityLabel(body.severity))
                LabeledContent("Subsystem", value: body.subsystemID.formatted())
                ForEach(Array(body.context.enumerated()), id: \.offset) { index, word in
                    LabeledContent("Context[\(index)]", value: "0x\(String(word, radix: 16, uppercase: true))")
                }
            }
        case let .modeChange(_, body):
            Section("Mode Change") {
                LabeledContent("From", value: body.fromMode.formatted())
                LabeledContent("To", value: body.toMode.formatted())
                LabeledContent("Trigger", value: body.trigger.formatted())
            }
        case let .post(_, body):
            Section("POST") {
                LabeledContent("Subsystem", value: body.subsystemID.formatted())
                LabeledContent("Result", value: body.result.formatted())
                LabeledContent("Detail", value: body.detail.formatted())
            }
        case let .snapshot(_, body):
            Section("Snapshot") {
                LabeledContent("Count", value: body.snapshotCount.formatted())
                LabeledContent("Reason", value: body.reason == 1 ? "Pre-fault" : "Periodic")
            }
        case .other:
            EmptyView()
        case let .unknown(header, raw):
            Section("Raw record") {
                LabeledContent("Event type", value: "0x\(String(header.eventTypeRaw, radix: 16, uppercase: true))")
                Text(raw.map { String(format: "%02X", $0) }.joined(separator: " "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func severityLabel(_ value: UInt8) -> String {
        switch value {
        case 0: "Info"
        case 1: "Warning"
        case 2: "Error"
        case 3: "Critical"
        default: "\(value)"
        }
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("Populated") {
        LogsView(eventLog: MockSystemEventLogService(records: SystemEventRecord.previewRecords))
    }

    #Preview("Empty") {
        LogsView(eventLog: MockSystemEventLogService(records: []))
    }

    extension SystemEventRecord {
        /// A spread of record variants for previews.
        static var previewRecords: [SystemEventRecord] {
            let base: UInt32 = 1_760_000_000
            return [
                .bootLifecycle(
                    SystemEventRecordHeader(unixTimestamp: base, eventTypeRaw: SystemEvent.bootComplete.rawValue),
                    BootLifecycleBody(
                        firmwareVersion: FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16),
                        bootCount: 7,
                        uptimeAtEvent: 0
                    )
                ),
                .firmwareUpdate(
                    SystemEventRecordHeader(
                        unixTimestamp: base + 120,
                        eventTypeRaw: SystemEvent.firmwareUpdateCompleted.rawValue
                    ),
                    FirmwareUpdateBody(
                        fromVersion: FirmwareVersion(major: 1, minor: 0, patch: 0, build: 14),
                        toVersion: FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16),
                        mcubootResult: 0
                    )
                ),
                .fault(
                    SystemEventRecordHeader(unixTimestamp: base + 300, eventTypeRaw: SystemEvent.faultRaised.rawValue),
                    FaultBody(faultID: 3, severity: 2, subsystemID: 5, context: [0xDEAD_BEEF, 0, 0, 0, 0, 0])
                ),
                .bleConnection(
                    SystemEventRecordHeader(
                        unixTimestamp: base + 400,
                        eventTypeRaw: SystemEvent.blePeripheralConnected.rawValue
                    ),
                    BLEConnectionBody(
                        peerAddress: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06],
                        addressType: 1,
                        disconnectReason: 0,
                        connectionInterval125us: 240,
                        peerMTU: 247
                    )
                )
            ]
        }
    }
#endif
