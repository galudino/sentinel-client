//
//  DeviceSnapshotProviderTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation
import Testing

@testable import Sentinel

/// The provider's keyPath → value extraction is the contract between the field
/// catalog and the capture engine; a typo in either would silently drop a field.
/// These tests pin the mapping and guarantee every advertised field resolves.
@MainActor
struct DeviceSnapshotProviderTests {
    private var provider: DeviceSnapshotDataProvider {
        DeviceSnapshotDataProvider(stream: MockSnapshotStreamService())
    }

    @Test func everyAdvertisedFieldExtractsWithoutError() {
        let sample = DeviceSnapshot.sample
        for field in DeviceSnapshot.availableFields() {
            let value = provider.extractValue(from: sample, keyPath: field.keyPath)
            if case .error = value {
                Issue.record("Field \(field.keyPath) extracted an error value")
            }
        }
    }

    @Test func unknownKeyPathReportsError() {
        if case .error = provider.extractValue(from: .sample, keyPath: "nope") {
            // expected
        } else {
            Issue.record("Unknown keyPath should extract .error")
        }
    }

    @Test func derivedEngineeringUnitsAreExtracted() {
        let sample = DeviceSnapshot.sample // temp 23.45 °C, humidity 45.67 %RH

        let temperature = provider.extractValue(from: sample, keyPath: "temperatureCelsius").numericValue
        #expect(temperature != nil)
        #expect(abs((temperature ?? 0) - 23.45) < 0.001)

        #expect(
            provider.extractValue(from: sample, keyPath: "humidityPercent").numericValue
                .map { abs($0 - 45.67) < 0.001 } == true
        )
        #expect(provider.extractValue(from: sample, keyPath: "bleConnected").boolValue == true)
        #expect(provider.extractValue(from: sample, keyPath: "postPassed").boolValue == true)
        #expect(provider.extractValue(from: sample, keyPath: "eventLogRecordCount") == .uint32(12))
    }

    @Test func fieldTypesAreChartabilityConsistent() {
        // Every numeric-typed field must produce a numeric value, and every bool a bool.
        let sample = DeviceSnapshot.sample
        for field in DeviceSnapshot.availableFields() {
            let value = provider.extractValue(from: sample, keyPath: field.keyPath)
            if field.dataType.isNumeric {
                #expect(value.numericValue != nil, "\(field.keyPath) should be numeric")
            } else if field.dataType == .bool {
                #expect(value.boolValue != nil, "\(field.keyPath) should be boolean")
            }
        }
    }
}
