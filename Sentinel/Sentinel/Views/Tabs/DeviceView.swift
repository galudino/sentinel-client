//
//  DeviceView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import SwiftUI

/// The **Device** tab (#18) — a navigation **hub**, not one inline screen. It
/// presents ``DeviceCategory`` rows; each pushes/selects a focused subview
/// (Device Info, Firmware, Time & Date, Storage, Debug Output, GATT Explorer).
/// Mirrors the proven control-panel-hub pattern.
///
/// Adaptive presentation:
/// - **compact (iPhone):** a `List` of navigation rows (`navigationDestination`).
/// - **regular (iPad / macOS):** `NavigationSplitView` — categories in the
///   sidebar, the selected subview in the detail pane.
///
/// Takes the `peer` (raw transport for the GATT Explorer + live link metrics +
/// the per-service clients), `any SystemService` (previewable identity reads for
/// the Firmware-row accessory + Device Info), and `firmwareUpdateAvailable`
/// (drives the Firmware-row badge, mirroring the Device-tab badge in #14).
struct DeviceView: View {
    let peer: ConnectedPeer
    let system: any SystemService
    let firmwareUpdateAvailable: Bool

    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var firmwareVersion: FirmwareVersion?
    @State private var selection: DeviceCategory? = .deviceInfo

    private var isRegularWidth: Bool { hSize == .regular }

    var body: some View {
        Group {
            if isRegularWidth {
                NavigationSplitView {
                    sidebar
                } detail: {
                    NavigationStack { detailView(for: selection) }
                }
            } else {
                NavigationStack {
                    compactList
                        .navigationDestination(for: DeviceCategory.self) { detailView(for: $0) }
                }
            }
        }
        .task { firmwareVersion = try? await system.readFirmwareVersion() }
    }

    // MARK: - Regular (split view) sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(DeviceCategory.phaseIRows) { row in
                    rowLabel(for: row).tag(row)
                }
            }
            phaseIISection
        }
        .navigationTitle("Device")
        .safeAreaInset(edge: .bottom) { disconnectButton.padding() }
    }

    // MARK: - Compact list

    private var compactList: some View {
        List {
            Section {
                ForEach(DeviceCategory.phaseIRows) { row in
                    NavigationLink(value: row) { rowLabel(for: row) }
                }
            }
            phaseIISection
            Section { disconnectButton }
        }
        .navigationTitle("Device")
    }

    @ViewBuilder private var phaseIISection: some View {
        let rows = DeviceCategory.phaseIIRows
        if !rows.isEmpty {
            Section("Sensor Configuration") {
                ForEach(rows) { row in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title)
                            Text("Coming in Phase II").font(.caption2).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: row.systemImage)
                    }
                    .foregroundStyle(.secondary)
                }
                .disabled(true)
            }
        }
    }

    private var disconnectButton: some View {
        Button(role: .destructive) {
            router.disconnect()
        } label: {
            Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
        }
    }

    // MARK: - Row label

    @ViewBuilder private func rowLabel(for category: DeviceCategory) -> some View {
        if category == .firmware {
            HStack {
                Label(category.title, systemImage: category.systemImage)
                Spacer()
                if let firmwareVersion {
                    Text(firmwareVersion.shortVersion)
                        .font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                if firmwareUpdateAvailable {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                        .accessibilityLabel("Update available")
                }
            }
        } else {
            Label(category.title, systemImage: category.systemImage)
        }
    }

    // MARK: - Detail routing

    @ViewBuilder private func detailView(for category: DeviceCategory?) -> some View {
        switch category {
        case .deviceInfo:
            DeviceInfoView(peer: peer, system: system)
        case .firmware:
            FirmwareSelectionView(peer: peer, installedVersion: firmwareVersion)
        case .timeAndDate:
            TimeAndDateView(ds3231: peer.ds3231)
        case .storage:
            StorageView(eventLog: peer.systemEventLog, snapshots: peer.snapshotHistory)
        case .debugStream:
            // #25 DebugOutputStreamView lands next; utilitarian placeholder for now.
            ContentUnavailableView(
                "Debug Output",
                systemImage: "text.alignleft",
                description: Text("The live debug output stream arrives in #25.")
            )
            .navigationTitle("Debug Output")
            .navigationBarTitleDisplayMode(.inline)
        case .gattExplorer:
            GATTExplorerView(transport: peer)
        case .bme280Config, .ds3231Config, .none:
            ContentUnavailableView(
                "Select a category",
                systemImage: "hand.tap",
                description: Text("Choose a device category from the list.")
            )
        }
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("Running 1.0.0") {
        DeviceView(
            peer: ConnectedPeer(name: "Sentinel"),
            system: MockSystemService(),
            firmwareUpdateAvailable: false
        )
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
        .environment(ImportedFirmwareStore())
    }

    #Preview("Update available") {
        DeviceView(
            peer: ConnectedPeer(name: "Sentinel"),
            system: MockSystemService(firmwareVersion: FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16)),
            firmwareUpdateAvailable: true
        )
        .environment(AppRouter(bluetoothManager: BluetoothManager()))
        .environment(ImportedFirmwareStore())
    }
#endif
