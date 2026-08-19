//
//  FirmwareVersionTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/18/26.
//

import Foundation
import Testing

@testable import Sentinel

/// Covers the ``FirmwareVersion`` additions the DFU flow relies on: dotted-string
/// parsing (#20 selection) and ordering (#20 recommend, #22 confirm).
struct FirmwareVersionTests {
    @Test func parsesThreeComponents() {
        let version = FirmwareVersion(parsing: "1.2.3")
        #expect(version == FirmwareVersion(major: 1, minor: 2, patch: 3, build: 0))
    }

    @Test func parsesFourComponentsWithBuild() {
        let version = FirmwareVersion(parsing: "1.2.3.45")
        #expect(version == FirmwareVersion(major: 1, minor: 2, patch: 3, build: 45))
    }

    @Test func rejectsMalformedStrings() {
        #expect(FirmwareVersion(parsing: "1.2") == nil)
        #expect(FirmwareVersion(parsing: "1.2.3.4.5") == nil)
        #expect(FirmwareVersion(parsing: "x.y.z") == nil)
        #expect(FirmwareVersion(parsing: "") == nil)
        #expect(FirmwareVersion(parsing: "300.0.0") == nil) // 300 overflows UInt8
    }

    @Test func ordersByComponentPrecedence() {
        #expect(
            FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16)
                < FirmwareVersion(major: 1, minor: 0, patch: 1, build: 0)
        )
        #expect(
            FirmwareVersion(major: 1, minor: 2, patch: 3, build: 0)
                < FirmwareVersion(major: 1, minor: 2, patch: 3, build: 1)
        )
        #expect(
            FirmwareVersion(major: 0, minor: 9, patch: 9, build: 99)
                < FirmwareVersion(major: 1, minor: 0, patch: 0, build: 0)
        )
    }

    @Test func equalVersionsAreNotLess() {
        let version = FirmwareVersion(major: 2, minor: 1, patch: 4, build: 7)
        #expect(!(version < version))
        #expect(version == FirmwareVersion(major: 2, minor: 1, patch: 4, build: 7))
    }
}
