# GitHub infrastructure, issue map & contribution rules

Durable reference for how sentinel-client is run on GitHub: the merged board, its
field/option IDs, milestones, labels, the issue map, and the contribution rules.
Rolled out of `docs/SESSION_HANDOFF.md` (2026-06-29). The board IDs are shared
with firmware — see
[`sentinel-firmware/docs/architecture/github-infrastructure.md`](https://github.com/galudino/sentinel-firmware/blob/main/docs/architecture/github-infrastructure.md).
Update the issue map as issues progress (it's a reference snapshot, not live).

---

## Contribution rules (same as firmware)

- **No outside-project references in any public artifact.** Outside projects
  are private development context only. Enforced unilaterally.
- **Branch workflow:** git-flow; branch off `develop`, incremental commits, tag
  the pre-squash tip (`<feature-name>-history`), squash-merge to `develop`,
  `--no-ff` merge `develop` → `main`.
- **No `Co-Authored-By` trailer on commits.** No "Generated with Claude Code"
  PR marketing either.
- **Issue Project fields to populate:** Status, Priority, Size, Start/Target
  date, Milestone.

---

## Board & repo

- **Repository:** [github.com/galudino/sentinel-client](https://github.com/galudino/sentinel-client)
- **Project board:** the **merged `sentinel` board** — `galudino/projects/2`,
  project ID `PVT_kwHOAbZCmc4BYDDx` (shared with firmware; the old standalone
  client board `projects/4` / `PVT_kwHOAbZCmc4BZ6kp` was **deleted** 2026-06-08,
  so its field/option IDs are dead — use the IDs below). Per-repo focus = saved
  Views filtered by `repository:`.
- **Milestones (repo, client):** Phase I (MVP on iOS); Phase II (Sensor/peripheral
  expansion + refinements); Phase III (iPadOS + macOS support); Phase IV (Cloud
  REST API integration). Titles are authoritative; don't rely on milestone numbers.
- **`gh`** fully configured (`repo` + `read:project` + `project` scopes).

## Project field IDs (on the merged board — same as firmware's)

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

## Issue map

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
- **#15–#19** Tabs: Home / Logs / Snapshots / Device / Settings (Backlog)
- **#20** FirmwareSelectionView · **#21** FirmwareUpdateView ·
  **#22** OTA upload state machine (Backlog)
- **#23** Persistence: paired peer registry (Backlog)
- **#24** Concurrency: Swift 6 strict concurrency hardening (Backlog; Phase II)
- **#25** DebugOutputStreamView (Backlog)
- **#26** SplashView (Ready — dependency-free first task)
- **#27** Sensor/peripheral expansion umbrella (Backlog; Phase II) —
  per-chip checklist for picking up firmware-backlog sensors as their GATT
  services land; mirrors firmware Phase II.
- **#32** Cloud REST API integration (Phase IV; spec TBD).
- **#33** Project config: Xcode app setup — schemes / configs / tests / icon /
  SPM (in progress).
