//
//  PairedPeerStoreTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/17/26.
//

import Foundation
import Testing

@testable import Sentinel

/// UserDefaults-backed persistence for the paired-peer registry (#23). Each test
/// uses a throwaway suite (unique random name) so nothing touches real defaults.
@MainActor
struct PairedPeerStoreTests {
    private func makeStore() -> (store: PairedPeerStore, suite: UserDefaults) {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return (PairedPeerStore(defaults: suite), suite)
    }

    @Test func registeredPeerPersistsAcrossReload() {
        let (store, suite) = makeStore()
        let id = UUID()
        store.register(id: id, name: "Sentinel")
        #expect(store.isTrusted(id))

        // A fresh store over the same suite = an app relaunch.
        let reloaded = PairedPeerStore(defaults: suite)
        #expect(reloaded.isTrusted(id))
        #expect(reloaded.peers.first?.displayName == "Sentinel")
    }

    @Test func forgetRemovesThePeer() {
        let (store, suite) = makeStore()
        let id = UUID()
        store.register(id: id, name: "Sentinel")
        store.forget(id)
        #expect(!store.isTrusted(id))
        #expect(PairedPeerStore(defaults: suite).isTrusted(id) == false)
    }

    @Test func updatePersistsDisplayNameAndFirmware() {
        let (store, suite) = makeStore()
        let id = UUID()
        store.register(id: id, name: "Sentinel")
        store.setDisplayName(id, to: "Bench Unit")
        let version = FirmwareVersion(major: 1, minor: 2, patch: 0, build: 40)
        store.update(id, firmwareVersion: version)

        let reloaded = PairedPeerStore(defaults: suite)
        #expect(reloaded.peers.first?.displayName == "Bench Unit")
        #expect(reloaded.lastFirmwareVersion(id) == version)
    }

    @Test func registerIsIdempotentOnLastConnected() {
        let (store, _) = makeStore()
        let id = UUID()
        let first = Date(timeIntervalSince1970: 1000)
        store.register(id: id, name: "Sentinel", at: first)
        let later = Date(timeIntervalSince1970: 2000)
        store.register(id: id, name: "Sentinel", at: later)
        #expect(store.peers.count == 1) // no duplicate
        #expect(store.peers.first?.lastConnectedAt == later)
        #expect(store.peers.first?.trustedAt == first) // trust date unchanged
    }

    @Test func forgetAllClearsEverything() {
        let (store, _) = makeStore()
        store.register(id: UUID(), name: "A")
        store.register(id: UUID(), name: "B")
        store.forgetAll()
        #expect(store.peers.isEmpty)
    }
}
