//
//  PeripheralRow.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import SwiftUI

/// One discovered-device row: name, last-seen (or "Last connected" for trusted),
/// and a signal-strength indicator. Takes display primitives — not a
/// `PeripheralScanItem` — so it previews with synthetic data and no
/// `BluetoothManager`.
struct PeripheralRow: View {
    let name: String?
    let rssi: Int
    /// When this device was last advertised (untrusted) or connected (trusted).
    let timestamp: Date
    var trusted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trusted ? "checkmark.seal.fill" : "sensor.fill")
                .font(.title3)
                .foregroundStyle(trusted ? Color.accentColor : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? "Unknown device")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            SignalStrengthView(rssi: rssi)
                .frame(width: 22, height: 18)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if trusted {
            "Last connected \(timestamp.formatted(.relative(presentation: .named)))"
        } else {
            "\(rssi) dBm · seen \(timestamp.formatted(.relative(presentation: .numeric)))"
        }
    }
}

/// Four-bar signal indicator driven by RSSI (dBm). Thresholds are the usual BLE
/// buckets: ≥ -55 excellent, ≥ -67 good, ≥ -80 fair, else weak.
struct SignalStrengthView: View {
    let rssi: Int

    private var activeBars: Int {
        switch rssi {
        case (-55)...: 4
        case -67 ..< -55: 3
        case -80 ..< -67: 2
        default: 1
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0 ..< 4) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < activeBars ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(height: CGFloat(6 + index * 4))
            }
        }
        .accessibilityLabel("Signal \(activeBars) of 4")
    }
}

#Preview("Rows") {
    List {
        PeripheralRow(name: "Sentinel", rssi: -48, timestamp: .now.addingTimeInterval(-3), trusted: true)
        PeripheralRow(name: "Sentinel-2F1A", rssi: -63, timestamp: .now.addingTimeInterval(-8))
        PeripheralRow(name: nil, rssi: -88, timestamp: .now.addingTimeInterval(-20))
    }
}
