//
//  PeripheralScanView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import SwiftUI

/// Entry screen — the app's "log in". Scans for sentinel peripherals and lets
/// the user pick one to connect. Picking a peripheral drives the router into
/// `.connecting`.
///
/// **Stub for #7.** The real scan list, RSSI, filtering, and the Debug button
/// (→ `DebugOutputStreamView`, #25) land in **#12**, built on ``BluetoothManager``
/// (#8). For now this exercises the state machine with a synthetic peripheral.
struct PeripheralScanView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ContentUnavailableView {
            Label("Scan for Devices", systemImage: "sensor.fill")
        } description: {
            Text("Discovered sentinel devices will appear here. (#12)")
        } actions: {
            Button {
                // Seed: synthesize a peripheral so the flow is walkable. #12 passes
                // a real peripheral from the scan list.
                router.beginConnect(peripheralID: UUID(), name: "Sentinel")
            } label: {
                Label("Connect to Sentinel", systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Sentinel")
    }
}

#Preview {
    NavigationStack {
        PeripheralScanView()
    }
    .environment(AppRouter(bluetoothManager: BluetoothManager()))
}
