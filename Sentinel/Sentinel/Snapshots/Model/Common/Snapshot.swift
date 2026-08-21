//
//  Snapshot.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import AsyncBluetooth
import Foundation

// MARK: - Snapshot

/// Ties a snapshot data type to its category enum and its display/export
/// metadata, so the generic logging, charting, and export machinery
/// (``SnapshotLoggingManager``, the chart views, the exporters) works for **any**
/// conforming type without modification.
///
/// Conformers decode off a BLE characteristic (``PeripheralDataConvertible``),
/// carry a device-side timestamp, and declare their loggable fields. Phase I ships
/// ``DeviceSnapshot`` as the sole conformer; Phase II adds per-sensor snapshot
/// types through the same seam.
protocol Snapshot: PeripheralDataConvertible, Sendable {
    /// The category enum used to group this type's fields in the UI.
    associatedtype Category: SnapshotCategory

    /// Device-side capture time, in Unix milliseconds.
    var unixTimeMs: UInt64 { get }

    // MARK: Display metadata

    /// Full name, e.g. "Device Snapshot".
    static var displayName: String { get }
    /// Short name for compact contexts, e.g. "Device".
    static var shortName: String { get }
    /// SF Symbol for empty-state / category icons.
    static var emptyStateIconName: String { get }
    /// Prefix for exported file names, e.g. "device_snapshot".
    static var exportFilePrefix: String { get }
    /// Explains the polling-interval control.
    static var pollingIntervalDescription: String { get }
    /// Placeholder for an empty configurations list.
    static var noConfigurationsText: String { get }
    /// Placeholder for an empty completed-sessions list.
    static var noCompletedSessionsText: String { get }
    /// Call-to-action for creating a configuration.
    static var createConfigurationPrompt: String { get }
    /// Navigation title for the live capture screen.
    static var captureNavigationTitle: String { get }

    /// The navigation route to this session's chart.
    static func chartRoute(for session: SnapshotLoggingSession) -> SnapshotRoute

    /// All loggable fields for this snapshot type.
    static func availableFields() -> [SnapshotFieldConfig<Self>]
}
