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

    /// Line severity. `Comparable` so a filter can express a threshold; `Codable`
    /// so a persisted filter can round-trip the enabled set.
    nonisolated enum Severity: Int, Comparable, Codable, Sendable {
        case info
        case warn
        case error

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Map a firmware `<level>` token to a severity.
        static func fromLevel(_ level: String) -> Severity {
            switch level.lowercased() {
            case "warn", "warning": .warn
            case "error", "err", "fatal", "critical": .error
            default: .info // info / debug / trace / verbose
            }
        }

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
    /// Source file the line came from (e.g. `sentinel_task_bme280_service.cpp`),
    /// parsed from `[file:line]`. Captured for future facet filtering (#44).
    let file: String?
    /// The firmware function that emitted the line (e.g. `run`, `init`), the token
    /// after `[file:line]`. Captured for future facet filtering (#44).
    let function: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        source: Source,
        severity: Severity,
        text: String,
        service: String? = nil,
        file: String? = nil,
        function: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.severity = severity
        self.text = text
        self.service = service
        self.file = file
        self.function = function
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

    /// Structured facets parsed from a device line.
    nonisolated struct DeviceFacets: Equatable, Sendable {
        var severity: Severity = .info
        var service: String?
        var file: String?
        var function: String?
    }

    /// Map one device-side debug line to a timeline line. The firmware format is
    /// `idx <ts> [file:line] function <level> service: message`; the full line is
    /// kept as the displayed text, and `<level>`, `service`, `file`, and `function`
    /// are parsed off it for filtering. Severity comes from `<level>` (falling back
    /// to a leading `[WARN]`/`[ERROR]` marker, then `info`) — **not** hardcoded, so
    /// warnings/errors classify correctly regardless of the emitting function.
    nonisolated static func fromDevice(_ raw: String, timestamp: Date = .now) -> DebugLogLine {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let facets = parseDeviceFacets(text)
        return DebugLogLine(
            timestamp: timestamp,
            source: .device,
            severity: facets.severity,
            text: text,
            service: facets.service,
            file: facets.file,
            function: facets.function
        )
    }

    /// Parse the structured firmware fields off a device line. Any field that
    /// doesn't match is left `nil` (and an un-tagged service is never hidden by the
    /// service filter). Robust to lines that only partially match the format.
    nonisolated static func parseDeviceFacets(_ text: String) -> DeviceFacets {
        var facets = DeviceFacets()

        // [file:line]
        if let open = text.firstIndex(of: "["), let close = text[open...].firstIndex(of: "]") {
            let inside = text[text.index(after: open) ..< close]
            facets.file = inside.split(separator: ":").first.map(String.init)

            // Everything after "]" — "function <level> service: message".
            let tail = text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
            facets.function = tail.split(separator: " ", maxSplits: 1).first.map(String.init)

            // <level>
            if let levelOpen = tail.firstIndex(of: "<"), let levelClose = tail[levelOpen...].firstIndex(of: ">") {
                let level = tail[tail.index(after: levelOpen) ..< levelClose]
                facets.severity = Severity.fromLevel(String(level))

                // service: token between "> " and the first ":".
                let afterLevel = tail[tail.index(after: levelClose)...]
                if let colon = afterLevel.firstIndex(of: ":") {
                    let candidate = afterLevel[..<colon].trimmingCharacters(in: .whitespaces)
                    if !candidate.isEmpty, !candidate.contains(" ") { facets.service = candidate }
                }
            }
        }

        // Fallback for an older leading-marker convention, when no <level> was found.
        if facets.severity == .info {
            let upper = text.uppercased()
            if upper.hasPrefix("[ERROR]") {
                facets.severity = .error
            } else if upper.hasPrefix("[WARN]") {
                facets.severity = .warn
            }
        }
        return facets
    }
}

// MARK: - Filter

/// The user-tunable filter applied to the merged buffer before display: which
/// sources to show, which severities to show (independently), which services are
/// muted, and a plain-text search. Value type so a change is a single observable
/// mutation on the view's `@State`.
nonisolated struct DebugLogFilter: Equatable, Sendable, Codable {
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

// MARK: - Persistence

/// JSON-backed `RawRepresentable` so the filter can persist across view instances
/// and app launches via `@AppStorage`. A corrupt/absent value falls back to the
/// default filter.
extension DebugLogFilter: RawRepresentable {
    nonisolated init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = decoded
    }

    nonisolated var rawValue: String {
        guard let data = try? JSONEncoder().encode(self), let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}
