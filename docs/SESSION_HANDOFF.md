# Session Handoff

Rolling status for AI assistants (Claude, etc.) and human collaborators who join
partway through: **what this repo is, what's blocked on firmware, what to pick up
next.** Durable design + infra reference lives in
[`docs/architecture/`](architecture/) — see the pointers below. Update this file
at the end of any session; keep it lean by pushing design decisions / infra into
the architecture docs rather than letting them accumulate here.

## Durable reference (read these for the "why")

- [`architecture/architecture.md`](architecture/architecture.md) — the decided
  app architecture: BLE central/connection split + two-layer protocols, DI
  (no singletons), **locked naming conventions** (mirror firmware), testability,
  snapshot-logging subsystem, OTA DFU wire protocol, navigation model + key UI
  decisions.
- [`architecture/github-infrastructure.md`](architecture/github-infrastructure.md)
  — merged board ID + all field/option IDs, milestones, labels, the **issue
  map**, and the **contribution rules** (branch workflow, commit conventions).

---

**Last updated:** 2026-08-16 (#8 **BLE layer done** — branch
`8-ble-central-connectedpeer` off `develop`). This session replaced the #7 seeds
with the real BLE layer on `AsyncBluetooth` 6.2.2:
- **`BluetoothManager`** (central): `waitUntilReady` → `scanForPeripherals` (filters
  by the known service UUIDs, 0.5 s advertisement throttle) driving
  `discoveredPeripherals: [PeripheralScanItem]`; `connect(peripheralID:)` resolves
  the id → `Peripheral` (scan list, then CoreBluetooth's retained set), connects,
  discovers services, returns a `ConnectedPeer`; `disconnect`; `bluetoothEventStream()`
  (fan-out of `BluetoothLogEvent`s for #25). **Holds no `connectedPeripheral`.**
- **`ConnectedPeer`** (active connection): owns the `Peripheral`, conforms to
  **`BluetoothPeripheralTransport`** (read/write/setNotify/notifications — the last
  bridges AsyncBluetooth's Combine `characteristicValueUpdatedPublisher` → an
  `AsyncStream`), holds live `rssi`/`negotiatedMTU`, and vends the 8 service clients.
  Detached `init(id:name:)` retained for previews/tests (transport throws `.detached`).
- **Transport + service layers:** `BluetoothPeripheralTransport` (+ `MockBluetoothTransport`);
  all 8 Phase I service trios — `BME280`/`DS3231`/`System`/`EventLog`/`SnapshotStream`/
  `SnapshotHistory`/`OTA`/`DebugStream` — each `<Name>Service` protocol +
  `<Name>ServiceClient<Transport>` + `Mock<Name>Service`. **`SystemService` is wired
  end-to-end** (the reference trio).
- **`PeripheralDataConvertible`** fixed-width conformances (`UInt8/16/32/64`,
  `Int8/16/32/64`; all `@retroactive nonisolated`) + a `TriviallyCopyable` marker for
  #10/#11's packed structs; `Peripheral+Hashable` (`@retroactive`); placeholder
  `ServiceUUIDs` (the `5E271E10…` base — **finalized in #9** vs firmware #6).

**Two deliberate deviations from the issue text, for testability (a locked
convention):** (1) `AppRouter.beginConnect(peripheralID:)` was **kept** (not rewired
to take a `Peripheral`) — the manager resolves the id internally, so the state
machine stays free of any AsyncBluetooth type; (2) `AppRouter` now holds
**`any BluetoothCentral`** (tiny connect/disconnect protocol; `BluetoothManager`
conforms) so `AppRouterTests` inject a `MockBluetoothCentral` (real BLE can't reach
`.connected` in a unit test). `PeripheralScanView` got a lean interim real scan+list
(polished UI still #12). **Concurrency note:** the target builds with
`-default-isolation=MainActor`; the transport/central types are `nonisolated` +
`@unchecked Sendable` (Phase I concession, #24), and `notifications`/`read`/`write`
are `<T: … & Sendable>`. Tests: `SystemServiceClientTests` + `BluetoothTransportTests`
(fixed-width decode, setNotify, notification bridge, detached-throws) + the existing
`AppRouterTests` (now on the mock central).

**Prior (2026-08-16):** #7 **navigation state machine done** —
squash-merged to `develop`, pre-squash history at tag
`7-navigation-state-machine-history`. Built `AppState` +
`@MainActor @Observable AppRouter` (four states: `.scanning` / `.connecting` /
`.connected` / `.updatingFirmware`; guarded intents, views never mutate `state`)
and `RootView` (the state switch, **no** outer `NavigationStack` — each branch
owns its nav container so the tab bar isn't wrapped; DFU leaves the tab bar);
wired `SentinelApp` DI (`BluetoothManager` → `AppRouter`, `.environment`
injection, splash→`RootView`) and **deleted the `ContentView` placeholder**.
`selectedTab` lives on `AppRouter` (not `MainTabView`) so tab selection survives
DFU round-trips + reconnects. Landed **minimal seeds** of the #8 types
(`BluetoothManager`, `ConnectedPeer`, `FirmwareImage`) — clearly marked
"expanded in #8" — plus stubs for `PeripheralScanView` (#12), `ConnectingView`
(#13), `MainTabView` (#14, 5 tabs), `FirmwareUpdateView` (#21). 14 Swift Testing
cases (`AppRouterTests`) cover every transition; verified green + a clean build
on an iOS 26.4 sim, and walked the full flow live (scan→connect→tabs→DFU→cancel).
**Prior (2026-08-16):** #26 **SplashView done** (tag `26-view-splashview-history`)
— `sensor.fill` variable-color pulse; `AccentColor` = brand cyan (#2DE2CD);
SwiftFormat added ahead of SwiftLint in the build phase. **Prior (2026-08-13):**
#33 Xcode config done (tag `33-xcode-config-icon-history`). **Prior (2026-06-29):**
durable sections rotated into [`docs/architecture/`](architecture/).

**App code so far:** `SentinelApp` (splash-gated root swap; creates
`BluetoothManager` + `AppRouter` in `init()`, injects via `.environment`) →
`SplashView` (#26) → `RootView` (#7) switching on `AppRouter.state`. `RootView`'s
four branches render `PeripheralScanView` (lean interim real scan+list; polished
UI #12) / `ConnectingView` / `MainTabView` / `FirmwareUpdateView` — the last three
still **stubs** pending #13/#14/#21. The **BLE layer is now real** (#8):
`BluetoothManager` + `ConnectedPeer` + `BluetoothPeripheralTransport` + the 8
service trios under `Sentinel/Sentinel/BLE/`. `FirmwareImage` remains a **seed**
awaiting #20/#21. Build phase runs SwiftFormat → SwiftLint on every build (configs:
`Sentinel/.swiftformat`, `Sentinel/.swiftlint.yml`; scripts in
`Sentinel/Scripts/`). Everything inside the stubs is still forward-spec.

---

## Working style — sessions

**One Claude Code session per issue** is the intended cadence (a session may
span two issues when genuinely intertwined, e.g. a view + the state machine
that drives it). Durable record = git history + GitHub issues/project boards +
this file + `docs/architecture/` + MEMORY.md. Opening prompt for a new session:

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
- **Targets:** latest iOS major at release (rolling deployment target — currently
  **iOS 26.4**; see #4); iPadOS & macOS latest (Phase III); AWS (Phase IV). Policy:
  personal client, no legacy-user base → track the newest OS, no `@available` gating.
- **Toolchain:** latest Xcode + Swift at release (currently Xcode 26+, Swift 6+),
  SwiftUI, `@Observable` (not the older `ObservableObject`/`@Published`)
- **BLE:** [`AsyncBluetooth`](https://github.com/manolofdez/AsyncBluetooth) SPM
  package — async/await + AsyncStream wrappers over CoreBluetooth. NOT raw
  CoreBluetooth, NOT a hand-rolled wrapper.
- **Xcode project root:** `Sentinel/` (target name "Sentinel";
  `Sentinel.xcodeproj`, `SentinelTests`, `SentinelUITests`).

**Status:** issues authored through #33; **zero app code beyond the stock Xcode
template** — everything is forward-spec. Tracked on the **merged `sentinel`
board** (`galudino/projects/2`) shared with firmware; the standalone client board
(the old `projects/4`) was deleted 2026-06-08. Per-repo focus = saved Views
filtered by `repository:`. The full architecture, issue map, and board IDs are in
[`docs/architecture/`](architecture/).

---

## Dependency on firmware

The client cannot finish BLE integration until **firmware #6 assigns the GATT
service + characteristic UUIDs.** Until then, the client-side UUID enums (#9)
hold `"TBD"` placeholders. Work that is NOT blocked on firmware UUIDs and can
start today:

- **#26 SplashView** — done (2026-08-16).
- **#7 AppRouter / navigation state machine** — done (2026-08-16).
- **#8 BluetoothManager + transport protocol** — **done (2026-08-16)**; concrete
  characteristic reads still use the placeholder `ServiceUUIDs` until #9 assigns
  the real values against firmware #6.
- **#10 / #11 decoders** — can be written + unit-tested against synthetic bytes
  before real UUIDs exist (the byte layout is known from firmware #34 / #36);
  conform the packed structs to the new `TriviallyCopyable` marker (#8).
- **#12 PeripheralScanView** — the real scan UI can now be built on the #8
  `BluetoothManager` (an interim scan+list already exists to replace).
- **#23 PairedPeerStore** — UserDefaults-backed; no firmware dependency.

> Firmware-side status: lane-2 live snapshot stream (firmware #46) is now built;
> the GATT contract that assigns UUIDs (firmware #6) is still the gate. Track it
> via the merged board.

---

## Repo setup to-dos

- **`.claude/` is NOT in `.gitignore`** (firmware repo gitignores it). Add it
  before committing if you don't want local Claude state tracked.
- **README.md is a 158-byte stub** — flesh out when there's something to show
  (mirror the firmware README structure: overview / status / architecture /
  build / layout).

(`develop` already exists; follow the git-flow in
[`architecture/github-infrastructure.md`](architecture/github-infrastructure.md).)

---

## Next session — recommended starting point

Two self-contained options, both **unblocked** by #8 and neither needing real
firmware UUIDs:

- **#10 / #11 decoders** (recommended) — write the packed wire structs
  (`DeviceSnapshot`, `SystemEventRecordRaw`, `FirmwareVersion`) conforming to the
  `TriviallyCopyable` marker (#8), decode from synthetic bytes, unit-test against
  the known firmware layouts (firmware #34 / #36). Fully off-device; feeds the
  service layer (`SnapshotStream`/`SnapshotHistory`/`EventLog` currently move raw
  `Data`).
- **#12 PeripheralScanView** — replace the interim scan list with the real UI
  (signal bars, filtering, permission/empty states, Debug button →
  `DebugOutputStreamView` #25) on the #8 `BluetoothManager`. Live end-to-end
  connect still needs a device advertising the (placeholder) service UUID.

Still gated on firmware **#6** (GATT contract) → client **#9** (real UUIDs): any
work that needs to read a *specific* real characteristic on hardware.

Done and on `develop`: **#33** (Xcode config, tooling, icon), **#26** (SplashView),
**#7** (navigation state machine — `AppRouter` / `RootView`). On branch
`8-ble-central-connectedpeer` (this session, pending squash-merge): **#8** (BLE
layer). Follow the git-flow in
[`architecture/github-infrastructure.md`](architecture/github-infrastructure.md):
branch off `develop`, tag the pre-squash tip (`NN-slug-history`), squash-merge, delete.

**Env note:** the app targets iOS 26.4, so run/test on an **iOS 26.4+ simulator**
(e.g. iPhone 17 Pro). Builds won't install on iOS 18 simulators ("requires a newer
version of iOS"), which manifests as a stale install / generic app icon.
