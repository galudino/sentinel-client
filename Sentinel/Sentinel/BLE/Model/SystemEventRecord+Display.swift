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
        case let .bootLifecycle(_, body):
            switch event {
            case .shutdownClean: "Clean shutdown"
            case .shutdownUnexpected: "Unexpected shutdown"
            default: "Boot complete (v\(body.firmwareVersion.shortVersion))"
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
        case .other: event.map { "\($0)" }?.humanized ?? "System event"
        case let .unknown(header, _): "Unknown event 0x\(String(header.eventTypeRaw, radix: 16, uppercase: true))"
        }
    }

    var displaySubtitle: String? {
        switch self {
        case let .firmwareUpdate(_, body): "v\(body.fromVersion.shortVersion) → v\(body.toVersion.shortVersion)"
        case let .bleConnection(_, body):
            event == .blePeripheralDisconnected
                ? "peer \(body.peerAddressString) · reason \(body.disconnectReason)"
                : "peer \(body.peerAddressString) · MTU \(body.peerMTU)"
        case let .modeChange(_, body): "\(body.fromMode) → \(body.toMode)"
        case let .fault(_, body): "id \(body.faultID) · severity \(body.severity) · subsystem \(body.subsystemID)"
        case let .post(_, body): event == .postPassed ? nil : "subsystem \(body.subsystemID) · result \(body.result)"
        case let .snapshot(_, body): "count \(body.snapshotCount)"
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

private extension String {
    /// "blePeripheralConnected" → "Ble peripheral connected" (rough humanize for
    /// the `.other` fallback title).
    var humanized: String {
        var out = ""
        for character in self {
            if character.isUppercase, !out.isEmpty { out += " " }
            out.append(character)
        }
        return out.prefix(1).uppercased() + out.dropFirst().lowercased()
    }
}
