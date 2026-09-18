//
//  SnapshotCategory.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

// MARK: - SnapshotCategory

/// The grouping enum a concrete ``Snapshot`` uses to organize its fields in the
/// UI (e.g. Environment / RTC / BLE / Health for ``DeviceSnapshot``). Tied to a
/// snapshot type through ``Snapshot/Category``.
protocol SnapshotCategory: Codable, CaseIterable, Identifiable, Hashable {
    var id: Self { get }
    var displayName: String { get }
}
