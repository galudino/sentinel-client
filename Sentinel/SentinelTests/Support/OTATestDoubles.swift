//
//  OTATestDoubles.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/18/26.
//

import Foundation

@testable import Sentinel

/// A scripted ``OTAService`` for driving ``OTAUploader`` through its full
/// transition table with no BLE. Each Control-Point command gets a canned status
/// reply (default `ok`); `writeData` records chunks (and can be made to throw at a
/// chosen chunk to simulate a mid-upload disconnect).
final class ScriptedOTAService: OTAService, @unchecked Sendable {
    /// Status byte replied to each command (0 = ok). Override to drive failures.
    var statusForPrepare: UInt8 = 0
    var statusForStart: UInt8 = 0
    var statusForVerify: UInt8 = 0

    /// When set, `writeData` throws once it has recorded this many chunks — models
    /// a link drop mid-upload.
    var failWriteAtChunk: Int?

    private(set) var controlWrites: [Data] = []
    private(set) var writtenChunks: [Data] = []
    private(set) var notifyEnabled = false

    private let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        var captured: AsyncStream<Data>.Continuation!
        stream = AsyncStream { captured = $0 }
        continuation = captured
    }

    func writeControlPoint(_ command: Data) async throws {
        controlWrites.append(command)
        switch command.first {
        case OTAUploader.Command.prepare.rawValue: continuation.yield(Data([statusForPrepare]))
        case OTAUploader.Command.start.rawValue: continuation.yield(Data([statusForStart]))
        case OTAUploader.Command.verify.rawValue: continuation.yield(Data([statusForVerify]))
        default: break // abort / finish: no status reply
        }
    }

    func writeData(_ chunk: Data) async throws {
        if let failWriteAtChunk, writtenChunks.count >= failWriteAtChunk {
            throw ScriptedOTAError.linkDropped
        }
        writtenChunks.append(chunk)
    }

    func setControlPointNotifying(_ enabled: Bool) async throws { notifyEnabled = enabled }

    func controlPointNotifications() -> AsyncStream<Data> { stream }

    /// The image bytes reassembled from the recorded chunks.
    var uploadedImage: Data { writtenChunks.reduce(into: Data()) { $0.append($1) } }

    /// The `uint32` LE payload the given command carried, if it was written.
    func payload(for command: OTAUploader.Command) -> UInt32? {
        guard let frame = controlWrites.first(where: { $0.first == command.rawValue }), frame.count >= 5 else {
            return nil
        }
        return frame.subdata(in: 1 ..< 5).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    }
}

enum ScriptedOTAError: Error { case linkDropped }

/// A ``FirmwareReconnector`` that returns a canned ``SystemService`` (no BLE), so
/// the `.reconnecting → .verifying → .complete` tail is testable.
final class MockFirmwareReconnector: FirmwareReconnector, @unchecked Sendable {
    let system: any SystemService
    var shouldFail = false
    private(set) var reconnectCount = 0

    init(system: any SystemService) { self.system = system }

    func reconnect() async throws -> any SystemService {
        reconnectCount += 1
        if shouldFail { throw ScriptedOTAError.linkDropped }
        return system
    }
}
