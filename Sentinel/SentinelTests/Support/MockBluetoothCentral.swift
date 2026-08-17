//
//  MockBluetoothCentral.swift
//  SentinelTests
//
//  Created by Gemuele Aludino on 8/16/26.
//

import Foundation

@testable import Sentinel

/// A ``BluetoothCentral`` that fakes connect/disconnect for `AppRouter` state-
/// machine tests — no CoreBluetooth, no hardware. `connect` returns a *detached*
/// ``ConnectedPeer`` (id + name only), which is all the router's transitions
/// need. Set ``shouldFailConnect`` to drive the failure path.
final class MockBluetoothCentral: BluetoothCentral, @unchecked Sendable {
    var shouldFailConnect = false
    private(set) var connectCount = 0
    private(set) var disconnectedPeerIDs: [UUID] = []

    func connect(peripheralID: UUID, name: String?) async throws -> ConnectedPeer {
        connectCount += 1
        if shouldFailConnect { throw MockCentralError.connectFailed }
        return ConnectedPeer(id: peripheralID, name: name)
    }

    func disconnect(_ peer: ConnectedPeer) async throws {
        disconnectedPeerIDs.append(peer.id)
    }
}

enum MockCentralError: Error {
    case connectFailed
}
