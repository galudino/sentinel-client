//
//  DeviceReadiness.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 9/4/26.
//

import AsyncBluetooth
import Foundation

/// Firmware POST subsystem ids (`sentinel_post.hpp` `post_subsystem`). Used to
/// name a failed self-test in the readiness/degraded UI (and, going forward, the
/// POST event-log rows, which carry the same id). Append-only wire contract —
/// mirror firmware 1:1, never reuse or renumber a value.
nonisolated enum POSTSubsystem: UInt8, Sendable, CaseIterable {
    case bme280 = 0x01
    case ds3231 = 0x02
    case w25q128 = 0x03
    case recordStore = 0x04
    case bleStack = 0x05
    case rotaryEncoder = 0x10 // Phase II/III
    case display = 0x11 // Phase II/III

    /// Human-readable name for the degraded/POST UI.
    nonisolated var displayName: String {
        switch self {
        case .bme280: "BME280 climate sensor"
        case .ds3231: "DS3231 real-time clock"
        case .w25q128: "W25Q128 flash storage"
        case .recordStore: "flash record store"
        case .bleStack: "Bluetooth stack"
        case .rotaryEncoder: "rotary encoder"
        case .display: "display"
        }
    }
}

/// Coarse boot/POST state, byte 0 of the System `Device Readiness`
/// characteristic (`sentinel::diagnostics::device_readiness`, #69).
nonisolated enum DeviceReadinessState: UInt8, Sendable {
    case booting = 0x00 // pre-POST: building context / scanning flash stores
    case postRunning = 0x01 // POST probes executing
    case ready = 0x02 // POST passed; sensors live
    case degraded = 0x03 // POST reported a failure (see subsystem id)
}

/// Decoded value of the System `Device Readiness` characteristic (#69): a coarse
/// boot/POST `state` plus, when `degraded`, the failing POST subsystem id. The
/// client gates sensor-dependent UI on this so a central that connects mid-boot
/// never renders stale/zero sensor values as if real.
nonisolated struct DeviceReadiness: Equatable, Sendable {
    let state: DeviceReadinessState
    /// Failing `POSTSubsystem` id when `state == .degraded`; `0` otherwise.
    let failedSubsystemID: UInt8

    /// The named failed subsystem, or `nil` when not degraded / id unrecognized.
    nonisolated var failedSubsystem: POSTSubsystem? {
        state == .degraded ? POSTSubsystem(rawValue: failedSubsystemID) : nil
    }

    /// Sensors are live and safe to read/subscribe.
    nonisolated var isReady: Bool { state == .ready }

    /// Still coming up (booting or running POST) — show an initializing state,
    /// do not read sensor characteristics yet.
    nonisolated var isInitializing: Bool { state == .booting || state == .postRunning }

    /// A ready device (the common connected steady-state).
    nonisolated static let ready = DeviceReadiness(state: .ready, failedSubsystemID: 0)
}

// MARK: PeripheralDataConvertible — read readiness straight off the characteristic

extension DeviceReadiness: nonisolated PeripheralDataConvertible {
    /// Decode the 2-byte value `[state, failedSubsystem]`. Returns `nil` only for
    /// a short buffer; an unknown state byte reads as `booting`.
    nonisolated static func fromData(_ data: Data) -> DeviceReadiness? {
        guard data.count >= 2 else { return nil }
        let state = DeviceReadinessState(rawValue: data.u8(at: 0)) ?? .booting
        return DeviceReadiness(state: state, failedSubsystemID: data.u8(at: 1))
    }

    nonisolated func toData() -> Data? { Data([state.rawValue, failedSubsystemID]) }
}
