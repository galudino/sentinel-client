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
/// Wraps the live `AsyncBluetooth` `Peripheral` together with the most recent
/// advertisement signal, so the scan UI can show a name + RSSI and, on tap, hand
/// the peripheral's identity to ``AppRouter/beginConnect(peripheralID:name:)``.
/// ``BluetoothManager`` keeps the backing peripheral so it can resolve that
/// identity back to a `Peripheral` at connect time.
struct PeripheralScanItem: Identifiable, Hashable {
    /// The live peripheral this row represents. Retained by
    /// ``BluetoothManager/discoveredPeripherals`` for connect-time lookup.
    let peripheral: Peripheral

    /// Most recent advertised RSSI, in dBm. `127` means "not available".
    var rssi: Int

    /// When this row last saw an advertisement — used to age out stale entries.
    var lastUpdated: Date

    /// Advertised / GAP name, when known. Display-only convenience.
    var name: String? { peripheral.name }

    /// Stable identity: the `CBPeripheral.identifier`.
    var id: UUID { peripheral.identifier }
}
