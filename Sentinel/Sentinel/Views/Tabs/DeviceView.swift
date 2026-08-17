//
//  DeviceView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import SwiftUI

/// The **Device** tab — the home for everything *about the connected device*:
/// firmware version, serial number, time sync, storage, firmware update, and the
/// GATT explorer (its scope mirrors iOS Settings → General for the iPhone).
///
/// **Stub for #14.** The real device panel (live identity via `peer.system`, DIS
/// reads from #9, controls, GATT explorer) lands in **#18**; the "Update Firmware"
/// row pushes `FirmwareSelectionView` (#20). For now it carries the DFU-entry seed
/// and the disconnect action so the connected subtree is fully walkable.
struct DeviceView: View {
    let peer: ConnectedPeer

    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            List {
                Section("Connected Device") {
                    LabeledContent("Name", value: peer.name ?? "Sentinel")
                    LabeledContent("Signal", value: "\(peer.rssi) dBm")
                    LabeledContent("MTU", value: "\(peer.negotiatedMTU)")
                }

                Section("Firmware") {
                    // Seed DFU entry — #18 makes this a NavigationStack push to
                    // FirmwareSelectionView (#20); #21/#22 own the actual update.
                    Button {
                        router.startFirmwareUpdate(FirmwareImage(version: "1.1.0"))
                    } label: {
                        Label("Update Firmware…", systemImage: "arrow.up.circle")
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
            .navigationTitle("Device")
        }
    }
}

#Preview {
    DeviceView(peer: ConnectedPeer(name: "Sentinel"))
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
}
