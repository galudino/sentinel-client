//
//  AppRouterTests.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation
import Testing

@testable import Sentinel

/// Covers the #7 acceptance criteria: every transition is router-driven, the
/// `.connected` states carry the peer, disconnect returns to `.scanning`, DFU
/// cancel/complete return to `.connected` with the same peer, and tab selection
/// survives DFU round-trips and reconnects.
@MainActor
struct AppRouterTests {
    /// Drive a fresh router through `beginConnect` and wait for the async connect
    /// to land in `.connected`. `MockBluetoothCentral.connect` completes
    /// immediately, so this yields at most a couple of times.
    private func makeConnectedRouter(
        name: String = "Test"
    ) async -> (router: AppRouter, peerID: UUID) {
        let router = AppRouter(bluetoothManager: MockBluetoothCentral())
        let id = UUID()
        router.beginConnect(peripheralID: id, name: name)
        for _ in 0 ..< 1000 {
            if case .connected = router.state { break }
            await Task.yield()
        }
        return (router, id)
    }

    @Test func initialStateIsScanning() {
        let router = AppRouter(bluetoothManager: MockBluetoothCentral())
        #expect(router.state == .scanning)
        #expect(router.selectedTab == .home)
    }

    @Test func beginConnectEntersConnectingSynchronously() {
        let router = AppRouter(bluetoothManager: MockBluetoothCentral())
        let id = UUID()
        router.beginConnect(peripheralID: id)
        // The async success hop runs on a scheduled Task, not inline, so the
        // state is observably `.connecting` right after the call returns.
        #expect(router.state == .connecting(peripheralID: id))
    }

    @Test func beginConnectSucceedsToConnected() async {
        let (router, id) = await makeConnectedRouter()
        guard case let .connected(peer) = router.state else {
            Issue.record("expected .connected, got \(router.state)")
            return
        }
        #expect(peer.id == id)
    }

    @Test func beginConnectIgnoredWhenNotScanning() async {
        let (router, _) = await makeConnectedRouter()
        let before = router.state
        router.beginConnect(peripheralID: UUID()) // illegal from .connected
        #expect(router.state == before)
    }

    @Test func cancelConnectAbortsBLEAndReturnsToScanning() async {
        let central = MockBluetoothCentral()
        central.connectDelay = .seconds(5) // keep the connect in flight
        let router = AppRouter(bluetoothManager: central)
        let id = UUID()
        router.beginConnect(peripheralID: id)
        #expect({ if case .connecting = router.state { true } else { false } }())

        router.cancelConnect()
        #expect(router.state == .scanning) // returns immediately
        // The BLE abort is fired on a detached task; give it a turn to land.
        for _ in 0 ..< 1000 where central.cancelledPeerIDs.isEmpty {
            await Task.yield()
        }
        #expect(central.cancelledPeerIDs == [id])
    }

    @Test func failedConnectEntersConnectFailedWithMessage() async {
        let central = MockBluetoothCentral()
        central.shouldFailConnect = true
        let router = AppRouter(bluetoothManager: central)
        let id = UUID()
        router.beginConnect(peripheralID: id)
        for _ in 0 ..< 1000 {
            if case .connectFailed = router.state { break }
            await Task.yield()
        }
        guard case let .connectFailed(failedID, message) = router.state else {
            Issue.record("expected .connectFailed, got \(router.state)")
            return
        }
        #expect(failedID == id)
        #expect(!message.isEmpty)
    }

    @Test func retryConnectFromFailedReconnects() async {
        let central = MockBluetoothCentral()
        central.shouldFailConnect = true
        let router = AppRouter(bluetoothManager: central)
        let id = UUID()
        router.beginConnect(peripheralID: id)
        for _ in 0 ..< 1000 {
            if case .connectFailed = router.state { break }
            await Task.yield()
        }
        central.shouldFailConnect = false
        router.retryConnect()
        for _ in 0 ..< 1000 {
            if case .connected = router.state { break }
            await Task.yield()
        }
        guard case let .connected(peer) = router.state else {
            Issue.record("expected .connected after retry, got \(router.state)")
            return
        }
        #expect(peer.id == id) // retried the same device
    }

    @Test func dismissConnectErrorReturnsToScanning() async {
        let central = MockBluetoothCentral()
        central.shouldFailConnect = true
        let router = AppRouter(bluetoothManager: central)
        router.beginConnect(peripheralID: UUID())
        for _ in 0 ..< 1000 {
            if case .connectFailed = router.state { break }
            await Task.yield()
        }
        router.dismissConnectError()
        #expect(router.state == .scanning)
    }

    @Test func disconnectFromConnectedReturnsToScanning() async {
        let (router, _) = await makeConnectedRouter()
        router.didDisconnect()
        #expect(router.state == .scanning)
    }

    @Test func userDisconnectTearsDownBLEAndReturnsToScanning() async {
        let central = MockBluetoothCentral()
        let router = AppRouter(bluetoothManager: central)
        let id = UUID()
        router.beginConnect(peripheralID: id)
        for _ in 0 ..< 1000 {
            if case .connected = router.state { break }
            await Task.yield()
        }
        router.disconnect()
        #expect(router.state == .scanning)
        for _ in 0 ..< 1000 where central.disconnectedPeerIDs.isEmpty {
            await Task.yield()
        }
        #expect(central.disconnectedPeerIDs == [id])
    }

    @Test func disconnectWhileScanningIsNoOp() {
        let router = AppRouter(bluetoothManager: MockBluetoothCentral())
        router.didDisconnect()
        #expect(router.state == .scanning)
    }

    @Test func startFirmwareUpdateCarriesPeerAndPayload() async {
        let (router, id) = await makeConnectedRouter()
        let image = FirmwareImage(version: "1.1.0")
        router.startFirmwareUpdate(image)
        guard case let .updatingFirmware(peer, payload) = router.state else {
            Issue.record("expected .updatingFirmware, got \(router.state)")
            return
        }
        #expect(peer.id == id)
        #expect(payload == image)
    }

    @Test func startFirmwareUpdateIgnoredWhenNotConnected() {
        let router = AppRouter(bluetoothManager: MockBluetoothCentral())
        router.startFirmwareUpdate(FirmwareImage(version: "1.1.0")) // illegal from .scanning
        #expect(router.state == .scanning)
    }

    @Test func cancelFirmwareUpdateReturnsToConnectedSamePeer() async {
        let (router, _) = await makeConnectedRouter()
        guard case let .connected(original) = router.state else {
            Issue.record("setup failed")
            return
        }
        router.startFirmwareUpdate(FirmwareImage(version: "1.1.0"))
        router.cancelFirmwareUpdate()
        guard case let .connected(peer) = router.state else {
            Issue.record("expected .connected after cancel, got \(router.state)")
            return
        }
        #expect(peer === original) // same peer, not a fresh connection
    }

    @Test func firmwareUpdateCompletedReturnsToConnected() async {
        let (router, _) = await makeConnectedRouter()
        router.startFirmwareUpdate(FirmwareImage(version: "1.1.0"))
        router.firmwareUpdateCompleted()
        #expect({ if case .connected = router.state { true } else { false } }())
    }

    @Test func selectedTabPersistsAcrossDfuRoundTrip() async {
        let (router, _) = await makeConnectedRouter()
        router.selectedTab = .device
        router.startFirmwareUpdate(FirmwareImage(version: "1.1.0"))
        router.firmwareUpdateCompleted()
        #expect(router.selectedTab == .device)
    }

    @Test func selectedTabPersistsAcrossReconnect() async {
        let (router, _) = await makeConnectedRouter()
        router.selectedTab = .snapshots
        router.didDisconnect() // link dropped
        #expect(router.selectedTab == .snapshots) // not reset by disconnect
        router.beginConnect(peripheralID: UUID())
        for _ in 0 ..< 1000 {
            if case .connected = router.state { break }
            await Task.yield()
        }
        #expect(router.selectedTab == .snapshots) // still there after reconnect
    }
}
