//
//  AppEnvironment.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/20/26.
//

import Foundation

/// Small runtime-environment probes. The one that matters today is detecting an
/// **Xcode Preview** render: the simulator that backs a preview has no BLE, so
/// the BLE-touching views (scan, connect) must take a synthetic path instead of
/// calling CoreBluetooth. Xcode sets `XCODE_RUNNING_FOR_PREVIEWS=1` in the preview
/// process, which is `false`/unset in the shipping app and on-device.
enum AppEnvironment {
    /// `true` only while rendering a SwiftUI Preview in Xcode.
    static var isRunningInXcodePreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
