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

    /// When set, `connect` waits this long before returning — lets tests drive the
    /// cancel/timeout paths deterministically.
    var connectDelay: Duration?

    private(set) var cancelledPeerIDs: [UUID] = []

    func connect(peripheralID: UUID, name: String?) async throws -> ConnectedPeer {
        connectCount += 1
        if let connectDelay { try await Task.sleep(for: connectDelay) }
        if shouldFailConnect { throw MockCentralError.connectFailed }
        return ConnectedPeer(id: peripheralID, name: name)
    }

    func cancelConnect(peripheralID: UUID) async {
        cancelledPeerIDs.append(peripheralID)
    }

    func disconnect(_ peer: ConnectedPeer) async throws {
        disconnectedPeerIDs.append(peer.id)
    }
}

enum MockCentralError: Error {
    case connectFailed
}
