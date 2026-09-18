//
//  SnapshotLoggingSession.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - SnapshotLoggingSession

/// One capture run of a configuration: lifecycle, timing bounds, pre-cached
/// device metadata, and (while active) the RAM window of ``SnapshotLogEntry``.
///
/// For completed sessions the entries live on disk in the `.sentinelsession`
/// binary file and `logEntries` is empty until loaded on demand — the
/// ``init(from:)`` from a ``SessionIndexEntry`` builds this lightweight shell for
/// the list.
nonisolated struct SnapshotLoggingSession: Codable, Identifiable, Hashable {
    let id: UUID
    let configurationId: UUID
    var name: String
    var startTime: Date
    var endTime: Date?
    var status: SnapshotLoggingStatus
    var logEntries: [SnapshotLogEntry]
    var duration: TimeInterval?
    /// `nil` means indefinite.
    var maxDuration: TimeInterval?
    var stopOnDisconnect: Bool
    var pollingInterval: TimeInterval
    var captureMode: SnapshotCaptureMode
    var selectedTimingFieldIds: Set<String>

    /// Metadata pre-cached before the session starts.
    var serialNumber: UInt32
    var firmwareVersion: String

    /// Auto-save interval in seconds (`nil` = disabled). Valid range 60...1800.
    var autoSaveInterval: TimeInterval?

    /// Total entries captured — may exceed `logEntries.count` when older entries
    /// have been flushed to disk only.
    var entryCount: Int

    private enum CodingKeys: String, CodingKey {
        case id, configurationId, name, startTime, endTime, status, logEntries
        case duration, maxDuration, stopOnDisconnect, pollingInterval
        case captureMode, selectedTimingFieldIds, serialNumber, firmwareVersion
        case autoSaveInterval, entryCount
    }

    /// Custom decoder that tolerates older archives missing the newer fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        configurationId = try container.decode(UUID.self, forKey: .configurationId)
        name = try container.decode(String.self, forKey: .name)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        status = try container.decode(SnapshotLoggingStatus.self, forKey: .status)
        logEntries = try container.decode([SnapshotLogEntry].self, forKey: .logEntries)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        maxDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .maxDuration)
        stopOnDisconnect = try container.decode(Bool.self, forKey: .stopOnDisconnect)
        pollingInterval = try container.decode(TimeInterval.self, forKey: .pollingInterval)
        captureMode = try container.decodeIfPresent(SnapshotCaptureMode.self, forKey: .captureMode) ?? .polling
        selectedTimingFieldIds = try container.decodeIfPresent(Set<String>.self, forKey: .selectedTimingFieldIds)
            ?? SnapshotTimingFieldConfig.defaultEnabledFieldIds(for: captureMode)
        serialNumber = try container.decode(UInt32.self, forKey: .serialNumber)
        firmwareVersion = try container.decode(String.self, forKey: .firmwareVersion)
        autoSaveInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .autoSaveInterval)
        entryCount = try container.decodeIfPresent(Int.self, forKey: .entryCount) ?? logEntries.count
    }

    /// Create a new session.
    init(
        configurationId: UUID,
        name: String,
        pollingInterval: TimeInterval,
        captureMode: SnapshotCaptureMode = .polling,
        selectedTimingFieldIds: Set<String>? = nil,
        maxDuration: TimeInterval? = nil,
        stopOnDisconnect: Bool = true,
        serialNumber: UInt32 = 0,
        firmwareVersion: String = "",
        autoSaveInterval: TimeInterval? = nil
    ) {
        id = UUID()
        self.configurationId = configurationId
        self.name = name
        startTime = Date()
        endTime = nil
        status = .pending
        logEntries = []
        duration = nil
        self.maxDuration = maxDuration
        self.stopOnDisconnect = stopOnDisconnect
        self.pollingInterval = pollingInterval
        self.captureMode = captureMode
        self.selectedTimingFieldIds = selectedTimingFieldIds
            ?? SnapshotTimingFieldConfig.defaultEnabledFieldIds(for: captureMode)
        self.serialNumber = serialNumber
        self.firmwareVersion = firmwareVersion
        self.autoSaveInterval = autoSaveInterval
        entryCount = 0
    }

    /// Full initializer for reconstructing from JSON or the session index.
    init(
        id: UUID,
        configurationId: UUID,
        name: String,
        startTime: Date,
        endTime: Date?,
        status: SnapshotLoggingStatus,
        logEntries: [SnapshotLogEntry],
        duration: TimeInterval?,
        maxDuration: TimeInterval?,
        stopOnDisconnect: Bool,
        pollingInterval: TimeInterval,
        captureMode: SnapshotCaptureMode = .polling,
        selectedTimingFieldIds: Set<String>? = nil,
        serialNumber: UInt32,
        firmwareVersion: String,
        autoSaveInterval: TimeInterval? = nil,
        entryCount: Int? = nil
    ) {
        self.id = id
        self.configurationId = configurationId
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.logEntries = logEntries
        self.duration = duration
        self.maxDuration = maxDuration
        self.stopOnDisconnect = stopOnDisconnect
        self.pollingInterval = pollingInterval
        self.captureMode = captureMode
        self.selectedTimingFieldIds = selectedTimingFieldIds
            ?? SnapshotTimingFieldConfig.defaultEnabledFieldIds(for: captureMode)
        self.serialNumber = serialNumber
        self.firmwareVersion = firmwareVersion
        self.autoSaveInterval = autoSaveInterval
        self.entryCount = entryCount ?? logEntries.count
    }

    /// Lightweight shell from a ``SessionIndexEntry`` — no entries loaded (they
    /// live on disk). Used to populate the completed-sessions list.
    init(from indexEntry: SessionIndexEntry) {
        id = indexEntry.id
        configurationId = indexEntry.configurationId
        name = indexEntry.name
        startTime = indexEntry.startTime
        endTime = indexEntry.endTime
        status = indexEntry.status
        logEntries = []
        duration = indexEntry.duration
        maxDuration = indexEntry.maxDuration
        stopOnDisconnect = indexEntry.stopOnDisconnect
        pollingInterval = indexEntry.pollingInterval
        captureMode = indexEntry.captureMode
        selectedTimingFieldIds = indexEntry.selectedTimingFieldIds
        serialNumber = indexEntry.serialNumber
        firmwareVersion = indexEntry.firmwareVersion
        autoSaveInterval = indexEntry.autoSaveInterval
        entryCount = indexEntry.entryCount
    }

    var isActive: Bool { status == .running }
    var isCompleted: Bool { status == .completed || status == .stopped }

    var actualDuration: TimeInterval {
        if let endTime {
            endTime.timeIntervalSince(startTime)
        } else if status == .running {
            Date().timeIntervalSince(startTime)
        } else {
            duration ?? 0
        }
    }

    mutating func start() {
        status = .running
        startTime = Date()
    }

    mutating func stop() {
        guard status == .running else { return }
        endTime = Date()
        duration = actualDuration
        status = .stopped
    }

    mutating func complete() {
        guard status == .running else { return }
        endTime = Date()
        duration = actualDuration
        status = .completed
    }

    mutating func addLogEntry(_ entry: SnapshotLogEntry) {
        logEntries.append(entry)
        entryCount += 1
    }

    func shouldStop() -> Bool {
        guard status == .running else { return false }
        if let maxDuration { return actualDuration >= maxDuration }
        return false
    }
}
