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

    /// Whether a newer firmware image is available — drives the Device-tab badge
    /// and the Home banner. #20 wires the real check (bundled/imported image
    /// version vs the device's running version); default `false` until then.
    var firmwareUpdateAvailable = false

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab(MainTab.home.title, systemImage: MainTab.home.systemImage, value: MainTab.home) {
                HomeView(
                    peer: peer,
                    firmwareUpdateAvailable: firmwareUpdateAvailable,
                    onShowFirmwareUpdate: { router.selectedTab = .device }
                )
            }

            Tab(MainTab.logs.title, systemImage: MainTab.logs.systemImage, value: MainTab.logs) {
                LogsView(peer: peer)
            }

            Tab(MainTab.snapshots.title, systemImage: MainTab.snapshots.systemImage, value: MainTab.snapshots) {
                SnapshotLoggingView(peer: peer)
            }

            Tab(MainTab.device.title, systemImage: MainTab.device.systemImage, value: MainTab.device) {
                DeviceView(peer: peer)
            }
            .badge(firmwareUpdateAvailable ? Text("!") : nil)

            Tab(MainTab.settings.title, systemImage: MainTab.settings.systemImage, value: MainTab.settings) {
                SettingsView()
            }
        }
    }
}

#Preview("Connected") {
    MainTabView()
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
        .environment(ConnectedPeer(name: "Sentinel"))
}

#Preview("Firmware update available") {
    MainTabView(firmwareUpdateAvailable: true)
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
        .environment(ConnectedPeer(name: "Sentinel"))
}
