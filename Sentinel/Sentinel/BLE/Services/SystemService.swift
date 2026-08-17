//
//  SystemService.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/16/26.
//

import AsyncBluetooth
import CoreBluetooth
import Foundation

/// Cross-cutting device identity + health, mirroring firmware
/// `sentinel_gatt_system.hpp`: Serial Number (R/W), Firmware Version (R),
/// Request Bootloader Mode (W), Platform ID (R), CPU Temperature (R/Notify).
///
/// The client reads ``readPlatformID()`` — never the human Model Number string —
/// to choose the firmware/DFU target and (Phase IV) the cloud `target`.
protocol SystemService {
    func readSerialNumber() async throws -> UInt32
    func readFirmwareVersion() async throws -> FirmwareVersion
    func readPlatformID() async throws -> PlatformID
    /// CPU/SoC temperature, 0.01 °C / LSB (0 until wired up on device).
    func readCPUTemperature() async throws -> UInt16
    /// Ask the device to reboot into bootloader/DFU mode (OTA flow, #22).
    func requestBootloaderMode() async throws
    func setCPUTemperatureNotifying(_ enabled: Bool) async throws
    func cpuTemperatureNotifications() -> AsyncStream<UInt16>
}

struct SystemServiceClient<Transport: BluetoothPeripheralTransport>: SystemService {
    let transport: Transport

    private var service: CBUUID { SentinelServiceUUID.system.cbuuid }

    func readSerialNumber() async throws -> UInt32 {
        try await transport.read(characteristic: SystemCharacteristicUUID.serialNumber.cbuuid, ofService: service) ?? 0
    }

    func readFirmwareVersion() async throws -> FirmwareVersion {
        try await transport.read(characteristic: SystemCharacteristicUUID.firmwareVersion.cbuuid, ofService: service)
            ?? FirmwareVersion(major: 0, minor: 0, patch: 0, build: 0)
    }

    func readPlatformID() async throws -> PlatformID {
        let raw: UInt8 = try await transport.read(
            characteristic: SystemCharacteristicUUID.platformID.cbuuid,
            ofService: service
        ) ?? 0
        return PlatformID(rawValue: raw) ?? .unknown
    }

    func readCPUTemperature() async throws -> UInt16 {
        try await transport
            .read(characteristic: SystemCharacteristicUUID.cpuTemperature.cbuuid, ofService: service) ?? 0
    }

    func requestBootloaderMode() async throws {
        try await transport.write(
            UInt8(1),
            characteristic: SystemCharacteristicUUID.requestBootloaderMode.cbuuid,
            ofService: service,
            type: .withResponse
        )
    }

    func setCPUTemperatureNotifying(_ enabled: Bool) async throws {
        try await transport.setNotify(
            enabled,
            characteristic: SystemCharacteristicUUID.cpuTemperature.cbuuid,
            ofService: service
        )
    }

    func cpuTemperatureNotifications() -> AsyncStream<UInt16> {
        transport.notifications(for: SystemCharacteristicUUID.cpuTemperature.cbuuid, ofService: service)
    }
}

struct MockSystemService: SystemService {
    var serialNumber: UInt32 = 0x0000_ABCD
    var firmwareVersion = FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16)
    var platformID: PlatformID = .cyble416045
    var cpuTemperature: UInt16 = 4200

    func readSerialNumber() async throws -> UInt32 { serialNumber }
    func readFirmwareVersion() async throws -> FirmwareVersion { firmwareVersion }
    func readPlatformID() async throws -> PlatformID { platformID }
    func readCPUTemperature() async throws -> UInt16 { cpuTemperature }
    func requestBootloaderMode() async throws {}
    func setCPUTemperatureNotifying(_: Bool) async throws {}
    func cpuTemperatureNotifications() -> AsyncStream<UInt16> { .init { $0.yield(cpuTemperature); $0.finish() } }
}
