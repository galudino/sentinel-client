//
//  SnapshotSessionMetadata.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

// MARK: - SnapshotSessionMetadata

/// Device identity captured once, at session start, and stamped into the session
/// header/index. Sentinel reads this from ``SystemService`` on the live peer;
/// keeping it a plain value (supplied to ``SnapshotLoggingManager`` as an async
/// closure) keeps the generic manager free of any BLE service type.
nonisolated struct SnapshotSessionMetadata: Sendable, Equatable {
    var serialNumber: UInt32
    var firmwareVersion: String

    static let unknown = SnapshotSessionMetadata(serialNumber: 0, firmwareVersion: "Unknown")
}
