# Architecture (decided; not yet implemented)

The durable design reference for the sentinel-client SwiftUI app: the BLE
central/connection model, dependency injection, naming conventions, testability,
the snapshot-logging subsystem, the OTA DFU wire protocol, and the navigation /
UI model. Rolled out of `docs/SESSION_HANDOFF.md` (2026-06-29) so the handoff can
stay a lean rolling-status doc — this is **active reference**, decided but not
yet implemented (the app is still the stock Xcode template).

The naming conventions and the one-shot-sample rule mirror the firmware GATT
contract 1:1 — see firmware decisions #8 and #9 in
[`sentinel-firmware/docs/architecture/decisions.md`](https://github.com/galudino/sentinel-firmware/blob/main/docs/architecture/decisions.md).

---

## Central / connection split + two-layer protocols (issue #8 is the foundation)

Mirrors CoreBluetooth's own model:
- **`BluetoothManager`** = the *central* (scan / connect / connection-state).
  One per app. Does NOT do characteristic I/O; does NOT retain the connected
  peripheral. `connect()` **returns** a `ConnectedPeer`.
- **`ConnectedPeer`** = one *active connection*. Owns the `Peripheral`,
  **conforms to `BluetoothPeripheralTransport`** (read/write/notify live here),
  holds live per-connection state (RSSI/MTU), and vends the service clients.
  Exists only while connected. Its `peripheral` property is the sole owner (no
  duplicate on the manager).

```
SwiftUI views + view models
        │  leaf views depend on `any <Chip>Service` (mock-injectable);
        │  containers read @Environment(ConnectedPeer.self)
        ▼
  Per-service protocols            ── mocked freely for tests + previews
        ▼
  *ServiceClient<Transport>        generic; transport = ConnectedPeer (prod)
        ▼
  BluetoothPeripheralTransport     ── ConnectedPeer (real) | MockBluetoothTransport (test)
        ▼
  ConnectedPeer  ── created by BluetoothManager.connect(); owns the Peripheral
        ▼
  BluetoothManager (central: scan/connect/state)  →  AsyncBluetooth → CoreBluetooth
```

## Dependency injection — NO singletons

App-wide `@Observable` objects (`BluetoothManager`, `AppRouter`,
`PairedPeerStore`, `AppPreferences`, snapshot logging managers) are created in
the `App` struct's `init()`, injected via `.environment(...)`, read via
`@Environment`. **No `.shared` anywhere.**
`ConnectedPeer` is injected into the **connected subtree only** (RootView's
`.connected`/`.updatingFirmware` branches do `.environment(peer)`), so the
"connection exists only while connected" invariant is structural, not optional-
guarded.

## Naming conventions (LOCKED — mirror firmware)

| Role | Convention | Examples |
|---|---|---|
| Chip-specific GATT service protocol | `<Chip>Service` | `BME280Service`, `DS3231Service` (Phase I); `SCD41Service`, `SGP30Service`, `TMP117Service`, `DS18B20Service` (Phase II) |
| Aggregate / cross-cutting service protocol | `<Function>Service` | `SnapshotStreamService`, `SnapshotHistoryService`, `SystemService`, `SystemEventLogService`, `OTAService`, `DebugStreamService` |
| Real generic impl | `<Name>ServiceClient<Transport>` | `BME280ServiceClient<ConnectedPeer>` |
| Mock for tests/previews | `Mock<Name>Service` | `MockBME280Service` |
| Transport protocol | `BluetoothPeripheralTransport` | — |
| Real transport | `ConnectedPeer` (conforms) | — |
| Mock transport | `MockBluetoothTransport` | — |

**Sensors are CHIP-NAMED, never a generic `SensorService`.** This mirrors the
firmware GATT contract (firmware #6 exposes a BME280 service + a DS3231 service
as distinct services). Reason: TMP117 vs DS18B20 (both temperature) need
disambiguation; chip quirks differ. `byte`-decode of packed firmware structs
uses AsyncBluetooth's `PeripheralDataConvertible` + `TriviallyCopyable`
(`data.readValue()` byte-exact) on `@frozen` POD mirrors of the firmware
structs.

**One-shot-sample rule (mirrors firmware #6).** Where a sensor IC + driver
return all fields in one read, the firmware exposes ONE packed-struct
characteristic and the client decodes the whole struct in one read — NOT one
read per field. BME280 = a single `BME280Sample` (`Int16` 0.01 °C, `UInt16`
0.01 %RH, `UInt32` Pa, 8 B), not three characteristics. Split only when the
registers are genuinely independent (DS3231 = Unix-time / temp / alarm-flags).
Aggregate service names are descriptive and locked 1:1 with firmware: `System`,
`SnapshotStream`, `SnapshotHistory`, `SystemEventLog`, `OTA`, `DebugStream`.
Firmware #6 owns the contract + UUIDs; #9 mirrors it (no client-side invention).

## Testability

Two strategies, both enabled by the protocol layering:
1. Mock the transport (`MockBluetoothTransport` w/ canned bytes), exercise the
   real `*ServiceClient` → catches byte-format bugs.
2. Mock the service (`MockBME280Service`), exercise the view → catches UI bugs
   with zero BLE involvement; also makes every SwiftUI Preview trivial.

Leaf views take `any *Service` in init (never a concrete `ConnectedPeer`) so
previews inject `Mock*Service`. Container/tab views read
`@Environment(ConnectedPeer.self)` and pass `peer.<service>` down. Container
previews inject a fresh `BluetoothManager()` / `AppRouter`.

## `@unchecked Sendable` is intentional for Phase I

`BluetoothManager` is `@unchecked Sendable` for now. Proper Swift 6 strict-
concurrency hardening is tracked separately in issue **#24** (Phase II).

## Snapshot logging is a generic, preserved architecture (#17)

The snapshot-logging subsystem (#17) is ported faithfully from the proven prior
design — keep it; it's genuinely generic. A `Snapshot` protocol (assoc.
`Category`) + a `SnapshotDataProvider` (assoc. `S: Snapshot`) make the whole
configure/capture/chart/export stack (`SnapshotLoggingManager<Provider>`,
`SnapshotLoggingView<Provider>`) work for ANY snapshot type via one code path.
`DeviceSnapshot` is the Phase I conformer; Phase II per-sensor snapshots plug in
with only a new `Snapshot` + `SnapshotDataProvider` (no manager/view changes).
Type names are already project-neutral — don't rename them. The ONE substantive
*new* deliverable is **chart performance on long (30–60 min+) sessions**:
display-only decimation (min/max-per-bucket), viewport-aware re-decimation on
zoom, debounced scrub, `.drawingGroup()`; full-resolution data is always kept
for export. Sessions are already file-based (entries on disk, lazy-loaded) — keep
that.

## OTA DFU wire protocol (#22)

The firmware's BLE OTA is the WICED **OTA FW Upgrade Service** (the
`ota-update` library's protocol; MCUBoot runs on-device afterward). Confirmed
against Infineon's `btsdk-peer-apps-ota` iOS reference — **protocol reused, code
not** (it's UIKit/CoreBluetooth/delegate-callbacks; we're SwiftUI/AsyncBluetooth/
async-await). Concrete details now live in #22:
- Service `ae5d1e47-…`; Control Point `a3dd50bf-…` (write cmds + indicate
  status); Control Data `a2e86c7a-…` (image chunks). **Source the real UUIDs
  from firmware #6** — don't hardcode the reference app's.
- Commands: PrepareDownload(1) → StartDownload(2,+uint32 size) → write chunks →
  Verify(3,+uint32 CRC32). CRC32 = standard zlib (poly `0xEDB88320`, init/final
  `0xFFFFFFFF`). Chunk = MTU−3 (negotiate; don't hardcode 244).
- **Device self-resets + disconnects after a successful Verify** → treat that
  disconnect as success, then reconnect + confirm version. Cancel is a no-op
  from `.validating` onward (point of no return).

---

## Navigation model

```
SplashView (#26)  → 2s SF-symbol fill-wipe ("sensor" → "sensor.fill")
   ▼
RootView  (AppRouter-driven, #7)
   ├── .scanning        → PeripheralScanView   (#12; "log in"; Debug button → DebugOutputStreamView)
   ├── .connecting      → ConnectingView        (#13)
   ├── .connected       → MainTabView           (#14; 5 tabs)
   │     ├── Home        (#15)  live + historical sensor data (Apple-Health-style)
   │     ├── Logs        (#16)  system event log
   │     ├── Snapshots   (#17)  snapshot history + live capture
   │     ├── Device      (#18)  device admin + GATT explorer; badge when FW update available
   │     │      └── Update Firmware → FirmwareSelectionView (#20)
   │     │      └── Open Debug Output Stream → DebugOutputStreamView (#25)
   │     └── Settings    (#19)  APP preferences ONLY (no device-side concerns)
   └── .updatingFirmware → FirmwareUpdateView    (#21; leaves the tab bar; driven by OTAUploader #22)
```

### Key UI decisions

- **`DeviceView` is a navigation-list hub, not one inline screen** (#18). It
  lists categories; each row opens a focused subview (DeviceInfo, Firmware,
  Time & Date, Storage, Debug Stream, GATT Explorer, + Phase-II per-chip config
  subviews). iPhone = pushed `NavigationLink` list; iPad/macOS =
  `NavigationSplitView` (sidebar + detail). Driven by a `DeviceCategory` enum +
  title/symbol mapping — mirrors the proven control-panel-hub pattern (a hub
  routing to per-section subviews), NOT a giant inline form. The **GATT
  Explorer** subview is itself a drill-down (services → characteristics →
  detail with typed read/write + dec/hex/oct/utf-8/raw toggle), catalog-driven
  so new characteristics appear for free. It's the first place a new
  characteristic is exercised before promotion into a polished view.
- **SettingsView (#19) is APP preferences ONLY** — theme, units, notifications,
  paired-peer management. Device-side concerns live in DeviceView. (Reviewer
  check: no firmware/device affordances in Settings.)
- **FirmwareSelectionView (#20) is NOT a tab** — pushed from DeviceView. Default
  selection = latest available newer than installed; "Other versions"
  disclosure for power users.
- **DebugOutputStreamView (#25)** merges local `BluetoothManager` events +
  device-side debug-stream characteristic into one chronological feed.
  Reachable from PeripheralScanView (watch the handshake) AND DeviceView
  (ongoing diagnostics).
- **5 tabs, not 6.** FirmwareSelection folded into DeviceView; Logs and
  Snapshots stay distinct (they are genuinely different data).
