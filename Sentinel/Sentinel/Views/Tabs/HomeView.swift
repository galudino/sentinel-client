//
//  HomeView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import SwiftUI

/// The **Home** tab — live + historical sensor data (Apple-Health-style).
///
/// **Stub for #14.** The real dashboard (live BME280 telemetry, charts, history)
/// lands in **#15**, built against `peer.bme280` / `peer.snapshotStream`. #14
/// wires it into the tab shell and drives the firmware-update banner.
struct HomeView: View {
    let peer: ConnectedPeer
    /// Whether a newer firmware image is available (from #20's check). Drives the
    /// dismissable banner; tapping it jumps to the Device tab.
    var firmwareUpdateAvailable: Bool = false
    var onShowFirmwareUpdate: () -> Void = {}

    @State private var bannerDismissed = false

    var body: some View {
        NavigationStack {
            List {
                if firmwareUpdateAvailable, !bannerDismissed {
                    Section {
                        Button(action: onShowFirmwareUpdate) {
                            Label {
                                Text("Firmware update available — tap to view")
                            } icon: {
                                Image(systemName: "arrow.up.circle.fill").foregroundStyle(.orange)
                            }
                        }
                        .swipeActions {
                            Button("Dismiss") { bannerDismissed = true }
                        }
                    }
                }

                ContentUnavailableView(
                    "Live Telemetry",
                    systemImage: "sensor.fill",
                    description: Text(
                        "BME280 temperature, humidity, and pressure — live and historical — arrive in #15."
                    )
                )
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Home")
        }
    }
}

#Preview {
    HomeView(peer: ConnectedPeer(name: "Sentinel"), firmwareUpdateAvailable: true)
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
}
