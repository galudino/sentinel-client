//
//  SnapshotLoggingManager.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

// A cohesive, tightly-coupled capture engine: every section (capture tasks,
// autosave, deadlines, file persistence) mutates the same private task/handle
// state, so splitting it across files would only leak that state module-wide
// rather than clarify. The two size rules are disabled deliberately for this one
// type; the export logic already lives in its own `+Export` extension.
// swiftlint:disable type_body_length file_length

import Foundation
import Observation

// MARK: - SnapshotLoggingManager

/// The engine behind the Snapshots tab: manages configurations, runs capture
/// sessions (polling or notification-driven), streams entries to disk crash-
/// safely, keeps O(1) running aggregates, and exports completed sessions.
///
/// Generic over a ``SnapshotDataProvider`` so the whole engine is written once and
/// works for any ``Snapshot`` type. Phase I instantiates it as
/// `SnapshotLoggingManager<DeviceSnapshotDataProvider>`.
///
/// Adapted from a proven prior design; the notable Sentinel-specific choices are
/// that BLE I/O flows through the provider's ``SnapshotStreamService`` and device
/// identity is supplied by an injected async metadata closure (so this stays free
/// of any BLE service type), and that capture stops structurally when the
/// connected subtree is torn down on disconnect rather than via a Combine event.
@Observable
@MainActor
final class SnapshotLoggingManager<Provider: SnapshotDataProvider> {
    typealias SnapshotType = Provider.SnapshotType
    typealias CategoryType = Provider.SnapshotType.Category

    // MARK: Published state

    private(set) var configurations: [SnapshotLoggingConfiguration<SnapshotType>] = []
    private(set) var activeSessions: [SnapshotLoggingSession] = []
    private(set) var completedSessions: [SnapshotLoggingSession] = []

    /// Running aggregates per session id — O(1) timing stats for live/completed views.
    private(set) var sessionAggregates: [UUID: SessionRunningAggregates] = [:]

    // MARK: Capture tasks

    private var pollingTasks: [UUID: Task<Void, Never>] = [:]
    private var notificationTasks: [UUID: Task<Void, Never>] = [:]
    private var durationDeadlineTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: Dependencies

    let provider: Provider
    /// Reads device identity (serial + firmware) once at session start.
    private let metadataProvider: @Sendable () async -> SnapshotSessionMetadata
    private let userDefaults = UserDefaults.standard
    let sessionFileManager = SessionFileManager.shared

    /// Exposed for field-sorting preferences keyed by the provider.
    var dataProvider: Provider { provider }

    // MARK: Capture bookkeeping

    private var lastNotificationTime: [UUID: Date] = [:]
    private var sessionFields: [UUID: [SnapshotFieldConfig<SnapshotType>]] = [:]

    // MARK: File-based persistence

    private var sessionFileHandles: [UUID: FileHandle] = [:]
    private var autoSaveTimers: [UUID: Timer] = [:]

    /// Max entries retained in RAM per active session; older entries live on disk
    /// only, bounding memory regardless of session length.
    static var maxEntriesInRAM: Int { 2000 }

    // MARK: Init

    init(
        provider: Provider,
        metadataProvider: @escaping @Sendable () async -> SnapshotSessionMetadata
    ) {
        self.provider = provider
        self.metadataProvider = metadataProvider
        loadConfigurations()
        loadCompletedSessions()
    }

    // MARK: Configuration management

    func saveConfiguration(_ configuration: SnapshotLoggingConfiguration<SnapshotType>) {
        if let index = configurations.firstIndex(where: { $0.id == configuration.id }) {
            configurations[index] = configuration
        } else {
            configurations.append(configuration)
        }
        saveConfigurations()
    }

    func deleteConfiguration(_ configuration: SnapshotLoggingConfiguration<SnapshotType>) {
        configurations.removeAll { $0.id == configuration.id }
        saveConfigurations()
    }

    func getConfiguration(by id: UUID) -> SnapshotLoggingConfiguration<SnapshotType>? {
        configurations.first { $0.id == id }
    }

    // MARK: Aggregates

    func aggregates(for sessionId: UUID) -> SessionRunningAggregates? { sessionAggregates[sessionId] }

    // MARK: Session lifecycle

    func startLoggingSession(
        with configuration: SnapshotLoggingConfiguration<SnapshotType>,
        name: String,
        captureMode: SnapshotCaptureMode? = nil,
        maxDuration: TimeInterval? = nil,
        stopOnDisconnect: Bool = true,
        autoSaveInterval: TimeInterval? = nil
    ) async throws {
        let enabledFields = configuration.enabledFields
        guard !enabledFields.isEmpty else { throw SnapshotLoggingError.noEnabledFields }

        let effectiveCaptureMode = captureMode ?? configuration.captureMode

        // Pre-cache device identity before the session starts.
        let metadata = await metadataProvider()

        var session = SnapshotLoggingSession(
            configurationId: configuration.id,
            name: name,
            pollingInterval: configuration.pollingInterval,
            captureMode: effectiveCaptureMode,
            maxDuration: maxDuration,
            stopOnDisconnect: stopOnDisconnect,
            serialNumber: metadata.serialNumber,
            firmwareVersion: metadata.firmwareVersion,
            autoSaveInterval: autoSaveInterval
        )
        session.start()

        try createSessionFileAndIndex(for: session, enabledFields: enabledFields)

        sessionAggregates[session.id] = SessionRunningAggregates()
        activeSessions.append(session)

        if let interval = autoSaveInterval {
            startAutoSaveTimer(for: session.id, interval: interval)
        }

        switch effectiveCaptureMode {
        case .polling:
            startPolling(for: session, with: enabledFields)
        case .notifications:
            try await startNotificationCapture(for: session, with: enabledFields)
        }

        // Independent hard deadline so a fixed-duration session still stops even if
        // notifications stall or the app is backgrounded.
        if let maxDuration {
            startDurationDeadlineTask(for: session.id, duration: maxDuration)
        }
    }

    /// Create the binary file + header and register the running session in the
    /// index. Everything but the field schema is derived from `session`.
    private func createSessionFileAndIndex(
        for session: SnapshotLoggingSession,
        enabledFields: [SnapshotFieldConfig<SnapshotType>]
    ) throws {
        let fieldSchema = enabledFields.map {
            BinaryFieldSchema(keyPath: $0.keyPath, displayName: $0.displayName, unit: $0.unit, dataType: $0.dataType)
        }
        let snapshotTypeTag: UInt8 = provider.snapshotTypeIdentifier == "deviceSnapshot" ? 0 : 1

        let header = SessionFileHeader(
            formatVersion: SessionBinaryFormat.currentVersion,
            snapshotType: snapshotTypeTag,
            captureMode: session.captureMode,
            sessionId: session.id,
            configurationId: session.configurationId,
            sessionName: session.name,
            startTime: session.startTime,
            pollingInterval: session.pollingInterval,
            maxDuration: session.maxDuration,
            stopOnDisconnect: session.stopOnDisconnect,
            serialNumber: session.serialNumber,
            firmwareVersion: session.firmwareVersion,
            selectedTimingFieldIds: session.selectedTimingFieldIds,
            fieldSchema: fieldSchema,
            autoSaveInterval: session.autoSaveInterval
        )

        try sessionFileManager.createSessionFile(header: header)
        sessionFileHandles[session.id] = try sessionFileManager.openForAppending(sessionId: session.id)

        let indexEntry = SessionIndexEntry(
            id: session.id,
            name: session.name,
            snapshotType: provider.snapshotTypeIdentifier,
            captureMode: session.captureMode,
            startTime: session.startTime,
            endTime: nil,
            duration: nil,
            entryCount: 0,
            status: .running,
            pollingInterval: session.pollingInterval,
            maxDuration: session.maxDuration,
            stopOnDisconnect: session.stopOnDisconnect,
            serialNumber: session.serialNumber,
            firmwareVersion: session.firmwareVersion,
            configurationId: session.configurationId,
            selectedTimingFieldIds: session.selectedTimingFieldIds,
            fileName: SessionFileManager.fileName(for: session.id),
            aggregates: nil,
            autoSaveInterval: session.autoSaveInterval
        )
        sessionFileManager.addToIndex(indexEntry)
    }

    func stopLoggingSession(_ sessionId: UUID) {
        guard let index = activeSessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let session = activeSessions[index]

        switch session.captureMode {
        case .polling:
            pollingTasks[sessionId]?.cancel()
            pollingTasks.removeValue(forKey: sessionId)
        case .notifications:
            stopNotificationCapture(for: sessionId)
        }

        cancelDurationDeadlineTask(for: sessionId)
        stopAutoSaveTimer(for: sessionId)

        activeSessions[index].stop()
        let completed = activeSessions[index]

        let footer = SessionFileFooter(
            endTime: completed.endTime ?? Date(),
            duration: completed.duration ?? completed.actualDuration,
            status: completed.status,
            entryCount: UInt32(completed.entryCount)
        )
        try? sessionFileManager.writeFooter(footer, to: sessionId)

        try? sessionFileHandles[sessionId]?.close()
        sessionFileHandles.removeValue(forKey: sessionId)

        let finalAggregates = sessionAggregates[sessionId]
        sessionFileManager.updateIndex(sessionId: sessionId) { entry in
            entry.endTime = completed.endTime
            entry.duration = completed.duration
            entry.entryCount = completed.entryCount
            entry.status = completed.status
            entry.aggregates = finalAggregates
        }

        var forCompleted = activeSessions.remove(at: index)
        forCompleted.logEntries = [] // entries live on disk now
        completedSessions.append(forCompleted)
    }

    func stopAllActiveSessions() {
        for sessionId in activeSessions.map(\.id) {
            stopLoggingSession(sessionId)
        }
    }

    func deleteCompletedSession(_ sessionId: UUID) {
        completedSessions.removeAll { $0.id == sessionId }
        sessionAggregates.removeValue(forKey: sessionId)
        sessionFileManager.deleteSession(sessionId: sessionId)
    }

    /// Load a completed session's entries from disk (call before export/chart).
    func loadSessionWithEntries(_ sessionId: UUID) async throws -> SnapshotLoggingSession {
        guard var session = completedSessions.first(where: { $0.id == sessionId }) else {
            throw SnapshotLoggingError.sessionNotFound
        }
        let entries = try await Task.detached(priority: .userInitiated) {
            try SessionFileManager.shared.loadEntries(for: sessionId).entries
        }.value
        session.logEntries = entries
        session.entryCount = entries.count
        return session
    }

    func renameSession(_ sessionId: UUID, to newName: String) {
        if let index = completedSessions.firstIndex(where: { $0.id == sessionId }) {
            completedSessions[index].name = newName
        }
        sessionFileManager.updateIndex(sessionId: sessionId) { $0.name = newName }
    }

    // MARK: Polling capture

    /// Whether the active session with this id has hit its duration bound.
    private func activeSessionShouldStop(_ sessionId: UUID) -> Bool {
        guard let idx = activeSessions.firstIndex(where: { $0.id == sessionId }) else { return false }
        return activeSessions[idx].shouldStop()
    }

    /// One BLE read plus the timestamps around it.
    private struct PollingRead {
        let actualStart: Date
        let actualFinishRead: Date
        let deviceUnixTimeMs: UInt64?
        let fieldValues: [SnapshotFieldValue]
    }

    /// Perform a single polling read, decoding the configured fields (or an error
    /// field on failure) and stamping the read start/finish times.
    private func performPollingRead(fields: [SnapshotFieldConfig<SnapshotType>]) async -> PollingRead {
        let actualStart = Date()
        var fieldValues: [SnapshotFieldValue] = []
        var deviceUnixTimeMs: UInt64?
        do {
            let snapshot = try await provider.readSnapshot()
            deviceUnixTimeMs = snapshot.unixTimeMs
            fieldValues = provider.extractFieldValues(from: snapshot, for: fields)
        } catch {
            fieldValues = [SnapshotFieldValue(
                displayName: "Error", keyPath: "error",
                value: .error(error.localizedDescription), unit: "", dataType: .string
            )]
        }
        return PollingRead(
            actualStart: actualStart, actualFinishRead: Date(),
            deviceUnixTimeMs: deviceUnixTimeMs, fieldValues: fieldValues
        )
    }

    private func startPolling(for session: SnapshotLoggingSession, with fields: [SnapshotFieldConfig<SnapshotType>]) {
        let sessionId = session.id
        let intervalNanos = UInt64(session.pollingInterval * 1_000_000_000)
        let wallStart = Date()
        var deadlineNs: UInt64 = 0

        pollingTasks[sessionId] = Task { @MainActor in
            while !Task.isCancelled {
                deadlineNs &+= intervalNanos
                let scheduledTick = Date()
                if activeSessionShouldStop(sessionId) {
                    stopLoggingSession(sessionId)
                    break
                }

                let read = await performPollingRead(fields: fields)

                // Hold the interval before closing the cycle.
                let nowNs = UInt64(max(0, Date().timeIntervalSince(wallStart)) * 1_000_000_000)
                if nowNs < deadlineNs {
                    try? await Task.sleep(nanoseconds: deadlineNs &- nowNs)
                }

                let finishCycle = Date()
                let entry = SnapshotLogEntry(
                    fieldValues: read.fieldValues,
                    deviceUnixTimeMs: read.deviceUnixTimeMs,
                    scheduledTick: scheduledTick,
                    actualStart: read.actualStart,
                    actualFinishRead: read.actualFinishRead,
                    finishCycle: finishCycle,
                    latencySeconds: read.actualStart.timeIntervalSince(scheduledTick),
                    readDurationSeconds: read.actualFinishRead.timeIntervalSince(read.actualStart),
                    cycleDurationSeconds: finishCycle.timeIntervalSince(scheduledTick)
                )
                if let idx = activeSessions.firstIndex(where: { $0.id == sessionId }) {
                    addEntryToActiveSession(entry, at: idx, captureMode: .polling)
                }
            }
        }
    }

    // MARK: Notification capture

    private func startNotificationCapture(
        for session: SnapshotLoggingSession,
        with fields: [SnapshotFieldConfig<SnapshotType>]
    ) async throws {
        let sessionId = session.id
        lastNotificationTime[sessionId] = nil
        sessionFields[sessionId] = fields

        // Attach the consumer BEFORE arming the stream so no frame the device
        // pushes right after enable is dropped. `snapshotStream()` subscribes to
        // the value-update publisher eagerly; `setStreaming(true)` then arms the
        // firmware flag + CCCD, after which frames flow into the live task.
        // (Capture the `Sendable` stream, not the provider, so the task closure
        // crosses no non-`Sendable` state.)
        let snapshots = provider.snapshotStream()
        notificationTasks[sessionId] = Task { @MainActor in
            for await snapshot in snapshots {
                if Task.isCancelled { break }
                handleNotificationSnapshot(snapshot, sessionId: sessionId)
            }
        }

        try await provider.setStreaming(true)
    }

    private func handleNotificationSnapshot(_ snapshot: SnapshotType, sessionId: UUID) {
        guard let idx = activeSessions.firstIndex(where: { $0.id == sessionId }),
              let fields = sessionFields[sessionId] else { return }

        if activeSessions[idx].shouldStop() {
            stopLoggingSession(sessionId)
            return
        }

        let now = Date()
        var interNotificationInterval: Double?
        if let last = lastNotificationTime[sessionId] {
            interNotificationInterval = now.timeIntervalSince(last)
        }
        lastNotificationTime[sessionId] = now

        let entry = SnapshotLogEntry(
            fieldValues: provider.extractFieldValues(from: snapshot, for: fields),
            deviceUnixTimeMs: snapshot.unixTimeMs,
            actualStart: now,
            interNotificationInterval: interNotificationInterval
        )
        addEntryToActiveSession(entry, at: idx, captureMode: .notifications)
    }

    private func stopNotificationCapture(for sessionId: UUID) {
        notificationTasks[sessionId]?.cancel()
        notificationTasks.removeValue(forKey: sessionId)
        lastNotificationTime.removeValue(forKey: sessionId)
        sessionFields.removeValue(forKey: sessionId)

        Task { @MainActor in try? await self.provider.setStreaming(false) }
    }

    // MARK: Entry ingestion (shared)

    private func addEntryToActiveSession(
        _ entry: SnapshotLogEntry,
        at sessionIndex: Int,
        captureMode: SnapshotCaptureMode
    ) {
        let sessionId = activeSessions[sessionIndex].id

        activeSessions[sessionIndex].addLogEntry(entry)

        let entryData = SessionBinaryFormat.encodeEntry(entry, captureMode: captureMode)
        sessionFileHandles[sessionId]?.write(entryData)

        let pollingInterval = activeSessions[sessionIndex].pollingInterval
        sessionAggregates[sessionId, default: SessionRunningAggregates()]
            .update(with: entry, pollingInterval: pollingInterval)

        let maxEntries = Self.maxEntriesInRAM
        if activeSessions[sessionIndex].logEntries.count > maxEntries {
            let excess = activeSessions[sessionIndex].logEntries.count - maxEntries
            activeSessions[sessionIndex].logEntries.removeFirst(excess)
        }
    }

    // MARK: Autosave

    private func startAutoSaveTimer(for sessionId: UUID, interval: TimeInterval) {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.performAutoSave(for: sessionId) }
        }
        autoSaveTimers[sessionId] = timer
    }

    private func stopAutoSaveTimer(for sessionId: UUID) {
        autoSaveTimers[sessionId]?.invalidate()
        autoSaveTimers.removeValue(forKey: sessionId)
    }

    private func performAutoSave(for sessionId: UUID) {
        guard let session = activeSessions.first(where: { $0.id == sessionId }) else { return }
        sessionFileHandles[sessionId]?.synchronizeFile()
        let currentAggregates = sessionAggregates[sessionId]
        sessionFileManager.updateIndex(sessionId: sessionId) { entry in
            entry.entryCount = session.entryCount
            entry.aggregates = currentAggregates
        }
    }

    // MARK: Duration deadline

    private func startDurationDeadlineTask(for sessionId: UUID, duration: TimeInterval) {
        durationDeadlineTasks[sessionId] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if activeSessions.contains(where: { $0.id == sessionId }) {
                stopLoggingSession(sessionId)
            }
        }
    }

    private func cancelDurationDeadlineTask(for sessionId: UUID) {
        durationDeadlineTasks[sessionId]?.cancel()
        durationDeadlineTasks.removeValue(forKey: sessionId)
    }

    // MARK: Configuration persistence (UserDefaults — small)

    private func saveConfigurations() {
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        userDefaults.set(data, forKey: provider.configurationsStorageKey)
    }

    private func loadConfigurations() {
        guard let data = userDefaults.data(forKey: provider.configurationsStorageKey),
              let decoded = try? JSONDecoder().decode(
                  [SnapshotLoggingConfiguration<SnapshotType>].self, from: data
              ) else { return }
        configurations = decoded
    }

    // MARK: Session persistence (file-based)

    func loadCompletedSessions() {
        let snapshotType = provider.snapshotTypeIdentifier
        let filtered = sessionFileManager.loadIndex().filter {
            $0.snapshotType == snapshotType && ($0.status == .completed || $0.status == .stopped)
        }
        completedSessions = filtered.map { SnapshotLoggingSession(from: $0) }
        for entry in filtered {
            if let agg = entry.aggregates { sessionAggregates[entry.id] = agg }
        }
    }
}

// swiftlint:enable type_body_length file_length
