//
//  PairedPeerStore.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation
import Observation

/// The persistent registry of previously-connected devices (Phase I:
/// UserDefaults-backed JSON under the versioned key `v1.peers`; SwiftData is the
/// Phase II evolution). `@Observable`, **no singleton** — created once in
/// `SentinelApp.init()` and injected with `.environment(...)`.
///
/// `register` takes the peripheral *identity* (`UUID` + name), not an
/// `AsyncBluetooth` `Peripheral`, keeping persistence free of BLE types (same
/// convention as `AppRouter.beginConnect(peripheralID:)`).
@Observable
final class PairedPeerStore {
    private(set) var peers: [PairedPeer]

    private let defaults: UserDefaults
    private static let storageKey = "v1.peers"

    /// - Parameter defaults: injectable for tests (pass a throwaway suite).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        peers = Self.load(from: defaults)
    }

    // MARK: Mutations

    /// Record a first pairing, or refresh `lastConnectedAt` if already known.
    func register(id: UUID, name: String?, at date: Date = .now) {
        if let index = peers.firstIndex(where: { $0.id == id }) {
            peers[index].lastConnectedAt = date
            if peers[index].displayName == nil { peers[index].displayName = name }
        } else {
            peers.append(PairedPeer(
                id: id,
                displayName: name,
                lastConnectedAt: date,
                lastFirmwareVersion: nil,
                trustedAt: date
            ))
        }
        persist()
    }

    /// Update connection metadata after a session.
    func update(_ id: UUID, lastConnected: Date = .now, firmwareVersion: FirmwareVersion?) {
        guard let index = peers.firstIndex(where: { $0.id == id }) else { return }
        peers[index].lastConnectedAt = lastConnected
        if let firmwareVersion { peers[index].lastFirmwareVersion = firmwareVersion }
        persist()
    }

    func setDisplayName(_ id: UUID, to name: String) {
        guard let index = peers.firstIndex(where: { $0.id == id }) else { return }
        peers[index].displayName = name
        persist()
    }

    func forget(_ id: UUID) {
        peers.removeAll { $0.id == id }
        persist()
    }

    func forgetAll() {
        peers.removeAll()
        persist()
    }

    // MARK: Queries

    func isTrusted(_ id: UUID) -> Bool {
        peers.contains { $0.id == id }
    }

    func lastFirmwareVersion(_ id: UUID) -> FirmwareVersion? {
        peers.first { $0.id == id }?.lastFirmwareVersion
    }

    // MARK: Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(peers) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> [PairedPeer] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PairedPeer].self, from: data)
        else { return [] }
        return decoded
    }
}

extension PairedPeerStore {
    /// A seeded, in-memory store for SwiftUI previews (serves the role of a
    /// `MockPairedPeerStore` — `@Environment` keys on the concrete type, so a
    /// throwaway-suite instance is the previewable "mock").
    static func preview(peers: [PairedPeer] = PairedPeer.samples) -> PairedPeerStore {
        let suite = UserDefaults(suiteName: "preview.\(UUID().uuidString)")!
        let store = PairedPeerStore(defaults: suite)
        for peer in peers {
            store.register(id: peer.id, name: peer.displayName, at: peer.lastConnectedAt)
        }
        return store
    }
}

extension PairedPeer {
    static let samples: [PairedPeer] = [
        PairedPeer(
            id: UUID(),
            displayName: "Sentinel",
            lastConnectedAt: .now.addingTimeInterval(-3600),
            lastFirmwareVersion: FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16),
            trustedAt: .now.addingTimeInterval(-86400)
        )
    ]
}
