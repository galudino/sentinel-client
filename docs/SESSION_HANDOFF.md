# Session Handoff

Rolling context for AI assistants (Claude, etc.) and human collaborators who
join the project partway through. Update at the end of any session that
introduced new architectural decisions, new GitHub infrastructure, or
non-obvious constraints. Keep under ~350 lines.

**Last updated:** 2026-06-09 (merged onto the shared `sentinel` board; GATT
contract sync with firmware #6 — descriptive aggregate names + BME280 one-shot
sample; phase milestone-epics; Phase III/IV redefined. No app code yet.)

---

## Working style — sessions

**One Claude Code session per issue** is the intended cadence (a session may
span two issues when genuinely intertwined, e.g. a view + the state machine
that drives it). Durable record = git history + GitHub issues/project boards +
this file + MEMORY.md. Opening prompt for a new session:

> "Working on issue #N in sentinel-client. Read `docs/SESSION_HANDOFF.md` and
> the body of issue #N, list the dependencies, propose the implementation,
> then proceed."

Cross-device: `claude remote-control` / `/remote-control` mirrors a session to
the Claude iOS app via QR code while code runs locally.

---

## What this repo is

Native **SwiftUI client** (iOS first; iPadOS + macOS later) that discovers,
pairs with, and exercises a Phase I **sentinel-firmware** device over BLE:
live BME280 telemetry, system event log retrieval, snapshot history + live
snapshot capture, OTA DFU via MCUBoot. Companion to
[github.com/galudino/sentinel-firmware](https://github.com/galudino/sentinel-firmware).

- **Phases (4):** I = iOS MVP (core sensors); II = sensor/peripheral expansion
  + refinements (mirrors firmware Phase II driver expansion; umbrella #27);
  III = **iPadOS + macOS** multi-platform adaptation; IV = **cloud REST API
  integration** (S3 OTA-DFU file storage + event-log / snapshot upload, partitioned
  by device serial number; issue #32 — spec TBD). Each phase has a `Main client
  application: Phase N` milestone-epic (#3 / #30 / #28 / #31) under root epic #29.
- **Targets:** iOS 17+ (Phase I/II); iPadOS 17+ & macOS 14+ (Phase III); AWS (Phase IV)
- **Toolchain:** Xcode 15+, Swift 5.9+, SwiftUI, `@Observable` (not the older
  `ObservableObject`/`@Published`)
- **BLE:** [`AsyncBluetooth`](https://github.com/manolofdez/AsyncBluetooth) SPM
  package — async/await + AsyncStream wrappers over CoreBluetooth. NOT raw
  CoreBluetooth, NOT a hand-rolled wrapper.
- **Xcode project root:** `Sentinel/` (target name "Sentinel";
  `Sentinel.xcodeproj`, `SentinelTests`, `SentinelUITests`).

**Status:** issues authored through #32; **zero app code written** beyond the
stock Xcode template — everything is forward-spec. Tracked on the **merged
`sentinel` board** (`galudino/projects/2`) shared with firmware; the standalone
client board (the old `projects/4`) was deleted 2026-06-08. Per-repo focus =
saved Views filtered by `repository:`.

---

## Architecture (decided; not yet implemented)

### Central / connection split + two-layer protocols (issue #8 is the foundation)

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

### Dependency injection — NO singletons

App-wide `@Observable` objects (`BluetoothManager`, `AppRouter`,
`PairedPeerStore`, `AppPreferences`, snapshot logging managers) are created in
the `App` struct's `init()`, injected via `.environment(...)`, read via
`@Environment`. **No `.shared` anywhere** (matches the voomair idiom).
`ConnectedPeer` is injected into the **connected subtree only** (RootView's
`.connected`/`.updatingFirmware` branches do `.environment(peer)`), so the
"connection exists only while connected" invariant is structural, not optional-
guarded.

### Naming conventions (LOCKED — mirror firmware)

| Role | Convention | Examples |
|---|---|---|
| Chip-specific GATT service protocol | `<Chip>Service` | `BME280Service`, `DS3231Service` (Phase I); `SCD41Service`, `SGP30Service`, `TMP117Service`, `DS18B20Service` (Phase II) |
| Aggregate / cross-cutting service protocol | `<Function>Service` | `LiveTelemetryService`, `SnapshotHistoryService`, `SystemService`, `SystemEventLogService`, `OTAService`, `DebugStreamService` |
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
`LiveTelemetry`, `SnapshotHistory`, `SystemEventLog`, `OTA`, `DebugStream`.
Firmware #6 owns the contract + UUIDs; #9 mirrors it (no client-side invention).

### Testability

Two strategies, both enabled by the protocol layering:
1. Mock the transport (`MockBluetoothTransport` w/ canned bytes), exercise the
   real `*ServiceClient` → catches byte-format bugs.
2. Mock the service (`MockBME280Service`), exercise the view → catches UI bugs
   with zero BLE involvement; also makes every SwiftUI Preview trivial.

Leaf views take `any *Service` in init (never a concrete `ConnectedPeer`) so
previews inject `Mock*Service`. Container/tab views read
`@Environment(ConnectedPeer.self)` and pass `peer.<service>` down. Container
previews inject a fresh `BluetoothManager()` / `AppRouter` (voomair idiom).

### `@unchecked Sendable` is intentional for Phase I

`BluetoothManager` is `@unchecked Sendable` for now. Proper Swift 6 strict-
concurrency hardening is tracked separately in issue **#24** (Phase II).

### Snapshot logging is a generic, preserved architecture (#17)

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

### OTA DFU wire protocol (#22)

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

---

## Dependency on firmware

The client cannot finish BLE integration until **firmware #6 assigns the GATT
service + characteristic UUIDs.** Until then, the client-side UUID enums (#9)
hold `"TBD"` placeholders. Work that is NOT blocked on firmware UUIDs and can
start today:

- **#26 SplashView** — fully dependency-free; good first implementation.
- **#7 AppRouter / navigation state machine** — pure SwiftUI structure.
- **#8 BluetoothManager + transport protocol** — scaffolding can land; the
  concrete characteristic reads wait on #9 UUIDs.
- **#10 / #11 decoders** — can be written + unit-tested against synthetic bytes
  before real UUIDs exist (the byte layout is known from firmware #34 / #36).
- **#23 PairedPeerStore** — UserDefaults-backed; no firmware dependency.

---

## GitHub infrastructure

- **Repository:** [github.com/galudino/sentinel-client](https://github.com/galudino/sentinel-client)
- **Project board:** the **merged `sentinel` board** — `galudino/projects/2`,
  project ID `PVT_kwHOAbZCmc4BYDDx` (shared with firmware; the old standalone
  client board `projects/4` / `PVT_kwHOAbZCmc4BZ6kp` was **deleted** 2026-06-08,
  so its field/option IDs are dead — use the IDs below).
- **Milestones (repo, client):** Phase I (MVP on iOS); Phase II (Sensor/peripheral
  expansion + refinements); Phase III (iPadOS + macOS support); Phase IV (Cloud
  REST API integration). Titles are authoritative; don't rely on milestone numbers.
- **`gh`** fully configured (`repo` + `read:project` + `project` scopes).
- **Project field IDs (on the merged board — same as firmware's handoff):**

  | Field | ID |
  |---|---|
  | Status | `PVTSSF_lAHOAbZCmc4BYDDxzhTLlPE` |
  | Phase | `PVTSSF_lAHOAbZCmc4BYDDxzhU_3FM` |
  | Priority | `PVTSSF_lAHOAbZCmc4BYDDxzhTLlU8` |
  | Size | `PVTSSF_lAHOAbZCmc4BYDDxzhTLlVA` |
  | Start date | `PVTF_lAHOAbZCmc4BYDDxzhTLlVI` |

- **Status option IDs:** Backlog `18fe16c9`, Ready `61e4505c`, In Progress
  `47fc9ee4`, In Review `df73e18b`, On Hold/Blocked `06bd8365`, Done `98236657`.
- **Phase option IDs:** Phase I `eb79509f`, II `2bd5ada7`, III `f009f762`, IV `a59b2206`.
- **Priority option IDs:** P0 `79628723`, P1 `0a877460`, P2 `da944a9c`.
- **Size option IDs:** XS `6c6483d2`, S `f784b110`, M `7515a9f1`, L `817d0097`, XL `db339eb2`.
- **Labels:** namespaced — `platform:`, `area:`, `swift:`, `subsystem:`, `test:`,
  plus `milestone` (phase-epic marker) and `project config: xcode`. The
  `subsystem:` set (ble/dfu/event-log/snapshot/debug) is spelled identically on
  the firmware repo.

### Issue map

- **All issues (through #32) assigned to `galudino`.** Structure: root epic **#29**
  *Main client application* parents the phase milestone-epics **#3** (I), **#30** (II,
  parents #27), **#28** (III, parents #5/#6), **#31** (IV, parents #32). The
  `Main client application: Phase N` epics carry the `milestone` label.
- **#2** Project: Initial Xcode scaffold (Done)
- **#3** Main client application: Phase I (umbrella; In progress; parents the rest)
- **#4** Platform Support: iOS (Phase I) · **#5** iPadOS & **#6** macOS
  (both Phase III, under #28)
- **#7** Architecture: SwiftUI navigation + state machine (Ready)
- **#8** BLE: AsyncBluetooth controller + service clients (Ready — FOUNDATION)
- **#9** BLE: GATT service contract (Ready — blocked on firmware #6 UUIDs)
- **#10/#11** Decoders: device_snapshot / system_event_record (Ready)
- **#12** PeripheralScanView (Ready) · **#13** ConnectingView (Ready) ·
  **#14** MainTabView (Ready)
- **#15–#19** Tabs: Home / Logs / Snapshots / Device / Settings (General Backlog)
- **#20** FirmwareSelectionView · **#21** FirmwareUpdateView ·
  **#22** OTA upload state machine (General Backlog)
- **#23** Persistence: paired peer registry (General Backlog)
- **#24** Concurrency: Swift 6 strict concurrency hardening (General Backlog; Phase II)
- **#25** DebugOutputStreamView (General Backlog)
- **#26** SplashView (Ready — dependency-free first task)
- **#27** Sensor/peripheral expansion umbrella (General Backlog; Phase II) —
  per-chip checklist for picking up firmware-backlog sensors as their GATT
  services land; mirrors firmware Phase II.

---

## Repo setup to-dos (not yet done)

- **No `develop` branch exists yet** — only `main`. Before the first feature
  branch, create it: `git checkout -b develop main && git push -u origin develop`.
  Then follow the same git-flow as firmware (branch off develop, tag pre-squash,
  squash-merge to develop, `--no-ff` merge develop→main).
- **`.claude/` is NOT in `.gitignore`** (firmware repo gitignores it). Add it
  before committing if you don't want local Claude state tracked.
- **README.md is a 158-byte stub** — flesh out when there's something to show
  (mirror the firmware README structure: overview / status / architecture /
  build / layout).

---

## Project / contribution rules (same as firmware)

- **No outside-project references in any public artifact.** Outside projects
  are private development context only. Enforced unilaterally.
- **Branch workflow:** git-flow; tag pre-squash tip; squash-merge to `develop`;
  `--no-ff` merge `develop` → `main`.
- **No `Co-Authored-By` trailer on commits.**
- **Issue Project fields to populate:** Status, Priority, Size, Start/Target
  date, Milestone.

---

## Next session — recommended starting point

**#26 SplashView** is the cleanest first implementation: dependency-free, self-
contained, satisfying. The SF-symbol `sensor` → `sensor.fill` vertical fill-wipe
is fully specced in the issue body. After that, **#7** (navigation skeleton) and
**#8** (BluetoothManager scaffolding) unblock everything else.

First, create the `develop` branch (see repo setup to-dos above).
