//
//  DeviceReadinessTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 9/4/26.
//

import Foundation
import Testing

@testable import Sentinel

struct DeviceReadinessTests {
    @Test func decodesEachState() {
        #expect(DeviceReadiness.fromData(Data([0, 0]))?.state == .booting)
        #expect(DeviceReadiness.fromData(Data([1, 0]))?.state == .postRunning)
        #expect(DeviceReadiness.fromData(Data([2, 0]))?.state == .ready)
        #expect(DeviceReadiness.fromData(Data([3, 0x01]))?.state == .degraded)
    }

    @Test func degradedCarriesFailedSubsystem() {
        let readiness = DeviceReadiness.fromData(Data([3, POSTSubsystem.bme280.rawValue]))
        #expect(readiness?.failedSubsystem == .bme280)
        #expect(readiness?.isReady == false)
        #expect(readiness?.isInitializing == false) // degraded is terminal, not initializing
    }

    @Test func failedSubsystemIsNilUnlessDegraded() {
        // A ready state never reports a failed subsystem even if the byte is set.
        let ready = DeviceReadiness(state: .ready, failedSubsystemID: POSTSubsystem.bme280.rawValue)
        #expect(ready.failedSubsystem == nil)
        #expect(ready.isReady)
    }

    @Test func initializingCoversBootingAndPost() {
        #expect(DeviceReadiness(state: .booting, failedSubsystemID: 0).isInitializing)
        #expect(DeviceReadiness(state: .postRunning, failedSubsystemID: 0).isInitializing)
        #expect(!DeviceReadiness(state: .ready, failedSubsystemID: 0).isInitializing)
    }

    @Test func unknownStateByteReadsAsBooting() {
        #expect(DeviceReadiness.fromData(Data([0xFF, 0]))?.state == .booting)
    }

    @Test func shortBufferFailsToDecode() {
        #expect(DeviceReadiness.fromData(Data([2])) == nil)
        #expect(DeviceReadiness.fromData(Data()) == nil)
    }

    @Test func roundTripsThroughData() throws {
        let original = DeviceReadiness(state: .degraded, failedSubsystemID: POSTSubsystem.ds3231.rawValue)
        let data = try #require(original.toData())
        #expect(DeviceReadiness.fromData(data) == original)
    }
}
