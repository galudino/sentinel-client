# Session Handoff

Rolling context for AI assistants (Claude, etc.) and human collaborators who
join the project partway through. Update at the end of any session that
introduced new architectural decisions, new GitHub infrastructure, or
non-obvious constraints. Keep under ~350 lines.

**Last updated:** 2026-06-08 (initial project board + issue scaffolding;
no app code written yet beyond the stock Xcode template)

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
  III = iPadOS adaptation; IV = macOS support. (Phase II was inserted between
  the old I and II, bumping the platform phases to III/IV.)
- **Targets:** iOS 17+ (Phase I/II), iPadOS 17+ (Phase III), macOS 14+ (Phase IV)
- **Toolchain:** Xcode 15+, Swift 5.9+, SwiftUI, `@Observable` (not the older
  `ObservableObject`/`@Published`)
- **BLE:** [`AsyncBluetooth`](https://github.com/manolofdez/AsyncBluetooth) SPM
  package — async/await + AsyncStream wrappers over CoreBluetooth. NOT raw
  CoreBluetooth, NOT a hand-rolled wrapper.
- **Xcode project root:** `Sentinel/` (target name "Sentinel";
  `Sentinel.xcodeproj`, `SentinelTests`, `SentinelUITests`).

**Status:** project board + 26 issues authored (#2–#27; no #1); **zero app code written** beyond
the stock Xcode template. Everything is forward-spec.

---

## Architecture (decided; not yet implemented)

### Two-layer protocol design (issue #8 is the foundation)

```
SwiftUI views + view models
        │  (depend on `any BME280Service`, `any EventLogService`, etc.)
        ▼
  Per-service protocols            ── mocked freely for tests + previews
        ▼
  *ServiceClient<Transport>        generic; holds a transport reference
        ▼
  BluetoothPeripheralTransport     ── mocked freely for client unit tests
        ▼  (real conformance)
  BluetoothManager (@Observable)   owns the AsyncBluetooth CentralManager
        ▼
  AsyncBluetooth → CoreBluetooth
```

### Naming conventions (LOCKED — mirror firmware)

| Role | Convention | Examples |
|---|---|---|
| Chip-specific GATT service protocol | `<Chip>Service` | `BME280Service`, `DS3231Service` (Phase I); `SCD41Service`, `SGP30Service`, `TMP117Service`, `DS18B20Service` (Phase II) |
| Aggregate / cross-cutting service protocol | `<Function>Service` | `LiveTelemetryService`, `SnapshotHistoryService`, `SystemService`, `EventLogService`, `OTAService`, `DebugStreamService` |
| Real generic impl | `<Name>ServiceClient<Transport>` | `BME280ServiceClient<BluetoothManager>` |
| Mock for tests/previews | `Mock<Name>Service` | `MockBME280Service` |
| Transport protocol | `BluetoothPeripheralTransport` | — |
| Real transport | `BluetoothManager` (conforms via extension) | — |
| Mock transport | `MockBluetoothTransport` | — |

**Sensors are CHIP-NAMED, never a generic `SensorService`.** This mirrors the
firmware GATT contract (firmware #6 exposes a BME280 service + a DS3231 service
as distinct services). Reason: TMP117 vs DS18B20 (both temperature) need
disambiguation; chip quirks differ. `byte`-decode of packed firmware structs
uses AsyncBluetooth's `PeripheralDataConvertible` + `TriviallyCopyable`
(`data.readValue()` byte-exact) on `@frozen` POD mirrors of the firmware
structs.

### Testability

Two strategies, both enabled by the protocol layering:
1. Mock the transport (`MockBluetoothTransport` w/ canned bytes), exercise the
   real `*ServiceClient` → catches byte-format bugs.
2. Mock the service (`MockBME280Service`), exercise the view → catches UI bugs
   with zero BLE involvement; also makes every SwiftUI Preview trivial.

Every view takes `any *Service` in its init (never a concrete `BluetoothManager`
or `ConnectedPeer`) so previews inject mocks.

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
- **Project board:** `galudino/projects/4` — project ID `PVT_kwHOAbZCmc4BZ6kp`
- **Milestones (4):** Phase I (MVP on iOS) `M1`; Phase II (Sensor/peripheral
  expansion + refinements) `M4`; Phase III (iPadOS adaptation) `M2`; Phase IV
  (macOS support) `M3`. NB: GitHub milestone *numbers* are immutable, so the
  internal numbers no longer match phase order (Phase II = M4). Titles are
  authoritative; the milestones page sorts correctly under **alphabetical** sort
  ("Phase I" < "Phase II" < … by prefix). Don't rely on milestone numbers.
- **`gh`** fully configured (`repo` + `read:project` + `project` scopes).
- **Project field IDs:**

  | Field | ID |
  |---|---|
  | Status | `PVTSSF_lAHOAbZCmc4BZ6kpzhU14To` |
  | Priority | `PVTSSF_lAHOAbZCmc4BZ6kpzhU14l0` |
  | Size | `PVTSSF_lAHOAbZCmc4BZ6kpzhU14l4` |
  | Start date | `PVTF_lAHOAbZCmc4BZ6kpzhU14l8` |
  | Target date | `PVTF_lAHOAbZCmc4BZ6kpzhU14mA` |
  | Estimate | `PVTF_lAHOAbZCmc4BZ6kpzhU14mE` |

- **Status option IDs:** Platform Backlog `c2572c94`, General Backlog `59e97350`,
  Ready `44704dd5`, In progress `f7bcb858`, In review `65d3c066`,
  On Hold/Blocked `002f3b32`, Done `7d76283f`.
- **Priority option IDs:** P0 `22dd173d`, P1 `e9ede4d3`, P2 `6199b95d`.
- **Size option IDs:** XS `789e3aa5`, S `b11167fb`, M `6b8fb536`,
  L `afcf795f`, XL `cbb0dedd`.

### Issue map

- **All 26 issues assigned to `galudino`.**
- **#2** Project: Initial Xcode scaffold (Done)
- **#3** Main client application: Phase I (umbrella; In progress; parents the rest)
- **#4** Platform Support: iOS (Phase I) · **#5** iPadOS (Phase III) ·
  **#6** macOS (Phase IV)
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
