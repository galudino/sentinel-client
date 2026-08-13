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

**Last updated:** 2026-08-13 (#33 Xcode project config **done** — squash-merged
to `develop`, pre-squash history at tag `33-xcode-config-icon-history`). This
session: single-size `sensor.fill` app icon; adopted the rolling latest-iOS
deployment policy (currently 26.4; see #4); reworked the #26 splash spec to a
`sensor.fill` variable-color pulse (replacing the old outline→fill wipe).
**Prior status (2026-06-29):** durable sections rotated into
[`docs/architecture/`](architecture/). **App code:** still only the stock Xcode
template (`SentinelApp.swift` / `ContentView.swift` + test stubs) — everything
below is forward-spec.

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

**#26 SplashView** is the cleanest first implementation: dependency-free, self-
contained, satisfying. The mark is `sensor.fill` (same glyph as the app icon)
animated with `.symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)`
— a "ping" pulse; fully specced in the issue body. After that, **#7** (navigation
skeleton) and **#8** (BluetoothManager scaffolding) unblock everything else.
(#33 Xcode project config is done and on `develop`.)
