//
//  MainTabView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import SwiftUI

/// The live operating mode — the tabbed home shown while connected. Five tabs:
/// Home (#15), Logs (#16), Snapshots (#17), Device (#18), Settings (#19). #14
/// assembles the shell; each tab's real content lands in its own issue.
///
/// Selection is bound to ``AppRouter/selectedTab`` (not local `@State`) so it
/// **persists** across a DFU round-trip and a disconnect/reconnect within a
/// session — a deliberate #7 decision (there's a test), which supersedes #14's
/// original "resets on reconnect" wording. Each tab owns its own `NavigationStack`
/// for drill-downs; there is intentionally **no** outer navigation container.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ConnectedPeer.self) private var peer
    @Environment(ImportedFirmwareStore.self) private var importedStore

    /// Whether a newer firmware image is available — drives the Device-tab badge
    /// and the Home banner. Computed on connect (#20): the recommended image
    /// (newest bundled/imported) vs the device's running version.
    @State private var firmwareUpdateAvailable = false

    init() {}

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab(MainTab.home.title, systemImage: MainTab.home.systemImage, value: MainTab.home) {
                HomeView(
                    deviceName: peer.name,
                    bme280: peer.bme280,
                    ds3231: peer.ds3231,
                    history: peer.snapshotHistory,
                    firmwareUpdateAvailable: firmwareUpdateAvailable,
                    onShowFirmwareUpdate: { router.selectedTab = .device }
                )
            }

            Tab(MainTab.logs.title, systemImage: MainTab.logs.systemImage, value: MainTab.logs) {
                LogsView(eventLog: peer.systemEventLog)
            }

            Tab(MainTab.snapshots.title, systemImage: MainTab.snapshots.systemImage, value: MainTab.snapshots) {
                SnapshotLoggingView(peer: peer)
            }

            Tab(MainTab.device.title, systemImage: MainTab.device.systemImage, value: MainTab.device) {
                DeviceView(peer: peer, system: peer.system, firmwareUpdateAvailable: firmwareUpdateAvailable)
            }
            .badge(firmwareUpdateAvailable ? Text("!") : nil)

            Tab(MainTab.settings.title, systemImage: MainTab.settings.systemImage, value: MainTab.settings) {
                SettingsView()
            }
        }
        .task(id: peer.id) { await refreshUpdateAvailability() }
    }

    /// Recompute ``firmwareUpdateAvailable`` from the device's running version vs
    /// the newest available image (bundled + imported). A read failure (e.g. the
    /// simulator's absent BLE) leaves the current value untouched.
    private func refreshUpdateAvailability() async {
        guard let installed = try? await peer.system.readFirmwareVersion() else { return }
        let images = FirmwareCatalog.bundledImages() + importedStore.images
        firmwareUpdateAvailable = FirmwareCatalog.recommended(installed: installed, among: images) != nil
    }
}

#if DEBUG
    extension MainTabView {
        /// Preview seam — seed the badge/banner without a live read.
        init(firmwareUpdateAvailable: Bool) {
            _firmwareUpdateAvailable = State(initialValue: firmwareUpdateAvailable)
        }
    }
#endif

#Preview("Connected") {
    MainTabView()
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
        .environment(AppPreferences())
        .environment(ConnectedPeer.preview())
        .environment(PairedPeerStore())
        .environment(ImportedFirmwareStore())
}

#Preview("Firmware update available") {
    MainTabView(firmwareUpdateAvailable: true)
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
        .environment(AppPreferences())
        .environment(ConnectedPeer.preview())
        .environment(PairedPeerStore())
        .environment(ImportedFirmwareStore())
}

// Detached peer → every service read throws, so the tabs show their "awaiting
// telemetry" / empty states — the freshly-connected-but-no-data-yet scenario.
#Preview("Awaiting telemetry") {
    MainTabView()
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
        .environment(AppPreferences())
        .environment(ConnectedPeer(name: "Sentinel"))
        .environment(PairedPeerStore())
        .environment(ImportedFirmwareStore())
}
