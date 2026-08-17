//
//  BluetoothPeripheralTransport.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// The low-level BLE I/O surface: read / write / notify a single characteristic
/// of a single service. This is the seam that decouples every per-service client
/// from CoreBluetooth.
///
/// Two conformers exist:
/// - ``ConnectedPeer`` — the real transport, backed by an `AsyncBluetooth`
///   `Peripheral`. It can only exist while connected, so service I/O is gated by
///   connection at the type level.
/// - ``MockBluetoothTransport`` — canned bytes for unit tests and previews; lets
///   a real `*ServiceClient` be exercised with zero BLE involvement.
///
/// Values cross the boundary as ``AsyncBluetooth/PeripheralDataConvertible`` —
/// primitives (see `PeripheralDataConvertible+FixedWidth`) and packed POD structs
/// (`TriviallyCopyable`) both qualify, so a client can `read()` an `Int16` or a
/// whole `DeviceSnapshot` through the same call.
protocol BluetoothPeripheralTransport: Sendable {
    /// Read and decode a characteristic's current value. Returns `nil` when the
    /// characteristic has no value yet; throws on a BLE or decode failure.
    func read<T: PeripheralDataConvertible & Sendable>(
        characteristic: CBUUID,
        ofService service: CBUUID
    ) async throws -> T?

    /// Encode and write a value to a characteristic.
    func write<T: PeripheralDataConvertible & Sendable>(
        _ value: T,
        characteristic: CBUUID,
        ofService service: CBUUID,
        type: CBCharacteristicWriteType
    ) async throws

    /// Enable or disable notifications/indications for a characteristic.
    func setNotify(
        _ enabled: Bool,
        characteristic: CBUUID,
        ofService service: CBUUID
    ) async throws

    /// A stream of decoded values pushed by the peer for a notifying
    /// characteristic. The caller is responsible for having enabled notifications
    /// via ``setNotify(_:characteristic:ofService:)`` first.
    func notifications<T: PeripheralDataConvertible & Sendable>(
        for characteristic: CBUUID,
        ofService service: CBUUID
    ) -> AsyncStream<T>
}
