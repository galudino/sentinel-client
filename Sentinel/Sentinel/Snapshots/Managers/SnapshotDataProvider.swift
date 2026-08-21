//
//  SnapshotDataProvider.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - SnapshotDataProvider

/// Abstracts the per-snapshot-type operations the generic
/// ``SnapshotLoggingManager`` needs: how to pull a snapshot off BLE, how to
/// extract a field by keyPath, how to format for export, and which storage keys
/// to persist under. Writing the manager against this protocol is what lets one
/// code path drive every snapshot type.
///
/// Sentinel's conformer (``DeviceSnapshotDataProvider``) wraps the connection's
/// ``SnapshotStreamService`` — so the manager never touches an `AsyncBluetooth`
/// type directly, mirroring how the rest of the client is layered.
protocol SnapshotDataProvider {
    /// The snapshot data type, e.g. ``DeviceSnapshot``.
    associatedtype S: Snapshot

    // MARK: Identification / storage keys

    var configurationsStorageKey: String { get }
    var completedSessionsStorageKey: String { get }
    /// Snapshot-type identifier for the index/JSON export, e.g. "deviceSnapshot".
    var snapshotTypeIdentifier: String { get }
    var sortingPreferencesStorageKey: String { get }

    // MARK: BLE operations

    /// Read + decode the most recent snapshot on demand (polling mode).
    func readSnapshot() async throws -> S
    /// Enable/disable the device's snapshot notification stream (notification mode).
    func setStreaming(_ enabled: Bool) async throws
    /// The live snapshot stream the device pushes while streaming is enabled.
    func snapshotStream() -> AsyncStream<S>

    // MARK: Field extraction

    /// Extract a single field value from a snapshot by keyPath.
    func extractValue(from snapshot: S, keyPath: String) -> SnapshotValue

    // MARK: Export formatting

    /// Format a field value for export. Override for types needing special
    /// presentation (e.g. a boolean shown as "Open"/"Closed").
    func formatValueForExport(_ value: SnapshotValue, keyPath: String) -> Any

    /// Whether a keyPath represents a valve-style field (import parsing hint).
    func isValveKeyPath(_ keyPath: String) -> Bool
}

// MARK: - Default Implementations

extension SnapshotDataProvider {
    func formatValueForExport(_ value: SnapshotValue, keyPath _: String) -> Any {
        value.jsonValue
    }

    func isValveKeyPath(_: String) -> Bool { false }

    /// Extract all configured field values from a snapshot.
    func extractFieldValues(
        from snapshot: S,
        for fields: [SnapshotFieldConfig<S>]
    ) -> [SnapshotFieldValue] {
        fields.map { field in
            SnapshotFieldValue(
                displayName: field.displayName,
                keyPath: field.keyPath,
                value: extractValue(from: snapshot, keyPath: field.keyPath),
                unit: field.unit,
                dataType: field.dataType
            )
        }
    }
}
