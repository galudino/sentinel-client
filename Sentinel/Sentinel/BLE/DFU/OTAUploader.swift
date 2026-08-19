//
//  OTAUploader.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/18/26.
//

import Foundation
import Observation

/// The protocol-layer engine that drives a BLE firmware upload (#22). Powers
/// `FirmwareUpdateView` (#21) but is not itself a view: it owns the Infineon
/// **OTA FW Upgrade Service** handshake, chunking, CRC32, the `Verify` step, and
/// the post-flash reconnect/verify. MCUBoot validates + swaps the image on the
/// device *after* it lands; this speaks the BLE wire protocol that gets it there.
///
/// ### Wire protocol (source of truth: #22 + firmware #6)
/// ```
/// 1. Enable Control-Point indications.
/// 2. Prepare Download (1)            → status ok
/// 3. Start Download   (2, imageSize) → status ok
/// 4. For each chunk: write Control Data; fold CRC32.   (write-ack = flow control)
/// 5. Verify (3, crc32)               → status ok
/// 6. Device self-resets + disconnects.  ← treated as SUCCESS, not an error
/// 7. Reconnect to the same identity; read the firmware version; confirm target.
/// ```
///
/// Cancel is honoured only through `.uploading`; from `.validating` on it is the
/// point of no return (the device is about to swap + reboot) and ``cancel()`` is a
/// no-op — the same guard `FirmwareUpdateView` enforces in its UI.
///
/// `@MainActor` (drives SwiftUI) and `@Observable` (`state` + `progressFraction`
/// are the view's bindings). The reconnect step is delegated to an injected
/// ``FirmwareReconnector`` so this type never depends on the BLE central and the
/// whole transition table — reconnect included — is unit-testable with mocks.
@MainActor
@Observable
final class OTAUploader {
    /// Control-Point commands (first byte of a control write; LE params follow).
    enum Command: UInt8 {
        case prepare = 1
        case start = 2
        case verify = 3
        case finish = 4
        case getStatus = 5
        case clearStatus = 6
        case abort = 7
    }

    /// Control-Point status responses (first byte of a status notification).
    enum Status: UInt8 {
        // swiftlint:disable:next identifier_name
        case ok = 0
        case unsupported = 1
        case illegal = 2
        case verificationFailed = 3
        case invalidImage = 4
        case invalidImageSize = 5
        case moreData = 6
        case invalidAppID = 7
        case invalidVersion = 8
        case `continue` = 9

        /// Human-readable decode for the failure UI.
        nonisolated var message: String {
            switch self {
            case .ok: "OK"
            case .unsupported: "Command not supported"
            case .illegal: "Illegal state"
            case .verificationFailed: "Image verification failed"
            case .invalidImage: "Invalid image"
            case .invalidImageSize: "Invalid image size"
            case .moreData: "More data expected"
            case .invalidAppID: "Invalid app ID"
            case .invalidVersion: "Invalid version"
            case .continue: "Continue"
            }
        }
    }

    enum State: Equatable {
        case idle
        case preparing
        case starting
        case uploading(chunkIndex: Int, totalChunks: Int)
        case validating
        case restarting
        case reconnecting
        case verifying
        case complete
        case failed(String)

        /// The phase label shown under the progress ring.
        var userFacingMessage: String {
            switch self {
            case .idle, .preparing: "Preparing…"
            case .starting: "Starting upload…"
            case .uploading: "Uploading…"
            case .validating: "Validating…"
            case .restarting: "Restarting device…"
            case .reconnecting: "Reconnecting…"
            case .verifying: "Confirming version…"
            case .complete: "Update complete"
            case let .failed(reason): reason
            }
        }

        /// Cancel is allowed only up to (and during) the upload. `.validating`
        /// onward is the point of no return.
        var isCancellable: Bool {
            switch self {
            case .idle, .preparing, .starting, .uploading: true
            default: false
            }
        }
    }

    private(set) var state: State = .idle
    /// Upload progress, `0…1`. Meaningful during `.uploading`; pinned to `1` on
    /// `.complete`.
    private(set) var progressFraction: Double = 0

    /// The original connection's identity/health service. Used to confirm the
    /// version when no ``reconnector`` is wired (tests / previews); production
    /// always injects a reconnector and reads the *reconnected* peer instead.
    let ota: any OTAService
    let system: any SystemService
    private let reconnector: (any FirmwareReconnector)?

    /// Negotiated ATT MTU — the chunk size is `MTU − 3` (never a hardcoded 244).
    let mtu: Int

    /// Timeouts per the #22 spec.
    private let controlPointTimeout: Duration = .seconds(10)
    private let verifyTimeout: Duration = .seconds(30)

    /// The running upload, retained so ``cancel()`` can abort it.
    private var runTask: Task<Void, Never>?

    /// Reads the Control-Point status stream, opened once before the first command
    /// so no early status is missed. A reference type (not an actor-isolated stored
    /// iterator) so `next()` can be `await`-ed without violating exclusive access.
    private var statusReader: StatusReader?

    init(
        ota: any OTAService,
        system: any SystemService,
        mtu: Int,
        reconnector: (any FirmwareReconnector)? = nil
    ) {
        self.ota = ota
        self.system = system
        self.mtu = mtu
        self.reconnector = reconnector
    }

    // MARK: Intents

    /// Begin (or retry, from `.failed`) the upload. Idempotent while a run is in
    /// flight. Drives `state`/`progressFraction` to completion or `.failed`.
    func start(image: FirmwareImage) {
        guard runTask == nil else { return }
        progressFraction = 0
        runTask = Task { [weak self] in await self?.run(image: image) }
    }

    /// Cancel an in-flight upload — abort the transfer, notify the device, and
    /// reset. A no-op once `.validating` is reached (point of no return).
    func cancel() async {
        guard state.isCancellable else { return }
        runTask?.cancel()
        runTask = nil
        try? await ota.writeControlPoint(Data([Command.abort.rawValue]))
        state = .idle
        progressFraction = 0
    }

    // MARK: Run

    private func run(image: FirmwareImage) async {
        defer { runTask = nil }
        do {
            guard !image.data.isEmpty else { throw OTAError.emptyImage }
            let chunkSize = max(mtu - 3, 20)

            // 1. Open the status stream BEFORE any command so the first response
            //    can't be missed, then Prepare Download.
            state = .preparing
            progressFraction = 0
            try await ota.setControlPointNotifying(true)
            statusReader = StatusReader(ota.controlPointNotifications())

            try await send(.prepare)
            try await expectOK(timeout: controlPointTimeout)

            // 2. Start Download (image size, LE uint32).
            state = .starting
            try await send(.start, payload: UInt32(image.data.count).littleEndianBytes)
            try await expectOK(timeout: controlPointTimeout)

            // 3. Stream Control-Data chunks, folding CRC32. The write-ack is the
            //    flow control — each `writeData` awaits before the next chunk.
            let totalChunks = (image.data.count + chunkSize - 1) / chunkSize
            var crc = CRC32()
            state = .uploading(chunkIndex: 0, totalChunks: totalChunks)
            for index in 0 ..< totalChunks {
                try Task.checkCancellation()
                let lowerBound = index * chunkSize
                let upperBound = min(lowerBound + chunkSize, image.data.count)
                let chunk = image.data.subdata(in: lowerBound ..< upperBound)
                crc.update(chunk)
                try await ota.writeData(chunk)
                state = .uploading(chunkIndex: index, totalChunks: totalChunks)
                progressFraction = Double(index + 1) / Double(totalChunks)
            }

            // 4. Verify (CRC32 of the whole image).
            try Task.checkCancellation()
            state = .validating
            try await send(.verify, payload: crc.checksum.littleEndianBytes)
            try await expectOK(timeout: verifyTimeout)

            // 5. On ok the device self-resets + disconnects — success, not error.
            state = .restarting

            // 6. Reconnect (production) then confirm the running version. With no
            //    reconnector wired (tests/previews) the original service stands in.
            let verifySystem: any SystemService
            if let reconnector {
                state = .reconnecting
                verifySystem = try await reconnector.reconnect()
            } else {
                verifySystem = system
            }
            state = .verifying
            let running = try await verifySystem.readFirmwareVersion()
            guard running.sameRelease(as: image.version) else {
                throw OTAError.versionMismatch(expected: image.version, actual: running)
            }

            state = .complete
            progressFraction = 1
        } catch is CancellationError {
            // `cancel()` already reset the state; nothing to surface.
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    // MARK: Control-Point helpers

    private func send(_ command: Command, payload: [UInt8] = []) async throws {
        try await ota.writeControlPoint(Data([command.rawValue] + payload))
    }

    /// Await the next status notification and require it to be `ok`, else throw a
    /// decoded failure.
    private func expectOK(timeout: Duration) async throws {
        let raw = try await nextStatusByte(timeout: timeout)
        guard let status = Status(rawValue: raw) else { throw OTAError.unknownStatus(raw) }
        guard status == .ok else { throw OTAError.deviceRejected(status) }
    }

    /// Pull the next Control-Point status byte, bounded by `timeout` — the reader's
    /// `next()` races a sleep; whichever wins, the other child is cancelled.
    private func nextStatusByte(timeout: Duration) async throws -> UInt8 {
        guard let reader = statusReader else { throw OTAError.streamEnded }
        let byte: UInt8? = try await withThrowingTaskGroup(of: UInt8?.self) { group in
            group.addTask { await reader.next()?.first }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw OTAError.timedOut
            }
            defer { group.cancelAll() }
            for try await value in group {
                return value
            }
            return nil
        }
        guard let byte else { throw OTAError.streamEnded }
        return byte
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Errors

nonisolated enum OTAError: LocalizedError, Equatable {
    case emptyImage
    case streamEnded
    case timedOut
    case unknownStatus(UInt8)
    case deviceRejected(OTAUploader.Status)
    case versionMismatch(expected: FirmwareVersion, actual: FirmwareVersion)

    var errorDescription: String? {
        switch self {
        case .emptyImage:
            "The selected firmware image is empty."
        case .streamEnded:
            "The device stopped responding during the update."
        case .timedOut:
            "The device did not respond in time during the update."
        case let .unknownStatus(raw):
            "The device reported an unknown status (0x\(String(raw, radix: 16)))."
        case let .deviceRejected(status):
            "The device rejected the update: \(status.message)."
        case let .versionMismatch(expected, actual):
            "The device restarted on \(actual.shortVersion), not the expected \(expected.shortVersion)."
        }
    }
}

// MARK: - Status stream reader

/// Owns the single iterator over the Control-Point status stream. A `nonisolated`
/// reference type so `next()` can be `await`-ed from a task-group child without the
/// exclusive-access violation an actor-isolated stored iterator would raise; single
/// consumer by construction, hence `@unchecked Sendable`.
private final nonisolated class StatusReader: @unchecked Sendable {
    private var iterator: AsyncStream<Data>.Iterator

    init(_ stream: AsyncStream<Data>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async -> Data? {
        await iterator.next()
    }
}

// MARK: - Little-endian encoding

private extension UInt32 {
    /// The value as 4 little-endian bytes — the wire form for `Start Download`'s
    /// image size and `Verify`'s CRC32.
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }
}

#if DEBUG
    extension OTAUploader {
        /// A uploader pinned to a specific phase for `FirmwareUpdateView` previews —
        /// no BLE, no running task. The view's preview path must skip `start(image:)`
        /// so this frozen state survives.
        static func preview(_ state: State, progress: Double = 0) -> OTAUploader {
            let uploader = OTAUploader(ota: MockOTAService(), system: MockSystemService(), mtu: 247)
            uploader.state = state
            uploader.progressFraction = progress
            return uploader
        }
    }
#endif
