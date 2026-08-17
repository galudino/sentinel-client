//
//  DS3231Service.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The DS3231 real-time clock — **read-only** in Phase I. The firmware surfaces
/// the current time on a cadence driven by the DS3231 SQW interrupt (firmware
/// #5); BLE time-*set* is deliberately deferred (firmware #6 owns the contract,
/// client mirrors it). No `writeTime` here by design.
protocol DS3231Service {
    /// Current device time as Unix epoch seconds (UTC).
    func readEpochSeconds() async throws -> UInt32
    func setNotifying(_ enabled: Bool) async throws
    /// Time ticks pushed on the SQW cadence.
    func timeNotifications() -> AsyncStream<UInt32>
}

struct DS3231ServiceClient<Transport: BluetoothPeripheralTransport>: DS3231Service {
    let transport: Transport

    private var service: CBUUID { DS3231ServiceUUID.ds3231.cbuuid }
    private var time: CBUUID { DS3231CharacteristicUUID.time.cbuuid }

    func readEpochSeconds() async throws -> UInt32 {
        try await transport.read(characteristic: time, ofService: service) ?? 0
    }

    func setNotifying(_ enabled: Bool) async throws {
        try await transport.setNotify(enabled, characteristic: time, ofService: service)
    }

    func timeNotifications() -> AsyncStream<UInt32> {
        transport.notifications(for: time, ofService: service)
    }
}

struct MockDS3231Service: DS3231Service {
    var epochSeconds: UInt32 = 1_760_000_000

    func readEpochSeconds() async throws -> UInt32 { epochSeconds }
    func setNotifying(_: Bool) async throws {}
    func timeNotifications() -> AsyncStream<UInt32> { .init { $0.yield(epochSeconds); $0.finish() } }
}
