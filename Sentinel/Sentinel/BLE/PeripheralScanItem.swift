//
//  PeripheralScanItem.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import Foundation

/// One row in the discovered-peripheral list (`PeripheralScanView`, #12).
///
/// Carries the display identity (id / name / RSSI / last-seen) plus the live
/// `AsyncBluetooth` ``peripheral`` so, on tap, ``AppRouter/beginConnect(peripheralID:name:)``
/// can hand off the identity and ``BluetoothManager`` can resolve it back to a
/// `Peripheral` at connect time.
///
/// ``peripheral`` is optional so **SwiftUI previews** can build synthetic rows: a
/// `Peripheral` wraps a `CBPeripheral` (no public initializer), so it can't be
/// constructed off-device. Preview items are display-only and never connect.
struct PeripheralScanItem: Identifiable, Hashable {
    /// Stable identity: the `CBPeripheral.identifier` (or a synthetic id in previews).
    let id: UUID

    /// Advertised / GAP name, when known. Display-only.
    let name: String?

    /// Most recent advertised RSSI, in dBm. `127` means "not available".
    var rssi: Int

    /// When this row last saw an advertisement — used to age out stale entries.
    var lastUpdated: Date

    /// The live peripheral this row represents, or `nil` for a synthetic preview
    /// item. Retained by ``BluetoothManager/discoveredPeripherals`` for
    /// connect-time lookup.
    let peripheral: Peripheral?

    /// Production: a real discovered peripheral.
    init(peripheral: Peripheral, rssi: Int, lastUpdated: Date) {
        self.peripheral = peripheral
        id = peripheral.identifier
        name = peripheral.name
        self.rssi = rssi
        self.lastUpdated = lastUpdated
    }

    #if DEBUG
        /// Preview-only: a synthetic row with no backing peripheral.
        init(previewName: String?, rssi: Int, lastUpdated: Date = .now, id: UUID = UUID()) {
            peripheral = nil
            self.id = id
            name = previewName
            self.rssi = rssi
            self.lastUpdated = lastUpdated
        }
    #endif
}
