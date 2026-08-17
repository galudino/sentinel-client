//
//  MainTabView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import SwiftUI

/// The live operating mode — the tabbed home shown while connected. Five tabs:
/// Home (#15), Logs (#16), Snapshots (#17), Device (#18), Settings (#19).
///
/// Selection is bound to ``AppRouter/selectedTab`` (not local `@State`) so it
/// survives a DFU round-trip and reconnects within a session. Each tab owns its
/// own `NavigationStack` for drill-downs — there is intentionally **no** outer
/// navigation container wrapping the tab bar.
///
/// **Stub for #7.** The real tab contents land in #15–#19; #14 assembles them.
/// Leaf views will take `any <Chip>Service` in their init (parent passes
/// `peer.bme280`, etc.) so they preview against mocks; this stub just proves the
/// state machine and tab-selection wiring.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ConnectedPeer.self) private var peer

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            ForEach(MainTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    TabPlaceholder(tab: tab, peer: peer)
                }
            }
        }
    }
}

/// Per-tab placeholder content. Replaced by the real tab views (#15–#19).
private struct TabPlaceholder: View {
    let tab: MainTab
    let peer: ConnectedPeer

    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    LabeledContent("Device", value: peer.name ?? "Sentinel")
                    LabeledContent("ID", value: peer.id.uuidString)
                }

                // Seed affordances so the remaining transitions are walkable.
                // These move to their real homes in #18 (DFU entry) / scan-and-
                // connection handling (#8/#13).
                if tab == .device {
                    Section("Firmware (seed — #18/#20/#21)") {
                        Button {
                            router.startFirmwareUpdate(FirmwareImage(version: "1.1.0"))
                        } label: {
                            Label("Update Firmware…", systemImage: "arrow.up.circle")
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        router.didDisconnect()
                    } label: {
                        Label("Disconnect", systemImage: "wifi.slash")
                    }
                }
            }
            .navigationTitle(tab.title)
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
        .environment(ConnectedPeer(name: "Sentinel"))
}
