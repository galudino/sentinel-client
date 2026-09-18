//
//  DebugOutputStreamView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 9/17/26.
//

import SwiftUI

// MARK: - DebugOutputStreamView

/// The floating **debug console** (#25): a live, scrollable log viewer over a
/// pinned connect header.
///
/// It renders the app-wide ``DebugLogStore`` — so the timeline **persists across
/// view instances** and already holds the scan → connect → discovery handshake
/// that happened before the console was opened. `RootView` feeds the store (local
/// BLE events for the app's lifetime; device debug output while connected), and
/// presents this view as a `.sheet` bound to ``DebugLogStore/isConsolePresented``,
/// so the console floats above the root and survives the
/// scanning → connecting → connected transitions.
///
/// The **pinned header** lists discovered peripherals with a per-row Connect /
/// Cancel / Retry control driven entirely by ``AppRouter/state`` — so you can
/// start (and cancel) a connection from inside the console and watch the handshake
/// stream live, without the control ever scrolling out of reach. Once connected it
/// collapses to a compact strip with the device-output streaming toggle.
struct DebugOutputStreamView: View {
    @Environment(DebugLogStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(BluetoothManager.self) private var bluetoothManager
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss

    /// When paused, the buffer keeps growing but the view stops auto-scrolling to
    /// the tail — so the user can read back without new lines yanking the viewport.
    @State private var paused = false
    @State private var filter = DebugLogFilter()
    @State private var showFilter = false
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                connectHeader
                Divider()
                logList
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
                Button("Clear", role: .destructive) { store.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This empties the on-screen buffer. New activity keeps appending.")
            }
            .sheet(isPresented: $showFilter) {
                DebugLogFilterSheet(filter: $filter)
            }
        }
    }

    // MARK: - Log feed

    private var logList: some View {
        let visible = filter.apply(to: store.lines)

        return ScrollViewReader { proxy in
            List {
                ForEach(visible) { line in
                    DebugLogLineRow(line: line)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        .id(line.id)
                }
                // Zero-height tail anchor so auto-scroll always has a target even
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
            .task {
                // Land at the tail when the console opens onto existing history.
                proxy.scrollTo(Self.tailAnchor, anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(store.lines.isEmpty ? "No Debug Output Yet" : "No Matching Lines", systemImage: "text.alignleft")
        } description: {
            Text(
                store.lines.isEmpty
                    ? "BLE activity and device debug lines appear here as they happen."
                    : "No lines match the current filter."
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Done") { dismiss() }
        }
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
            .disabled(store.lines.isEmpty)
        }
    }

    // MARK: - Pinned connect header

    @ViewBuilder private var connectHeader: some View {
        switch router.state {
        case let .connected(peer), let .updatingFirmware(peer, _):
            connectedStrip(peer)
        default:
            discoveredTargets
        }
    }

    /// Discovered peripherals with per-row Connect / Cancel / Retry. Pinned above
    /// the (scrolling) log so the control is always reachable while lines stream.
    private var discoveredTargets: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Discovered", systemImage: "dot.radiowaves.left.and.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if bluetoothManager.isScanning {
                    ProgressView().controlSize(.mini)
                }
            }
            if bluetoothManager.discoveredPeripherals.isEmpty {
                Text("Searching for devices…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bluetoothManager.discoveredPeripherals) { item in
                    targetRow(item)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private func targetRow(_ item: PeripheralScanItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name ?? "Unknown Device")
                    .font(.subheadline.weight(.medium))
                Text("\(item.rssi) dBm")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            targetControl(for: item)
        }
    }

    /// The trailing control for a discovered row — a pure function of the router's
    /// connection state. Only the peripheral being connected is actionable; the
    /// others are disabled (the router guards `beginConnect` to `.scanning`, so a
    /// tap would no-op — disabling makes that truthful).
    @ViewBuilder private func targetControl(for item: PeripheralScanItem) -> some View {
        switch router.state {
        case .scanning:
            connectButton(item)

        case let .connecting(id):
            if id == item.id {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Button(role: .destructive) {
                        router.cancelConnect()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                connectButton(item, disabled: true)
            }

        case let .connectFailed(id, message):
            if id == item.id {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(message)
                    Button {
                        router.retryConnect()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button {
                        router.dismissConnectError()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("Dismiss error")
                }
            } else {
                connectButton(item, disabled: true)
            }

        case .connected, .updatingFirmware:
            EmptyView()
        }
    }

    private func connectButton(_ item: PeripheralScanItem, disabled: Bool = false) -> some View {
        Button {
            router.beginConnect(peripheralID: item.id, name: item.name)
        } label: {
            Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(disabled)
        .accessibilityLabel("Connect to \(item.name ?? "device")")
    }

    /// Compact strip shown once connected: identity + link metric + the
    /// device-output streaming toggle (same persisted flag as Settings, so it can
    /// be flipped here without a trip to Settings).
    private func connectedStrip(_ peer: ConnectedPeer) -> some View {
        @Bindable var prefs = prefs
        return HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Connected — \(peer.name ?? "Sentinel")")
                    .font(.subheadline.weight(.medium))
                Text("MTU \(peer.negotiatedMTU)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle(isOn: $prefs.debugModeEnabled) {
                Text("Device output").font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
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
    /// Connected: merged local + device timeline, device-output toggle on.
    #Preview("Connected — merged feed") {
        @Previewable @State var router = AppRouter(bluetoothManager: PreviewBluetoothCentral(connectDelay: .zero))
        DebugOutputStreamView()
            .environment(DebugLogStore.preview())
            .environment(router)
            .environment(BluetoothManager.preview(discovered: []))
            .environment(AppPreferences())
            .task { router.beginConnect(peripheralID: UUID(), name: "Sentinel") }
    }

    /// Pre-connection: discovered peripherals with Connect buttons + local history.
    #Preview("Scanning — connect targets") {
        DebugOutputStreamView()
            .environment(DebugLogStore.preview(lines: Array(DebugLogLine.previewTimeline().prefix(2))))
            .environment(AppRouter(bluetoothManager: PreviewBluetoothCentral()))
            .environment(BluetoothManager.preview(discovered: [
                PeripheralScanItem(previewName: "Sentinel", rssi: -47, lastUpdated: .now.addingTimeInterval(-1)),
                PeripheralScanItem(previewName: "Sentinel-2F1A", rssi: -66, lastUpdated: .now.addingTimeInterval(-4))
            ]))
            .environment(AppPreferences())
    }

    /// Empty: no activity yet — the `ContentUnavailableView` state.
    #Preview("Empty") {
        DebugOutputStreamView()
            .environment(DebugLogStore())
            .environment(AppRouter(bluetoothManager: PreviewBluetoothCentral()))
            .environment(BluetoothManager.preview(discovered: []))
            .environment(AppPreferences())
    }
#endif
