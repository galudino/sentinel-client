//
//  DeviceReadinessGate.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 9/4/26.
//

import SwiftUI

/// Gates sensor-dependent tab content on device readiness (#38): until the device
/// reports `ready`, it shows an initializing (or degraded) placeholder instead of
/// sensor cards that could display stale/zero values from a mid-POST connect.
///
/// Admin surfaces (Device / Settings / Logs) intentionally do **not** use this —
/// firmware, the GATT explorer, and DFU must stay reachable while the device is
/// still booting or has a failed self-test.
struct DeviceReadinessGate<Content: View>: View {
    let readiness: DeviceReadiness
    @ViewBuilder var content: () -> Content

    var body: some View {
        if readiness.isReady {
            content()
        } else {
            DeviceInitializingView(readiness: readiness)
        }
    }
}

/// The placeholder shown while the device is still coming up or reports a failed
/// self-test: booting / POST → a progress spinner; degraded → the failed
/// subsystem, so a missing sensor reads as "BME280 failed self-test" rather than
/// an endless spinner.
struct DeviceInitializingView: View {
    let readiness: DeviceReadiness

    var body: some View {
        if readiness.state == .degraded {
            ContentUnavailableView {
                Label("Self-Test Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(degradedMessage)
            }
        } else {
            ContentUnavailableView {
                Label("Starting Up", systemImage: "gearshape.2")
            } description: {
                Text("The device is running its power-on self-test. Live readings appear once it reports ready.")
            } actions: {
                ProgressView()
            }
        }
    }

    private var degradedMessage: String {
        let subsystem = readiness.failedSubsystem?.displayName ?? "A subsystem"
        return "\(subsystem.capitalizedFirst) failed its power-on self-test. Sensor data may be unavailable. "
            + "Firmware and diagnostics are still reachable from the Device tab."
    }
}

private extension String {
    /// Capitalize only the first character, leaving acronyms (BME280, DS3231)
    /// untouched — unlike `capitalized`, which lowercases the rest.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

#if DEBUG
    #Preview("Booting") {
        DeviceInitializingView(readiness: DeviceReadiness(state: .booting, failedSubsystemID: 0))
    }

    #Preview("Degraded — BME280") {
        DeviceInitializingView(
            readiness: DeviceReadiness(state: .degraded, failedSubsystemID: POSTSubsystem.bme280.rawValue)
        )
    }
#endif
