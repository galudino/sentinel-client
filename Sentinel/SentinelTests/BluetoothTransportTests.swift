//
//  BluetoothTransportTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation
import Testing

@testable import Sentinel

/// Exercises the transport seam directly: packed-struct decode round-trips, write
/// recording, and the notification bridge — through the real `BME280ServiceClient`
/// (one-shot `BME280Sample` per the #9 contract) over a `MockBluetoothTransport`.
@MainActor
struct BluetoothTransportTests {
    /// A packed 8-byte BME280 sample: temp -12.34 °C, humidity 45.67 %, 101325 Pa.
    private var sampleWire: Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: Int16(-1234).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(4567).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(101_325).littleEndian) { Array($0) })
        return data
    }

    @Test func packedSampleDecodesByteExact() async throws {
        let transport = MockBluetoothTransport()
        transport.setReadData(sampleWire, for: BME280CharacteristicUUID.ambientSample.cbuuid)

        let bme = BME280ServiceClient(transport: transport)
        let sample = try await bme.readAmbientSample()
        #expect(sample == BME280Sample(temperatureCentiDegC: -1234, humidityCentiPct: 4567, pressurePa: 101_325))
        #expect(sample.temperatureCelsius == -12.34)
        #expect(sample.pressureHectopascals == 1013.25)
    }

    @Test func bme280SampleRoundTripsThroughTriviallyCopyable() {
        let original = BME280Sample(temperatureCentiDegC: 2345, humidityCentiPct: 5010, pressurePa: 99800)
        let data = original.toData()
        #expect(data?.count == 8)
        #expect(BME280Sample.fromData(data!) == original)
    }

    @Test func setNotifyingTogglesTheSampleCharacteristic() async throws {
        let transport = MockBluetoothTransport()
        let bme = BME280ServiceClient(transport: transport)

        try await bme.setNotifying(true)
        #expect(transport.isNotifying(BME280CharacteristicUUID.ambientSample.cbuuid))
        try await bme.setNotifying(false)
        #expect(!transport.isNotifying(BME280CharacteristicUUID.ambientSample.cbuuid))
    }

    @Test func notificationBridgeDeliversInjectedSamples() async throws {
        let transport = MockBluetoothTransport()
        let bme = BME280ServiceClient(transport: transport)

        let stream = bme.ambientSampleNotifications()
        var iterator = stream.makeAsyncIterator()

        let injected = BME280Sample(temperatureCentiDegC: 2100, humidityCentiPct: 4000, pressurePa: 100_000)
        transport.injectNotification(injected, for: BME280CharacteristicUUID.ambientSample.cbuuid)
        #expect(await iterator.next() == injected)
    }

    @Test func detachedPeerThrowsOnTransportUse() async {
        let peer = ConnectedPeer(id: UUID(), name: "Detached")
        await #expect(throws: ConnectedPeerError.detached) {
            let _: UInt32? = try await peer.read(
                characteristic: SystemCharacteristicUUID.serialNumber.cbuuid,
                ofService: SentinelServiceUUID.system.cbuuid
            )
        }
    }
}
