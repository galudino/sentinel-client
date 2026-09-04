//
//  SnapshotFieldConfig.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - SnapshotFieldConfig

/// A selectable field of a snapshot type `S`, as presented in the create-config
/// UI: identity (`keyPath`), display metadata, and whether it's enabled for
/// capture. Generic over the snapshot type so a configuration is type-checked to
/// its snapshot.
nonisolated struct SnapshotFieldConfig<S: Snapshot>: Codable, Identifiable {
    let id: UUID
    let keyPath: String
    let displayName: String
    let unit: String
    let dataType: SnapshotFieldDataType
    let dataDescription: String
    let category: S.Category
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        keyPath: String,
        displayName: String,
        unit: String,
        dataType: SnapshotFieldDataType,
        dataDescription: String,
        category: S.Category,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.keyPath = keyPath
        self.displayName = displayName
        self.unit = unit
        self.dataType = dataType
        self.dataDescription = dataDescription
        self.category = category
        self.isEnabled = isEnabled
    }
}
