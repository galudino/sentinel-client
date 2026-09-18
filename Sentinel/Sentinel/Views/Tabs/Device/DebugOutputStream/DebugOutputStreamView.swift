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
/// The **pinned header** (in `DebugOutputStreamView+ConnectHeader.swift`) lists
/// discovered peripherals with a per-row Connect / Cancel / Retry control driven by
/// ``AppRouter/state`` (collapsing to a connected strip once linked). The **feed**
/// supports newest-first / oldest-first sort, a messaging-app-style "N new" banner
/// with an auto-scroll toggle, and rich filtering (source, per-severity,
/// per-service, and debounced text search).
struct DebugOutputStreamView: View {
    @Environment(DebugLogStore.self) var store
    @Environment(AppRouter.self) var router
    @Environment(BluetoothManager.self) var bluetoothManager
    @Environment(AppPreferences.self) var prefs
    @Environment(\.dismiss) private var dismiss

    // Filter, sort, and follow settings persist across console instances and app
    // launches (per-view filter persistence, generalized in #44).
    @AppStorage("v1.debugConsole.filter") private var filter = DebugLogFilter()
    @AppStorage("v1.debugConsole.sortNewestFirst") private var sortNewestFirst = false
    /// Follow new lines to the latest edge when the user is already there. When
    /// off, arrivals never move the viewport — the "N new" banner is the only way
    /// to jump. Toggled from the toolbar.
    @AppStorage("v1.debugConsole.autoScroll") private var autoScroll = true
    /// Show the client receive time on device rows (display option).
    @AppStorage("v1.debugConsole.showReceiveTime") private var showReceiveTime = true

    @State private var showFilter = false
    @State private var showClearConfirmation = false

    /// Whether the latest-edge anchor is on screen (user is viewing the newest
    /// lines). Drives whether arrivals follow or accrue into the banner.
    @State private var atLatestEdge = true

    /// Count of *visible* arrivals since the user last saw the latest edge — the
    /// banner's number.
    @State private var newCount = 0

    /// Debounced copy of the search text actually applied to the buffer (typing
    /// updates the field live; filtering waits for it to settle).
    @State private var appliedSearch = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                connectHeader
                Divider()
                logFeed
            }
            .navigationTitle("Debug Stream")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter.searchText, prompt: "Filter messages")
            .task(id: filter.searchText) {
                try? await Task.sleep(for: .milliseconds(250))
                appliedSearch = filter.searchText
            }
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
                DebugConsoleOptionsSheet(
                    filter: $filter,
                    sortNewestFirst: $sortNewestFirst,
                    showReceiveTime: $showReceiveTime,
                    services: discoveredServices
                )
            }
        }
    }

    /// Distinct firmware services seen in the buffer, sorted — the universe the
    /// filter sheet offers per-service toggles for.
    private var discoveredServices: [String] {
        Array(Set(store.lines.compactMap(\.service))).sorted()
    }

    // MARK: - Log feed

    private var logFeed: some View {
        var effective = filter
        effective.searchText = appliedSearch
        let filtered = effective.apply(to: store.lines)
        // Display order: latest is at the bottom (oldest-first) or top (newest-first).
        let visible = sortNewestFirst ? Array(filtered.reversed()) : filtered

        return ScrollViewReader { proxy in
            let scrollToLatest = {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(Self.latestAnchor, anchor: sortNewestFirst ? .top : .bottom)
                }
            }

            ZStack(alignment: sortNewestFirst ? .top : .bottom) {
                List {
                    if sortNewestFirst { latestAnchorRow }
                    ForEach(visible) { line in
                        DebugLogLineRow(line: line, showReceiveTime: showReceiveTime)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                            .id(line.id)
                    }
                    if !sortNewestFirst { latestAnchorRow }
                }
                .listStyle(.plain)
                .overlay { if visible.isEmpty { emptyState } }

                if newCount > 0 {
                    newEntriesBanner { scrollToLatest(); newCount = 0 }
                        .padding(.vertical, 10)
                }
            }
            .animation(.spring(duration: 0.25), value: newCount > 0)
            // Arrivals: observe the monotonic append counter (not lines.count, which
            // plateaus at the cap). Count only *visible* new lines; follow the tail
            // if the user is already there and auto-scroll is on, else bank them
            // into the banner.
            .onChange(of: store.appendCount) { old, new in
                guard new > old else { return }
                let added = store.lines.suffix(new - old)
                let visibleAdded = effective.apply(to: Array(added)).count
                guard visibleAdded > 0 else { return }
                if atLatestEdge, autoScroll {
                    scrollToLatest()
                } else {
                    newCount += visibleAdded
                }
            }
            .onChange(of: autoScroll) { _, enabled in
                if enabled { scrollToLatest(); newCount = 0 }
            }
            .onChange(of: sortNewestFirst) { _, newestFirst in
                newCount = 0
                // A sort flip reorders every row. Defer the scroll to the next tick
                // and disable its animation, so scrollToLatest's animation
                // transaction doesn't wrap (and animate) the whole reorder — that
                // coupling pins the main thread on a large buffer (the "hang").
                Task { @MainActor in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(Self.latestAnchor, anchor: newestFirst ? .top : .bottom)
                    }
                }
            }
            .task {
                // Land on the latest edge when the console opens onto existing history.
                scrollToLatest()
            }
        }
    }

    /// Zero-height marker at the latest end of the list. Its visibility tells us
    /// whether the user is viewing the newest lines.
    private var latestAnchorRow: some View {
        Color.clear
            .frame(height: 1)
            .listRowSeparator(.hidden)
            .id(Self.latestAnchor)
            .onAppear { atLatestEdge = true; newCount = 0 }
            .onDisappear { atLatestEdge = false }
    }

    private func newEntriesBanner(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("\(newCount) new", systemImage: sortNewestFirst ? "arrow.up.to.line" : "arrow.down.to.line")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
                .shadow(radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: sortNewestFirst ? .top : .bottom).combined(with: .opacity))
        .accessibilityLabel("\(newCount) new entries, scroll to latest")
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
                // Funnel doubles as an active-filter indicator (filled when filtering).
                Label(
                    "Options",
                    systemImage: filter.isActive
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
            Button {
                autoScroll.toggle()
            } label: {
                // Direction-aware: the arrow points toward the latest edge (which
                // flips with sort order); fill + tint carry the on/off state
                // (arrow.{down,up}.to.line.circle has real fill/outline variants).
                Label(
                    "Follow new entries",
                    systemImage: sortNewestFirst ? "arrow.up.to.line.circle" : "arrow.down.to.line.circle"
                )
                .symbolVariant(autoScroll ? .fill : .none)
            }
            .tint(autoScroll ? .accentColor : .secondary)
            .accessibilityValue(autoScroll ? "On" : "Off")
            .help(autoScroll ? "Stop following new entries" : "Follow new entries to the latest")
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(store.lines.isEmpty)
        }
    }

    /// Stable id for the latest-edge anchor row.
    static let latestAnchor = "debug-stream-latest"
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
