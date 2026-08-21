//
//  SnapshotFieldValue.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - SnapshotFieldValue

/// One decoded field of a captured snapshot: its display metadata plus the
/// type-erased ``SnapshotValue``. A ``SnapshotLogEntry`` is a timestamped bag of
/// these.
nonisolated struct SnapshotFieldValue: Codable, Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let keyPath: String
    let value: SnapshotValue
    let unit: String
    let dataType: SnapshotFieldDataType

    /// Standard initializer for a freshly captured value.
    init(
        displayName: String,
        keyPath: String,
        value: SnapshotValue,
        unit: String,
        dataType: SnapshotFieldDataType
    ) {
        id = UUID()
        self.displayName = displayName
        self.keyPath = keyPath
        self.value = value
        self.unit = unit
        self.dataType = dataType
    }

    /// Full initializer for reconstructing a value from JSON/binary.
    init(
        id: UUID,
        displayName: String,
        keyPath: String,
        value: SnapshotValue,
        unit: String,
        dataType: SnapshotFieldDataType
    ) {
        self.id = id
        self.displayName = displayName
        self.keyPath = keyPath
        self.value = value
        self.unit = unit
        self.dataType = dataType
    }
}
