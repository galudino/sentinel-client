//
//  OTAService.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The OTA DFU control/data surface — the Infineon OTA FW Upgrade Service
/// (`AE5D1E47-…`). Control Point is W/Notify/Indicate; Upgrade Data is W.
///
/// **Command/status byte semantics are finalized in #22** (the DFU uploader)
/// against the OTA wire protocol in `docs/architecture/architecture.md`: data
/// chunks are sized to the negotiated MTU (chunk = MTU − 3; see
/// ``ConnectedPeer/negotiatedMTU``). Phase I (#9) defines the move-bytes surface.
protocol OTAService {
    /// Write a control-plane command frame (prepare / verify / apply — #22).
    func writeControlPoint(_ command: Data) async throws
    /// Write one firmware data chunk (sized to the negotiated MTU by the caller).
    func writeData(_ chunk: Data) async throws
    func setControlPointNotifying(_ enabled: Bool) async throws
    /// Device-reported DFU status/progress frames (enumerated in #22).
    func controlPointNotifications() -> AsyncStream<Data>
}

struct OTAServiceClient<Transport: BluetoothPeripheralTransport>: OTAService {
    let transport: Transport

    private var service: CBUUID { SentinelServiceUUID.ota.cbuuid }
    private var control: CBUUID { OTACharacteristicUUID.controlPoint.cbuuid }
    private var data: CBUUID { OTACharacteristicUUID.data.cbuuid }

    func writeControlPoint(_ command: Data) async throws {
        try await transport.write(command, characteristic: control, ofService: service, type: .withResponse)
    }

    func writeData(_ chunk: Data) async throws {
        // Data streams without response for throughput; the control plane gates
        // correctness (#22).
        try await transport.write(chunk, characteristic: data, ofService: service, type: .withoutResponse)
    }

    func setControlPointNotifying(_ enabled: Bool) async throws {
        try await transport.setNotify(enabled, characteristic: control, ofService: service)
    }

    func controlPointNotifications() -> AsyncStream<Data> {
        transport.notifications(for: control, ofService: service)
    }
}

struct MockOTAService: OTAService {
    func writeControlPoint(_: Data) async throws {}
    func writeData(_: Data) async throws {}
    func setControlPointNotifying(_: Bool) async throws {}
    func controlPointNotifications() -> AsyncStream<Data> { .init { $0.finish() } }
}
