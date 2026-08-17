//
//  BME280Service.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The BME280 environmental sensor. Per the firmware GATT contract (#9) the
/// driver's combined read is exposed as **one** packed ``BME280Sample``
/// characteristic (the one-shot-sample rule) — a single read/notify yields
/// temperature, humidity, and pressure together. Chip-named to mirror firmware.
protocol BME280Service {
    /// One-shot read of the current ambient sample.
    func readAmbientSample() async throws -> BME280Sample
    /// Enable/disable ambient-sample notifications.
    func setNotifying(_ enabled: Bool) async throws
    /// Live ambient samples as the device emits them.
    func ambientSampleNotifications() -> AsyncStream<BME280Sample>
}

struct BME280ServiceClient<Transport: BluetoothPeripheralTransport>: BME280Service {
    let transport: Transport

    private var service: CBUUID { SentinelServiceUUID.bme280.cbuuid }
    private var sample: CBUUID { BME280CharacteristicUUID.ambientSample.cbuuid }

    func readAmbientSample() async throws -> BME280Sample {
        try await transport.read(characteristic: sample, ofService: service)
            ?? BME280Sample(temperatureCentiDegC: 0, humidityCentiPct: 0, pressurePa: 0)
    }

    func setNotifying(_ enabled: Bool) async throws {
        try await transport.setNotify(enabled, characteristic: sample, ofService: service)
    }

    func ambientSampleNotifications() -> AsyncStream<BME280Sample> {
        transport.notifications(for: sample, ofService: service)
    }
}

struct MockBME280Service: BME280Service {
    var sample = BME280Sample(temperatureCentiDegC: 2200, humidityCentiPct: 4500, pressurePa: 101_325)

    func readAmbientSample() async throws -> BME280Sample { sample }
    func setNotifying(_: Bool) async throws {}
    func ambientSampleNotifications() -> AsyncStream<BME280Sample> {
        .init { $0.yield(sample); $0.finish() }
    }
}
