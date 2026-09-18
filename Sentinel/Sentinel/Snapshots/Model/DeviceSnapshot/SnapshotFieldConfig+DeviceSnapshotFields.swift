//
//  SnapshotFieldConfig+DeviceSnapshotFields.swift
//  Sentinel
//
//  Created by Gemuele Aludino on 8/21/26.
//

// MARK: - DeviceSnapshot field catalog

/// The loggable fields of a ``DeviceSnapshot``. `keyPath` strings here must match
/// the switch in ``DeviceSnapshotDataProvider/extractValue(from:keyPath:)``.
/// Derived engineering-unit values (°C, %RH, hPa, dBm) are surfaced rather than
/// the raw fixed-point wire integers, so charts and exports read naturally. The
/// catalog is assembled per subsystem section to keep each list readable.
nonisolated extension SnapshotFieldConfig where S == DeviceSnapshot {
    static func availableFields() -> [Self] {
        environmentFields + rtcFields + storageFields + bluetoothFields + healthFields
    }

    private static var environmentFields: [Self] { [
        Self(
            keyPath: "temperatureCelsius",
            displayName: "Temperature",
            unit: "°C",
            dataType: .float32,
            dataDescription: "Ambient temperature from the BME280 sensor.",
            category: .environment
        ),
        Self(
            keyPath: "humidityPercent",
            displayName: "Humidity",
            unit: "%RH",
            dataType: .float32,
            dataDescription: "Relative humidity from the BME280 sensor.",
            category: .environment
        ),
        Self(
            keyPath: "pressureHectopascals",
            displayName: "Pressure",
            unit: "hPa",
            dataType: .float32,
            dataDescription: "Barometric pressure from the BME280 sensor.",
            category: .environment
        )
    ] }

    private static var rtcFields: [Self] { [
        Self(
            keyPath: "rtcTemperatureCelsius",
            displayName: "RTC Temperature",
            unit: "°C",
            dataType: .float32,
            dataDescription: "On-die temperature reported by the DS3231 RTC.",
            category: .rtc
        ),
        Self(
            keyPath: "rtcAlarm1Fired",
            displayName: "RTC Alarm 1 Fired",
            unit: "T/F",
            dataType: .bool,
            dataDescription: "DS3231 alarm-1 flag (A1F).",
            category: .rtc
        ),
        Self(
            keyPath: "rtcAlarm2Fired",
            displayName: "RTC Alarm 2 Fired",
            unit: "T/F",
            dataType: .bool,
            dataDescription: "DS3231 alarm-2 flag (A2F).",
            category: .rtc
        ),
        Self(
            keyPath: "rtcOscillatorStopped",
            displayName: "RTC Oscillator Stopped",
            unit: "T/F",
            dataType: .bool,
            dataDescription: "DS3231 oscillator-stop flag (OSF) — set if the clock lost time.",
            category: .rtc
        )
    ] }

    private static var storageFields: [Self] { [
        Self(
            keyPath: "eventLogRecordCount",
            displayName: "Event Log Records",
            unit: "records",
            dataType: .uint32,
            dataDescription: "Number of event-log records retained in on-device flash.",
            category: .storage
        ),
        Self(
            keyPath: "snapshotLogRecordCount",
            displayName: "Snapshot Log Records",
            unit: "records",
            dataType: .uint32,
            dataDescription: "Number of snapshot-history records retained in on-device flash.",
            category: .storage
        )
    ] }

    private static var bluetoothFields: [Self] { [
        Self(
            keyPath: "bleConnected",
            displayName: "BLE Connected",
            unit: "T/F",
            dataType: .bool,
            dataDescription: "Whether the device reports an active BLE connection.",
            category: .bluetooth
        ),
        Self(
            keyPath: "bleTxPowerDbm",
            displayName: "BLE TX Power",
            unit: "dBm",
            dataType: .uint8,
            dataDescription: "Configured BLE transmit power.",
            category: .bluetooth
        ),
        Self(
            keyPath: "blePeerRssiDbm",
            displayName: "BLE Peer RSSI",
            unit: "dBm",
            dataType: .float32,
            dataDescription: "Signal strength of the connected peer as seen by the device (0 when disconnected).",
            category: .bluetooth
        )
    ] }

    private static var healthFields: [Self] { [
        Self(
            keyPath: "cpuTemperatureCelsius",
            displayName: "CPU Temperature",
            unit: "°C",
            dataType: .float32,
            dataDescription: "SoC / CPU die temperature.",
            category: .health
        ),
        Self(
            keyPath: "uptimeSeconds",
            displayName: "Uptime",
            unit: "s",
            dataType: .uint32,
            dataDescription: "Seconds since the device last booted.",
            category: .health
        ),
        Self(
            keyPath: "postPassed",
            displayName: "POST Passed",
            unit: "T/F",
            dataType: .bool,
            dataDescription: "Whether power-on self-test passed (last status = 0).",
            category: .health
        ),
        Self(
            keyPath: "postLastStatus",
            displayName: "POST Last Status",
            unit: "#",
            dataType: .uint8,
            dataDescription: "Power-on self-test status code (0 = pass, else failing subsystem id).",
            category: .health
        )
    ] }
}
