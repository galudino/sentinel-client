//
//  Peripheral+Hashable.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import Foundation

// AsyncBluetooth's `Peripheral` is a `final class` with no `Equatable`/`Hashable`
// conformance, but the scan list (`PeripheralScanItem`) needs both so SwiftUI can
// diff and animate discovered rows. Identity is the stable
// `CBPeripheral.identifier`, so declare the conformance once, here, and reuse it
// everywhere (`@retroactive` because neither the type nor the protocols are ours).

extension Peripheral: @retroactive Equatable {
    public static func == (lhs: Peripheral, rhs: Peripheral) -> Bool {
        lhs.identifier == rhs.identifier
    }
}

extension Peripheral: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}
