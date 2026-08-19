//
//  OTAUploaderTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/18/26.
//

import Foundation
import Testing

@testable import Sentinel

/// Covers the #22 acceptance criteria: the full transition table via mocks, CRC32
/// round-trip, MTU-derived chunking, reconnect/verify, decoded failure statuses,
/// and cancel gating.
@MainActor
struct OTAUploaderTests {
    private let target = FirmwareVersion(major: 1, minor: 1, patch: 0, build: 0)

    private func image(bytes: Int = 2000) -> FirmwareImage {
        FirmwareImage(
            version: target,
            data: Data((0 ..< bytes).map { UInt8($0 & 0xFF) }),
            source: .bundled
        )
    }

    /// Run `start` and spin the run loop until a terminal state.
    private func run(_ uploader: OTAUploader, _ image: FirmwareImage) async {
        uploader.start(image: image)
        for _ in 0 ..< 200_000 {
            switch uploader.state {
            case .complete, .failed: return
            default: await Task.yield()
            }
        }
        Issue.record("uploader did not reach a terminal state; stuck at \(uploader.state)")
    }

    // MARK: Happy path

    @Test func endToEndReachesComplete() async {
        let ota = ScriptedOTAService()
        let reconnector = MockFirmwareReconnector(system: MockSystemService(firmwareVersion: target))
        let uploader = OTAUploader(ota: ota, system: MockSystemService(), mtu: 247, reconnector: reconnector)

        await run(uploader, image())

        #expect(uploader.state == .complete)
        #expect(uploader.progressFraction == 1)
        #expect(ota.notifyEnabled)
        #expect(reconnector.reconnectCount == 1)
    }

    @Test func crc32RoundTripsThroughVerify() async {
        let ota = ScriptedOTAService()
        let img = image()
        let uploader = OTAUploader(
            ota: ota,
            system: MockSystemService(firmwareVersion: target),
            mtu: 247
        )

        await run(uploader, img)

        // Verify carried the CRC32 of the whole image, and the reassembled upload
        // matches the source bytes.
        #expect(ota.payload(for: .verify) == CRC32.checksum(of: img.data))
        #expect(ota.uploadedImage == img.data)
    }

    @Test func startDownloadCarriesImageSize() async {
        let ota = ScriptedOTAService()
        let img = image(bytes: 1234)
        let uploader = OTAUploader(ota: ota, system: MockSystemService(firmwareVersion: target), mtu: 247)

        await run(uploader, img)

        #expect(ota.payload(for: .start) == 1234)
    }

    @Test func chunkSizeDerivesFromNegotiatedMTU() async {
        let ota = ScriptedOTAService()
        let img = image(bytes: 1000)
        // MTU 100 → chunk = 97.
        let uploader = OTAUploader(ota: ota, system: MockSystemService(firmwareVersion: target), mtu: 100)

        await run(uploader, img)

        #expect(ota.writtenChunks.map(\.count).max() == 97)
        #expect(ota.writtenChunks.count == (1000 + 96) / 97)
    }

    @Test func verifiesViaOriginalSystemWhenNoReconnector() async {
        let ota = ScriptedOTAService()
        // No reconnector — the original system stands in for the version check.
        let uploader = OTAUploader(ota: ota, system: MockSystemService(firmwareVersion: target), mtu: 247)

        await run(uploader, image())

        #expect(uploader.state == .complete)
    }

    // MARK: Failure paths

    @Test func nonOKPrepareStatusFails() async {
        let ota = ScriptedOTAService()
        ota.statusForPrepare = OTAUploader.Status.illegal.rawValue
        let uploader = OTAUploader(ota: ota, system: MockSystemService(firmwareVersion: target), mtu: 247)

        await run(uploader, image())

        guard case let .failed(reason) = uploader.state else {
            Issue.record("expected .failed, got \(uploader.state)")
            return
        }
        #expect(reason.contains("Illegal state"))
        #expect(ota.writtenChunks.isEmpty) // never reached the upload
    }

    @Test func verificationFailedStatusSurfaces() async {
        let ota = ScriptedOTAService()
        ota.statusForVerify = OTAUploader.Status.verificationFailed.rawValue
        let uploader = OTAUploader(ota: ota, system: MockSystemService(firmwareVersion: target), mtu: 247)

        await run(uploader, image())

        guard case let .failed(reason) = uploader.state else {
            Issue.record("expected .failed, got \(uploader.state)")
            return
        }
        #expect(reason.contains("verification failed"))
    }

    @Test func unknownStatusFails() async {
        let ota = ScriptedOTAService()
        ota.statusForStart = 0x2A // not a known status
        let uploader = OTAUploader(ota: ota, system: MockSystemService(firmwareVersion: target), mtu: 247)

        await run(uploader, image())

        guard case let .failed(reason) = uploader.state else {
            Issue.record("expected .failed, got \(uploader.state)")
            return
        }
        #expect(reason.contains("unknown status"))
    }

    @Test func writeErrorDuringUploadFails() async {
        let ota = ScriptedOTAService()
        ota.failWriteAtChunk = 3 // link drops mid-upload
        let uploader = OTAUploader(ota: ota, system: MockSystemService(firmwareVersion: target), mtu: 247)

        await run(uploader, image())

        if case .complete = uploader.state {
            Issue.record("expected failure, reached .complete")
        }
        #expect(uploader.progressFraction < 1)
    }

    @Test func versionMismatchAfterReconnectFails() async {
        let ota = ScriptedOTAService()
        // Device reboots on the wrong version.
        let wrong = FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16)
        let reconnector = MockFirmwareReconnector(system: MockSystemService(firmwareVersion: wrong))
        let uploader = OTAUploader(ota: ota, system: MockSystemService(), mtu: 247, reconnector: reconnector)

        await run(uploader, image())

        guard case let .failed(reason) = uploader.state else {
            Issue.record("expected .failed, got \(uploader.state)")
            return
        }
        #expect(reason.contains("restarted on 1.0.0"))
    }

    @Test func emptyImageFails() async {
        let ota = ScriptedOTAService()
        let empty = FirmwareImage(version: target, data: Data(), source: .bundled)
        let uploader = OTAUploader(ota: ota, system: MockSystemService(firmwareVersion: target), mtu: 247)

        await run(uploader, empty)

        guard case let .failed(reason) = uploader.state else {
            Issue.record("expected .failed, got \(uploader.state)")
            return
        }
        #expect(reason.contains("empty"))
    }

    // MARK: Cancel gating

    @Test func cancelSendsAbortAndResets() async {
        let ota = ScriptedOTAService()
        let uploader = OTAUploader(ota: ota, system: MockSystemService(), mtu: 247)

        await uploader.cancel() // cancellable from .idle

        #expect(uploader.state == .idle)
        #expect(uploader.progressFraction == 0)
        #expect(ota.controlWrites.last?.first == OTAUploader.Command.abort.rawValue)
    }

    @Test func cancelIsNoOpPastPointOfNoReturn() {
        #expect(OTAUploader.State.uploading(chunkIndex: 1, totalChunks: 2).isCancellable)
        #expect(OTAUploader.State.preparing.isCancellable)
        #expect(!OTAUploader.State.validating.isCancellable)
        #expect(!OTAUploader.State.restarting.isCancellable)
        #expect(!OTAUploader.State.reconnecting.isCancellable)
        #expect(!OTAUploader.State.verifying.isCancellable)
        #expect(!OTAUploader.State.complete.isCancellable)
        #expect(!OTAUploader.State.failed("x").isCancellable)
    }
}
