//
//  SnapshotLoggingManager+Export.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - Export

extension SnapshotLoggingManager {
    /// Export a *fully loaded* session (call ``loadSessionWithEntries(_:)`` first
    /// for JSON/CSV). Exports are always full-resolution.
    func exportSession(
        _ session: SnapshotLoggingSession,
        format: LoggingExportFormat,
        selectedFieldKeyPaths: Set<String>? = nil,
        selectedTimingFieldIds: Set<String>? = nil
    ) -> Data? {
        switch format {
        case .json:
            exportSessionAsJSON(
                session,
                selectedFieldKeyPaths: selectedFieldKeyPaths,
                selectedTimingFieldIds: selectedTimingFieldIds
            )
        case .csv:
            exportSessionAsCSV(
                session,
                selectedFieldKeyPaths: selectedFieldKeyPaths,
                selectedTimingFieldIds: selectedTimingFieldIds
            )
        case .binary:
            try? Data(contentsOf: sessionFileManager.sessionFileURL(for: session.id))
        }
    }

    // MARK: Timing helpers

    /// Device Timestamp Period (ms) for the entry at `index`.
    func calculateDeviceTimestampPeriodMs(entries: [SnapshotLogEntry], index: Int) -> Double? {
        guard index > 0,
              let current = entries[index].deviceUnixTimeMs,
              let previous = entries[index - 1].deviceUnixTimeMs else { return nil }
        return Double(Int64(bitPattern: current) - Int64(bitPattern: previous))
    }

    func shouldIncludeTimingField(_ fieldId: String, selectedTimingFieldIds: Set<String>?) -> Bool {
        guard let selected = selectedTimingFieldIds else { return true }
        return selected.contains(fieldId)
    }

    // MARK: JSON

    // swiftlint:disable:next function_body_length
    private func exportSessionAsJSON(
        _ session: SnapshotLoggingSession,
        selectedFieldKeyPaths: Set<String>?,
        selectedTimingFieldIds: Set<String>?
    ) -> Data? {
        let pollingIntervalMs = UInt32(session.pollingInterval * 1000)
        let isPollingMode = session.captureMode == .polling

        var fieldSchema: [[String: Any]] = []
        if let firstEntry = session.logEntries.first {
            let fields = filteredFieldValues(firstEntry.fieldValues, keyPaths: selectedFieldKeyPaths)
            fieldSchema = fields.map {
                [
                    "id": $0.id.uuidString,
                    "displayName": $0.displayName,
                    "keyPath": $0.keyPath,
                    "unit": $0.unit,
                    "dataType": $0.dataType.rawValue
                ]
            }
        }

        let entries: [[String: Any]] = session.logEntries.enumerated().map { index, entry in
            var entryDict: [String: Any] = [
                "id": entry.id.uuidString,
                "timestamp": formatDateWithMicroseconds(entry.timestamp),
                "timestampUnix": formatUnixTimestamp(entry.timestamp),
                "values": filteredFieldValues(entry.fieldValues, keyPaths: selectedFieldKeyPaths).map {
                    [$0.id.uuidString: provider.formatValueForExport($0.value, keyPath: $0.keyPath)]
                }
            ]

            if shouldIncludeTimingField("deviceTimestamp", selectedTimingFieldIds: selectedTimingFieldIds),
               let millis = entry.deviceUnixTimeMs
            {
                entryDict["deviceTimestamp"] =
                    formatDateWithMicroseconds(Date(timeIntervalSince1970: Double(millis) / 1000))
                entryDict["deviceTimestampUnixMs"] = millis
            }
            if shouldIncludeTimingField("deviceTimestampPeriod", selectedTimingFieldIds: selectedTimingFieldIds),
               let periodMs = calculateDeviceTimestampPeriodMs(entries: session.logEntries, index: index)
            {
                entryDict["deviceTimestampPeriodMs"] = periodMs
            }

            if isPollingMode {
                entryDict["timeSampleMs"] = UInt32(index) * pollingIntervalMs
                addPollingTimingJSON(&entryDict, entry: entry, selectedTimingFieldIds: selectedTimingFieldIds)
            } else {
                addNotificationTimingJSON(&entryDict, entry: entry, selectedTimingFieldIds: selectedTimingFieldIds)
            }
            return entryDict
        }

        var exportData: [String: Any] = [
            "snapshotType": provider.snapshotTypeIdentifier,
            "sessionId": session.id.uuidString,
            "sessionName": session.name,
            "configurationId": session.configurationId.uuidString,
            "startTime": formatDateWithMicroseconds(session.startTime),
            "endTime": session.endTime.map { formatDateWithMicroseconds($0) } as Any,
            "duration": session.actualDuration,
            "pollingInterval": session.pollingInterval,
            "serialNumber": session.serialNumber,
            "firmwareVersion": session.firmwareVersion,
            "status": session.status.rawValue,
            "entryCount": session.logEntries.count,
            "stopOnDisconnect": session.stopOnDisconnect,
            "fields": fieldSchema,
            "entries": entries
        ]
        if let maxDuration = session.maxDuration { exportData["maxDuration"] = maxDuration }

        return try? JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
    }

    private func addPollingTimingJSON(
        _ entryDict: inout [String: Any],
        entry: SnapshotLogEntry,
        selectedTimingFieldIds: Set<String>?
    ) {
        func include(_ id: String) -> Bool {
            shouldIncludeTimingField(id, selectedTimingFieldIds: selectedTimingFieldIds)
        }
        if include("scheduledStartCycle"), let value = entry.scheduledTick {
            entryDict["scheduledStartCycleTimestamp"] = formatDateWithMicroseconds(value)
            entryDict["scheduledStartCycleTimestampUnix"] = formatUnixTimestamp(value)
        }
        if include("actualStartRead"), let value = entry.actualStart {
            entryDict["actualStartReadTimestamp"] = formatDateWithMicroseconds(value)
            entryDict["actualStartReadTimestampUnix"] = formatUnixTimestamp(value)
        }
        if include("actualFinishRead"), let value = entry.actualFinishRead {
            entryDict["actualFinishReadTimestamp"] = formatDateWithMicroseconds(value)
            entryDict["actualFinishReadTimestampUnix"] = formatUnixTimestamp(value)
        }
        if include("finishCycle"), let value = entry.finishCycle {
            entryDict["finishCycleTimestamp"] = formatDateWithMicroseconds(value)
            entryDict["finishCycleTimestampUnix"] = formatUnixTimestamp(value)
        }
        if include("scheduleToReadLatency"), let value = entry.latencySeconds {
            entryDict["scheduleToReadLatencyMs"] = value * 1000
        }
        if include("deviceToReadLatency"), let value = entry.deviceToReadLatencySeconds {
            entryDict["deviceToReadLatencyMs"] = value * 1000
        }
        if include("bleReadDuration"), let value = entry.readDurationSeconds {
            entryDict["bleReadDurationMs"] = value * 1000
        }
        if include("cycleDuration"), let value = entry.cycleDurationSeconds {
            entryDict["cycleDurationMs"] = value * 1000
        }
    }

    private func addNotificationTimingJSON(
        _ entryDict: inout [String: Any],
        entry: SnapshotLogEntry,
        selectedTimingFieldIds: Set<String>?
    ) {
        func include(_ id: String) -> Bool {
            shouldIncludeTimingField(id, selectedTimingFieldIds: selectedTimingFieldIds)
        }
        if include("notificationReceived"), let value = entry.actualStart {
            entryDict["notificationReceivedTimestamp"] = formatDateWithMicroseconds(value)
            entryDict["notificationReceivedTimestampUnix"] = formatUnixTimestamp(value)
        }
        if include("notificationLatency"), let value = entry.notificationLatencySeconds {
            entryDict["notificationLatencyMs"] = value * 1000
        }
        if include("notificationPeriod"), let value = entry.interNotificationInterval {
            entryDict["notificationPeriodMs"] = value * 1000
        }
    }

    // MARK: CSV

    private func exportSessionAsCSV(
        _ session: SnapshotLoggingSession,
        selectedFieldKeyPaths: Set<String>?,
        selectedTimingFieldIds: Set<String>?
    ) -> Data? {
        let pollingIntervalMs = UInt32(session.pollingInterval * 1000)
        let isPollingMode = session.captureMode == .polling

        var headers = buildCSVHeaders(isPollingMode: isPollingMode, selectedTimingFieldIds: selectedTimingFieldIds)
        if let firstEntry = session.logEntries.first {
            for fieldValue in filteredFieldValues(firstEntry.fieldValues, keyPaths: selectedFieldKeyPaths) {
                let header = fieldValue.unit.isEmpty
                    ? fieldValue.displayName
                    : "\(fieldValue.displayName) (\(fieldValue.unit))"
                headers.append(escapeCSVField(header))
            }
        }

        var csvData = Data()
        csvData.reserveCapacity((session.logEntries.count + 1) * 500)
        csvData.append(Data((headers.joined(separator: ",") + "\n").utf8))

        for (index, entry) in session.logEntries.enumerated() {
            autoreleasepool {
                var row = isPollingMode
                    ? buildPollingCSVRow(
                        entry: entry, index: index, pollingIntervalMs: pollingIntervalMs,
                        session: session, selectedTimingFieldIds: selectedTimingFieldIds
                    )
                    : buildNotificationCSVRow(
                        entry: entry, index: index,
                        session: session, selectedTimingFieldIds: selectedTimingFieldIds
                    )
                for fieldValue in filteredFieldValues(entry.fieldValues, keyPaths: selectedFieldKeyPaths) {
                    let formatted = provider.formatValueForExport(fieldValue.value, keyPath: fieldValue.keyPath)
                    row.append(escapeCSVField("\(formatted)"))
                }
                csvData.append(Data((row.joined(separator: ",") + "\n").utf8))
            }
        }
        return csvData
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func buildCSVHeaders(isPollingMode: Bool, selectedTimingFieldIds: Set<String>?) -> [String] {
        func include(_ id: String) -> Bool {
            shouldIncludeTimingField(id, selectedTimingFieldIds: selectedTimingFieldIds)
        }
        var headers: [String] = []
        if isPollingMode {
            headers.append("Time Sample (ms)")
            if include("deviceTimestamp") { headers += ["Device Timestamp", "Device Timestamp (Unix ms)"] }
            if include("deviceTimestampPeriod") { headers.append("Device Timestamp Period (ms)") }
            if include("scheduledStartCycle") { headers += ["Scheduled Start Cycle", "Scheduled Start Cycle (Unix ms)"]
            }
            if include("actualStartRead") { headers += ["Actual Start Read", "Actual Start Read (Unix ms)"] }
            if include("actualFinishRead") { headers += ["Actual Finish Read", "Actual Finish Read (Unix ms)"] }
            if include("finishCycle") { headers += ["Finish Cycle", "Finish Cycle (Unix ms)"] }
            if include("scheduleToReadLatency") { headers.append("Schedule-to-Read Latency (ms)") }
            if include("deviceToReadLatency") { headers.append("Device-to-Read Latency (ms)") }
            if include("bleReadDuration") { headers.append("BLE Read Duration (ms)") }
            if include("cycleDuration") { headers.append("Cycle Duration (ms)") }
        } else {
            if include("deviceTimestamp") { headers += ["Device Timestamp", "Device Timestamp (Unix ms)"] }
            if include("deviceTimestampPeriod") { headers.append("Device Timestamp Period (ms)") }
            if include("notificationReceived") {
                headers += ["Notification Received", "Notification Received (Unix ms)"]
            }
            if include("notificationLatency") { headers.append("Notification Latency (ms)") }
            if include("notificationPeriod") { headers.append("Notification Period (ms)") }
        }
        headers += ["Serial Number", "Firmware Version"]
        return headers
    }

    // swiftlint:disable:next function_body_length
    private func buildPollingCSVRow(
        entry: SnapshotLogEntry,
        index: Int,
        pollingIntervalMs: UInt32,
        session: SnapshotLoggingSession,
        selectedTimingFieldIds: Set<String>?
    ) -> [String] {
        func include(_ id: String) -> Bool {
            shouldIncludeTimingField(id, selectedTimingFieldIds: selectedTimingFieldIds)
        }
        var row = ["\(UInt32(index) * pollingIntervalMs)"]
        if include("deviceTimestamp") { row += deviceTimestampColumns(entry) }
        if include("deviceTimestampPeriod") {
            row.append(
                calculateDeviceTimestampPeriodMs(entries: session.logEntries, index: index)
                    .map { String(format: "%.0f", $0) } ?? ""
            )
        }
        if include("scheduledStartCycle") { row += dateColumns(entry.scheduledTick) }
        if include("actualStartRead") { row += dateColumns(entry.actualStart) }
        if include("actualFinishRead") { row += dateColumns(entry.actualFinishRead) }
        if include("finishCycle") { row += dateColumns(entry.finishCycle) }
        if include("scheduleToReadLatency") { row.append(msString(entry.latencySeconds)) }
        if include("deviceToReadLatency") { row.append(msString(entry.deviceToReadLatencySeconds)) }
        if include("bleReadDuration") { row.append(msString(entry.readDurationSeconds)) }
        if include("cycleDuration") { row.append(msString(entry.cycleDurationSeconds)) }
        row += ["\(session.serialNumber)", escapeCSVField(session.firmwareVersion)]
        return row
    }

    private func buildNotificationCSVRow(
        entry: SnapshotLogEntry,
        index: Int,
        session: SnapshotLoggingSession,
        selectedTimingFieldIds: Set<String>?
    ) -> [String] {
        func include(_ id: String) -> Bool {
            shouldIncludeTimingField(id, selectedTimingFieldIds: selectedTimingFieldIds)
        }
        var row: [String] = []
        if include("deviceTimestamp") { row += deviceTimestampColumns(entry) }
        if include("deviceTimestampPeriod") {
            row.append(
                calculateDeviceTimestampPeriodMs(entries: session.logEntries, index: index)
                    .map { String(format: "%.0f", $0) } ?? ""
            )
        }
        if include("notificationReceived") { row += dateColumns(entry.actualStart) }
        if include("notificationLatency") { row.append(msString(entry.notificationLatencySeconds)) }
        if include("notificationPeriod") { row.append(msString(entry.interNotificationInterval)) }
        row += ["\(session.serialNumber)", escapeCSVField(session.firmwareVersion)]
        return row
    }

    // MARK: Formatting helpers

    private func filteredFieldValues(
        _ values: [SnapshotFieldValue],
        keyPaths: Set<String>?
    ) -> [SnapshotFieldValue] {
        guard let keyPaths else { return values }
        return values.filter { keyPaths.contains($0.keyPath) }
    }

    private func deviceTimestampColumns(_ entry: SnapshotLogEntry) -> [String] {
        guard let millis = entry.deviceUnixTimeMs else { return ["", ""] }
        return [formatDateWithMicroseconds(Date(timeIntervalSince1970: Double(millis) / 1000)), "\(millis)"]
    }

    private func dateColumns(_ date: Date?) -> [String] {
        [date.map { formatDateWithMicroseconds($0) } ?? "", date.map { formatUnixTimestamp($0) } ?? ""]
    }

    private func msString(_ seconds: Double?) -> String {
        seconds.map { String(format: "%.3f", $0 * 1000) } ?? ""
    }

    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }

    private func formatDateWithMicroseconds(_ date: Date) -> String {
        let components = Calendar.current.dateComponents(in: .current, from: date)
        let fractional = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%06d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0,
            components.hour ?? 0, components.minute ?? 0, components.second ?? 0,
            Int(fractional * 1_000_000)
        )
    }

    private func formatUnixTimestamp(_ date: Date) -> String {
        String(format: "%.3f", date.timeIntervalSince1970 * 1000)
    }
}
