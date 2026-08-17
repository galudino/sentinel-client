//
//  BluetoothTransportTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation
import Testing

@testable import Sentinel

/// Exercises the transport seam directly: fixed-width decode/encode round-trips,
/// write recording, and the notification bridge — through the real
/// `BME280ServiceClient` over a `MockBluetoothTransport`.
@MainActor
struct BluetoothTransportTests {
    @Test func fixedWidthReadsDecodeAtExactWidth() async throws {
        let transport = MockBluetoothTransport()
        // 2-byte Int16 temperature, 2-byte UInt16 humidity, 4-byte UInt32 pressure.
        transport.setReadValue(Int16(-1234), for: BME280CharacteristicUUID.temperature.cbuuid)
        transport.setReadValue(UInt16(4567), for: BME280CharacteristicUUID.humidity.cbuuid)
        transport.setReadValue(UInt32(101_325), for: BME280CharacteristicUUID.pressure.cbuuid)

        let bme = BME280ServiceClient(transport: transport)
        #expect(try await bme.readTemperature() == -1234)
        #expect(try await bme.readHumidity() == 4567)
        #expect(try await bme.readPressure() == 101_325)
    }

    @Test func setNotifyingTogglesEachCharacteristic() async throws {
        let transport = MockBluetoothTransport()
        let bme = BME280ServiceClient(transport: transport)

        try await bme.setNotifying(true)
        #expect(transport.isNotifying(BME280CharacteristicUUID.temperature.cbuuid))
        #expect(transport.isNotifying(BME280CharacteristicUUID.humidity.cbuuid))
        #expect(transport.isNotifying(BME280CharacteristicUUID.pressure.cbuuid))

        try await bme.setNotifying(false)
        #expect(!transport.isNotifying(BME280CharacteristicUUID.pressure.cbuuid))
    }

    @Test func notificationBridgeDeliversInjectedValues() async throws {
        let transport = MockBluetoothTransport()
        let bme = BME280ServiceClient(transport: transport)

        let stream = bme.temperatureNotifications()
        var iterator = stream.makeAsyncIterator()

        transport.injectNotification(Int16(2100), for: BME280CharacteristicUUID.temperature.cbuuid)
        let first = await iterator.next()
        #expect(first == 2100)
    }

    @Test func detachedPeerThrowsOnTransportUse() async {
        let peer = ConnectedPeer(id: UUID(), name: "Detached")
        await #expect(throws: ConnectedPeerError.detached) {
            let _: UInt32? = try await peer.read(
                characteristic: SystemCharacteristicUUID.uptimeSeconds.cbuuid,
                ofService: SystemServiceUUID.system.cbuuid
            )
        }
    }
}
