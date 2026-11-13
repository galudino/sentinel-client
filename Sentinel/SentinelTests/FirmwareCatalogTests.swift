//
//  FirmwareCatalogTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/18/26.
//

import Foundation
import Testing

@testable import Sentinel

/// Covers #20's source/recommend logic: file-name parsing (incl. the pre-release
/// flag), stable-only recommendation, and that the real bundled `.bin`s ship + parse.
@MainActor
struct FirmwareCatalogTests {
    // MARK: File-name parsing

    @Test func parsesConventionName() {
        let parsed = FirmwareCatalog.parse(fileName: "sentinel-firmware_1.0.1.bin")
        #expect(parsed?.version == FirmwareVersion(major: 1, minor: 0, patch: 1, build: 0))
        #expect(parsed?.displayName == "1.0.1")
        #expect(parsed?.isPrerelease == false)
    }

    @Test func parsesPrereleaseLabel() {
        let parsed = FirmwareCatalog.parse(fileName: "sentinel-firmware_255.255.255-test.bin")
        // Numeric version drops the label; the display label keeps it; flagged pre-release.
        #expect(parsed?.version == FirmwareVersion(major: 255, minor: 255, patch: 255, build: 0))
        #expect(parsed?.displayName == "255.255.255-test")
        #expect(parsed?.isPrerelease == true)
    }

    @Test func parsesVersionAfterLastUnderscoreWithoutPrefix() {
        let parsed = FirmwareCatalog.parse(fileName: "build_2.3.4-rc1.bin")
        #expect(parsed?.version == FirmwareVersion(major: 2, minor: 3, patch: 4, build: 0))
        #expect(parsed?.displayName == "2.3.4-rc1")
        #expect(parsed?.isPrerelease == true)
    }

    @Test func rejectsUnparseableName() {
        #expect(FirmwareCatalog.parse(fileName: "random-notes.bin") == nil)
    }

    // MARK: Recommendation (stable-only)

    private var v100: FirmwareImage { FirmwareImage(version: "1.0.0") }
    private var v101: FirmwareImage { FirmwareImage(version: "1.0.1") }
    private var vTest: FirmwareImage { FirmwareImage(version: "255.255.255-test") }

    @Test func recommendsNewestStableNewerThanInstalled() {
        let installed = FirmwareVersion(major: 1, minor: 0, patch: 0, build: 0)
        let recommended = FirmwareCatalog.recommended(installed: installed, among: [v100, v101])
        #expect(recommended?.version == FirmwareVersion(major: 1, minor: 0, patch: 1, build: 0))
    }

    @Test func recommendsNothingWhenUpToDate() {
        let installed = FirmwareVersion(major: 1, minor: 0, patch: 1, build: 0)
        #expect(FirmwareCatalog.recommended(installed: installed, among: [v100, v101]) == nil)
    }

    @Test func recommendsNothingWhenAhead() {
        let installed = FirmwareVersion(major: 2, minor: 0, patch: 0, build: 0)
        #expect(FirmwareCatalog.recommended(installed: installed, among: [v100, v101]) == nil)
    }

    @Test func excludesPrereleaseFromRecommend() {
        // The 255.255.255-test pre-release is newer than everything, but must NOT
        // be recommended — the newest *stable* (1.0.1) is.
        let installed = FirmwareVersion(major: 1, minor: 0, patch: 0, build: 0)
        let recommended = FirmwareCatalog.recommended(installed: installed, among: [v101, vTest])
        #expect(recommended?.version == FirmwareVersion(major: 1, minor: 0, patch: 1, build: 0))
        #expect(recommended?.isPrerelease == false)
    }

    @Test func recommendsNothingWhenOnlyPrereleasesAreNewer() {
        let installed = FirmwareVersion(major: 1, minor: 0, patch: 1, build: 0)
        #expect(FirmwareCatalog.recommended(installed: installed, among: [vTest]) == nil)
    }

    // MARK: Bundled resources (integration — proves the .bin files ship + parse)

    @Test func bundledImagesShipAndParse() {
        // Anchor on an app-module type so this resolves to the app bundle that
        // carries Resources/Firmware, not the test bundle.
        let bundle = Bundle(for: BluetoothManager.self)
        let images = FirmwareCatalog.bundledImages(in: bundle)
        // fw v1.0.2 bundle: stock 1.0.2.0, its +50 DFU target 51.0.2.0-test, the
        // two -testbench images, and the 0-byte 0.0.0.0-empty rejection image.
        let v102 = FirmwareVersion(major: 1, minor: 0, patch: 2, build: 0)
        let vTest = FirmwareVersion(major: 51, minor: 0, patch: 2, build: 0)

        let versions = Set(images.map(\.version))
        #expect(versions.contains(v102)) // real 1.0.2.0 (recommended baseline)
        #expect(versions.contains(vTest)) // 51.0.2.0-test (+50 DFU target)
        // Newest-first ordering.
        #expect(images.first?.version == images.map(\.version).max())
        // Every 51.0.2.0 image (-test, -testbench) is pre-release; the stock
        // 1.0.2.0 is stable (its -testbench twin shares the version, so look
        // for the unlabeled one).
        let testImagesArePrerelease = images
            .filter { $0.version == vTest }
            .allSatisfy(\.isPrerelease)
        let stockIsStable = images.contains { $0.version == v102 && !$0.isPrerelease }
        #expect(testImagesArePrerelease)
        #expect(stockIsStable)
        // Real signed MCUBoot images carry the header magic 0x96f3b83d (LE).
        if let latest = images.first {
            #expect(latest.data.count > 1000)
            #expect(latest.data.prefix(4) == Data([0x3D, 0xB8, 0xF3, 0x96]))
        }
    }
}
