//
//  DeviceSnapshot+Preview.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/20/26.
//

#if DEBUG
    import Foundation

    extension DeviceSnapshot {
        /// Build a 24 h ramp of snapshots for previews/mocks: `count` frames ending
        /// at `endingAt`, temperature swinging on a diurnal-ish curve. Shared by
        /// HomeView's leaf previews and ``ConnectedPeer/preview(name:rssi:mtu:)``.
        nonisolated static func previewSeries(
            count: Int = 24,
            endingAt end: UInt32 = 1_760_000_000
        ) -> [DeviceSnapshot] {
            (0 ..< count).map { index in
                let time = end - UInt32((count - 1 - index) * 3600)
                let phase = Double(index) / Double(max(count - 1, 1)) * 2 * .pi
                let tempC = 21.5 + 2.5 * sin(phase) // ~19–24 °C
                return DeviceSnapshot(
                    unixTimestamp: time,
                    snapshotVersion: 1,
                    firmwareVersion: FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16),
                    temperatureCentiDegC: Int16(tempC * 100),
                    humidityCentiPct: UInt16(4500 + index * 10),
                    pressurePa: 101_325,
                    rtcTemperatureCentiDegC: Int16(2450 + index * 4), // ~24.5–25.4 °C ramp
                    rtcAlarmFlags: 0,
                    eventLogRecordCount: 12,
                    snapshotLogRecordCount: UInt32(index),
                    bleConnected: true,
                    bleTxPowerDbm: 4,
                    blePeerRssiNeg: 58,
                    cpuTemperatureCentiDegC: 4200,
                    postLastStatus: 0,
                    uptimeSeconds: 3600
                )
            }
        }

        /// A single representative preview frame (avoids the main-actor `sample`).
        nonisolated static var previewFrame: DeviceSnapshot { previewSeries(count: 1)[0] }

        /// The `previewSeries` encoded as one contiguous record block (each frame is
        /// 80 wire bytes), for seeding a paged-store mock transport.
        nonisolated static func previewHistoryBlock(count: Int = 24) -> Data {
            previewSeries(count: count).reduce(into: Data()) { $0.append(encode($1)) }
        }
    }
#endif
