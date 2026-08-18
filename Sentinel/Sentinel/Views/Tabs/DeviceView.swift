//
//  DeviceView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import SwiftUI

/// The **Device** tab — the home for everything *about the connected device*:
/// firmware version, identity, health, firmware update, and (later) the GATT
/// explorer. Scope mirrors iOS Settings → General for the iPhone.
///
/// **Partial #18 (device identity + health).** This lands the identity/health
/// panel — crucially the **running firmware version**, so a DFU's success is
/// verifiable at a glance (#22). The full device admin surface + GATT explorer
/// remain for #18; the "Update Firmware…" row is the DFU entry (#20/#21/#22).
///
/// Takes `any SystemService` (previewable against `MockSystemService`) plus the
/// `peer` for live link metrics and the router for disconnect / DFU launch.
struct DeviceView: View {
    let peer: ConnectedPeer
    let system: any SystemService

    @Environment(AppRouter.self) private var router

    @State private var firmwareVersion: FirmwareVersion?
    @State private var platformID: PlatformID?
    @State private var serialNumber: UInt32?
    @State private var cpuTemperatureCentiC: UInt16?

    var body: some View {
        NavigationStack {
            List {
                Section("Firmware") {
                    LabeledContent("Version") {
                        if let firmwareVersion {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(firmwareVersion.shortVersion)
                                    .font(.body.monospaced().weight(.semibold))
                                Text("build \(firmwareVersion.build)")
                                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            }
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        // DFU entry seed — #20 makes this push FirmwareSelectionView;
                        // #21/#22 own the actual update. Kept as-is until that session.
                        router.startFirmwareUpdate(FirmwareImage(version: "1.1.0"))
                    } label: {
                        Label("Update Firmware…", systemImage: "arrow.up.circle")
                    }
                }

                Section("Device") {
                    LabeledContent("Model", value: platformID?.modelName ?? "—")
                    LabeledContent("Manufacturer", value: platformID?.vendor.manufacturerName ?? "—")
                    LabeledContent("Serial", value: serialText)
                    LabeledContent("CPU temperature", value: cpuTemperatureText)
                }

                Section("Connection") {
                    LabeledContent("Name", value: peer.name ?? "Sentinel")
                    LabeledContent("Signal", value: "\(peer.rssi) dBm")
                    LabeledContent("MTU", value: "\(peer.negotiatedMTU) B")
                }

                Section {
                    Button(role: .destructive) {
                        router.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "wifi.slash")
                    }
                }
            }
            .navigationTitle("Device")
            .task { await loadIdentity() }
            .refreshable { await loadIdentity() }
        }
    }

    // MARK: - Derived text

    private var serialText: String {
        serialNumber.map { String(format: "0x%08X", $0) } ?? "—"
    }

    private var cpuTemperatureText: String {
        guard let cpuTemperatureCentiC, cpuTemperatureCentiC != 0 else { return "—" }
        return (Double(cpuTemperatureCentiC) / 100.0).formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    // MARK: - Loading

    private func loadIdentity() async {
        firmwareVersion = try? await system.readFirmwareVersion()
        platformID = try? await system.readPlatformID()
        serialNumber = try? await system.readSerialNumber()
        cpuTemperatureCentiC = try? await system.readCPUTemperature()
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("Running 1.0.0") {
        DeviceView(peer: ConnectedPeer(name: "Sentinel-A1B2"), system: MockSystemService())
            .environment(AppRouter(bluetoothManager: BluetoothManager()))
    }

    #Preview("After DFU → 1.0.1") {
        DeviceView(
            peer: ConnectedPeer(name: "Sentinel-A1B2"),
            system: MockSystemService(firmwareVersion: FirmwareVersion(major: 1, minor: 0, patch: 1, build: 17))
        )
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
    }
#endif
