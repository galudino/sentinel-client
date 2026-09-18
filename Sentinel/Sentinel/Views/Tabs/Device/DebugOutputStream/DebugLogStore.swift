//
//  DebugLogStore.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 9/17/26.
//

import Foundation
import Observation

/// App-wide, runtime-lifetime buffer for the merged debug timeline (#25).
///
/// The store — not the view — owns the lines, so they **persist across view
/// instances**: opening `DebugOutputStreamView`, leaving, and returning shows the
/// same history, and events that happened *before* the console was opened (the
/// scan → connect → discovery handshake) are already here. `RootView` feeds it for
/// the whole app run: local BLE events for the app's lifetime, and — while
/// connected and Debug streaming is enabled — the device's own debug output.
///
/// Created once in `SentinelApp` and injected app-wide, like `BluetoothManager`.
/// It is a pure buffer: it does not subscribe to anything itself (the feeders live
/// in `RootView`'s `.task`s, matching the codebase's view-owned-stream idiom), so
/// it stays trivially testable.
@MainActor
@Observable
final class DebugLogStore {
    /// The merged buffer, oldest → newest.
    private(set) var lines: [DebugLogLine] = []

    /// Monotonic count of every line ever appended (never decremented by eviction).
    /// The console observes this — not `lines.count`, which plateaus at the cap —
    /// to detect arrivals for the "N new" banner and auto-scroll even at capacity.
    private(set) var appendCount = 0

    /// Whether the floating debug console is on screen. Lives here (rather than as
    /// a separate presenter) so any entry point can raise the console with one
    /// mutation and `RootView` can bind a single `.sheet` to it — the console then
    /// floats above whatever root state is active and survives the
    /// scanning → connecting → connected transitions.
    var isConsolePresented = false

    /// Upper bound on retained lines; the oldest are dropped past this.
    private let maxLines: Int

    /// How far back an out-of-order line may be inserted by timestamp — bounds the
    /// reordering work when the two sources interleave (the issue's "small
    /// reordering window", as a count).
    private let reorderWindow = 64

    init(maxLines: Int = 10000) {
        self.maxLines = maxLines
    }

    /// Append a line, keeping the buffer roughly timestamp-ordered and bounded. A
    /// line older than the tail is inserted back among the last ``reorderWindow``
    /// entries; beyond that window it is appended as-is (bounded work, no reindex).
    func append(_ line: DebugLogLine) {
        appendCount += 1
        if let last = lines.last, line.timestamp < last.timestamp {
            let floor = max(0, lines.count - reorderWindow)
            var index = lines.count
            while index > floor, lines[index - 1].timestamp > line.timestamp {
                index -= 1
            }
            lines.insert(line, at: index)
        } else {
            lines.append(line)
        }
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    /// Empty the buffer (the console's Clear action). Collection continues — new
    /// activity keeps appending.
    func clear() {
        lines.removeAll()
    }
}

#if DEBUG
    extension DebugLogStore {
        /// A store pre-seeded with synthetic lines, for previews of
        /// `DebugOutputStreamView` with no BLE. Lines are appended in order with
        /// increasing timestamps so they render exactly as collected.
        static func preview(lines: [DebugLogLine] = DebugLogLine.previewTimeline()) -> DebugLogStore {
            let store = DebugLogStore()
            for line in lines {
                store.append(line)
            }
            return store
        }
    }

    extension DebugLogLine {
        /// A representative merged timeline (local handshake + device output,
        /// including parsed `[WARN]`/`[ERROR]` markers) for previews.
        static func previewTimeline(start: Date = .now.addingTimeInterval(-20)) -> [DebugLogLine] {
            var stamp = start
            func next() -> Date { stamp = stamp.addingTimeInterval(0.4); return stamp }
            return [
                DebugLogLine(timestamp: next(), source: .local, severity: .info, text: "Scan started"),
                DebugLogLine(timestamp: next(), source: .local, severity: .info, text: "Discovered Sentinel"),
                DebugLogLine(timestamp: next(), source: .local, severity: .info, text: "Connecting to Sentinel"),
                DebugLogLine(timestamp: next(), source: .local, severity: .info, text: "Discovering services"),
                DebugLogLine(timestamp: next(), source: .local, severity: .info, text: "Connected (MTU 247)"),
                DebugLogLine(timestamp: next(), source: .device, severity: .info, text: "POST: pass"),
                DebugLogLine(timestamp: next(), source: .device, severity: .info, text: "RTC synced via SQW (P6_3)"),
                DebugLogLine(
                    timestamp: next(),
                    source: .device,
                    severity: .info,
                    text: "bme280 sample: T=22.05 H=48.2 P=1013.0"
                ),
                DebugLogLine(timestamp: next(), source: .device, severity: .warn, text: "snapshot store 80% full"),
                DebugLogLine(timestamp: next(), source: .device, severity: .error, text: "i2c timeout on retry 2")
            ]
        }
    }
#endif
