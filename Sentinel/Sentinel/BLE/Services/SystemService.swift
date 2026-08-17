//
//  SystemService.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import Foundation

/// Cross-cutting device identity + liveness: firmware version and uptime.
///
/// **The Phase I reference trio, wired end-to-end** — protocol + generic
/// ``SystemServiceClient`` (real, over any ``BluetoothPeripheralTransport``) +
/// ``MockSystemService`` (canned). The other Phase I services follow this exact
/// pattern.
protocol SystemService {
    /// Human-readable firmware version string, e.g. `"1.0.0"`.
    func readFirmwareVersion() async throws -> String

    /// Seconds since the device last booted.
    func readUptimeSeconds() async throws -> UInt32
}

/// The real ``SystemService`` — decodes values read over a transport. Stateless
/// beyond the transport reference, so it's cheap to build on demand from
/// ``ConnectedPeer/system``.
struct SystemServiceClient<Transport: BluetoothPeripheralTransport>: SystemService {
    let transport: Transport

    func readFirmwareVersion() async throws -> String {
        try await transport.read(
            characteristic: SystemCharacteristicUUID.firmwareVersion.cbuuid,
            ofService: SystemServiceUUID.system.cbuuid
        ) ?? ""
    }

    func readUptimeSeconds() async throws -> UInt32 {
        try await transport.read(
            characteristic: SystemCharacteristicUUID.uptimeSeconds.cbuuid,
            ofService: SystemServiceUUID.system.cbuuid
        ) ?? 0
    }
}

/// A canned ``SystemService`` for previews and view tests — no transport.
struct MockSystemService: SystemService {
    var firmwareVersion = "1.0.0"
    var uptimeSeconds: UInt32 = 3600

    func readFirmwareVersion() async throws -> String { firmwareVersion }
    func readUptimeSeconds() async throws -> UInt32 { uptimeSeconds }
}
