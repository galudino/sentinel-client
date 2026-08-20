//
//  SettingsView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import SwiftUI

/// The **Settings** tab — strictly *app-side* preferences + paired-device
/// management. Device-side concerns (firmware, GATT, device controls) live in the
/// Device tab (#18), never here.
///
/// Reads the app-wide `@Observable` stores: ``AppPreferences`` + ``PairedPeerStore``
/// (#23). "Currently connected" shows the peripheral **identifier** — iOS
/// CoreBluetooth does not expose the BD_ADDR (the wire MAC), only the stable
/// per-install `CBPeripheral.identifier`.
struct SettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(PairedPeerStore.self) private var pairedStore
    @Environment(AppRouter.self) private var router
    @Environment(ConnectedPeer.self) private var peer

    @State private var confirmingForgetAll = false

    var body: some View {
        @Bindable var preferences = preferences

        NavigationStack {
            Form {
                pairedDevicesSection
                connectionSection

                Section("Appearance") {
                    Picker("Theme", selection: $preferences.theme) {
                        ForEach(Theme.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }

                Section("Units") {
                    Picker("Temperature", selection: $preferences.temperatureUnit) {
                        Text("Celsius (°C)").tag(TemperatureUnit.celsius)
                        Text("Fahrenheit (°F)").tag(TemperatureUnit.fahrenheit)
                    }
                    Picker("Pressure", selection: $preferences.pressureUnit) {
                        ForEach(PressureUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
                    }
                }

                Section("Notifications") {
                    Toggle("Firmware-update banner on Home", isOn: $preferences.showFirmwareUpdateBanner)
                }

                Section("Developer") {
                    Toggle("Debug mode", isOn: $preferences.debugModeEnabled)
                }

                aboutSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: Paired devices

    @ViewBuilder
    private var pairedDevicesSection: some View {
        Section("Paired Devices") {
            if pairedStore.peers.isEmpty {
                Text("No paired devices yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pairedStore.peers) { paired in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(paired.displayName ?? "Sentinel")
                        Text("Last connected \(paired.lastConnectedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Forget", role: .destructive) { pairedStore.forget(paired.id) }
                    }
                }

                Button("Forget All Devices", role: .destructive) { confirmingForgetAll = true }
                    .confirmationDialog(
                        "Forget all paired devices?",
                        isPresented: $confirmingForgetAll,
                        titleVisibility: .visible
                    ) {
                        Button("Forget All", role: .destructive) { pairedStore.forgetAll() }
                        Button("Cancel", role: .cancel) {}
                    }
            }
        }
    }

    // MARK: Current connection

    private var connectionSection: some View {
        Section("Connected Device") {
            LabeledContent("Name", value: peer.name ?? "Sentinel")
            LabeledContent("Identifier") {
                Text(peer.id.uuidString).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                router.disconnect()
            } label: {
                Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Self.appVersion)
            LabeledContent("Build", value: Self.appBuild)
            Link(destination: URL(string: "https://github.com/galudino/sentinel-client")!) {
                Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

#Preview {
    SettingsView()
        .environment(AppPreferences())
        .environment(PairedPeerStore.preview())
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
        .environment(ConnectedPeer(name: "Sentinel"))
}
