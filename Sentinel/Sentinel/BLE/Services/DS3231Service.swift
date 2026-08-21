//
//  DS3231Service.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The DS3231 real-time clock. Its registers are independent, so the contract
/// gives one characteristic each: Unix Time (R/W), RTC Temperature (R/Notify),
/// Alarm Flags (R). Mirrors firmware `sentinel_gatt_ds3231.hpp`.
///
/// The Unix Time characteristic is R/W on the wire; ``writeUnixTime(_:)`` backs
/// the DeviceView "Sync from iPhone" control (#18). Whether the device *honors*
/// the write depends on firmware #6 wiring the set-time handler — the client
/// re-reads after writing so a silent no-op surfaces as an unchanged value.
protocol DS3231Service {
    /// Current device time as Unix epoch seconds (UTC).
    func readUnixTime() async throws -> UInt32
    /// Set the device clock to `seconds` (Unix epoch, UTC). Depends on firmware #6
    /// honoring the write; callers should re-read to confirm.
    func writeUnixTime(_ seconds: UInt32) async throws
    /// On-die RTC temperature, 0.01 °C / LSB.
    func readRTCTemperature() async throws -> Int16
    /// Alarm/status flags: bit0=A1F, bit1=A2F, bit7=OSF.
    func readAlarmFlags() async throws -> UInt8
    /// Enable/disable RTC-temperature notifications.
    func setTemperatureNotifying(_ enabled: Bool) async throws
    func rtcTemperatureNotifications() -> AsyncStream<Int16>
}

struct DS3231ServiceClient<Transport: BluetoothPeripheralTransport>: DS3231Service {
    let transport: Transport

    private var service: CBUUID { SentinelServiceUUID.ds3231.cbuuid }

    func readUnixTime() async throws -> UInt32 {
        try await transport.read(characteristic: DS3231CharacteristicUUID.unixTime.cbuuid, ofService: service) ?? 0
    }

    func writeUnixTime(_ seconds: UInt32) async throws {
        try await transport.write(
            seconds,
            characteristic: DS3231CharacteristicUUID.unixTime.cbuuid,
            ofService: service,
            type: .withResponse
        )
    }

    func readRTCTemperature() async throws -> Int16 {
        try await transport
            .read(characteristic: DS3231CharacteristicUUID.rtcTemperature.cbuuid, ofService: service) ?? 0
    }

    func readAlarmFlags() async throws -> UInt8 {
        try await transport.read(characteristic: DS3231CharacteristicUUID.alarmFlags.cbuuid, ofService: service) ?? 0
    }

    func setTemperatureNotifying(_ enabled: Bool) async throws {
        try await transport.setNotify(
            enabled,
            characteristic: DS3231CharacteristicUUID.rtcTemperature.cbuuid,
            ofService: service
        )
    }

    func rtcTemperatureNotifications() -> AsyncStream<Int16> {
        transport.notifications(for: DS3231CharacteristicUUID.rtcTemperature.cbuuid, ofService: service)
    }
}

final class MockDS3231Service: DS3231Service, @unchecked Sendable {
    var unixTime: UInt32
    var rtcTemperature: Int16
    var alarmFlags: UInt8

    init(unixTime: UInt32 = 1_760_000_000, rtcTemperature: Int16 = 2500, alarmFlags: UInt8 = 0) {
        self.unixTime = unixTime
        self.rtcTemperature = rtcTemperature
        self.alarmFlags = alarmFlags
    }

    func readUnixTime() async throws -> UInt32 { unixTime }
    func writeUnixTime(_ seconds: UInt32) async throws { unixTime = seconds }
    func readRTCTemperature() async throws -> Int16 { rtcTemperature }
    func readAlarmFlags() async throws -> UInt8 { alarmFlags }
    func setTemperatureNotifying(_: Bool) async throws {}
    func rtcTemperatureNotifications() -> AsyncStream<Int16> { .init { $0.yield(rtcTemperature); $0.finish() } }
}
