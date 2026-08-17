//
//  PeripheralScanView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import SwiftUI

/// Entry screen — the app's "log in". Scans for sentinel peripherals and lets the
/// user pick one to connect. Picking a peripheral drives the router into
/// `.connecting`.
///
/// **Interim scan list for #8.** This is the minimum needed to exercise the real
/// ``BluetoothManager`` end-to-end (start a scan, list discovered peers, connect a
/// real one). The polished scan UI — signal bars, filtering, empty/permission
/// states, and the Debug button (→ `DebugOutputStreamView`, #25) — is **#12**.
struct PeripheralScanView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BluetoothManager.self) private var bluetoothManager

    @State private var scanError: String?

    var body: some View {
        Group {
            if bluetoothManager.discoveredPeripherals.isEmpty {
                ContentUnavailableView {
                    Label("Scanning for Devices", systemImage: "sensor.fill")
                } description: {
                    Text(scanError ?? "Discovered sentinel devices will appear here. (polished list: #12)")
                } actions: {
                    if scanError != nil {
                        Button("Retry") { startScan() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        ProgressView()
                    }
                }
            } else {
                List(bluetoothManager.discoveredPeripherals) { item in
                    Button {
                        router.beginConnect(peripheralID: item.id, name: item.name)
                    } label: {
                        LabeledContent(item.name ?? "Unnamed device") {
                            Text("\(item.rssi) dBm").monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle("Sentinel")
        .task { startScan() }
    }

    private func startScan() {
        scanError = nil
        Task {
            do {
                try await bluetoothManager.scanForPeripherals()
            } catch {
                scanError = "Bluetooth unavailable: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        PeripheralScanView()
    }
    .environment(AppRouter(bluetoothManager: BluetoothManager()))
    .environment(BluetoothManager())
}
