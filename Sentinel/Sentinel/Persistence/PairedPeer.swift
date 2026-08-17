//
//  PairedPeer.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation

/// A device the user has previously connected to. Persisted by ``PairedPeerStore``
/// so `PeripheralScanView` (#12) can elevate trusted devices and auto-connect, and
/// so the firmware-update signal (#14/#18/#20) can compare last-seen versions.
struct PairedPeer: Codable, Identifiable, Equatable, Sendable {
    /// The `CBPeripheral.identifier`.
    let id: UUID
    /// User-overridable; defaults to the advertised name.
    var displayName: String?
    var lastConnectedAt: Date
    /// Firmware version last read from the device's ``SystemService``.
    var lastFirmwareVersion: FirmwareVersion?
    /// When this peer was first paired/trusted.
    var trustedAt: Date
}
