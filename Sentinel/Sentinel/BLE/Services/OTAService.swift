//
//  OTAService.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The OTA DFU control/data surface (WICED OTA FW Upgrade Service on the firmware
/// side). Aggregate service.
///
/// **Shape finalized in #22** (the DFU uploader) against the OTA wire protocol in
/// `docs/architecture/architecture.md`: a control characteristic for
/// prepare/verify/apply commands and a data characteristic for MTU-sized chunks
/// (chunk = negotiated MTU − 3; see ``ConnectedPeer/negotiatedMTU``). Phase I
/// defines the minimal move-bytes surface so `FirmwareUpdateView` (#21) can be
/// built against it.
protocol OTAService {
    /// Write a control-plane command byte (prepare / verify / apply — enumerated
    /// in #22).
    func writeControl(_ command: UInt8) async throws
    /// Write one firmware data chunk (sized to the negotiated MTU by the caller).
    func writeChunk(_ chunk: Data) async throws
    func setNotifying(_ enabled: Bool) async throws
    /// Device-reported DFU status/progress bytes (enumerated in #22).
    func statusNotifications() -> AsyncStream<UInt8>
}

struct OTAServiceClient<Transport: BluetoothPeripheralTransport>: OTAService {
    let transport: Transport

    private var service: CBUUID { OTAServiceUUID.ota.cbuuid }
    private var control: CBUUID { OTACharacteristicUUID.control.cbuuid }
    private var data: CBUUID { OTACharacteristicUUID.data.cbuuid }

    func writeControl(_ command: UInt8) async throws {
        try await transport.write(command, characteristic: control, ofService: service, type: .withResponse)
    }

    func writeChunk(_ chunk: Data) async throws {
        // Chunks stream without response for throughput; the control plane gates
        // correctness (#22).
        try await transport.write(chunk, characteristic: data, ofService: service, type: .withoutResponse)
    }

    func setNotifying(_ enabled: Bool) async throws {
        try await transport.setNotify(enabled, characteristic: control, ofService: service)
    }

    func statusNotifications() -> AsyncStream<UInt8> {
        transport.notifications(for: control, ofService: service)
    }
}

struct MockOTAService: OTAService {
    func writeControl(_: UInt8) async throws {}
    func writeChunk(_: Data) async throws {}
    func setNotifying(_: Bool) async throws {}
    func statusNotifications() -> AsyncStream<UInt8> { .init { $0.finish() } }
}
