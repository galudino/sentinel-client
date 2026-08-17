//
//  PeripheralScanView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import CoreBluetooth
import SwiftUI

/// Entry screen — the app's "log in". Scans for sentinel peripherals, lists them
/// with signal + last-seen, and connects the one the user taps (driving the router
/// to `.connecting`).
///
/// Deferred to their owning issues: the **Trusted devices** section (needs the
/// paired-peer registry, #23) and the toolbar **Debug** button → `DebugOutputStreamView`
/// (#25). Everything else — live scan list, RSSI, staleness fade, empty state,
/// Bluetooth-unavailable/permission path, connect-on-tap — is here.
struct PeripheralScanView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BluetoothManager.self) private var bluetoothManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    /// Set when a scan attempt fails; categorized from the central's state.
    @State private var unavailable: BluetoothUnavailableReason?

    var body: some View {
        Group {
            if let unavailable {
                unavailableView(unavailable)
            } else if bluetoothManager.discoveredPeripherals.isEmpty {
                emptyState
            } else {
                deviceList
            }
        }
        .navigationTitle("Sentinel Devices")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Re-scan", systemImage: "arrow.clockwise") { startScan() }
            }
        }
        .task { startScan() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: startScan()
            default: Task { try? await bluetoothManager.stopScan() }
            }
        }
    }

    private var deviceList: some View {
        List {
            Section("Other Devices Nearby") {
                ForEach(bluetoothManager.discoveredPeripherals) { item in
                    Button {
                        router.beginConnect(peripheralID: item.id, name: item.name)
                    } label: {
                        PeripheralRow(name: item.name, rssi: item.rssi, timestamp: item.lastUpdated)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Scanning for Devices", systemImage: "sensor.fill")
        } description: {
            Text("No Sentinel devices found nearby. Make sure your device is powered on and within Bluetooth range.")
        } actions: {
            Button("Scan Again", systemImage: "arrow.clockwise") { startScan() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func unavailableView(_ reason: BluetoothUnavailableReason) -> some View {
        ContentUnavailableView {
            Label(reason.title, systemImage: reason.systemImage)
        } description: {
            Text(reason.message)
        } actions: {
            if reason.showsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Try Again") { startScan() }
            }
        }
    }

    private func startScan() {
        unavailable = nil
        Task {
            do {
                try await bluetoothManager.scanForPeripherals()
            } catch {
                // Categorize from the central's current state (poweredOff vs.
                // unauthorized vs. unsupported) for an actionable message.
                unavailable = BluetoothUnavailableReason(state: bluetoothManager.bluetoothState)
            }
        }
    }
}

/// A user-facing reason the scan can't proceed, derived from `CBManagerState`.
enum BluetoothUnavailableReason {
    case poweredOff
    case unauthorized
    case unsupported

    init?(state: CBManagerState) {
        switch state {
        case .poweredOff: self = .poweredOff
        case .unauthorized: self = .unauthorized
        case .unsupported: self = .unsupported
        default: return nil // poweredOn / resetting / unknown → retryable, not a hard stop
        }
    }

    var title: String {
        switch self {
        case .poweredOff: "Bluetooth is Off"
        case .unauthorized: "Bluetooth Permission Needed"
        case .unsupported: "Bluetooth Unavailable"
        }
    }

    var message: String {
        switch self {
        case .poweredOff: "Turn on Bluetooth in Control Center or Settings to find your Sentinel device."
        case .unauthorized: "Sentinel needs Bluetooth permission to find your device. Enable it in Settings."
        case .unsupported: "This device doesn't support Bluetooth Low Energy."
        }
    }

    var systemImage: String {
        switch self {
        case .poweredOff: "wave.3.right.circle"
        case .unauthorized: "lock.circle"
        case .unsupported: "exclamationmark.triangle"
        }
    }

    var showsSettings: Bool {
        switch self {
        case .unauthorized, .poweredOff: true
        case .unsupported: false
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
