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

**Last updated:** 2026-08-16 (#26 **SplashView done** — squash-merged to
`develop`, pre-squash history at tag `26-view-splashview-history`). This session:
built `SplashView` (`sensor.fill` variable-color pulse, gates the root swap in
`SentinelApp`); set `AccentColor` to brand cyan (#2DE2CD) so splash + icon + tint
match; fixed the build's lint phase and added **SwiftFormat** (runs format-fix
**before** SwiftLint, phase moved ahead of compile, and `run-swiftlint.sh` no
longer ships inside the `.app`). **Prior (2026-08-13):** #33 Xcode config done
(tag `33-xcode-config-icon-history`) — single-size `sensor.fill` app icon; rolling
latest-iOS policy (currently 26.4; see #4). **Prior (2026-06-29):** durable
sections rotated into [`docs/architecture/`](architecture/).

**App code so far:** `SentinelApp` (splash-gated root swap) → `SplashView` (#26,
done) → falls through to the stock `ContentView` **placeholder** (replaced by
`RootView` when #7 lands). Build phase runs SwiftFormat → SwiftLint on every
build (configs: `Sentinel/.swiftformat`, `Sentinel/.swiftlint.yml`; scripts in
`Sentinel/Scripts/`). Everything below `RootView` is still forward-spec.

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

- **#26 SplashView** — fully dependency-free; good first implementation.
- **#7 AppRouter / navigation state machine** — pure SwiftUI structure.
- **#8 BluetoothManager + transport protocol** — scaffolding can land; the
  concrete characteristic reads wait on #9 UUIDs.
- **#10 / #11 decoders** — can be written + unit-tested against synthetic bytes
  before real UUIDs exist (the byte layout is known from firmware #34 / #36).
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

**#7 (Architecture: SwiftUI navigation + state machine)** is next. It introduces
`AppRouter` (the `@Observable` state machine) and `RootView`, which **replaces the
`ContentView` placeholder** that `SplashView` currently falls through to. Concretely:
`SentinelApp.init()` creates `AppRouter` (+ the other app-wide `@Observable`s as they
arrive) and injects via `.environment(...)`; `RootView` switches on router state
(`.scanning` / `.connecting` / `.connected` / `.updatingFirmware`) per the
navigation model in [`architecture/architecture.md`](architecture/architecture.md).
Wire `SplashView`'s `onComplete` to reveal `RootView`. No firmware dependency —
pure SwiftUI structure. After #7, **#8** (BluetoothManager + transport protocol)
is the BLE foundation (concrete characteristic reads wait on firmware #6 UUIDs / #9).

Done and on `develop`: **#33** (Xcode config, tooling, icon), **#26** (SplashView).
Follow the git-flow in
[`architecture/github-infrastructure.md`](architecture/github-infrastructure.md):
branch off `develop`, tag the pre-squash tip (`NN-slug-history`), squash-merge, delete.

**Env note:** the app targets iOS 26.4, so run/test on an **iOS 26.4+ simulator**
(e.g. iPhone 17 Pro). Builds won't install on iOS 18 simulators ("requires a newer
version of iOS"), which manifests as a stale install / generic app icon.
