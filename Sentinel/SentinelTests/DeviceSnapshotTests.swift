//
//  DeviceSnapshotTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation
import Testing

@testable import Sentinel

/// Byte-exact decode of the 80-byte `device_snapshot` wire record against the
/// firmware's locked field offsets (`sentinel_device_snapshot.hpp` static_asserts).
@MainActor
struct DeviceSnapshotTests {
    /// Build an 80-byte record with distinct little-endian values at each firmware
    /// offset, so a mis-placed field is caught.
    private func wire(trailer: UInt16 = DeviceSnapshot.trailerMagic) -> Data {
        var bytes = [UInt8](repeating: 0, count: 80)
        func put32(_ value: UInt32, _ offset: Int) {
            for index in 0 ..< 4 {
                bytes[offset + index] = UInt8((value >> (8 * index)) & 0xFF)
            }
        }
        func put16(_ value: UInt16, _ offset: Int) {
            bytes[offset] = UInt8(value & 0xFF); bytes[offset + 1] = UInt8(value >> 8)
        }
        put32(1_760_000_000, 0) // unix_timestamp
        bytes[4] = 1 // snapshot_version
        bytes[5] = 1; bytes[6] = 4; bytes[7] = 2 // fw major/minor/patch
        put16(1801, 8) // fw build
        put16(UInt16(bitPattern: -1234), 16) // temperature 0.01C = -12.34
        put16(4567, 18) // humidity 0.01% = 45.67
        put32(101_325, 20) // pressure Pa
        put16(UInt16(bitPattern: 2500), 24) // rtc temp 25.00 C
        bytes[26] = 0x81 // alarm flags: A1F | OSF
        put32(12, 32) // event log count
        put32(34, 36) // snapshot log count
        bytes[48] = 1 // ble connected
        bytes[49] = 4 // tx power dBm
        bytes[50] = 58 // -RSSI → -58 dBm
        put16(4200, 56) // cpu temp 42.00 C
        bytes[58] = 0 // post pass
        put32(3600, 60) // uptime
        put16(trailer, 78) // trailer magic
        return Data(bytes)
    }

    @Test func decodesEveryFieldAtItsFirmwareOffset() throws {
        let snapshot = try #require(DeviceSnapshot.decode(wire()))
        #expect(snapshot.unixTimestamp == 1_760_000_000)
        #expect(snapshot.snapshotVersion == 1)
        #expect(snapshot.firmwareVersion == FirmwareVersion(major: 1, minor: 4, patch: 2, build: 1801))
        #expect(snapshot.temperatureCentiDegC == -1234)
        #expect(snapshot.temperatureCelsius == -12.34)
        #expect(snapshot.humidityCentiPct == 4567)
        #expect(snapshot.pressurePa == 101_325)
        #expect(snapshot.rtcTemperatureCentiDegC == 2500)
        #expect(snapshot.rtcAlarmFlags == 0x81)
        #expect(snapshot.eventLogRecordCount == 12)
        #expect(snapshot.snapshotLogRecordCount == 34)
        #expect(snapshot.bleConnected)
        #expect(snapshot.bleTxPowerDbm == 4)
        #expect(snapshot.blePeerRssiDbm == -58)
        #expect(snapshot.cpuTemperatureCentiDegC == 4200)
        #expect(snapshot.postPassed)
        #expect(snapshot.uptimeSeconds == 3600)
    }

    @Test func rejectsWrongTrailerMagic() {
        #expect(DeviceSnapshot.decode(wire(trailer: 0x0000)) == nil)
    }

    @Test func rejectsShortBuffer() {
        #expect(DeviceSnapshot.decode(Data(repeating: 0, count: 79)) == nil)
    }

    @Test func peripheralDataConvertibleRoundTrips() {
        let data = DeviceSnapshot.sample.toData()
        #expect(data?.count == 80)
        #expect(DeviceSnapshot.fromData(data!) == .sample)
    }

    @Test func disconnectedPeerReportsZeroRSSI() throws {
        var bytes = [UInt8](wire())
        bytes[48] = 0 // not connected
        bytes[50] = 58 // stale -RSSI byte
        let snapshot = try #require(DeviceSnapshot.decode(Data(bytes)))
        #expect(snapshot.blePeerRssiDbm == 0)
    }

    @Test func historyServiceDecodesConcatenatedRecords() async throws {
        let transport = MockBluetoothTransport()
        let two = DeviceSnapshot.sample.toData()! + DeviceSnapshot.sample.toData()!
        transport.setReadValue(UInt32(2), for: SnapshotHistoryCharacteristicUUID.recordCount.cbuuid)
        transport.setReadData(two, for: SnapshotHistoryCharacteristicUUID.recordBlock.cbuuid)

        let history = SnapshotHistoryServiceClient(transport: transport)
        let snapshots = try await history.readAllSnapshots()
        #expect(snapshots.count == 2)
        #expect(snapshots.allSatisfy { $0 == .sample })
    }
}
