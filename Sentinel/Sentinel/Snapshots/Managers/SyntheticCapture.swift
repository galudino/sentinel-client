//
//  SyntheticCapture.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

#if DEBUG
    import Foundation

    // MARK: - Synthetic DeviceSnapshot series

    extension DeviceSnapshot {
        /// A realistic run of `count` frames spaced `intervalSeconds` apart, ending
        /// ~now — smooth sinusoidal trends plus light noise so decimation has real
        /// peaks/troughs to preserve. DEBUG-only, for exercising the chart + disk
        /// paging without a live hour-long capture.
        static func syntheticSeries(count: Int, intervalSeconds: Double) -> [DeviceSnapshot] {
            let baseUnix = UInt32(Date().timeIntervalSince1970) - UInt32(Double(count) * intervalSeconds)
            let firmware = FirmwareVersion(major: 1, minor: 0, patch: 1, build: 17)

            return (0 ..< count).map { index in
                let phase = Double(index)
                let tempC = 21.5 + 2.5 * sin(phase * 0.01) + Double.random(in: -0.15 ... 0.15)
                let humidityPct = 45.0 + 6.0 * sin(phase * 0.004) + Double.random(in: -0.3 ... 0.3)
                let pressurePa = 101_325.0 + 60.0 * sin(phase * 0.02) + Double.random(in: -10 ... 10)
                let rtcTempC = 24.8 + 0.6 * sin(phase * 0.008)
                let cpuTempC = 42.0 + 3.0 * sin(phase * 0.03) + Double.random(in: -0.5 ... 0.5)
                let rssiNeg = UInt8(min(90, max(45, 58.0 + 10.0 * sin(phase * 0.02) + Double.random(in: -3 ... 3))))

                return DeviceSnapshot(
                    unixTimestamp: baseUnix + UInt32(Double(index) * intervalSeconds),
                    snapshotVersion: 1,
                    firmwareVersion: firmware,
                    temperatureCentiDegC: Int16(tempC * 100),
                    humidityCentiPct: UInt16(max(0, humidityPct * 100)),
                    pressurePa: UInt32(pressurePa),
                    rtcTemperatureCentiDegC: Int16(rtcTempC * 100),
                    rtcAlarmFlags: index % 900 == 0 ? 0x01 : 0x00, // occasional A1F blip
                    eventLogRecordCount: UInt32(index / 120),
                    snapshotLogRecordCount: UInt32(index),
                    bleConnected: true,
                    bleTxPowerDbm: 4,
                    blePeerRssiNeg: rssiNeg,
                    cpuTemperatureCentiDegC: UInt16(max(0, cpuTempC * 100)),
                    postLastStatus: 0,
                    uptimeSeconds: UInt32(Double(index) * intervalSeconds)
                )
            }
        }
    }

    // MARK: - Synthetic entries (via the real extraction path)

    extension DeviceSnapshotDataProvider {
        /// Build `count` log entries from a synthetic snapshot series using the real
        /// ``extractValue(from:keyPath:)`` path, so the values and schema match a
        /// genuine capture. Notification-mode timing (receipt + inter-notification
        /// interval) with historical timestamps.
        func syntheticEntries(count: Int, intervalSeconds: Double) -> [SnapshotLogEntry] {
            let fields = DeviceSnapshot.availableFields()
            let series = DeviceSnapshot.syntheticSeries(count: count, intervalSeconds: intervalSeconds)
            let start = Date().addingTimeInterval(-Double(count) * intervalSeconds)
            var previousReceipt: Date?

            return series.enumerated().map { index, snapshot in
                let receipt = start.addingTimeInterval(Double(index) * intervalSeconds)
                let interval = previousReceipt.map { receipt.timeIntervalSince($0) }
                previousReceipt = receipt
                return SnapshotLogEntry(
                    id: UUID(),
                    timestamp: receipt,
                    fieldValues: extractFieldValues(from: snapshot, for: fields),
                    deviceUnixTimeMs: snapshot.unixTimeMs,
                    actualStart: receipt,
                    interNotificationInterval: interval
                )
            }
        }
    }

    // MARK: - Install a synthetic completed session

    /// Everything needed to persist one synthetic completed session, grouped so it
    /// crosses into the detached writer as a single `Sendable` value.
    private nonisolated struct SyntheticSessionSpec {
        let name: String
        let sessionId = UUID()
        let configurationId = UUID()
        let start: Date
        let end: Date
        let pollingInterval: TimeInterval
        let captureMode: SnapshotCaptureMode
        let snapshotType: String
        let serialNumber: UInt32 = 0x5EED_C0DE
        let firmwareVersion = "synthetic"
        let timingIds: Set<String>
        let fieldSchema: [BinaryFieldSchema]

        var duration: TimeInterval { end.timeIntervalSince(start) }
        var snapshotTypeTag: UInt8 { snapshotType == "deviceSnapshot" ? 0 : 1 }
    }

    extension SnapshotLoggingManager {
        /// Persist `entries` as a completed session (binary file + index) exactly as
        /// a real capture would, then reload the completed list. The heavy write runs
        /// off the main actor. DEBUG-only.
        func installSyntheticSession(
            name: String,
            pollingInterval: TimeInterval,
            captureMode: SnapshotCaptureMode,
            entries: [SnapshotLogEntry]
        ) async {
            let spec = SyntheticSessionSpec(
                name: name,
                start: entries.first?.timestamp ?? Date(),
                end: entries.last?.timestamp ?? Date(),
                pollingInterval: pollingInterval,
                captureMode: captureMode,
                snapshotType: provider.snapshotTypeIdentifier,
                timingIds: SnapshotTimingFieldConfig.defaultEnabledFieldIds(for: captureMode),
                fieldSchema: (entries.first?.fieldValues ?? []).map {
                    BinaryFieldSchema(
                        keyPath: $0.keyPath, displayName: $0.displayName, unit: $0.unit, dataType: $0.dataType
                    )
                }
            )
            await Task.detached(priority: .userInitiated) {
                do {
                    try SyntheticSessionWriter.write(spec, entries: entries)
                } catch {
                    assertionFailure("Synthetic session write failed: \(error)")
                }
            }.value
            loadCompletedSessions()
        }
    }

    /// File-based persistence for one synthetic session. Deliberately kept off the
    /// generic `SnapshotLoggingManager<Provider>`: the detached writer must not
    /// capture `Self` (i.e. `Provider.Type`), which is non-Sendable because
    /// `SnapshotDataProvider` isn't `Sendable`. These helpers need only the
    /// `Sendable` `SyntheticSessionSpec` + entries, so they live in a non-generic
    /// namespace that's safe to reference from the detached task.
    private enum SyntheticSessionWriter {
        nonisolated static func write(_ spec: SyntheticSessionSpec, entries: [SnapshotLogEntry]) throws {
            let fileManager = SessionFileManager.shared
            try fileManager.createSessionFile(header: header(for: spec))
            let handle = try fileManager.openForAppending(sessionId: spec.sessionId)
            for entry in entries {
                handle.write(SessionBinaryFormat.encodeEntry(entry, captureMode: spec.captureMode))
            }
            try handle.close()
            try fileManager.writeFooter(
                SessionFileFooter(
                    endTime: spec.end, duration: spec.duration, status: .completed, entryCount: UInt32(entries.count)
                ),
                to: spec.sessionId
            )
            var aggregates = SessionRunningAggregates()
            for entry in entries {
                aggregates.update(with: entry, pollingInterval: spec.pollingInterval)
            }
            fileManager.addToIndex(indexEntry(for: spec, entryCount: entries.count, aggregates: aggregates))
        }

        private nonisolated static func header(for spec: SyntheticSessionSpec) -> SessionFileHeader {
            SessionFileHeader(
                formatVersion: SessionBinaryFormat.currentVersion,
                snapshotType: spec.snapshotTypeTag,
                captureMode: spec.captureMode,
                sessionId: spec.sessionId,
                configurationId: spec.configurationId,
                sessionName: spec.name,
                startTime: spec.start,
                pollingInterval: spec.pollingInterval,
                maxDuration: nil,
                stopOnDisconnect: true,
                serialNumber: spec.serialNumber,
                firmwareVersion: spec.firmwareVersion,
                selectedTimingFieldIds: spec.timingIds,
                fieldSchema: spec.fieldSchema,
                autoSaveInterval: nil
            )
        }

        private nonisolated static func indexEntry(
            for spec: SyntheticSessionSpec,
            entryCount: Int,
            aggregates: SessionRunningAggregates
        ) -> SessionIndexEntry {
            SessionIndexEntry(
                id: spec.sessionId,
                name: spec.name,
                snapshotType: spec.snapshotType,
                captureMode: spec.captureMode,
                startTime: spec.start,
                endTime: spec.end,
                duration: spec.duration,
                entryCount: entryCount,
                status: .completed,
                pollingInterval: spec.pollingInterval,
                maxDuration: nil,
                stopOnDisconnect: true,
                serialNumber: spec.serialNumber,
                firmwareVersion: spec.firmwareVersion,
                configurationId: spec.configurationId,
                selectedTimingFieldIds: spec.timingIds,
                fileName: SessionFileManager.fileName(for: spec.sessionId),
                aggregates: aggregates,
                autoSaveInterval: nil
            )
        }
    }
#endif
