//
//  SessionFileManager.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - SessionIndexEntry

/// Lightweight metadata for a session, stored in the JSON session index and
/// loaded at startup to populate the completed-sessions list. Does **not**
/// include log entries — those live in the `.sentinelsession` binary file and are
/// paged in on demand (export, charting).
nonisolated struct SessionIndexEntry: Codable, Identifiable {
    let id: UUID
    var name: String
    /// Snapshot type identifier, e.g. "deviceSnapshot".
    let snapshotType: String
    let captureMode: SnapshotCaptureMode
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval?
    var entryCount: Int
    var status: SnapshotLoggingStatus
    let pollingInterval: TimeInterval
    let maxDuration: TimeInterval?
    let stopOnDisconnect: Bool
    let serialNumber: UInt32
    let firmwareVersion: String
    let configurationId: UUID
    let selectedTimingFieldIds: Set<String>
    /// Binary file name, e.g. "<UUID>.sentinelsession".
    let fileName: String
    var aggregates: SessionRunningAggregates?
    let autoSaveInterval: TimeInterval?
}

// MARK: - SessionFileManager

/// Owns the `.sentinelsession` binary files and the JSON session index in
/// Application Support: create/append/read/delete session files, maintain the
/// index for fast list loading, and support crash recovery for files that never
/// got a footer.
final nonisolated class SessionFileManager: @unchecked Sendable {
    static let shared = SessionFileManager()

    private let fileManager = FileManager.default
    private let sessionsDirectoryName = "SentinelSessions"
    private let indexFileName = "session_index.json"

    // MARK: Directories

    var sessionsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(sessionsDirectoryName)
    }

    private var indexFileURL: URL {
        sessionsDirectory.appendingPathComponent(indexFileName)
    }

    init() {
        createSessionsDirectoryIfNeeded()
    }

    private func createSessionsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: sessionsDirectory.path) {
            try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: Session file URLs

    func sessionFileURL(for sessionId: UUID) -> URL {
        sessionsDirectory.appendingPathComponent("\(sessionId.uuidString).\(SessionBinaryFormat.fileExtension)")
    }

    /// The binary file name for a session (as stored in the index).
    static func fileName(for sessionId: UUID) -> String {
        "\(sessionId.uuidString).\(SessionBinaryFormat.fileExtension)"
    }

    // MARK: Index management

    func loadIndex() -> [SessionIndexEntry] {
        guard fileManager.fileExists(atPath: indexFileURL.path),
              let data = try? Data(contentsOf: indexFileURL),
              let entries = try? JSONDecoder().decode([SessionIndexEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    func saveIndex(_ entries: [SessionIndexEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexFileURL, options: .atomic)
    }

    func addToIndex(_ entry: SessionIndexEntry) {
        var index = loadIndex()
        index.removeAll { $0.id == entry.id }
        index.append(entry)
        saveIndex(index)
    }

    func updateIndex(sessionId: UUID, update: (inout SessionIndexEntry) -> Void) {
        var index = loadIndex()
        if let idx = index.firstIndex(where: { $0.id == sessionId }) {
            update(&index[idx])
            saveIndex(index)
        }
    }

    func removeFromIndex(sessionId: UUID) {
        var index = loadIndex()
        index.removeAll { $0.id == sessionId }
        saveIndex(index)
    }

    // MARK: Session file creation

    @discardableResult
    func createSessionFile(header: SessionFileHeader) throws -> URL {
        let fileURL = sessionFileURL(for: header.sessionId)
        try header.encode().write(to: fileURL)
        return fileURL
    }

    // MARK: File-handle operations (streaming writes)

    /// Open a handle positioned at end-of-file for appending. The caller closes it.
    func openForAppending(sessionId: UUID) throws -> FileHandle {
        let fileURL = sessionFileURL(for: sessionId)
        guard fileManager.fileExists(atPath: fileURL.path) else { throw BinaryFormatError.fileNotFound }
        let handle = try FileHandle(forWritingTo: fileURL)
        handle.seekToEndOfFile()
        return handle
    }

    // MARK: Footer

    func writeFooter(_ footer: SessionFileFooter, to sessionId: UUID) throws {
        let fileURL = sessionFileURL(for: sessionId)
        guard fileManager.fileExists(atPath: fileURL.path) else { throw BinaryFormatError.fileNotFound }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(footer.encode())
    }

    // MARK: Session loading

    /// Read and decode the whole session file. For long sessions call this off the
    /// main actor.
    func loadEntries(
        for sessionId: UUID
    ) throws -> (header: SessionFileHeader, entries: [SnapshotLogEntry], footer: SessionFileFooter?) {
        let data = try Data(contentsOf: sessionFileURL(for: sessionId))
        let reader = BinaryReader(data: data)
        let header = try SessionFileHeader.decode(from: reader)

        var entries: [SnapshotLogEntry] = []
        var footer: SessionFileFooter?

        while !reader.isAtEnd {
            let savedOffset = reader.offset
            do {
                let nextByte = try reader.readUInt8()
                reader.offset = savedOffset // undo the peek

                if nextByte == SessionBinaryFormat.footerMarker {
                    footer = try SessionFileFooter.decode(from: reader)
                    break
                } else if nextByte == SessionBinaryFormat.entryMarker {
                    let entry = try SessionBinaryFormat.decodeEntry(
                        from: reader,
                        captureMode: header.captureMode,
                        schema: header.fieldSchema
                    )
                    entries.append(entry)
                } else {
                    // Unknown byte — scan forward for the next valid marker.
                    _ = try reader.readUInt8()
                    while !reader.isAtEnd {
                        let scanByte = try reader.readUInt8()
                        if scanByte == SessionBinaryFormat.entryMarker || scanByte == SessionBinaryFormat.footerMarker {
                            reader.offset -= 1
                            break
                        }
                    }
                }
            } catch {
                break // end of data or corruption — stop
            }
        }

        return (header, entries, footer)
    }

    // MARK: Deletion

    func deleteSessionFile(for sessionId: UUID) {
        try? fileManager.removeItem(at: sessionFileURL(for: sessionId))
    }

    func deleteSession(sessionId: UUID) {
        deleteSessionFile(for: sessionId)
        removeFromIndex(sessionId: sessionId)
    }

    // MARK: File info

    func sessionFileSize(for sessionId: UUID) -> Int64? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: sessionFileURL(for: sessionId).path) else {
            return nil
        }
        return attrs[.size] as? Int64
    }

    func sessionFileExists(for sessionId: UUID) -> Bool {
        fileManager.fileExists(atPath: sessionFileURL(for: sessionId).path)
    }

    // MARK: Crash recovery

    /// Sessions the index still marks `running` but whose file exists — candidates
    /// to recover after an unclean shutdown.
    func findRecoverableSessions() -> [SessionIndexEntry] {
        loadIndex().filter { $0.status == .running && sessionFileExists(for: $0.id) }
    }

    /// Recover the entries from a session file that never got a footer.
    func recoverSession(sessionId: UUID) throws -> (header: SessionFileHeader, entries: [SnapshotLogEntry]) {
        let result = try loadEntries(for: sessionId)
        return (result.header, result.entries)
    }
}
