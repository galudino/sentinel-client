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

**Last updated:** 2026-08-21 (session 6) — **#17 SnapshotLoggingView DONE** — the
whole generic snapshot-logging + charting + export subsystem, faithfully ported
from the proven prior design and adapted to Sentinel. **On feature branch
`17-snapshot-logging`** (8 incremental commits, tag `17-snapshot-logging-history`
at the tip); **NOT yet squash-merged to `develop`** — left for a review pass
given its size (56 files, ~+7900 lines). Build + SwiftFormat + SwiftLint + all
`SentinelTests` green (13 new tests). To land it, follow the branch workflow:
squash-merge `17-snapshot-logging` → `develop`, delete the branch (history
preserved by the tag).

- **Layout:** model + engine under `Sentinel/Snapshots/` (`Model/Common`,
  `Model/DeviceSnapshot`, `Managers`); views under `Views/Tabs/Snapshots/`. The
  Xcode project uses synchronized folders, so new files are picked up with no
  `.pbxproj` edits.
- **Architecture (kept generic):** `Snapshot` protocol + type-erased value/field
  system + `SnapshotDataProvider` → one `SnapshotLoggingManager<Provider>` drives
  every snapshot type. `DeviceSnapshot` is the Phase I conformer; its field
  catalog/categories reflect the **real firmware telemetry** (environment / RTC /
  storage / BLE / health). Views are generic over `Provider` and specialized to
  `DeviceSnapshotDataProvider` at the `SnapshotLoggingView(peer:)` entry point.
- **Sentinel adaptations vs. the source design (all deliberate):** BLE I/O flows
  through the connection's `SnapshotStreamService` (+ `SystemService` for device
  identity via an injected async metadata closure) instead of a monolithic BLE
  manager; notifications use its `AsyncStream`. Value/persistence types are
  `nonisolated` (target is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; disk
  decode runs on a detached task). `.voomsession`→`.sentinelsession` (magic
  "SNTL"); "POC"→"device" throughout (incl. `deviceUnixTimeMs`,
  `deviceToReadLatency`, `deviceTimestampPeriod` timing ids). **Dropped** the
  source's UserDefaults→binary migration path (no legacy Sentinel sessions).
  Navigation is the per-tab `NavigationStack` + a `SnapshotRoute` enum (the
  Sentinel analogue of the source's router). The export **preview reuses the real
  exporter on a truncated session** (no duplicated CSV/JSON formatting — preview
  is byte-for-byte the output). Capture supports **both** polling and
  notifications (the source had deprecated polling).
- **The one genuinely-new deliverable — long-session chart perf — is done:**
  `ChartDecimator` (min/max-per-bucket for numeric series, transitions-only for
  boolean step-lines, viewport slice). The inline session chart decimates the
  displayed series (cached in `@State`, recomputed only on load/selection). The
  **full-screen chart** does real pinch-zoom + drag-pan + tap-scrub with
  **viewport-aware re-decimation** (debounced ~30ms) and `.drawingGroup()`. Full
  resolution stays on disk and in exports. (Note: the source's full-screen "zoom"
  state was inert; here zoom/pan actually drive the viewport.)
- **Known follow-ups / gaps (not blockers):** (1) active-session teardown on
  disconnect relies on crash-recovery + explicit Stop rather than a
  `stopOnDisconnect` hook — the manager is per-connection and torn down with the
  subtree; a footer-on-teardown pass would be cleaner. (2) Sort preference is
  local `@State` (not persisted) — the source persisted it via a `PresentationState`
  store Sentinel doesn't have. (3) No SwiftUI previews were added for the new
  views (they need the manager in the environment); the "preview simulation stack"
  seam could seed one. (4) Perf is engineered to the acceptance targets but not
  yet measured against a real ~36k-sample capture on device.
- **voomair (the port source):** keep it available through any immediate #17
  finish-up; after this lands, `sentinel-client` is self-sufficient for the
  snapshot feature (drop voomair unless a later issue ports another subsystem,
  e.g. the #25/#34 debug-stream UI).

**⏭️ PICK UP HERE (next session):** review + squash-merge #17 to `develop` (and
`--no-ff` develop → main if batching a release), then the post-#17 roadmap:
client #25 DebugOutputStreamView + #34 decode (together), #37 main menu / #38
MainTabView gating, firmware #68 (RTC SQW) / #69 device readiness.

---

**Last updated:** 2026-08-19 (session 5) — **#18 DeviceView + #15 HomeView DONE,
landed on `develop` as two separated commits.** Build + lint + tests green
(9 new `CharacteristicCatalogTests`). **Now on `develop`** (linear, **not pushed**):
- `80b4b28` **View: DeviceView hub + GATT explorer (#18)** — tag `18-device-view-history`
  (verified it builds standalone).
- `0884584` **View: HomeView climate/trends/clock refinements + reusable chart & clock (#15)**
  — tag `15-homeview-history`.
Feature branch `18-device-view` was deleted after the fast-forward. **Board: #15,
#16, #18 marked Done + closed** with per-issue "what shipped" archive comments;
**#17 stays Ready** (next session). **#17 SnapshotLoggingView is still the stub** —
deliberately its own dedicated session (the generic snapshot-logging + charting +
export subsystem; chart perf on long captures is the one new problem).
- **DeviceView is now a hub, not a flat list** — `DeviceCategory` enum
  (`Model/DeviceCategory.swift`) drives it: **compact (iPhone)** = `List` +
  `navigationDestination`; **regular (iPad/macOS)** = `NavigationSplitView`
  (sidebar + detail). Adding a subview = a case + a `detailView` branch. Phase II
  rows (`bme280Config`, `ds3231Config`) show disabled with "Coming in Phase II".
- **Subviews** (`Views/Tabs/Device/`): `DeviceInfoView` (identity/health/link +
  pushed `SerialNumberEditView`), `TimeAndDateView`, `StorageView`,
  `GATTExplorerView` → `ServiceCharacteristicsView` → `CharacteristicDetailView`.
  The Firmware row still pushes `FirmwareSelectionView` (#20) and shows the
  version + an update dot driven by `firmwareUpdateAvailable` (now passed from
  `MainTabView`). The **Debug Output** row is a placeholder `ContentUnavailableView`
  until **#25** lands.
- **GATT Explorer** is catalog-driven: `CharacteristicCatalog`
  (`BLE/UUIDs/CharacteristicCatalog.swift`) has one `CharacteristicDescriptor` per
  characteristic in #9 (name, `GATTDataType`, LSB unit, `CBCharacteristicProperties`).
  Detail view reads/writes/notifies via the **raw** `BluetoothPeripheralTransport`
  (not the `*ServiceClient` APIs), with a Dec/Hex/Oct/UTF-8/Raw format toggle + a
  typed write editor. Char UUID enums are now `CaseIterable`; the new test asserts
  the catalog stays 1:1 with the contract (build fails if a characteristic is added
  without a descriptor).
- **New service writes (per maintainer decision this session):**
  `DS3231Service.writeUnixTime` (backs "Sync from iPhone") and
  `SystemService.writeSerialNumber` (backs the serial editor) — **overrides the
  earlier `project_rtc_time_design` "defer BLE time-set to firmware #6" note.** The
  char is R/W on the wire; whether the device *honors* the write is a firmware #6
  concern, so both call sites **re-read to confirm** rather than assume success.
  `MockDS3231Service` / `MockSystemService` are now `final class … @unchecked
  Sendable` (needed so the write persists through `any *Service`).
- **⚠️ Sim has no BLE** — the live hub only renders against a real connection;
  every subview has `#if DEBUG` previews (mock services / `MockBluetoothTransport`)
  for design work in Xcode.

**HomeView (#15) refinements this session** (maintainer-directed, sets conventions
for later work — will sign off after review):
- **"Ambient" → "Climate"** throughout (Climate Readings / Climate Trends / Climate
  History Detail); the hero card **is** the navigation to Climate History Detail
  (no separate "show all" button — Apple-Health style). *(Renames were the
  maintainer's; the items below are this session's additions.)*
- **Reusable components** under `Views/Components/`: **`TrendChart`** (one
  domain-agnostic line chart + min/max/avg, takes converted `TrendPoint`s + chrome
  — **not** per-metric chart types) and **`AnalogClockView`** (stateless `Canvas`
  clock face; tick it from a `TimelineView`).
- **Climate Trends** now: `ContentUnavailableView` when `trendSnapshots.isEmpty`,
  else a **paged swipe** (`.tabViewStyle(.page)`) between temperature / humidity /
  air-pressure `TrendChart`s, driven by a private `ClimateTrendMetric` enum (the
  thin snapshot-field → chart-inputs mapping; Phase II sensors = new cases).
- **Real Time Clock** now: a **live-ticking analog clock** + full device date/time
  (one `TimelineView` feeds both, using a stored **device-minus-phone clock
  offset** so the face shows device time without re-reading), plus a **24-h
  component-temperature `TrendChart`**. The clock card is a **`NavigationLink` →
  `RealTimeClockHistoryDetail`** (parity with the Climate hero card → history).
- **Card parity + swipe dots:** both hero cards tap through to a per-snapshot
  history list. The Climate-Trends page indicator lives in the **section footer**
  (custom tappable dots) so it sits on the List background beneath the card, not
  inside it — the native "swipeable cards" look. Home supporting types
  (`ClimateHeroCard`, `ClimateTrendMetric`, both `*HistoryDetail`s) were extracted
  to `Views/Tabs/Home/HomeSupportingViews.swift` to keep `HomeView.swift` under the
  500-line lint cap.
- **Convention to carry forward** (per maintainer): prefer one generic reusable
  view parameterized by a metric enum over duplicated per-metric types; shared UI
  lives in `Views/Components/`. See [[reusable-view-conventions]].

**Preview-simulation stack (post-#15 follow-up, this session):** the whole app is
now drivable in the Xcode preview canvas through `RootView` — see
[[preview-simulation-stack]].
- `RootView` gained a **"Full flow"** preview: starts at `PeripheralScanView` with a
  seeded "Sentinel" → tap → `ConnectingView` ("Connecting to Sentinel…") → a
  **populated `MainTabView`**. Plus a "Connected (populated)" preview that lands on
  the tabs directly (zero-delay fake connect).
- Fixes the two reported bugs: (1) **RootView preview crashed** — it now injects all
  five app-wide environment objects, and `PeripheralScanView.isPreview` defaults to
  `AppEnvironment.isRunningInXcodePreview` (`XCODE_RUNNING_FOR_PREVIEWS`), so it skips
  the real BLE scan even when built via the plain `init()`. (2) **MainTabView mock
  snapshots didn't propagate** — `ConnectedPeer.preview()` now also seeds the **paged
  snapshot history** (record count + one encoded block; the mock transport returns the
  same block per read, so one page resolves the whole store), so Home's trends +
  Climate History populate.
- New pieces: `App/AppEnvironment.swift`, `BLE/PreviewBluetoothCentral.swift`
  (`BluetoothCentral` that fakes connect → `ConnectedPeer.preview()`),
  `BLE/Model/DeviceSnapshot+Preview.swift` (moved `previewSeries` + a
  `previewHistoryBlock`/`previewFrame`, all `nonisolated`).
- **Known gaps (follow-ups):** LogsView stays **empty** in container previews —
  `SystemEventRecord` has decoders but **no byte encoder**, so the event-log paged
  store can't be seeded yet (add an encoder to populate it). And the **DFU flow**
  through RootView (Device → Firmware → FirmwareUpdateView) still builds a *real*
  `OTAUploader` against the mock transport, so it won't complete in preview; to
  simulate it, have `FirmwareUpdateView` use a preview uploader (mock OTA +
  reconnector, like `OTAUploaderTests`) when `AppEnvironment.isRunningInXcodePreview`.

**Post-batch UX refinements (this session, on `develop`):**
- `836c665` **connected-device identity → DeviceView** (#18/#19): DeviceInfo Identity
  gains an "Identifier" row under Serial; SettingsView drops its Connected-Device
  section and is now **peer-independent** (no `ConnectedPeer`/`AppRouter` deps) —
  groundwork for #37.
- `38743c1` **PeripheralScanView Start/Stop scan toggle** (#12): observable
  `BluetoothManager.isScanning` drives a toolbar toggle + "Scanning…/Paused" header.
  (Pull-to-refresh deliberately **not** added — scanning is continuous and
  `pruneStale()` already drops out-of-range devices, so it'd be redundant with the
  toggle + auto-prune.)
- `0afe33c` **DFU status text** tidy (maintainer tweak). Tag
  `post-batch-ui-refinements-history`.
- **Storage review links (considered, declined):** the Logs tab already *is* the full
  System Event Log browser and the Snapshots tab (#17) will be the Snapshot History
  browser; `LogsView` owns its own `NavigationStack` (not push-safe), so a
  Storage→browser link would duplicate/nest. Kept Storage as management (counts +
  clear).
- **Catalogued:** **#37** (main-menu entry — reach Snapshots/Settings without
  connecting; Backlog/Phase I; depends on #17) and a scope comment on **#25**
  (client-side logging is already the `BluetoothLogEvent`/`bluetoothEventStream`
  feed this view merges — no `print`s by design; possible expansion: more client log
  sources + OSLog bridge + export).

**⏭️ PICK UP HERE (next session):** **#17 SnapshotLoggingView** — its own dedicated
session (the generic snapshot-logging subsystem: `Snapshot` protocol, type-erased
field/value system, `SnapshotDataProvider`, capture sessions, file-based
persistence, CSV/JSON/binary export, and the real new deliverable — **viewport-aware
chart decimation** for long captures). Then **#25 DebugOutputStreamView** (the
Device→Debug placeholder is already wired to receive it). After that, MainTabView
is fully fleshed out.

**Last updated:** 2026-08-19 (session 4) — **DFU trio #20/#21/#22 DONE, hardware-
validated, released to `main`; issues closed + marked Done on the board.** The full
OTA DFU works end-to-end on a real CYBLE-416045: bundled/imported firmware select →
chunked upload (CRC32 verify) → MCUBoot swap → reconnect → version confirm → back
to DeviceView (better than voomair's return-to-scan). All on `main`.
- **Pacing fix that made it work on hardware:** OTA data chunks write **with
  response** (`OTAService.writeData`) — AsyncBluetooth doesn't pace
  `.withoutResponse` writes, so a 322 KB image overran the FIFO. Post-DFU confirm
  matches on `major.minor.patch` (`FirmwareVersion.sameRelease`).
- **Stock-firmware bundle (this session):** `Resources/Firmware/` now ships the
  real signed **`sentinel-firmware_1.0.1.bin`** (recommended baseline / factory-
  reset image; dropped 1.0.0 + the old 1.0.1-test) + **`sentinel-firmware_255.255.255-test.bin`**
  (the 1.0.1 code signed at 255.255.255 so a test image can't be mistaken for a
  real release). `FirmwareImage.isPrerelease` + `FirmwareCatalog` **exclude any
  `-<label>` build from `recommended()`** and the badge/banner — test images stay
  selectable for rollback/testing but are never auto-recommended. Keep this bundle
  in sync with each firmware release (factory-reset intent).
- **Firmware side:** sentinel-firmware **v1.0.1 released** (record-store resilience
  fix — see that repo) with a GitHub Release + signed assets; the 1.0.1 `.bin` here
  is that release's OTA image.

**⏭️ PICK UP HERE (next session): tab content #15 / #16 / #17 / #18.** Current
state — **#15 HomeView + #16 LogsView are already implemented** (may just need a
review/close pass); the substantive remaining work is **#17 SnapshotLoggingView**
(the generic snapshot-logging + charting + export subsystem — a dedicated session;
chart perf on long captures is the one new problem) and **#18 DeviceView** (full
device admin + GATT explorer; only the identity/health panel landed so far). All
have `Mock*Service` types for previews; follow the preview convention below. #25
DebugOutputStreamView is the remaining non-tab view.

**Last updated:** 2026-08-18 (session 3) — **#20 FirmwareSelectionView done →
DFU trio (20/21/22) complete.** On branch `20-firmware-selection-view` off
`develop`, **not committed** (maintainer will validate the DFU on a physical board
first, then we run the tag/commit routine and merge `develop → main`). The DFU
`model`+`engine` (#21/#22) is already on `develop` (squash `f54ef2a`, granular
history at tag `22-dfu-ota-uploader-history`). Build + lint clean; **7 new unit
tests green** (file-name parse, recommend logic, and an integration test proving
the bundled `.bin`s ship + parse) on top of the prior 22.
- **Bundled catalog** — two real signed MCUBoot images ship under
  `Sentinel/Sentinel/Resources/Firmware/`: `sentinel-firmware_1.0.0.bin`
  (rollback) + `sentinel-firmware_1.0.1-test.bin` (newest/recommended). Loaded by
  `FirmwareCatalog` (parses `sentinel-firmware_<ver>[-label].bin`; `-test` is a
  display label, numeric version is `1.0.1`). "Latest" = newest bundled until S3
  (Phase IV / #32) becomes a source — `recommended(installed:among:)` is
  source-agnostic.
- **Files import** — `ImportedFirmwareStore` (`@Observable`, injected app-wide)
  copies a picked `.bin` into `Documents/ImportedFirmware/`, persists across
  launches, lists newest-first; `FirmwareSelectionView` uses `.fileImporter`.
- **`FirmwareSelectionView` (#20)** — pushed from DeviceView → "Update Firmware…":
  installed card, recommended card (Δ + "Update available"), "Other versions"
  disclosure (bundled + imported, badged newer/older/installed, size, source,
  swipe-to-delete imports), import button, confirm → `router.startFirmwareUpdate`.
- **Real update-available signal** — `MainTabView` now computes
  `firmwareUpdateAvailable` (device version vs recommended) on connect, driving
  the Device badge + Home banner (was a hardcoded `false`).
- **DFU pacing fix (important for hardware):** OTA data chunks now write **with
  response** (`OTAService.writeData`). AsyncBluetooth does **not** pace
  `.withoutResponse` writes — it fires and synthesizes completion immediately
  (Peripheral.swift:161) — so streaming a 322 KB image that way overruns the
  controller FIFO and drops chunks. Ack-per-chunk is #22's intended "write-ack =
  flow control" and keeps the transfer intact (~<60 s at BLE speeds).
- **Post-DFU confirm relaxed to `major.minor.patch`** (`FirmwareVersion.sameRelease`)
  — a filename-derived target carries `build == 0` while the device may report a
  real build for the same release.
- **⚠️ Still hardware-unverified** — the sim has no BLE, so the live
  upload+reconnect path (and the pacing fix) can only be proven on a real
  CYBLE-416045. That's the maintainer's next step before commit.

**Last updated:** 2026-08-18 (later session) — **DFU engine + flow done: #22
OTAUploader + #21 FirmwareUpdateView + the #20 model pieces they need.** On branch
`22-dfu-ota-uploader` off `develop` (not yet squash-merged). Build + lint clean;
**22 new unit tests green** (uploader transition table, CRC32 vectors, version
ordering) on top of the existing suite.
- **`OTAUploader` (#22)** — `@MainActor @Observable` engine for the Infineon **OTA
  FW Upgrade Service** handshake: enable CP indications → Prepare → Start(size) →
  chunked Control-Data (chunk = **MTU−3**, never hardcoded 244; CRC32 folded
  per-chunk) → Verify(crc32) → **device self-reset+disconnect = success** →
  reconnect → read `SystemService` firmware version → confirm target → `.complete`.
  Decoded status strings on any non-`ok`; cancel honoured through `.uploading`,
  no-op from `.validating` on (point of no return). New files under `BLE/DFU/`:
  `OTAUploader.swift`, `CRC32.swift` (zlib/PNG, incremental), `FirmwareReconnector.swift`.
- **`FirmwareUpdateView` (#21)** — austere full-screen takeover (no tab bar);
  progress ring + phase text bound to `uploader.state`/`progressFraction`;
  confirm-to-cancel dialog; "Done" hands the **reconnected** peer to the router.
  Five `#if DEBUG` phase previews via a frozen `OTAUploader.preview(_:progress:)`.
- **#20 model pieces** (the shared bits #21/#22 require; **full selection UI still
  deferred to #20**): `FirmwareImage` now carries `version: FirmwareVersion` + image
  `data` + `source`; `FirmwareVersion` gained `Comparable` + `init(parsing:)`. A
  `#if DEBUG` string init keeps old `FirmwareImage(version: "1.1.0")` call sites
  working; non-DEBUG `.placeholder()` backs the DeviceView "Update Firmware…" seed.
- **Reconnect seam (deliberate deviation, documented in-code):** the uploader owns
  the whole state machine incl. `.reconnecting`/`.verifying` via an injected
  `FirmwareReconnector`, so the reconnect tail is unit-testable with a mock (no
  hardware). Added `reconnect(peripheralID:name:)` to `BluetoothCentral`
  (`BluetoothManager` rescans then connects); `AppRouter.firmwareUpdateReconnected(peer:)`
  swaps `.updatingFirmware → .connected` onto the **fresh** peer.
- **Concurrency notes:** CP status reads go through a `nonisolated StatusReader`
  (an actor-isolated stored `AsyncIterator` can't be `next()`-ed across `await`);
  `FirmwareVersion` is now fully `nonisolated` so its `Equatable` is usable from the
  nonisolated `OTAError`. Per-chunk write pacing relies on AsyncBluetooth's
  write-ack; explicit per-chunk timeout left as a Phase-I nicety.
- **On-hardware DFU is unverified** — the sim has no BLE, so the live upload +
  reconnect path can only be exercised on a real CYBLE-416045. Mocks cover the
  logic end-to-end.

**Last updated:** 2026-08-18 — **#15 HomeView + #16 LogsView done; scan narrowed
to the advertised System UUID.** All on `develop` (linear, not pushed):
- **`6a9314f` BLE scan filter (fw #67):** `scanForPeripherals` now filters on the
  single **advertised** service — `SentinelServiceUUID.advertisedForScan =
  [.system]` — since the board advertises only the System 128-bit UUID (firmware
  #67, fixed same day on the firmware `develop`). Post-connect `discoverServices`
  still walks the full `cbuuids` contract. Build + unit tests green.
- **`6a91f9d` #15 HomeView + #16 LogsView:**
  - **#15 HomeView** — Apple-Health-Summary-style: BME280 ambient hero card
    (T/H/P), 24 h Swift-Charts temperature trend (min/max/avg), DS3231 time &
    clock, firmware-update banner. Unit-aware via `AppPreferences`. Leaf view
    taking `any *Service`; 4 preview states (live / empty / update / °F·inHg).
    "Show all environmental data" pushes a lightweight snapshot list (rich
    per-section charts are deliberately deferred per the issue).
  - **#16 LogsView** — System Event Log browser: scrollable filter chips
    (All/Boot/Firmware/BLE/Faults/POST/Other), day-sectioned most-recent-first
    list via the `SystemEventRecord` display API (#11), per-variant `EventDetailView`
    (typed fields + raw bytes for `.unknown`). Leaf view taking
    `any SystemEventLogService`.
  - `MainTabView` now injects the per-service clients (leaf-view convention).

**⏭️ PICK UP HERE (next session), in the maintainer's stated order:**
1. **#17 SnapshotLoggingView** — *deliberately deferred to its own session:* it is
   not a single view but a **generic snapshot-logging + charting + export
   subsystem** (Snapshot protocol, type-erased field/value system, data providers,
   capture sessions), a faithful port of a proven prior design that lives in
   another project (**no in-repo code to port from yet**). Sized for a dedicated
   session per the ~1-issue-per-session cadence; the one genuinely new problem is
   chart performance on long (30–60 min+) capture sessions.
2. **#18 DeviceView** (device admin + GATT explorer) — more self-contained;
   good candidate if #17 is postponed.
3. **#20 FirmwareSelectionView** — the DFU *onboarding* view is all that's left of
   the trio: bundled-image catalog, Files/`.bin` import (persisted to Documents),
   recommended-image card, and pushing to `FirmwareUpdateView`. The model + engine
   it feeds (`FirmwareImage` bytes/version/source, `FirmwareVersion` compare/parse,
   `OTAUploader`) are **done** this session; #20 just needs the picker UI + real
   `firmwareUpdateAvailable` signal that #14's badge/banner already consume.
   **#21 / #22 are done.**
4. **#25 / #34** (debug output stream) last.

> **DFU trio status:** #21 (`FirmwareUpdateView`) + #22 (`OTAUploader`) landed this
> session on `22-dfu-ota-uploader`, along with the #20 *model* pieces. Remaining #20
> work = the selection view only. On-hardware validation of the live upload+reconnect
> still pending a physical board.

**Note (firmware CI):** the maintainer asked whether CI publishes firmware
releases — it does **not** (only the Pages/Doxygen workflow exists). That's
firmware **#60** (Phase II); investigation was cataloged to that issue and
deferred. Not a client concern.

**Last updated:** 2026-08-17 (**#8–#14 all done + closed**, and **`develop` merged
to `main`** — merge commit `784a292`; not pushed). Foundational BLE + models + the
scan/connect/tabs flow. Firmware **#6 / #34 / #36 are CLOSED**, so #9/#10/#11 were
sourced from the firmware repo (no client invention). Highlights beyond #8–#12:
- **#13 ConnectingView** — presentational (router owns the connect); added
  `.connectFailed` state + a **15 s timeout** (`withThrowingTimeout`) + cancel /
  retry / dismiss intents + `BluetoothCentral.cancelConnect`. Phases from the live
  `ConnectionState`.
- **#14 MainTabView** — the 5-tab shell (Home/Logs/Snapshots/Device/Settings), each
  tab stubbed under `Views/Tabs/` (fleshed out by #15–#19); Device badge + Home
  banner driven by `firmwareUpdateAvailable` (#20 wires the real signal).
- **#23 PairedPeerStore + AppPreferences** — UserDefaults-backed, `@Observable`,
  versioned keys, injected app-wide; `register(id:name:)` uses peripheral identity;
  `FirmwareVersion` gained `Codable`.
- **#19 SettingsView** — real Form: paired devices (forget / forget-all), connection
  (identifier + Disconnect), Appearance/Units/Notifications/Developer bound to
  `AppPreferences`, About. Added **`AppRouter.disconnect()`** (user-initiated BLE
  teardown, vs the involuntary-drop `didDisconnect()`).
- Added `Sentinel.xctestplan` (wired into the scheme).
- **Follow-ups (post-#19):** new tab icon set; **register-on-connect** wired
  (`RootView` `.task(id: peer.id)` → `PairedPeerStore.register`, so trusted devices
  now populate); **`PeripheralScanView` preview scenarios** — see the convention
  below.

### Preview convention (do this for every view going forward)

The simulator has **no BLE**, so live-data views render empty/unavailable on the
preview canvas. Demonstrate real scenarios anyway via a **`#if DEBUG` preview
seam** (pattern borrowed from `voomair-client-ios`'s `#if targetEnvironment(simulator)`
swap, but scoped per-preview so the real path still previews):
- Give types that wrap a non-constructible SDK object a `#if DEBUG` synthetic init
  (e.g. `PeripheralScanItem(previewName:…)` — `peripheral` is now optional).
- Give the owning `@Observable` a `#if DEBUG static func preview(…)` that seeds
  its state (e.g. `BluetoothManager.preview(discovered:)`).
- Give the view a `#if DEBUG init(preview…:)` that seeds `@State` and sets an
  `isPreview` flag so `.task`/`.onChange` **skip real hardware calls**.
- Provide **multiple named `#Preview`s** covering the meaningful states (empty, one,
  many, error). `PeripheralScanView` is the reference: Bluetooth-unavailable /
  no-devices / one Sentinel / mixed. **#15 HomeView etc. should follow this** using
  the `Mock*Service` types (already exist) for live/empty/streaming states.

**Flow is now real end-to-end:** `PeripheralScanView → ConnectingView → MainTabView`
works on hardware (connect + discovery are real); tab *contents* are stubs until
#15–#19. **57 unique tests green.**

Earlier this session (#8–#12), sourced from firmware:
- **#9 GATT contract** — `GATTContract.swift`: real 128-bit UUIDs transcribed from
  firmware `cycfg_gatt_db.h` (one `SentinelServiceUUID` + per-service char enums);
  `PlatformID`/`VendorID`, `FirmwareVersion` (5-byte packed, hand-decoded),
  `BME280Sample` (8-byte packed). **Rewrote the #8 service layer to the real
  contract**: BME280 → one packed `BME280Sample` (one-shot rule); `EventLog` →
  **`SystemEventLog`**; `System` → serial/fwVersion/requestBootloaderMode/
  platformID/cpuTemperature (dropped invented `uptimeSeconds`); DS3231 →
  unixTime/rtcTemp/alarmFlags; paged stores via `PagedStore`. `GATTContractTests`
  pins every UUID.
- **#10 `DeviceSnapshot`** — 80-byte record decoded by explicit LE offsets
  (`Data+LittleEndian`), trailer-magic validated; SnapshotStream/History services
  now vend typed `DeviceSnapshot`.
- **#11 `SystemEventRecord`** — 36-byte records; `SystemEvent` enum +
  header→typed-body dispatch (Boot/FwUpdate/BLE/Fault/Mode/POST/Snapshot, `.other`,
  `.unknown`) + display API; SystemEventLog service vends `[SystemEventRecord]`.
- **#12 `PeripheralScanView`** — real scan list (name/RSSI bars/last-seen),
  empty + Bluetooth-unavailable/permission paths, connect-on-tap; `BluetoothManager`
  gained `bluetoothState` + 10 s staleness pruning. Verified live on an iOS 26.4 sim.

**Decoder convention:** packed wire records are decoded by **explicit little-endian
offset reads** (mirroring the firmware `offsetof` static_asserts), *not*
`TriviallyCopyable` raw-copy — robust to Swift struct layout. `TriviallyCopyable`
is kept only for the small naturally-aligned `BME280Sample`. **Isolation:** the
target is `-default-isolation=MainActor`, so decode entry points / model statics /
`Data` helpers are `nonisolated`, and test structs are `@MainActor`. **Total: 40
Swift Testing cases green.**

**Prior (2026-08-16):** #8 **BLE layer done** — replaced the #7 seeds with the real
BLE layer on `AsyncBluetooth` 6.2.2:
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

The GATT contract is **no longer a gate** — firmware **#6 (GATT services) / #34
(event log) / #36 (device snapshot) are CLOSED**, and the client mirrors them:
real UUIDs in `GATTContract.swift` (#9), record layouts in `DeviceSnapshot` (#10)
and `SystemEventRecord` (#11). Foundation status:

- **#26 / #7 / #8 / #9 / #10 / #11 / #12** — all **done** (see the top summary).
- **#23 PairedPeerStore** — UserDefaults-backed; no firmware dependency. **Unblocks
  the #12 Trusted-devices section** (deferred there).
- **#25 DebugOutputStreamView** — merges `BluetoothManager.bluetoothEventStream()`
  (built) + the on-device `DebugStreamService` (built). Unblocks the #12 Debug
  button (deferred there).

> On-hardware end-to-end connect still needs a physical CYBLE-416045 advertising the
> Sentinel service UUIDs — the iOS simulator has no BLE (it renders the
> Bluetooth-unavailable path, as verified for #12).

> ⚠️ **Discovery blocked on firmware fix — [sentinel-firmware #67](https://github.com/galudino/sentinel-firmware/issues/67).**
> The board currently advertises only its name + the 16-bit **Battery** UUID
> (`0x180F`), **not** any custom 128-bit Sentinel service UUID — so a service-filtered
> scan (`scanForPeripherals(withServices:)`) can't discover it (name-only scan does).
> Advertised service UUIDs are separate from the GATT DB. Firmware #67 will advertise
> the **System** UUID (primary adv) + name (scan response) + re-advertise on disconnect.
> **Client impact: none required** — CoreBluetooth's filter is OR-semantics and
> `System` is already in the 8-UUID filter, so it works once firmware advertises it.
> **Optional follow-up:** narrow `PeripheralScanView`'s scan from
> `SentinelServiceUUID.cbuuids` (all 8) to just the advertised **System** UUID for
> selectivity, once #67 lands.

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

**Start here: #15 HomeView** (the flagship tab — live sensor data). Everything it
needs exists:
- `peer.bme280` (`BME280Service`) → `readAmbientSample()` / `ambientSampleNotifications()`
  → `BME280Sample` (0.01 °C / 0.01 % / Pa, with `temperatureCelsius` etc.). Enable
  the stream with `setNotifying(true)`.
- Apply the user's unit prefs via `@Environment(AppPreferences.self)`
  (`temperatureUnit.convert(celsius:)`, `pressureUnit.convert(hectopascals:)`).
- Charts: `import Charts` (Swift Charts); the current `HomeView` stub already has the
  firmware-update banner + `chart.xyaxis.line`→`sensor.fill` placeholder to replace.
- **Previews are mandatory** (see the Preview convention above): inject
  `MockBME280Service` for live/steady/empty states — `HomeView` should take
  `any BME280Service` in its init so a leaf preview needs no `ConnectedPeer`.

Then the rest of the tab content, same pattern:
- **#16 LogsView** (`peer.systemEventLog` → `SystemEventRecord` display API),
  **#17 SnapshotLoggingView** (`peer.snapshotHistory`/`snapshotStream` →
  `DeviceSnapshot`), **#18 DeviceView** (`peer.system` + DIS reads from #9; GATT
  explorer). All have `Mock*Service` types for previews.
- **#25 DebugOutputStreamView** — merge `BluetoothManager.bluetoothEventStream()`
  + on-device `DebugStreamService`; unblocks the #12 Debug button.
- **#20 firmware selection** — provides the real `firmwareUpdateAvailable` signal
  that #14's badge/banner already consume.

Done and on `develop` (and merged to `main`): **#33**, **#26**, **#7**, **#8**,
**#9**, **#10**, **#11**, **#12**, **#13**, **#14**, **#19**, **#23** (this session
added #8–#14, #19, #23 + the test plan + post-#19 follow-ups, and merged
`develop`→`main`). Follow the git-flow in
[`architecture/github-infrastructure.md`](architecture/github-infrastructure.md):
branch off `develop`, tag the pre-squash tip (`NN-slug-history`), squash-merge, delete.

**Env note:** the app targets iOS 26.4, so run/test on an **iOS 26.4+ simulator**
(e.g. iPhone 17 Pro). Builds won't install on iOS 18 simulators ("requires a newer
version of iOS"), which manifests as a stale install / generic app icon.
