//
//  BluetoothLogEvent.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation

/// A single structured entry in the local BLE activity log.
///
/// ``BluetoothManager`` emits these for lifecycle moments (scan start/stop,
/// connect, service discovery, disconnect, errors). `DebugOutputStreamView` (#25)
/// merges this local stream with the on-device ``DebugStreamService`` output into
/// one timeline. Kept deliberately small for Phase I — a category, a message, and
/// the peer it concerns.
nonisolated struct BluetoothLogEvent: Identifiable, Hashable, Sendable {
    nonisolated enum Category: String, Sendable {
        case scan
        case connection
        case discovery
        case error
    }

    let id: UUID
    let timestamp: Date
    let category: Category
    let message: String
    /// The peripheral this event concerns, when applicable.
    let peripheralID: UUID?

    init(
        category: Category,
        message: String,
        peripheralID: UUID? = nil,
        timestamp: Date = .now,
        id: UUID = UUID()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = message
        self.peripheralID = peripheralID
    }
}
