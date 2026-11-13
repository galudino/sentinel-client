//
//  SystemEventRecord+Display.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation

/// The view-facing rendering API for ``SystemEventRecord``. Views render these
/// three; the typed bodies stay for a detail sheet that wants every field.
extension SystemEventRecord {
    var displayTitle: String {
        switch self {
        case .bootLifecycle:
            switch event {
            case .shutdownClean: "Clean shutdown"
            case .shutdownUnexpected: "Unexpected shutdown"
            default: "Boot complete"
            }
        case .firmwareUpdate:
            switch event {
            case .firmwareUpdateCompleted: "Firmware update completed"
            case .firmwareUpdateFailed: "Firmware update failed"
            case .firmwareReverted: "Firmware reverted"
            default: "Firmware update attempted"
            }
        case .bleConnection:
            event == .blePeripheralConnected ? "BLE connected" : "BLE disconnected"
        case .modeChange: "Mode changed"
        case .fault: event == .faultRaised ? "Fault raised" : "Fault cleared"
        case .post: event == .postPassed ? "POST passed" : "POST subsystem failed"
        case let .snapshot(_, body): body.reason == 1 ? "Pre-fault snapshot" : "Snapshot persisted"
        case .other: event?.displayName ?? "System event"
        case .unknown: "Unknown event"
        }
    }

    var displaySubtitle: String? {
        switch self {
        case let .bootLifecycle(_, body):
            // The running firmware version rides as the subtitle (boot only); the
            // title stays a plain "Boot complete".
            event == .bootComplete ? "v\(body.firmwareVersion.shortVersion)" : nil
        case let .firmwareUpdate(_, body): "v\(body.fromVersion.shortVersion) → v\(body.toVersion.shortVersion)"
        case let .bleConnection(_, body):
            event == .blePeripheralDisconnected
                ? "peer \(body.peerAddressString) · reason \(body.disconnectReason)"
                : "peer \(body.peerAddressString) · MTU \(body.peerMTU)"
        case let .modeChange(_, body): "\(body.fromMode) → \(body.toMode)"
        case let .fault(_, body): "id \(body.faultID) · severity \(body.severity) · subsystem \(body.subsystemID)"
        case let .post(_, body): event == .postPassed ? nil : "subsystem \(body.subsystemID) · result \(body.result)"
        case let .snapshot(_, body): "count \(body.snapshotCount)"
        case let .unknown(header, _): "type 0x\(String(header.eventTypeRaw, radix: 16, uppercase: true))"
        default: nil
        }
    }

    var iconSystemName: String {
        switch self {
        case .bootLifecycle: "power"
        case .firmwareUpdate: "arrow.down.circle"
        case .bleConnection: "dot.radiowaves.left.and.right"
        case .modeChange: "arrow.triangle.2.circlepath"
        case .fault: "exclamationmark.triangle"
        case .post: event == .postPassed ? "checkmark.seal" : "xmark.seal"
        case .snapshot: "camera.viewfinder"
        case .other: "gearshape"
        case .unknown: "questionmark.circle"
        }
    }
}

extension SystemEvent {
    /// Acronyms kept upper-cased in generated titles. **Single source of truth** for
    /// the `.other` fallback (and any other generated event copy), so a case like
    /// `rtcSetFromBLE` reads "RTC set from BLE" rather than "Rtc set from b l e".
    /// Extend this as new acronyms appear in the `SystemEvent` vocabulary.
    nonisolated static let titleAcronyms: Set<String> = [
        "BLE", "RPM", "RTC", "POST", "CPU", "MTU", "GATT", "OTA", "DFU", "RSSI",
        "ID", "LED", "ADC", "MCU", "FW", "HW"
    ]

    /// A human-readable title generated from the case name, with acronyms preserved —
    /// `rtcSetFromBLE` → "RTC set from BLE", `fanRPMThresholdChanged` → "Fan RPM
    /// threshold changed". Used by the `.other` event fallback in
    /// ``SystemEventRecord/displayTitle`` so generated titles read uniformly with the
    /// explicit ones; events with a dedicated title never reach this.
    nonisolated var displayName: String {
        String(describing: self).titleCased(preservingAcronyms: Self.titleAcronyms)
    }
}

private extension String {
    /// Split a `camelCase` / acronym identifier into words and render it as a
    /// sentence-case title: the first word is capitalized and the rest lower-cased,
    /// except any word whose upper-cased form is in `acronyms`, which stays upper.
    nonisolated func titleCased(preservingAcronyms acronyms: Set<String>) -> String {
        let words = camelCaseWords
        guard !words.isEmpty else { return self }
        return words.enumerated()
            .map { index, word in
                if acronyms.contains(word.uppercased()) { return word.uppercased() }
                let lowered = word.lowercased()
                guard index == 0, let first = lowered.first else { return lowered }
                return first.uppercased() + lowered.dropFirst()
            }
            .joined(separator: " ")
    }

    /// Tokenize a `camelCase` identifier into words, keeping acronym runs intact:
    /// a boundary starts at a lower→upper transition (`fanTemperature` →
    /// `fan`,`Temperature`) and at the end of an upper-case run that precedes a new
    /// word (`RPMThreshold` → `RPM`,`Threshold`; `BLEStack` → `BLE`,`Stack`).
    nonisolated var camelCaseWords: [String] {
        let chars = Array(self)
        guard !chars.isEmpty else { return [] }
        var words: [String] = []
        var current = String(chars[0])
        for index in 1 ..< chars.count {
            let character = chars[index]
            let previous = chars[index - 1]
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            let startsLowerToUpper = character.isUppercase && previous.isLowercase
            let endsAcronymRun = character.isUppercase && previous.isUppercase
                && (next?.isLowercase ?? false)
            if startsLowerToUpper || endsAcronymRun {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        words.append(current)
        return words
    }
}
