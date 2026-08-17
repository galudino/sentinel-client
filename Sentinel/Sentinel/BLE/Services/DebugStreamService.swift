//
//  DebugStreamService.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The device's debug log stream — UTF-8 lines the firmware emits when streaming
/// is enabled. Aggregate service. `DebugOutputStreamView` (#25) merges this with
/// the local ``BluetoothManager/bluetoothEventStream()`` into one timeline.
protocol DebugStreamService {
    /// Turn the device's debug output stream on or off.
    func setStreaming(_ enabled: Bool) async throws
    /// UTF-8 log lines pushed by the device while streaming is on.
    func outputNotifications() -> AsyncStream<String>
}

struct DebugStreamServiceClient<Transport: BluetoothPeripheralTransport>: DebugStreamService {
    let transport: Transport

    private var service: CBUUID { DebugStreamServiceUUID.debugStream.cbuuid }
    private var output: CBUUID { DebugStreamCharacteristicUUID.output.cbuuid }

    func setStreaming(_ enabled: Bool) async throws {
        try await transport.setNotify(enabled, characteristic: output, ofService: service)
    }

    func outputNotifications() -> AsyncStream<String> {
        transport.notifications(for: output, ofService: service)
    }
}

struct MockDebugStreamService: DebugStreamService {
    var lines: [String] = ["[boot] sentinel up", "[ble] link established"]

    func setStreaming(_: Bool) async throws {}
    func outputNotifications() -> AsyncStream<String> {
        .init { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }
}
