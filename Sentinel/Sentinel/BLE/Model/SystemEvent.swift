//
//  SystemEvent.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation

/// The event-type discriminator carried in a `system_event_record` header
/// (byte 4). Mirrors firmware `sentinel::diagnostics::system_event`
/// (`sentinel_system_event.hpp`, firmware #34) value-for-value.
enum SystemEvent: UInt8, Sendable {
    // Boot / lifecycle
    case bootComplete = 0x01
    case shutdownClean = 0x02
    case shutdownUnexpected = 0x03
    case firmwareUpdateAttempted = 0x04
    case firmwareUpdateCompleted = 0x05
    case firmwareUpdateFailed = 0x06
    case firmwareReverted = 0x07
    // POST
    case postPassed = 0x10
    case postSubsystemFailed = 0x11
    // Configuration
    case configChanged = 0x20
    case configResetToDefault = 0x21
    case rtcSetFromBLE = 0x22
    case serialNumberSet = 0x23
    // BLE
    case bleStackInitialized = 0x30
    case bleStackDeinitialized = 0x31
    case blePeripheralConnected = 0x32
    case blePeripheralDisconnected = 0x33
    case blePaired = 0x34
    case bleUnpaired = 0x35
    // Operational
    case modeChanged = 0x40
    case faultRaised = 0x41
    case faultCleared = 0x42
    case userInput = 0x43
    case sensorThresholdCrossed = 0x44
    case snapshotPersisted = 0x45
    case preFaultSnapshotCaptured = 0x46
    // Fan (Phase II range 0x50–0x56)
    case fanRPMThresholdChanged = 0x50
    case fanRPMMinMet = 0x51
    case fanRPMMaxExceeded = 0x52
    case fanTemperatureThresholdChanged = 0x53
    case fanTemperatureMinMet = 0x54
    case fanTemperatureMaxExceeded = 0x55
    case fanPowerConsumptionExceeded = 0x56

    var isBootLifecycle: Bool {
        self == .bootComplete || self == .shutdownClean || self == .shutdownUnexpected
    }

    var isFirmwareUpdate: Bool {
        switch self {
        case .firmwareUpdateAttempted, .firmwareUpdateCompleted, .firmwareUpdateFailed, .firmwareReverted: true
        default: false
        }
    }
}
