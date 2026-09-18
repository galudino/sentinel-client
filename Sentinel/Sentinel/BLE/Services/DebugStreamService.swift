//
//  DebugStreamService.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The device's debug log stream — UTF-8 lines (≤128 B) the firmware emits when
/// streaming is enabled. Mirrors firmware `sentinel_gatt_debug.hpp`.
/// `DebugOutputStreamView` (#25) merges this with the local
/// ``BluetoothManager/bluetoothEventStream()`` into one timeline.
/// `Sendable` so `DebugOutputStreamView` (#25) can hand the service to a detached
/// teardown task that disarms the stream even after its consuming `.task` was
/// cancelled on disappear. Both conformers are value/`@unchecked Sendable`-backed.
protocol DebugStreamService: Sendable {
    /// Turn the device's debug output stream on or off.
    func setStreaming(_ enabled: Bool) async throws
    /// UTF-8 log lines pushed by the device while streaming is on.
    func outputNotifications() -> AsyncStream<String>
}

struct DebugStreamServiceClient<Transport: BluetoothPeripheralTransport>: DebugStreamService {
    let transport: Transport

    private var service: CBUUID { SentinelServiceUUID.debugStream.cbuuid }
    private var output: CBUUID { DebugStreamCharacteristicUUID.outputStream.cbuuid }

    /// The firmware gates the stream behind a separate notify-enable flag that must
    /// be armed **before** the CCCD subscribe (and cleared **after** unsubscribe),
    /// so the two writes are ordered symmetrically here.
    func setStreaming(_ enabled: Bool) async throws {
        if enabled {
            try await streamNotifyEnable(true)
            try await transport.setNotify(true, characteristic: output, ofService: service)
        } else {
            try await transport.setNotify(false, characteristic: output, ofService: service)
            try await streamNotifyEnable(false)
        }
    }

    func outputNotifications() -> AsyncStream<String> {
        transport.notifications(for: output, ofService: service)
    }

    private func streamNotifyEnable(_ enabled: Bool) async throws {
        try await transport.write(
            UInt8(enabled ? 1 : 0),
            characteristic: DebugStreamCharacteristicUUID.notifyEnable.cbuuid,
            ofService: service,
            type: .withResponse
        )
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
