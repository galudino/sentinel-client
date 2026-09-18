//
//  GATTContract.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/17/26.
//

import CoreBluetooth
import Foundation

// ============================================================================
// GATT service contract — the Swift mirror of the firmware's Phase I GATT
// database. UUIDs are transcribed **verbatim** from firmware #6's generated
// database (`Sentinel/src/GeneratedSource/cycfg_gatt_db.h`, byte arrays there are
// little-endian; the canonical big-endian strings live here). Firmware owns the
// contract — nothing here is client-invented. See the per-characteristic
// `firmware:` comments for the owning header.
//
// Naming (mirrors architecture.md + firmware):
//   SentinelServiceUUID          — one enum, every custom Phase I service
//   <Service>CharacteristicUUID  — one enum per service, its characteristics
// ============================================================================

/// Every custom (128-bit) Phase I service. `cbuuids` is the scan filter.
enum SentinelServiceUUID: String, CaseIterable {
    /// firmware: sentinel_gatt_bme280.hpp — BME280 one-shot ambient sample.
    case bme280 = "5C3F249D-1AB4-423A-9DA7-2CD67E526C45"
    /// firmware: sentinel_gatt_ds3231.hpp — DS3231 real-time clock.
    case ds3231 = "3E28CA68-D66B-4FF1-ADA0-79225F3076F2"
    /// firmware: sentinel_gatt_system.hpp — device identity + health.
    case system = "11A3488D-B5D5-4145-A322-8EC8E819F166"
    /// firmware: sentinel_gatt_snapshot_stream.hpp — live device snapshot.
    case snapshotStream = "8935D83C-FAE8-439E-ADCF-F38B67AF7F55"
    /// firmware: sentinel_gatt_paged.hpp (SNAPSHOT_HISTORY) — persisted snapshots.
    case snapshotHistory = "55E2C813-F552-40CB-BB26-4694451DBD0A"
    /// firmware: sentinel_gatt_paged.hpp (SYSTEM_EVENT_LOG) — persisted events.
    case systemEventLog = "09A79D7A-7C5A-4D0D-AB42-BEEFA1ABA947"
    /// firmware: OTA FW Upgrade Service (Infineon standard, cycfg_gatt_db.h).
    case ota = "AE5D1E47-5C13-43A0-8635-82AD38A1381F"
    /// firmware: sentinel_gatt_debug.hpp — debug output stream.
    case debugStream = "6847AEEA-E7F5-42DE-8DAF-10D7FB344EF7"

    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
    nonisolated static let cbuuids: [CBUUID] = allCases.map(\.cbuuid)

    /// The scan filter. The firmware advertises **only** the System 128-bit UUID
    /// in its advertisement packet (firmware #67) — the other services are
    /// discoverable only after connecting — so a service-filtered scan must
    /// filter on exactly this one UUID, not all of ``cbuuids``. The full GATT DB
    /// is discovered post-connect via `discoverServices(cbuuids)`.
    nonisolated static let advertisedForScan: [CBUUID] = [system.cbuuid]
}

// MARK: - Chip-specific services

/// firmware: sentinel_gatt_bme280.hpp. One packed ``BME280Sample`` per the
/// one-shot-sample rule (the driver returns T/H/P in a single read).
enum BME280CharacteristicUUID: String, CaseIterable {
    /// R/Notify — `BME280Sample` (8 B packed). firmware: CHAR_BME280_AMBIENT_SAMPLE.
    case ambientSample = "11AC7ECD-3752-4300-A600-7790721AD4C5"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

/// firmware: sentinel_gatt_ds3231.hpp. Registers are independent → one
/// characteristic each (not a packed struct).
enum DS3231CharacteristicUUID: String, CaseIterable {
    /// R/W — `UInt32` seconds since 1970. firmware: CHAR_DS3231_UNIX_TIME.
    case unixTime = "2021C969-6F28-4A17-9347-ABEE83337EE1"
    /// R/Notify — `Int16` 0.01 °C. firmware: CHAR_DS3231_RTC_TEMPERATURE.
    case rtcTemperature = "64E51871-745E-42ED-A382-33D670F16ED1"
    /// R — `UInt8` bit0=A1F bit1=A2F bit7=OSF. firmware: CHAR_DS3231_ALARM_FLAGS.
    case alarmFlags = "BD627112-6AF2-40CF-9C9C-AA0BFD3E7003"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

// MARK: - Aggregate / cross-cutting services

/// firmware: sentinel_gatt_system.hpp.
enum SystemCharacteristicUUID: String, CaseIterable {
    /// R/W — `UInt32` device-identity key. firmware: CHAR_SYSTEM_SERIAL_NUMBER.
    case serialNumber = "49666C6D-2A24-4978-B4E5-A3C3D5B18B93"
    /// R — `FirmwareVersion` (5 B). firmware: CHAR_SYSTEM_FIRMWARE_VERSION.
    case firmwareVersion = "D4EE3C16-5EEC-469E-910A-51C95C9DFE83"
    /// W — `UInt8` request DFU/bootloader. firmware: CHAR_SYSTEM_REQUEST_BOOTLOADER_MODE.
    case requestBootloaderMode = "9EA19980-36C2-49CD-A348-CCD803820915"
    /// R — `UInt8` (`PlatformID`). firmware: CHAR_SYSTEM_PLATFORM_ID.
    case platformID = "EC5DBBC3-B5D1-40D3-8022-D4531CDD227C"
    /// R/Notify — `UInt16` 0.01 °C. firmware: CHAR_SYSTEM_CPU_TEMPERATURE.
    case cpuTemperature = "098FA125-5909-4442-B691-7041807581D0"
    /// R/Notify — 2 B `[state, failedSubsystem]` device readiness (#69).
    /// firmware: CHAR_SYSTEM_DEVICE_READINESS.
    case deviceReadiness = "D3E542A5-3476-4A48-B4F5-1D0D0699DB28"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

/// firmware: sentinel_gatt_snapshot_stream.hpp.
enum SnapshotStreamCharacteristicUUID: String, CaseIterable {
    /// R/Notify — `DeviceSnapshot` (80 B). firmware: CHAR_SNAPSHOT_STREAM_CURRENT_DEVICE_SNAPSHOT.
    case currentDeviceSnapshot = "B1D01D8B-32EB-491B-943D-E24C2527FCA0"
    /// R/W — `UInt8`. firmware: CHAR_SNAPSHOT_STREAM_SNAPSHOT_NOTIFY_ENABLE.
    case snapshotNotifyEnable = "AB3D9BD0-98DD-4586-929E-2DC0BE69BEA9"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

/// firmware: sentinel_gatt_paged.hpp (SNAPSHOT_HISTORY). Paged store — see
/// ``PagedStoreReader``.
enum SnapshotHistoryCharacteristicUUID: String, CaseIterable {
    /// R — `UInt32`. firmware: CHAR_SNAPSHOT_HISTORY_RECORD_COUNT.
    case recordCount = "DAF37BD0-CD19-497E-98C7-2F119F0CDD16"
    /// R/W — `UInt32` read cursor. firmware: CHAR_SNAPSHOT_HISTORY_INDEX.
    case index = "8E863A28-49A7-4EEF-8B9E-5E9309761FEC"
    /// R — `DeviceSnapshot` × N from the cursor. firmware: CHAR_SNAPSHOT_HISTORY_RECORD_BLOCK.
    case recordBlock = "4B85F62B-EDAA-48B1-B7D7-70067B6B2D3E"
    /// R/W — `UInt8`. firmware: CHAR_SNAPSHOT_HISTORY_CLEAR_STORE.
    case clearStore = "9B2BAFC1-A490-450C-9BBA-923C3677A7BF"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

/// firmware: sentinel_gatt_paged.hpp (SYSTEM_EVENT_LOG). Paged store.
enum SystemEventLogCharacteristicUUID: String, CaseIterable {
    /// R — `UInt32`. firmware: CHAR_SYSTEM_EVENT_LOG_RECORD_COUNT.
    case recordCount = "A6B48D8A-F48D-4036-9A64-CEE4F8928E85"
    /// R/W — `UInt32` read cursor. firmware: CHAR_SYSTEM_EVENT_LOG_INDEX.
    case index = "F48F1D41-0CF1-43F5-9E3C-FD695AE960ED"
    /// R — 36-byte records × N from the cursor. firmware: CHAR_SYSTEM_EVENT_LOG_RECORD_BLOCK.
    case recordBlock = "ECD7927C-6DB4-4FD2-A8AE-DE104DB0BAA2"
    /// R/W — `UInt8`. firmware: CHAR_SYSTEM_EVENT_LOG_CLEAR_STORE.
    case clearStore = "203CD4E1-0F6A-4E80-ABBF-66472FB36FAB"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

/// firmware: OTA FW Upgrade Service (Infineon standard).
enum OTACharacteristicUUID: String, CaseIterable {
    /// W/Notify/Indicate. firmware: CHAR_OTA_FW_UPGRADE_SERVICE_OTA_UPGRADE_CONTROL_POINT.
    case controlPoint = "A3DD50BF-F7A7-4E99-838E-570A086C661B"
    /// W. firmware: CHAR_OTA_FW_UPGRADE_SERVICE_OTA_UPGRADE_DATA.
    case data = "A2E86C7A-D961-4091-B74F-2409E72EFE26"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

/// firmware: sentinel_gatt_debug.hpp.
enum DebugStreamCharacteristicUUID: String, CaseIterable {
    /// R/Notify — UTF-8 (≤128 B). firmware: CHAR_DEBUG_OUTPUT_STREAM.
    case outputStream = "83F4C70C-D09E-4C0C-8835-3B8CFA2202D9"
    /// R/W — `UInt8`. firmware: CHAR_DEBUG_OUTPUT_STREAM_NOTIFY_ENABLE.
    case notifyEnable = "22C782A5-9CDD-4AAC-9E6A-8BB9D52F6B03"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

// MARK: - Standard SIG services (not firmware-sourced)

/// Standard Device Information Service (`0x180A`) — 16-bit SIG UUIDs surfaced by
/// CoreBluetooth directly, **not** from firmware #6. Read-only display mirrors;
/// the client authoritatively reads identity from ``SystemService`` instead.
enum DeviceInformationCharacteristicUUID: String {
    case manufacturerName = "2A29"
    case modelNumber = "2A24"
    case hardwareRevision = "2A27"
    case firmwareRevision = "2A26"
    case serialNumber = "2A25"
    case pnpID = "2A50"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}

enum StandardServiceUUID: String {
    case deviceInformation = "180A"
    case battery = "180F"
    nonisolated var cbuuid: CBUUID { CBUUID(string: rawValue) }
}
