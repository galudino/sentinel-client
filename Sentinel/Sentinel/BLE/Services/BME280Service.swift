//
//  BME280Service.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The BME280 environmental sensor: temperature, humidity, pressure — one-shot
/// reads plus live notifications. Chip-named to mirror the firmware GATT contract
/// 1:1 (not a generic `SensorService`).
///
/// Scaling matches the firmware fixed-point wire format: temperature in
/// 0.01 °C/LSB (`Int16`), humidity in 0.01 %/LSB (`UInt16`), pressure in Pa
/// (`UInt32`).
protocol BME280Service {
    func readTemperature() async throws -> Int16
    func readHumidity() async throws -> UInt16
    func readPressure() async throws -> UInt32

    /// Enable/disable notifications for all three characteristics.
    func setNotifying(_ enabled: Bool) async throws

    func temperatureNotifications() -> AsyncStream<Int16>
    func humidityNotifications() -> AsyncStream<UInt16>
    func pressureNotifications() -> AsyncStream<UInt32>
}

struct BME280ServiceClient<Transport: BluetoothPeripheralTransport>: BME280Service {
    let transport: Transport

    private var service: CBUUID { BME280ServiceUUID.bme280.cbuuid }

    func readTemperature() async throws -> Int16 {
        try await transport.read(characteristic: BME280CharacteristicUUID.temperature.cbuuid, ofService: service) ?? 0
    }

    func readHumidity() async throws -> UInt16 {
        try await transport.read(characteristic: BME280CharacteristicUUID.humidity.cbuuid, ofService: service) ?? 0
    }

    func readPressure() async throws -> UInt32 {
        try await transport.read(characteristic: BME280CharacteristicUUID.pressure.cbuuid, ofService: service) ?? 0
    }

    func setNotifying(_ enabled: Bool) async throws {
        try await transport.setNotify(
            enabled,
            characteristic: BME280CharacteristicUUID.temperature.cbuuid,
            ofService: service
        )
        try await transport.setNotify(
            enabled,
            characteristic: BME280CharacteristicUUID.humidity.cbuuid,
            ofService: service
        )
        try await transport.setNotify(
            enabled,
            characteristic: BME280CharacteristicUUID.pressure.cbuuid,
            ofService: service
        )
    }

    func temperatureNotifications() -> AsyncStream<Int16> {
        transport.notifications(for: BME280CharacteristicUUID.temperature.cbuuid, ofService: service)
    }

    func humidityNotifications() -> AsyncStream<UInt16> {
        transport.notifications(for: BME280CharacteristicUUID.humidity.cbuuid, ofService: service)
    }

    func pressureNotifications() -> AsyncStream<UInt32> {
        transport.notifications(for: BME280CharacteristicUUID.pressure.cbuuid, ofService: service)
    }
}

struct MockBME280Service: BME280Service {
    var temperature: Int16 = 2200 // 22.00 °C
    var humidity: UInt16 = 4500 // 45.00 %
    var pressure: UInt32 = 101_325 // Pa

    func readTemperature() async throws -> Int16 { temperature }
    func readHumidity() async throws -> UInt16 { humidity }
    func readPressure() async throws -> UInt32 { pressure }
    func setNotifying(_: Bool) async throws {}
    func temperatureNotifications() -> AsyncStream<Int16> { .init { $0.yield(temperature); $0.finish() } }
    func humidityNotifications() -> AsyncStream<UInt16> { .init { $0.yield(humidity); $0.finish() } }
    func pressureNotifications() -> AsyncStream<UInt32> { .init { $0.yield(pressure); $0.finish() } }
}
