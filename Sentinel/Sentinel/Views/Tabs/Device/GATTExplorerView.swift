//
//  GATTExplorerView.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/19/26.
//

import CoreBluetooth
import SwiftUI

/// **GATT Explorer** (#18) — the diagnostic drill-down: services →
/// characteristics → characteristic detail. Catalog-driven
/// (``CharacteristicCatalog``), so every service/characteristic in the #9
/// contract appears automatically; a new firmware characteristic shows up here
/// for free once it has a catalog descriptor.
///
/// Reads and writes go through the **raw** ``BluetoothPeripheralTransport``
/// primitives — not the opinionated `*ServiceClient` APIs — so it can exercise a
/// characteristic before any polished view exists. Intentionally utilitarian
/// (system fonts/colors); design effort belongs in the polished tabs.
struct GATTExplorerView: View {
    let transport: any BluetoothPeripheralTransport

    var body: some View {
        List(SentinelServiceUUID.allCases, id: \.self) { service in
            NavigationLink {
                ServiceCharacteristicsView(service: service, transport: transport)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.displayName)
                    Text(service.cbuuid.uuidString)
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("GATT Explorer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The characteristics of a single service.
struct ServiceCharacteristicsView: View {
    let service: SentinelServiceUUID
    let transport: any BluetoothPeripheralTransport

    private var descriptors: [CharacteristicDescriptor] {
        CharacteristicCatalog.descriptors(for: service)
    }

    var body: some View {
        List(descriptors) { descriptor in
            NavigationLink {
                CharacteristicDetailView(descriptor: descriptor, transport: transport)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(descriptor.displayName)
                        Spacer()
                        Text(descriptor.properties.compactLabel)
                            .font(.caption.monospaced()).foregroundStyle(.tint)
                    }
                    Text(descriptor.characteristicCBUUID.uuidString)
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(service.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if descriptors.isEmpty {
                ContentUnavailableView("No characteristics", systemImage: "list.bullet.rectangle")
            }
        }
    }
}

extension CBCharacteristicProperties {
    /// Compact `R/W/N/I` label for the catalogued properties.
    var compactLabel: String {
        var parts: [String] = []
        if contains(.read) { parts.append("R") }
        if contains(.write) || contains(.writeWithoutResponse) { parts.append("W") }
        if contains(.notify) { parts.append("N") }
        if contains(.indicate) { parts.append("I") }
        return parts.isEmpty ? "—" : parts.joined(separator: "/")
    }
}

// MARK: - Previews

#if DEBUG
    #Preview("Services") {
        NavigationStack {
            GATTExplorerView(transport: MockBluetoothTransport())
        }
    }

    #Preview("System characteristics") {
        NavigationStack {
            ServiceCharacteristicsView(service: .system, transport: MockBluetoothTransport())
        }
    }
#endif
