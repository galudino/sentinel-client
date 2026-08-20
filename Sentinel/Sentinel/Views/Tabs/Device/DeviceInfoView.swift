//
//  DeviceInfoView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/19/26.
//

import SwiftUI

/// **Device Info** (#18) — the read-only "About" panel for the connected device:
/// identity (name / model / manufacturer / serial), health (CPU temperature),
/// and live link metrics (RSSI / MTU). Serial is editable via a pushed
/// ``SerialNumberEditView``.
///
/// Reads identity through `any SystemService` (previewable against
/// `MockSystemService`); pulls live RSSI/MTU + name from the `peer`.
struct DeviceInfoView: View {
    let peer: ConnectedPeer
    let system: any SystemService

    @State private var firmwareVersion: FirmwareVersion?
    @State private var platformID: PlatformID?
    @State private var serialNumber: UInt32?
    @State private var cpuTemperatureCentiC: UInt16?

    var body: some View {
        List {
            Section("Identity") {
                LabeledContent("Name", value: peer.name ?? "Sentinel")
                LabeledContent("Model", value: platformID?.modelName ?? "—")
                LabeledContent("Manufacturer", value: platformID?.vendor.manufacturerName ?? "—")
                NavigationLink {
                    SerialNumberEditView(system: system, current: serialNumber) { new in
                        serialNumber = new
                    }
                } label: {
                    LabeledContent("Serial", value: serialText)
                }
            }

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
            }

            Section("Health") {
                LabeledContent("CPU temperature", value: cpuTemperatureText)
            }

            Section("Connection") {
                LabeledContent("Signal", value: "\(peer.rssi) dBm")
                LabeledContent("MTU", value: "\(peer.negotiatedMTU) B")
            }
        }
        .navigationTitle("Device Info")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Derived text

    private var serialText: String {
        serialNumber.map { String(format: "0x%08X", $0) } ?? "—"
    }

    private var cpuTemperatureText: String {
        guard let cpuTemperatureCentiC, cpuTemperatureCentiC != 0 else { return "—" }
        return (Double(cpuTemperatureCentiC) / 100.0)
            .formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    // MARK: - Loading

    private func load() async {
        firmwareVersion = try? await system.readFirmwareVersion()
        platformID = try? await system.readPlatformID()
        serialNumber = try? await system.readSerialNumber()
        cpuTemperatureCentiC = try? await system.readCPUTemperature()
        await peer.refreshSignal()
    }
}

// MARK: - Previews

#if DEBUG
    #Preview {
        NavigationStack {
            DeviceInfoView(peer: ConnectedPeer(name: "Sentinel"), system: MockSystemService())
        }
    }
#endif
