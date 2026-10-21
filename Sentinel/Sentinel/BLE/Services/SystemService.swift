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
/// Platform ID (R), CPU Temperature (R/Notify).
///
/// The client reads ``readPlatformID()`` — never the human Model Number string —
/// to choose the firmware/DFU target and (Phase IV) the cloud `target`.
protocol SystemService {
    func readSerialNumber() async throws -> UInt32
    /// Write the device-identity serial number (R/W characteristic). Sensitive —
    /// the DeviceInfo serial editor (#18) confirms before calling. Re-read to
    /// verify the device accepted it.
    func writeSerialNumber(_ serial: UInt32) async throws
    func readFirmwareVersion() async throws -> FirmwareVersion
    func readPlatformID() async throws -> PlatformID
    /// CPU/SoC temperature, 0.01 °C / LSB (0 until wired up on device).
    func readCPUTemperature() async throws -> UInt16
    func setCPUTemperatureNotifying(_ enabled: Bool) async throws
    func cpuTemperatureNotifications() -> AsyncStream<UInt16>
    /// Device readiness (boot/POST state, #69). Read once on connect to gate the
    /// sensor UI, then subscribe for the `→ ready` transition when connecting
    /// mid-boot.
    func readDeviceReadiness() async throws -> DeviceReadiness
    func setDeviceReadinessNotifying(_ enabled: Bool) async throws
    func deviceReadinessNotifications() -> AsyncStream<DeviceReadiness>
}

struct SystemServiceClient<Transport: BluetoothPeripheralTransport>: SystemService {
    let transport: Transport

    private var service: CBUUID { SentinelServiceUUID.system.cbuuid }

    func readSerialNumber() async throws -> UInt32 {
        try await transport.read(characteristic: SystemCharacteristicUUID.serialNumber.cbuuid, ofService: service) ?? 0
    }

    func writeSerialNumber(_ serial: UInt32) async throws {
        try await transport.write(
            serial,
            characteristic: SystemCharacteristicUUID.serialNumber.cbuuid,
            ofService: service,
            type: .withResponse
        )
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

    func readDeviceReadiness() async throws -> DeviceReadiness {
        try await transport.read(characteristic: SystemCharacteristicUUID.deviceReadiness.cbuuid, ofService: service)
            ?? DeviceReadiness(state: .booting, failedSubsystemID: 0)
    }

    func setDeviceReadinessNotifying(_ enabled: Bool) async throws {
        try await transport.setNotify(
            enabled,
            characteristic: SystemCharacteristicUUID.deviceReadiness.cbuuid,
            ofService: service
        )
    }

    func deviceReadinessNotifications() -> AsyncStream<DeviceReadiness> {
        transport.notifications(for: SystemCharacteristicUUID.deviceReadiness.cbuuid, ofService: service)
    }
}

final class MockSystemService: SystemService, @unchecked Sendable {
    var serialNumber: UInt32
    var firmwareVersion: FirmwareVersion
    var platformID: PlatformID
    var cpuTemperature: UInt16
    var readiness: DeviceReadiness

    init(
        serialNumber: UInt32 = 0x0000_ABCD,
        firmwareVersion: FirmwareVersion = FirmwareVersion(major: 1, minor: 0, patch: 0, build: 16),
        platformID: PlatformID = .cyble416045,
        cpuTemperature: UInt16 = 4200,
        readiness: DeviceReadiness = .ready
    ) {
        self.serialNumber = serialNumber
        self.firmwareVersion = firmwareVersion
        self.platformID = platformID
        self.cpuTemperature = cpuTemperature
        self.readiness = readiness
    }

    func readSerialNumber() async throws -> UInt32 { serialNumber }
    func writeSerialNumber(_ serial: UInt32) async throws { serialNumber = serial }
    func readFirmwareVersion() async throws -> FirmwareVersion { firmwareVersion }
    func readPlatformID() async throws -> PlatformID { platformID }
    func readCPUTemperature() async throws -> UInt16 { cpuTemperature }
    func setCPUTemperatureNotifying(_: Bool) async throws {}
    func cpuTemperatureNotifications() -> AsyncStream<UInt16> { .init { $0.yield(cpuTemperature); $0.finish() } }
    func readDeviceReadiness() async throws -> DeviceReadiness { readiness }
    func setDeviceReadinessNotifying(_: Bool) async throws {}
    func deviceReadinessNotifications() -> AsyncStream<DeviceReadiness> { .init { $0.yield(readiness); $0.finish() } }
}
