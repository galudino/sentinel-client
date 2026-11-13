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

    /// #59: the post-DFU **success** reconnect must be bounded like the failure path
    /// (#52) — CoreBluetooth's connect never times out. A hung reconnect after a
    /// confirmed swap resolves to `.complete` within `recoveryTimeout` (the update DID
    /// succeed), never an indefinite "Reconnecting…" and never `.failed`.
    @Test func successReconnectTimesOutButStillCompletes() async {
        let ota = ScriptedOTAService()
        let reconnector = MockFirmwareReconnector(system: MockSystemService(firmwareVersion: target))
        reconnector.shouldHang = true
        let uploader = OTAUploader(
            ota: ota, system: MockSystemService(), mtu: 247,
            reconnector: reconnector, recoveryTimeout: .milliseconds(50)
        )

        await run(uploader, image())

        #expect(uploader.state == .complete)
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

    // MARK: Recovery (#50, #52, #53)

    /// #53 fast path: a failure that never dropped the link (a verify rejection,
    /// before the device self-resets) recovers *in place* — the still-live link is
    /// reused and the full reconnect is skipped. `.failed` → `recover()` →
    /// `.recovered`, with a best-effort ABORT sent and the reconnector left untouched.
    @Test func recoverReusesLiveLinkWithoutReconnecting() async {
        let ota = ScriptedOTAService()
        ota.statusForVerify = OTAUploader.Status.verificationFailed.rawValue
        let reconnector = MockFirmwareReconnector(system: MockSystemService(firmwareVersion: target))
        // The uploader's own link is alive (reads succeed), so the liveness probe
        // passes and recovery short-circuits before any reconnect.
        let uploader = OTAUploader(
            ota: ota, system: MockSystemService(firmwareVersion: target),
            mtu: 247, reconnector: reconnector
        )

        await run(uploader, image())
        guard case .failed = uploader.state else {
            Issue.record("expected .failed before recovery, got \(uploader.state)")
            return
        }

        await uploader.recover()

        #expect(uploader.state == .recovered)
        #expect(reconnector.reconnectCount == 0) // fast path — no rescan/reconnect
        #expect(uploader.progressFraction == 0)
        #expect(ota.controlWrites.contains { $0.first == OTAUploader.Command.abort.rawValue })
    }

    /// #53 slow path: when the original link is gone (the liveness probe fails),
    /// recovery falls through to the full reconnect and reaches `.recovered`.
    @Test func recoverReconnectsWhenOriginalLinkIsDown() async {
        let ota = ScriptedOTAService()
        ota.statusForVerify = OTAUploader.Status.verificationFailed.rawValue
        let deadLink = MockSystemService(firmwareVersion: target)
        deadLink.failReads = true // the original link dropped — probe fails
        let reconnector = MockFirmwareReconnector(system: MockSystemService(firmwareVersion: target))
        let uploader = OTAUploader(ota: ota, system: deadLink, mtu: 247, reconnector: reconnector)

        await run(uploader, image())
        await uploader.recover()

        #expect(uploader.state == .recovered)
        #expect(reconnector.reconnectCount == 1) // the probe failed, so the reconnect ran
    }

    /// Recovery that can't re-establish the link stays `.failed` (the view then
    /// routes to scanning) rather than claiming a clean connection.
    @Test func recoverStaysFailedWhenReconnectFails() async {
        let ota = ScriptedOTAService()
        ota.statusForVerify = OTAUploader.Status.verificationFailed.rawValue
        let deadLink = MockSystemService(firmwareVersion: target)
        deadLink.failReads = true // force past the #53 fast path to the reconnect
        let reconnector = MockFirmwareReconnector(system: MockSystemService(firmwareVersion: target))
        reconnector.shouldFail = true
        let uploader = OTAUploader(ota: ota, system: deadLink, mtu: 247, reconnector: reconnector)

        await run(uploader, image())
        await uploader.recover()

        guard case .failed = uploader.state else {
            Issue.record("expected .failed after a failed reconnect, got \(uploader.state)")
            return
        }
    }

    /// #52: a reconnect that never completes (CoreBluetooth's `connect` has no
    /// timeout) must not hang on `.recovering` forever — `recoveryTimeout` resolves
    /// `recover()` to `.failed`, so the view can route to scanning.
    @Test func recoverTimesOutWhenReconnectHangs() async {
        let ota = ScriptedOTAService()
        ota.statusForVerify = OTAUploader.Status.verificationFailed.rawValue
        let deadLink = MockSystemService(firmwareVersion: target)
        deadLink.failReads = true // force past the #53 fast path to the reconnect, which hangs
        let reconnector = MockFirmwareReconnector(system: MockSystemService(firmwareVersion: target))
        reconnector.shouldHang = true
        let uploader = OTAUploader(
            ota: ota, system: deadLink, mtu: 247,
            reconnector: reconnector, recoveryTimeout: .milliseconds(50)
        )

        await run(uploader, image())
        await uploader.recover()

        guard case .failed = uploader.state else {
            Issue.record("expected .failed after a hung reconnect timed out, got \(uploader.state)")
            return
        }
        #expect(reconnector.reconnectCount == 1)
    }

    /// With no reconnector and a dead link there is nothing to re-establish, so
    /// recovery stays `.failed`.
    @Test func recoverStaysFailedWithoutReconnector() async {
        let ota = ScriptedOTAService()
        ota.statusForVerify = OTAUploader.Status.verificationFailed.rawValue
        let deadLink = MockSystemService(firmwareVersion: target)
        deadLink.failReads = true // no live link to reuse, and no reconnector
        let uploader = OTAUploader(ota: ota, system: deadLink, mtu: 247)

        await run(uploader, image())
        await uploader.recover()

        guard case .failed = uploader.state else {
            Issue.record("expected .failed without a reconnector, got \(uploader.state)")
            return
        }
    }

    /// `recover()` is a no-op unless the uploader is `.failed`, so repeated or
    /// mistimed calls are idempotent.
    @Test func recoverIsNoOpUnlessFailed() async {
        let ota = ScriptedOTAService()
        let reconnector = MockFirmwareReconnector(system: MockSystemService(firmwareVersion: target))
        let uploader = OTAUploader(ota: ota, system: MockSystemService(), mtu: 247, reconnector: reconnector)

        await uploader.recover() // from .idle

        #expect(uploader.state == .idle)
        #expect(reconnector.reconnectCount == 0)
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
        #expect(!OTAUploader.State.recovering.isCancellable)
        #expect(!OTAUploader.State.recovered.isCancellable)
        #expect(!OTAUploader.State.complete.isCancellable)
        #expect(!OTAUploader.State.failed("x").isCancellable)
    }
}
