//
//  ChartDecimatorTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation
import Testing

@testable import Sentinel

/// The decimation engine is what keeps long capture sessions (tens of thousands
/// of samples) chartable, so its two invariants — bounded output and preserved
/// visual shape (endpoints + extremes) — are covered directly.
struct ChartDecimatorTests {
    private func series(_ values: [Double]) -> [ChartDataPoint] {
        values.enumerated().map { index, value in
            ChartDataPoint(sampleNumber: index + 1, secondsElapsed: Double(index), value: value)
        }
    }

    @Test func minMaxKeepsEndpointsAndExtremesWithinBudget() {
        var values = [Double](repeating: 0, count: 1000)
        values[500] = 100 // spike
        values[700] = -50 // dip
        let decimated = ChartDecimator.minMaxDecimated(series(values), targetPoints: 100)

        #expect(decimated.count <= 102) // ~targetPoints (+ retained endpoints)
        #expect(decimated.count < 1000)
        #expect(decimated.first?.sampleNumber == 1)
        #expect(decimated.last?.sampleNumber == 1000)
        #expect(decimated.contains { $0.value == 100 }) // peak survives
        #expect(decimated.contains { $0.value == -50 }) // trough survives
    }

    @Test func minMaxLeavesSmallSeriesUntouched() {
        let points = series([1, 2, 3, 4])
        #expect(ChartDecimator.minMaxDecimated(points, targetPoints: 100).count == 4)
    }

    @Test func transitionsOnlyKeepsOnlyChanges() {
        let points = series([0, 0, 0, 1, 1, 0, 0])
        let transitions = ChartDecimator.transitionsOnly(points)
        // Far fewer than the input, but the endpoints and both edges are present.
        #expect(transitions.count < points.count)
        #expect(transitions.first?.value == 0)
        #expect(transitions.last?.sampleNumber == 7)
        #expect(transitions.contains { $0.value == 1 })
    }

    @Test func slicePadsAroundTheRequestedRange() {
        let points = series((1 ... 100).map(Double.init))
        let sliced = ChartDecimator.slice(points, in: 40 ... 60)
        // Padded by one point on each side so the line reaches the viewport edges.
        #expect(sliced.first!.sampleNumber <= 40)
        #expect(sliced.last!.sampleNumber >= 60)
        #expect(sliced.first!.sampleNumber >= 38)
        #expect(sliced.last!.sampleNumber <= 62)
    }
}
