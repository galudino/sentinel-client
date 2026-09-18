//
//  DebugLogModel.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 9/17/26.
//

import Foundation

/// One line in the merged debug timeline shown by ``DebugOutputStreamView`` (#25).
///
/// Two producers feed the timeline and both normalize to this shape:
/// - **local** — this app's BLE lifecycle events from
///   ``BluetoothManager/bluetoothEventStream()`` (`•`).
/// - **device** — the sentinel firmware's own debug output from
///   ``DebugStreamService`` (`→`).
///
/// The line carries the *local* arrival timestamp (both sources are stamped when
/// the app observes them — there is no device-side clock on the debug stream), a
/// source, a severity, and the message text.
nonisolated struct DebugLogLine: Identifiable, Hashable, Sendable {
    /// Which producer emitted the line.
    nonisolated enum Source: Sendable {
        /// This app's BLE stack (`•`).
        case local
        /// The sentinel firmware (`→`).
        case device

        /// The single-character source glyph used in the row.
        var glyph: String { self == .local ? "•" : "→" }
    }

    /// Line severity. `Comparable` so a filter can express a *minimum* threshold
    /// (`>= .warn` shows warnings and errors).
    nonisolated enum Severity: Int, Comparable, Sendable {
        case info
        case warn
        case error

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Fixed-width label for the monospaced row (`err ` pads to four columns).
        var label: String {
            switch self {
            case .info: "info"
            case .warn: "warn"
            case .error: "err "
            }
        }
    }

    let id: UUID
    let timestamp: Date
    let source: Source
    let severity: Severity
    let text: String
    /// The originating firmware task/service (e.g. `bme280_service`, `rtc_service`)
    /// parsed from a device line, for per-service filtering. `nil` for local events
    /// and unparseable device lines (those are never hidden by the service filter).
    let service: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        source: Source,
        severity: Severity,
        text: String,
        service: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.severity = severity
        self.text = text
        self.service = service
    }
}

// MARK: - Source adapters

extension DebugLogLine {
    /// Map a local ``BluetoothLogEvent`` to a timeline line. `BluetoothLogEvent`
    /// carries a *category* rather than a severity, so only
    /// ``BluetoothLogEvent/Category/error`` becomes ``Severity/error``; every other
    /// category is informational. The event's own id/timestamp are preserved so a
    /// line is stable across re-filters.
    nonisolated static func from(_ event: BluetoothLogEvent) -> DebugLogLine {
        DebugLogLine(
            id: event.id,
            timestamp: event.timestamp,
            source: .local,
            severity: event.category == .error ? .error : .info,
            text: event.message
        )
    }

    /// Map one device-side debug line to a timeline line. Phase I treats device
    /// lines as ``Severity/info`` unless the firmware prefixes them with a
    /// severity marker (`[WARN]` / `[ERROR]`, case-insensitive), in which case the
    /// marker is parsed and stripped from the displayed text.
    nonisolated static func fromDevice(_ raw: String, timestamp: Date = .now) -> DebugLogLine {
        let (severity, text) = parseDeviceSeverity(raw)
        return DebugLogLine(
            timestamp: timestamp,
            source: .device,
            severity: severity,
            text: text,
            service: parseService(text)
        )
    }

    /// Extract the firmware service tag from a device line. The firmware format is
    /// `NNNN <ts> [file.cpp:line] run <sev> <service>: message`, so the token
    /// between `run <sev> ` and the first `:` is the service (e.g. `bme280_service`,
    /// `rtc_service`, `cpu_die_temp`). Returns `nil` if the line doesn't match —
    /// such lines are treated as un-tagged and never hidden by the service filter.
    nonisolated static func parseService(_ text: String) -> String? {
        guard let runRange = text.range(of: "] run <") else { return nil }
        let afterRun = text[runRange.upperBound...]
        guard let sevEnd = afterRun.range(of: "> ") else { return nil }
        let afterSeverity = afterRun[sevEnd.upperBound...]
        guard let colon = afterSeverity.firstIndex(of: ":") else { return nil }
        let candidate = afterSeverity[..<colon]
        guard !candidate.isEmpty, !candidate.contains(" ") else { return nil }
        return String(candidate)
    }

    /// Parse a leading `[WARN]` / `[ERROR]` marker (case-insensitive) off a device
    /// line, returning the severity and the remaining text. Unmarked lines are
    /// ``Severity/info``. The raw line is whitespace-trimmed first.
    private nonisolated static func parseDeviceSeverity(_ raw: String) -> (Severity, String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers: [(String, Severity)] = [("[ERROR]", .error), ("[WARN]", .warn)]
        for (marker, severity) in markers where trimmed.uppercased().hasPrefix(marker) {
            let body = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return (severity, body)
        }
        return (.info, trimmed)
    }
}

// MARK: - Filter

/// The user-tunable filter applied to the merged buffer before display: which
/// sources to show, which severities to show (independently), which services are
/// muted, and a plain-text search. Value type so a change is a single observable
/// mutation on the view's `@State`.
nonisolated struct DebugLogFilter: Equatable, Sendable {
    var showLocal = true
    var showDevice = true
    /// Severities currently shown; all three by default. Independent toggles rather
    /// than a single minimum threshold.
    var severities: Set<DebugLogLine.Severity> = [.info, .warn, .error]
    /// Services the user has hidden. Empty by default — a newly-seen service shows
    /// until explicitly muted (so new output is never silently dropped).
    var mutedServices: Set<String> = []
    var searchText = ""

    static let allSeverities: Set<DebugLogLine.Severity> = [.info, .warn, .error]

    /// The filtered view of `lines`, in the same order.
    func apply(to lines: [DebugLogLine]) -> [DebugLogLine] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lines.filter { line in
            switch line.source {
            case .local where !showLocal: return false
            case .device where !showDevice: return false
            default: break
            }
            guard severities.contains(line.severity) else { return false }
            if let service = line.service, mutedServices.contains(service) { return false }
            if !query.isEmpty, !line.text.lowercased().contains(query) { return false }
            return true
        }
    }

    /// Whether the filter narrows anything — drives the toolbar button's "active"
    /// badge so the user can tell the list is filtered.
    var isActive: Bool {
        !showLocal || !showDevice || severities != Self.allSeverities || !mutedServices.isEmpty
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
