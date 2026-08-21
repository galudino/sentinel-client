//
//  ImportedFieldSchema.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

import Foundation

// MARK: - ImportedFieldSchema

/// A field descriptor reconstructed when importing a session from JSON.
nonisolated struct ImportedFieldSchema {
    let id: UUID
    let displayName: String
    let keyPath: String
    let unit: String
    let dataType: SnapshotFieldDataType
}
