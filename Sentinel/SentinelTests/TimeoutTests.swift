//
//  TimeoutTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation
import Testing

@testable import Sentinel

/// The `withThrowingTimeout` helper behind the router's 15 s connect budget (#13),
/// exercised with tiny durations so the tests stay fast.
struct TimeoutTests {
    @Test func returnsResultWhenOperationBeatsTheClock() async throws {
        let value = try await withThrowingTimeout(.seconds(1)) { 42 }
        #expect(value == 42)
    }

    @Test func throwsTimeoutWhenOperationIsTooSlow() async {
        await #expect(throws: TimeoutError.self) {
            try await withThrowingTimeout(.milliseconds(20)) {
                try await Task.sleep(for: .seconds(5))
                return 0
            }
        }
    }

    @Test func propagatesTheOperationsOwnError() async {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await withThrowingTimeout(.seconds(1)) { throw Boom() }
        }
    }
}
