//
//  SystemServiceClientTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation
import Testing

@testable import Sentinel

/// Testing strategy #1: mock the transport, exercise the *real* client. Catches
/// byte-format bugs in the reference `SystemService` trio (#8 acceptance).
@MainActor
struct SystemServiceClientTests {
    @Test func readsFirmwareVersionAndUptimeFromCannedBytes() async throws {
        let transport = MockBluetoothTransport()
        transport.setReadValue("1.4.2", for: SystemCharacteristicUUID.firmwareVersion.cbuuid)
        transport.setReadValue(UInt32(7200), for: SystemCharacteristicUUID.uptimeSeconds.cbuuid)

        let system = SystemServiceClient(transport: transport)

        #expect(try await system.readFirmwareVersion() == "1.4.2")
        #expect(try await system.readUptimeSeconds() == 7200)
    }

    @Test func missingValueDecodesToDefault() async throws {
        // No canned bytes seeded → transport returns nil → client yields its
        // default rather than throwing.
        let system = SystemServiceClient(transport: MockBluetoothTransport())
        #expect(try await system.readFirmwareVersion() == "")
        #expect(try await system.readUptimeSeconds() == 0)
    }

    @Test func mockServiceStandsInForPreviews() async throws {
        let mock = MockSystemService(firmwareVersion: "9.9.9", uptimeSeconds: 42)
        #expect(try await mock.readFirmwareVersion() == "9.9.9")
        #expect(try await mock.readUptimeSeconds() == 42)
    }
}
