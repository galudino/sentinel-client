//
//  SnapshotTimingFieldConfig.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - SnapshotTimingFieldCategory

/// Groups the diagnostic timing fields that describe the *capture process*
/// (as opposed to device data) into raw timestamps vs. derived metrics.
nonisolated enum SnapshotTimingFieldCategory: String, CaseIterable, Identifiable, Codable {
    case timestamps = "Timestamps"
    case derivedMetrics = "Derived Metrics"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var description: String {
        switch self {
        case .timestamps: "Raw timestamp values captured during logging"
        case .derivedMetrics: "Calculated timing metrics derived from timestamps"
        }
    }
}

// MARK: - SnapshotTimingFieldConfig

/// Describes one optional timing/diagnostic column a session can carry into its
/// export. These capture how the *client* scheduled and received each sample —
/// latency, read duration, cadence — independent of the device data itself.
nonisolated struct SnapshotTimingFieldConfig: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let shortName: String
    let description: String
    let calculation: String
    let unit: String
    let category: SnapshotTimingFieldCategory
    let applicableModes: Set<SnapshotCaptureMode>
    let defaultEnabled: Bool

    var isTimestamp: Bool { category == .timestamps }

    func appliesTo(mode: SnapshotCaptureMode) -> Bool { applicableModes.contains(mode) }
}

// MARK: - SnapshotTimingFieldConfig Static Definitions

nonisolated extension SnapshotTimingFieldConfig {
    // MARK: Timestamps

    static let deviceTimestamp = SnapshotTimingFieldConfig(
        id: "deviceTimestamp",
        displayName: "Device Timestamp",
        shortName: "Device Timestamp",
        description: "The device's own clock time when it captured the snapshot.",
        calculation: "Directly from the snapshot's unixTimeMs field",
        unit: "",
        category: .timestamps,
        applicableModes: [.polling, .notifications],
        defaultEnabled: true
    )

    static let scheduledStartCycle = SnapshotTimingFieldConfig(
        id: "scheduledStartCycle",
        displayName: "Scheduled Start Cycle Timestamp",
        shortName: "Scheduled Start",
        description: "Client-side time the next read was scheduled to begin (current time + polling interval).",
        calculation: "Client-side: beginning of polling iteration",
        unit: "",
        category: .timestamps,
        applicableModes: [.polling],
        defaultEnabled: true
    )

    static let actualStartRead = SnapshotTimingFieldConfig(
        id: "actualStartRead",
        displayName: "Actual Start Read Timestamp",
        shortName: "Actual Start",
        description: "Client-side time the BLE read actually began.",
        calculation: "Client-side: just before readSnapshot() is called",
        unit: "",
        category: .timestamps,
        applicableModes: [.polling],
        defaultEnabled: true
    )

    static let actualFinishRead = SnapshotTimingFieldConfig(
        id: "actualFinishRead",
        displayName: "Actual Finish Read Timestamp",
        shortName: "Actual Finish",
        description: "Client-side time the BLE read ended.",
        calculation: "Client-side: just after readSnapshot() returns",
        unit: "",
        category: .timestamps,
        applicableModes: [.polling],
        defaultEnabled: false
    )

    static let finishCycle = SnapshotTimingFieldConfig(
        id: "finishCycle",
        displayName: "Finish Cycle Timestamp",
        shortName: "Finish Cycle",
        description: "Client-side time after the post-read sleep completes.",
        calculation: "Client-side: after sleep completes",
        unit: "",
        category: .timestamps,
        applicableModes: [.polling],
        defaultEnabled: false
    )

    static let notificationReceived = SnapshotTimingFieldConfig(
        id: "notificationReceived",
        displayName: "Notification Received Timestamp",
        shortName: "Notification Received",
        description: "Client-side time the BLE notification was received from the device.",
        calculation: "Client-side: notification handler execution time",
        unit: "",
        category: .timestamps,
        applicableModes: [.notifications],
        defaultEnabled: true
    )

    // MARK: Derived metrics

    static let deviceTimestampPeriod = SnapshotTimingFieldConfig(
        id: "deviceTimestampPeriod",
        displayName: "Device Timestamp Period",
        shortName: "Device Period",
        description: "Time between consecutive device timestamps — the device's actual update rate.",
        calculation: "Device Timestamp − Previous Device Timestamp",
        unit: "ms",
        category: .derivedMetrics,
        applicableModes: [.polling, .notifications],
        defaultEnabled: true
    )

    static let deviceToReadLatency = SnapshotTimingFieldConfig(
        id: "deviceToReadLatency",
        displayName: "Device-to-Read Latency",
        shortName: "Device-to-Read Latency",
        description: "End-to-end latency from device capture to when the client started reading it.",
        calculation: "Actual Start Read Timestamp − Device Timestamp",
        unit: "ms",
        category: .derivedMetrics,
        applicableModes: [.polling],
        defaultEnabled: true
    )

    static let scheduleToReadLatency = SnapshotTimingFieldConfig(
        id: "scheduleToReadLatency",
        displayName: "Schedule-to-Read Latency",
        shortName: "Schedule-to-Read Latency",
        description: "Client-side scheduling overhead: time from scheduled to actual read start.",
        calculation: "Actual Start Read Timestamp − Scheduled Start Cycle Timestamp",
        unit: "ms",
        category: .derivedMetrics,
        applicableModes: [.polling],
        defaultEnabled: true
    )

    static let bleReadDuration = SnapshotTimingFieldConfig(
        id: "bleReadDuration",
        displayName: "BLE Read Duration",
        shortName: "BLE Read Duration",
        description: "How long the BLE read took. If this exceeds the polling interval, capture can't keep up.",
        calculation: "Actual Finish Read Timestamp − Actual Start Read Timestamp",
        unit: "ms",
        category: .derivedMetrics,
        applicableModes: [.polling],
        defaultEnabled: true
    )

    static let cycleDuration = SnapshotTimingFieldConfig(
        id: "cycleDuration",
        displayName: "Cycle Duration",
        shortName: "Cycle Duration",
        description: "Total time for one polling cycle including the intentional sleep — should track the interval.",
        calculation: "Finish Cycle Timestamp − Scheduled Start Cycle Timestamp",
        unit: "ms",
        category: .derivedMetrics,
        applicableModes: [.polling],
        defaultEnabled: false
    )

    static let notificationLatency = SnapshotTimingFieldConfig(
        id: "notificationLatency",
        displayName: "Notification Latency",
        shortName: "Notification Latency",
        description: "⚠️ Requires synchronized clocks. Device capture to client notification receipt.",
        calculation: "Notification Received Timestamp − Device Timestamp",
        unit: "ms",
        category: .derivedMetrics,
        applicableModes: [.notifications],
        defaultEnabled: false
    )

    static let notificationPeriod = SnapshotTimingFieldConfig(
        id: "notificationPeriod",
        displayName: "Notification Period",
        shortName: "Notification Period",
        description: "Time between consecutive notifications received — client-perceived cadence and gaps.",
        calculation: "Notification Received − Previous Notification Received",
        unit: "ms",
        category: .derivedMetrics,
        applicableModes: [.notifications],
        defaultEnabled: true
    )

    // MARK: Collections

    static var allFields: [SnapshotTimingFieldConfig] {
        [
            deviceTimestamp, scheduledStartCycle, actualStartRead, actualFinishRead, finishCycle,
            notificationReceived,
            deviceTimestampPeriod, deviceToReadLatency, scheduleToReadLatency, bleReadDuration,
            cycleDuration, notificationLatency, notificationPeriod
        ]
    }

    static var pollingFields: [SnapshotTimingFieldConfig] { allFields.filter { $0.appliesTo(mode: .polling) } }

    static var notificationFields: [SnapshotTimingFieldConfig] {
        allFields.filter { $0.appliesTo(mode: .notifications) }
    }

    static func fields(for mode: SnapshotCaptureMode) -> [SnapshotTimingFieldConfig] {
        allFields.filter { $0.appliesTo(mode: mode) }
    }

    static func fieldsByCategory(
        for mode: SnapshotCaptureMode
    ) -> [SnapshotTimingFieldCategory: [SnapshotTimingFieldConfig]] {
        Dictionary(grouping: fields(for: mode), by: \.category)
    }

    static func defaultEnabledFieldIds(for mode: SnapshotCaptureMode) -> Set<String> {
        Set(fields(for: mode).filter(\.defaultEnabled).map(\.id))
    }
}
