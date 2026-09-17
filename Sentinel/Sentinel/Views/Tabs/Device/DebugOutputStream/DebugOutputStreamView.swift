//
//  DebugOutputStreamView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 9/17/26.
//

import SwiftUI

// MARK: - DebugOutputStreamView

/// A live, scrollable log viewer (#25) that merges two BLE-adjacent sources into
/// one chronological feed:
///
/// 1. **Local BLE events** — `BluetoothManager.bluetoothEventStream()`
///    (`AsyncStream<BluetoothLogEvent>`). Always available, even pre-connection,
///    so the scan → connect → discovery handshake is watchable live.
/// 2. **Device-side debug output** — the firmware's ``DebugStreamService``
///    (`nil` before a connection exists). Armed on appear, disarmed on disappear.
///
/// Reached from two entry points that push the same view onto a `NavigationStack`:
/// the **PeripheralScanView** toolbar (pre-connection, `deviceStream == nil`) and
/// the **DeviceView** "Debug Output" row (post-connection, with a live stream).
///
/// This is a **leaf view**: it takes its two sources as inputs (a local-stream
/// *provider* closure + an optional `any DebugStreamService`) rather than reaching
/// into the environment, so a Preview renders synthetic lines with no BLE — the
/// injected streams are the preview seam, mirroring `HomeView`'s convention.
struct DebugOutputStreamView: View {
    /// Produces a fresh subscription to the local BLE event stream. A closure (not
    /// a stored `AsyncStream`) because each `bluetoothEventStream()` call vends an
    /// independent subscriber, created when this view appears.
    let localEvents: () -> AsyncStream<BluetoothLogEvent>
    /// The device-side debug stream, or `nil` when reached before a connection.
    let deviceStream: (any DebugStreamService)?

    /// The merged, bounded line buffer (oldest → newest).
    @State private var lines: [DebugLogLine] = []
    /// When paused, the buffer keeps growing but the view stops auto-scrolling to
    /// the tail — so the user can read back without new lines yanking the viewport.
    @State private var paused = false
    @State private var filter = DebugLogFilter()
    @State private var showFilter = false
    @State private var showClearConfirmation = false

    /// Upper bound on retained lines; the oldest are dropped past this. Matches the
    /// issue's Phase I budget.
    private let maxLines = 10000

    /// How far back an out-of-order line may be inserted by timestamp. Both sources
    /// stamp on arrival so lines are near-monotonic; this bounds the reordering
    /// work when the two interleave, without a timer (the issue's "small reordering
    /// window", expressed as a count).
    private let reorderWindow = 64

    var body: some View {
        let visible = filter.apply(to: lines)

        ScrollViewReader { proxy in
            List {
                ForEach(visible) { line in
                    DebugLogLineRow(line: line)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        .id(line.id)
                }
                // A zero-height tail anchor so auto-scroll always has a target even
                // when the last row is tall/wrapped.
                Color.clear
                    .frame(height: 1)
                    .listRowSeparator(.hidden)
                    .id(Self.tailAnchor)
            }
            .listStyle(.plain)
            .overlay { if visible.isEmpty { emptyState } }
            .onChange(of: visible.count) {
                guard !paused else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(Self.tailAnchor, anchor: .bottom)
                }
            }
        }
        .navigationTitle("Debug Stream")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filter.searchText, prompt: "Filter messages")
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Clear current log?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { lines.removeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This empties the on-screen buffer. New activity keeps appending.")
        }
        .sheet(isPresented: $showFilter) {
            DebugLogFilterSheet(filter: $filter)
        }
        // Two lifetime tasks, mirroring HomeView's per-source `.task`s: both run on
        // the view's MainActor context, so appends from either source are
        // serialized (no data race) and the reordering insert handles interleaving.
        .task { await consumeLocal() }
        .task { await consumeDevice() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showFilter = true
            } label: {
                Label(
                    "Filter",
                    systemImage: filter.isActive
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }

            Button {
                paused.toggle()
            } label: {
                Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
            }

            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(lines.isEmpty)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(lines.isEmpty ? "No Debug Output Yet" : "No Matching Lines", systemImage: "text.alignleft")
        } description: {
            Text(
                lines.isEmpty
                    ? "BLE activity and device debug lines appear here as they happen."
                    : "No lines match the current filter."
            )
        }
    }

    // MARK: - Source consumers

    /// Subscribe to the local BLE event stream for the view's lifetime. Cancelled
    /// on disappear (the `for await` ends when the `.task` is cancelled).
    private func consumeLocal() async {
        for await event in localEvents() {
            append(.from(event))
        }
    }

    /// Arm the device debug stream (if connected), consume it for the view's
    /// lifetime, and disarm on teardown. The disarm runs on a **detached** task so
    /// a parent `.task` cancelled on disappear doesn't abort the teardown writes —
    /// leaving the device to keep transmitting debug lines over the air.
    private func consumeDevice() async {
        guard let deviceStream else { return }
        try? await deviceStream.setStreaming(true)
        for await raw in deviceStream.outputNotifications() {
            append(.fromDevice(raw))
        }
        Task.detached { try? await deviceStream.setStreaming(false) }
    }

    /// Append a line, keeping the buffer roughly timestamp-ordered and bounded.
    /// A line older than the tail is inserted back among the last ``reorderWindow``
    /// entries; beyond that window it is appended as-is (bounded work, no reindex).
    private func append(_ line: DebugLogLine) {
        if let last = lines.last, line.timestamp < last.timestamp {
            let floor = max(0, lines.count - reorderWindow)
            var index = lines.count
            while index > floor, lines[index - 1].timestamp > line.timestamp {
                index -= 1
            }
            lines.insert(line, at: index)
        } else {
            lines.append(line)
        }
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    /// Stable id for the tail anchor row that auto-scroll targets.
    private static let tailAnchor = "debug-stream-tail"
}

// MARK: - Row

/// One log line: fixed-width timestamp, color-coded source glyph + severity, then
/// the wrapping message. Monospaced so columns line up like a console.
struct DebugLogLineRow: View {
    let line: DebugLogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.timeFormatter.string(from: line.timestamp))
                .foregroundStyle(.secondary)
            Text(line.source.glyph)
                .foregroundStyle(sourceColor)
                .frame(width: 10)
            Text(line.severity.label)
                .foregroundStyle(severityColor)
            Text(line.text)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.caption.monospaced())
        .accessibilityElement(children: .combine)
    }

    private var sourceColor: Color {
        switch line.source {
        case .local: .blue
        case .device: .green
        }
    }

    private var severityColor: Color {
        switch line.severity {
        case .info: .secondary
        case .warn: .orange
        case .error: .red
        }
    }

    /// `HH:mm:ss.SSS` in local time — cached; `Date.FormatStyle` has no
    /// milliseconds component.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Filter sheet

/// Source + severity controls for the debug stream. The plain-text search lives in
/// the navigation `.searchable` bar; this sheet holds the toggles that don't fit a
/// search field.
struct DebugLogFilterSheet: View {
    @Binding var filter: DebugLogFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Sources") {
                    Toggle("Local BLE events", isOn: $filter.showLocal)
                    Toggle("Device debug output", isOn: $filter.showDevice)
                }
                Section("Severity") {
                    Picker("Minimum severity", selection: $filter.minimumSeverity) {
                        Text("Info").tag(DebugLogLine.Severity.info)
                        Text("Warnings").tag(DebugLogLine.Severity.warn)
                        Text("Errors").tag(DebugLogLine.Severity.error)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button("Reset Filters") { filter = DebugLogFilter() }
                        .disabled(!filter.isActive)
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Previews

#if DEBUG
    /// A synthetic local event stream that replays a scan → connect → discovery
    /// handshake, then drips a couple of live events, so the Preview shows the feed
    /// filling and auto-scrolling with no BLE hardware.
    private func previewLocalEvents() -> AsyncStream<BluetoothLogEvent> {
        AsyncStream { continuation in
            let scripted: [BluetoothLogEvent] = [
                .init(category: .scan, message: "Scan started"),
                .init(category: .scan, message: "Discovered Sentinel"),
                .init(category: .connection, message: "Connecting to Sentinel"),
                .init(category: .discovery, message: "Discovering services"),
                .init(category: .connection, message: "Connected (MTU 247)"),
                .init(category: .error, message: "RSSI read failed (transient)")
            ]
            Task {
                for event in scripted {
                    continuation.yield(event)
                    try? await Task.sleep(for: .milliseconds(180))
                }
                continuation.finish()
            }
        }
    }

    /// Connected: local handshake interleaved with device-side debug lines,
    /// including parsed `[WARN]` / `[ERROR]` markers.
    #Preview("Connected — merged feed") {
        NavigationStack {
            DebugOutputStreamView(
                localEvents: previewLocalEvents,
                deviceStream: MockDebugStreamService(lines: [
                    "[boot] sentinel up",
                    "POST: pass",
                    "RTC synced via SQW (P6_3)",
                    "bme280 sample: T=22.05 H=48.2 P=1013.0",
                    "[WARN] snapshot store 80% full",
                    "[ERROR] i2c timeout on retry 2"
                ])
            )
        }
    }

    /// Pre-connection (from the scan screen): local events only, no device stream.
    #Preview("Pre-connection — local only") {
        NavigationStack {
            DebugOutputStreamView(localEvents: previewLocalEvents, deviceStream: nil)
        }
    }

    /// Empty: no activity yet — the `ContentUnavailableView` state.
    #Preview("Empty") {
        NavigationStack {
            DebugOutputStreamView(
                localEvents: { AsyncStream { $0.finish() } },
                deviceStream: nil
            )
        }
    }
#endif
