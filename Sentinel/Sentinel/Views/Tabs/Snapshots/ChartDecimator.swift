//
//  ChartDecimator.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - ChartableField

/// A numeric or boolean field of a snapshot that can be plotted.
nonisolated struct ChartableField: Identifiable {
    let keyPath: String
    let displayName: String
    let unit: String
    let dataType: SnapshotFieldDataType

    var id: String { keyPath }
}

// MARK: - ChartDataPoint

/// One plotted sample: its 1-based sample number, seconds since session start, and value.
nonisolated struct ChartDataPoint: Identifiable {
    let id: Int // sampleNumber is unique per series — stable id avoids per-frame UUIDs
    let sampleNumber: Int
    let secondsElapsed: TimeInterval
    let value: Double

    init(sampleNumber: Int, secondsElapsed: TimeInterval, value: Double) {
        id = sampleNumber
        self.sampleNumber = sampleNumber
        self.secondsElapsed = secondsElapsed
        self.value = value
    }
}

// MARK: - ChartDecimator

/// Reduces a dense series to a small displayed series **without losing visual
/// shape** — the core of keeping long capture sessions (30–60 min, tens of
/// thousands of samples) scrollable and zoomable at ~60fps. Only the *displayed*
/// series is decimated; full resolution stays on disk and in exports.
///
/// Numeric series use **min/max per bucket**: each bucket contributes its extreme
/// low and high points (in sample order), so peaks and troughs survive even at
/// aggressive reduction. Boolean/step series keep only **transitions**, which is
/// both exact and tiny.
nonisolated enum ChartDecimator {
    /// Target displayed points for the inline preview chart.
    static let inlineTargetPoints = 400
    /// Target displayed points for the interactive full-screen chart viewport.
    static let fullScreenTargetPoints = 1200

    /// Min/max-per-bucket decimation to at most ~`targetPoints` points. Returns the
    /// input unchanged when it's already small enough.
    static func minMaxDecimated(_ points: [ChartDataPoint], targetPoints: Int) -> [ChartDataPoint] {
        let count = points.count
        guard targetPoints >= 4, count > targetPoints else { return points }

        // Two points (min + max) per bucket, plus the retained endpoints.
        let bucketCount = max(1, targetPoints / 2)
        let step = Double(count) / Double(bucketCount)

        var result: [ChartDataPoint] = []
        result.reserveCapacity(bucketCount * 2 + 2)
        result.append(points[0])

        for bucket in 0 ..< bucketCount {
            let start = Int(Double(bucket) * step)
            let end = min(count, Int(Double(bucket + 1) * step))
            guard start < end else { continue }

            var minPoint = points[start]
            var maxPoint = points[start]
            for index in (start + 1) ..< end {
                let point = points[index]
                if point.value < minPoint.value { minPoint = point }
                if point.value > maxPoint.value { maxPoint = point }
            }

            // Emit in sample order so the drawn line doesn't zig-zag backwards.
            if minPoint.sampleNumber <= maxPoint.sampleNumber {
                result.append(minPoint)
                if maxPoint.sampleNumber != minPoint.sampleNumber { result.append(maxPoint) }
            } else {
                result.append(maxPoint)
                result.append(minPoint)
            }
        }

        if let last = points.last, last.sampleNumber != result.last?.sampleNumber {
            result.append(last)
        }
        return result
    }

    /// Keep only points where the value changes, plus the endpoints — exact for
    /// step/boolean series and dramatically smaller.
    static func transitionsOnly(_ points: [ChartDataPoint]) -> [ChartDataPoint] {
        guard points.count > 2 else { return points }
        var result: [ChartDataPoint] = [points[0]]
        for index in 1 ..< points.count where points[index].value != points[index - 1].value {
            if result.last?.sampleNumber != points[index - 1].sampleNumber {
                result.append(points[index - 1]) // hold the level up to the transition
            }
            result.append(points[index])
        }
        if let last = points.last, last.sampleNumber != result.last?.sampleNumber {
            result.append(last)
        }
        return result
    }

    /// The sub-range of `points` whose sample numbers fall within `range`, padded by
    /// one point on each side so the line reaches the viewport edges. Used for
    /// viewport-aware re-decimation on zoom/scrub.
    static func slice(_ points: [ChartDataPoint], in range: ClosedRange<Int>) -> [ChartDataPoint] {
        guard !points.isEmpty else { return points }
        var lower = points.firstIndex { $0.sampleNumber >= range.lowerBound } ?? points.startIndex
        var upper = points.lastIndex { $0.sampleNumber <= range.upperBound } ?? (points.endIndex - 1)
        if lower > points.startIndex { lower -= 1 }
        if upper < points.endIndex - 1 { upper += 1 }
        guard lower <= upper else { return [] }
        return Array(points[lower ... upper])
    }
}

// MARK: - ChartMath

/// Axis normalization + label formatting shared by the session and full-screen
/// charts (two independently-scaled series share one 0…1 plotting range).
nonisolated enum ChartMath {
    /// The value range of a series, padded 10% top and bottom. `(0, 1)` when empty.
    static func paddedRange(_ points: [ChartDataPoint]) -> ClosedRange<Double> {
        guard !points.isEmpty else { return 0 ... 1 }
        let values = points.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let padding = (maxValue - minValue) * 0.1
        let lower = minValue - padding
        let upper = maxValue + padding
        return lower < upper ? lower ... upper : lower ... (lower + 1)
    }

    static func normalize(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard range.upperBound != range.lowerBound else { return 0.5 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    static func denormalize(_ normalized: Double, in range: ClosedRange<Double>) -> Double {
        range.lowerBound + normalized * (range.upperBound - range.lowerBound)
    }

    static func axisLabel(_ value: Double) -> String {
        if abs(value) >= 1000 { return String(format: "%.0f", value) }
        if abs(value) >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }
}
