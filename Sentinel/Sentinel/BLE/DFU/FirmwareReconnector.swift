//
//  FirmwareReconnector.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/18/26.
//

import Foundation

/// Re-establishes the BLE link *after* a DFU reboot so the uploader (#22) can
/// confirm the new firmware version.
///
/// The device self-resets the instant it accepts `Verify` and drops the
/// connection (see the OTA wire protocol in #22). The uploader treats that
/// disconnect as success, then needs a fresh connection to read
/// ``SystemService/readFirmwareVersion()`` back. That reconnect needs the BLE
/// central — which the uploader deliberately does not depend on — so it is
/// injected behind this one-method seam:
///
/// - **Production** (``CentralFirmwareReconnector``) rescans + reconnects to the
///   same peripheral identity and hands back its live `SystemService`.
/// - **Tests** inject a mock that returns a `MockSystemService` pinned to the
///   target version, so the whole `.reconnecting → .verifying → .complete` tail
///   of the state machine is exercisable with no hardware.
protocol FirmwareReconnector: Sendable {
    /// Re-establish the connection and return the reconnected peer's identity +
    /// health service. Throws on timeout / failure.
    func reconnect() async throws -> any SystemService
}

/// Production ``FirmwareReconnector`` backed by the BLE central. After the DFU
/// reboot it reconnects to the same peripheral identity and exposes both the new
/// ``ConnectedPeer`` (so the router can swap `.updatingFirmware → .connected` onto
/// the *fresh* connection) and its `SystemService` (for the version check).
///
/// `@unchecked Sendable`: the captured central is already a Phase I concession
/// (#24); ``reconnectedPeer`` is written once on the reconnect task and read on the
/// main actor after `.complete`.
final class CentralFirmwareReconnector: FirmwareReconnector, @unchecked Sendable {
    private let central: any BluetoothCentral
    private let peripheralID: UUID
    private let name: String?

    /// The connection established by ``reconnect()`` — read by
    /// `FirmwareUpdateView` on completion to hand the new peer to the router.
    private(set) var reconnectedPeer: ConnectedPeer?

    init(central: any BluetoothCentral, peripheralID: UUID, name: String?) {
        self.central = central
        self.peripheralID = peripheralID
        self.name = name
    }

    func reconnect() async throws -> any SystemService {
        let peer = try await central.reconnect(peripheralID: peripheralID, name: name)
        reconnectedPeer = peer
        return peer.system
    }
}
