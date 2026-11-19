<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# G0 interim receipt: workspace layout transport

Status: **interim, for the owner's review; not a G0 pass.** Recorded on 2026-11-19 (UTC). The
fixtures are those of signed local commit `e1977ac1f51f5d976ca28acc102a1a99c51e30b2` (tree
`53fe91665ec84be670fa4c8e03e0cd4efb960ab2`) on `feat/workspace-layout-control`; the evidence comes
from that commit and earlier slices, as the qualification baseline shows. The commits after it
change documentation only. Nothing is pushed.

[plan.md](plan.md) asks G0 to record source, traces, controls and failure cases and to review
that receipt before settling the contract; review gate 2 covers "G0's real receipt and chosen
contract" before production integration. This interim receipt records what P0 has shown so far,
the evidence for it, what that evidence does not cover and the decisions that belong to the
owner. It changes no fixture and clears neither G0 nor P1. A final receipt follows the open
obligations.

## Reading the evidence

Evidence is kept in the project evidence store under
`artifacts/plasma-fusion/2026-11-17-desktop-workflow-scope/p0/`, one directory per step, written
`p0/<name>` below. Each of the 36 directories has a manifest, `SHA256.json` or `SHA256SUMS`. On
2026-11-19 all 36 manifests (3,109 entries) were recomputed from their files with no mismatch or
missing file. Three review notes were added after their manifests and are not covered by them:
`p0/lifecycle-first-restart/REVIEW-1.md`, `p0/lifecycle-review-fixes/REVIEW-2.md` and
`p0/silent-retirement-green/REVIEW-3.md`. Later directories have a `RESULTS.md`. Earlier ones are
named by their red or green step and keep the changed source as `changes-after-<commit>.patch`.
Each task commit's exact tree from `f3e0f50` on appears in its slice's proof: in
`shipping-tree-*.txt` for the early slices, in export, savepoint or launch records later.

A native run is the real KWin fork and plasmashell in an isolated container session. Passing a
scope means `prepare_seed.py --check-result <run> --scope <scope>` succeeded: it needs the scope's
own receipt, zero inner scenario and session codes and, from `55a921f` on, the independent cleanup
qualification ([testing.md](../../docs/parts/testing.md#workspace-layout-transport-probe-p0)).
The process-replacement runner `lifecycle.py` writes its own `lifecycle-result.json` instead and
is outside that cleanup qualification.

## Environment

- Image `localhost/pf-layout-probe:f44-pf5-20261117`, ID
  `1decadab422761dff57b8eda74596f1fd31bd020b4c6c0b4f110fa6fba9765a3`, built in `p0/bootstrap`.
  Its Containerfile asserts KWin `6.8.2-3.fc44.pf5`, plasma-workspace 6.8.3 and Qt 6.11.2.
  Later receipts also record KF 6.32 and Python 3.14.10.
- The existing `tools/vsession/cvsession.sh`, unchanged: private HOME, session bus and runtime
  directory, 1440x900 and `PFV_DRI=1`. 57 of the 59 unpacked `compositor.txt` files in `p0/`
  record AMD Radeon, Mesa 26.2.7 and Linux 7.2.15; two are empty. The view-loss case adds
  `PFV_OUTPUTS=2`. `lifecycle.py` uses its own container.
- Every probe scenario, `lifecycle.py` included, adds one probe panel with two probe widgets beside
  Plasma's default panel, and the mixed case adds its replacement widget to the probe panel. No
  run puts probe widgets on two bars. The zero-probe teardown controls add none.
- The cvsession proofs made before focus observation do not record the image ID, and neither do
  `p0/target-guard-first-attempt`, `p0/target-guard-context-green` and `p0/teardown-baseline`.
  The process-replacement receipts do. The qualification baseline below therefore uses later
  runs, which record both image and tree.

Not covered: KWin 6.8.3, Plasma 6.7, a stock KWin, XWayland, a fixed Qt, real hardware and the
logged-in desktop.

## The transport as built

Both ends are test fixtures in `tools/tests/layout-control/`: the KWin script
`plasmafusion-layout-probe` (provider, `provider.qml`) and the applet `org.plasmafusion.layoutprobe`
(consumer, `consumer.qml`). The provider stays inert without `ProbeAuthorized=true` in the seed's
private KWin configuration. The seed enables only the probe. The placement script does not run,
and the probe registers itself as the fork's tiling provider.

1. **Capability.** `Workspace.transientTiling().registerProvider()` returns the native ownership
   token; `capable` means it was accepted. The probe then registers a second object and calls
   `createTile` with a null output, and both must be refused (`competingProviderRejected`,
   refusal `-1`). The scenario asserts all three, and all 78 frames received in `v06` carry them.
   These are self-tests of the native codes: the probe's own registration was accepted in every
   passing run.
2. **Request.** The consumer writes JSON to its `layoutRequest` field and saves it with
   `writeConfig()`, because desktop scripting reads the saved group, not the unsaved property map.
   Every request has the consumer's boot label and a request number. In target mode the consumer
   adds `version: 1`, the intent (`query`, `prepare` or `validate`), the output name, the handle,
   the frozen view context and its freshness lease. In target mode the provider checks the version
   only for `prepare` and `validate`: a request without an intent or with `query` is served as a
   plain query, and any other intent is refused as `malformed` before any capture. Default mode
   reads but ignores `intent` and `version`, so there every request gets an ordinary online frame.
3. **Wake-up.** The consumer calls `invokeShortcut("Plasma Fusion: Layout Probe Wake")` on
   `org.kde.kglobalaccel` `/component/kwin`. The provider's `ShortcutHandler` has an empty
   sequence, so no key is bound, and starts a scan. Wake-ups coalesce: one arriving during a read
   schedules one more scan. In target mode every context change also starts a scan.
4. **Read.** Each scan looks up the current `org.kde.plasmashell` owner with `GetNameOwner` (in
   target mode also its PID with `GetConnectionUnixProcessID`) and calls `evaluateScript` on that
   unique name to read every probe widget's request.
   Target mode reads a complete inventory of at most 16 widgets and 2048 characters per request,
   and an incomplete read unconfirms records without retiring a consumer. The default reader has
   neither bound.
5. **Publish.** Every scan re-evaluates every saved request and publishes to every widget with a
   readable request, not only to the requester, through `evaluateScript` on the captured
   destination, delayed replies included. A publication is sent without waiting for the previous
   one; only reads are serialized. Data is embedded with `JSON.stringify`, and the shell's applet
   `writeConfig` saves each response.
6. **Identity.** Each provider lifetime holds the alias `org.plasmafusion.LayoutProbe.p<epoch>`,
   requested with `RequestName` flag 4 (do not queue) and released at teardown. It exports no
   objects or methods. The epoch is the MD5 of the native ownership token.
7. **Acceptance.** A consumer accepts an online frame only for its own boot label and current
   request, and only after `GetNameOwner` shows that the current `org.kde.KWin` owner and the
   alias owner are the frame's backend connection. Request and revision order are checked again
   after those lookups. A `NameOwnerChanged` for the bound owner or alias, or for a frame being
   verified, clears state and sends a fresh query. This fences provider lifetimes; it does not
   authenticate the writer. Any session client that can call `evaluateScript` can write a frame
   with the current identities: the scenario's own burst frames are written that way and accepted.
8. **Retirement.** At teardown the provider publishes a cached `offline` frame to its last
   recipients. Receivers become unknown; the frame cannot keep state authoritative.
9. **Deadlines.** Each query owns a one-shot deadline, 100 to 10000 ms and 10000 ms by default.
   Expiry reports unconfirmed. It does not cancel, renumber or retry the query.

In target mode a menu request freezes the confirmed provider lifetime, context generation and
desktop, activity and output IDs before its deferred send. The first popup input sends `prepare`
against that frozen context. Only the single recorded eligible-app or panel-to-popup handoff may
bridge one generation. KWin keeps the captured window, focus surface, desktop and output objects.
Every focus, membership or view event advances a bounded generation and invalidates the reference
instead of choosing another window. `validate` rechecks native state; it is not an acknowledgement.
There is one prepared slot: a competitor is refused `busy`, each consumer's request and refusal
history is bounded, and a refused or busy request cannot become a later capture. Leases are
issued monotonically and exhaustion refuses. A shell surface counts only with the verified shell
PID and the intended native output. Because scans re-evaluate saved requests, one `prepare` can
be published ready and later refused: in `v06` request 9 was ready at revision 75 and
`stale-context` at revision 77.

A ready preparation received in `layout-control-v06`, reformatted. The consumer's trace line also
adds its own `receiverBoot`, which is not on the wire and is omitted here.

```json
{
  "consumer": "1795040089518:0.7750638433230217",
  "epoch": "d1ddaf2f84f022df0900886594932d48",
  "revision": 9, "status": "online", "capable": true, "refusal": -1, "request": 2,
  "preparation": {"intent": "prepare", "ready": true, "reason": "",
                  "token": "d1ddaf2f84f022df0900886594932d48:1"},
  "targetContext": {"epoch": "d1ddaf2f84f022df0900886594932d48", "generation": 4,
                    "desktopId": "54956ad7-363a-46ed-96ae-a6554bad684e",
                    "activityId": "6f50efc6-1c87-42d6-bad9-13cd35f453e9",
                    "outputName": "Virtual-0",
                    "consumerLease": "d1ddaf2f84f022df0900886594932d48:1"},
  "competingProviderRejected": true,
  "backendOwner": ":1.0",
  "identityName": "org.plasmafusion.LayoutProbe.pd1ddaf2f84f022df0900886594932d48"
}
```

Refusals have the same shape with `ready: false`, an empty token and a reason such as
`stale-context`, `busy`, `refused`, `consumer-not-current` or `malformed`. Frames carry no window
IDs, PIDs, app classes, titles or placement records.

## G0 obligations

| Plan G0 item | Status | Evidence |
|---|---|---|
| 1. Wake-up dispatch into the real declarative script | Shown | First-slice receipts: real wake-up, two-widget correlation and native refusal codes (`smoke6`, `u22`) |
| 2. Delivery to the intended live widget, fresh lifetimes, ordering | Shown for read-only state on one panel | Receiver-recorded delivery of native frames to two widgets (`u22`, `y22`, `m03`); driver-injected low/high/middle frames (`u22`); fresh receivers after restarts with plain-query fixtures (`lc-restart3`). The swapped-receiver negative control is an offline checker test. |
| 3. Native capability/refusal reporting; updates from the existing shortcut | Partly shown | Native codes are decoded by self-tests (transport item 1). A refused or absent backend as consumers see it (`unsupported`, the `stock` epoch) has no test at any level. Updates from the existing shortcut are open: the placement script does not run in the fixture. |
| 4. Invalidation on script disable/reload, shell restart, KWin owner replacement | Partly shown | Script unload, then load and start, gives a new epoch and a fresh query, with and without the final frame (`u22`, `y22`, `m03`). In `lc-loss1` and `lc-time1` a stopping KWin also retires the probe: the old shell's consumers receive its offline frames without accepting them and invalidate on the alias release before the shell exits with its compositor (logged, not asserted by `lifecycle.py`). New consumers bootstrap fresh in every passing restart run, as `lifecycle.py` asserts (`lc-restart3`). All restart runs use plain-query fixtures of the `7045b03`, `b137d56` and `3639779` slices. No target-mode fixture was restarted, no consumer outlived its compositor, and the watcher's `org.kde.KWin` branch is unit-tested only. A driver-injected frame claiming the wrong backend is rejected (`u22`). |
| 5. No idle polling, reload as a command, per-action global reconfigure, daemon or new native RPC/object export | Holds in the fixtures | A source property, not a measurement: scans follow wake-ups and context events, deadlines are one-shot and the alias exports nothing. Requests and every scan's responses are saved applet configuration. |

Open items that plan.md or [todo.md](todo.md) place in G0:

- a bounded and serialized read/publish pipeline (plan.md's G0 section): reads are serialized, but
  publications are not awaited and the default reader has no bounds;
- updates from the existing shortcut, which need the existing tiler (plan.md G0 item 3);
- a refused or absent backend as consumers see it (plan.md G0 item 3);
- shell and KWin restarts with target-mode fixtures and current code (plan.md G0 item 4);
- keyboard entry after the panel itself has focus (todo.md's P0 keyboard target preparation and
  the specification's technical-plan list): every run opens the popup with a pointer click, and
  the panel never has keyboard focus first;
- competing requests from probe widgets on two bars (todo.md's P0 competing-bar ordering and the
  specification);
- the G0 checkpoint in todo.md: evidence for every claim, the boundary check and the owner's
  review of the final receipt and any design changes.

testing.md and the P0 proof records also list mutating-action acknowledgements and timeouts, fair
arbitration and a mixed shell/KWin replacement matrix as G0 work; plan.md and todo.md do not name
them.
plan.md puts completion semantics in the contract to establish after G0, and todo.md handles
mutation outcomes in P5.

## Acceptance matrix in P0

| Case (plan.md) | P0 status | Evidence or gap |
|---|---|---|
| Cold start or shell restart with old saved fields | Partly shown | Plain queries: saved response fields exist before the first restart, and every new receiver traces unknown with zero accepted frames before a fresh bind (`lc-restart3`). Prepared intents: refused after their busy holder leaves (`w22`) and across provider reload with consumer replacement (`m03`), both within one shell and KWin lifetime; across a restart only in unit tests. No mutation exists to replay. |
| Stock/absent/disabled/refused backend | Disabled shown; the rest untested | Unload leaves consumers unknown (`y22`). The consumer's `unsupported` state and the provider's `stock` path have no test at any level; no stock-KWin image was run; no UI exists yet. |
| Existing shortcut on/off | Open | Needs the placement script's tiler (P1). |
| Floating requested on B while A is tiled | Open | Needs mutating requests (P5). |
| Tiled transfer A→B with B refused | Open | Needs mutating requests (P5). |
| Keyboard entry after panel focus | Open; a pointer-opened popup is shown | Every run opens the popup with a pointer click, and the panel never has keyboard focus first. In target mode Space in the popup prepares the controlled app, never the panel (`w22`, `v06`); `x22` correlates the key with a query. No activation in `v06` has the panel active, and the dock or desktop branch of the handoff has no test at any level. XWayland is not qualified. |
| App focus change/close/departure while menu open | Shown, non-mutating | Another app's activation, a close, a desktop leave and return, output removal and an activity switch each refuse the old handle (`w22`, `v06`). |
| Two controls for one view; two bars for different views | Partly shown | Two widgets on the one probe panel: one prepared slot, and a competitor is refused `busy` and succeeds only after new explicit input once the holder is gone (`w22`, `m03`). Probe widgets on two bars, different views per bar, fair arbitration and double-toggle prevention are untested. |
| Same provider/view, out-of-order replies | State part shown | Driver-injected low/high/middle frames never regress accepted state (`u22`). Completion acknowledgements do not exist yet. |
| Timeout followed by late confirmation | Query part shown | With a configured publication delay: unknown, then unconfirmed once, then the valid late state on the same query and provider lifetime, with no retry (`v22`). Mutating timeouts are open; todo.md handles mutation outcomes in P5. |
| Provider reload/disable, KWin owner replacement | Partly shown | G0 item 4. |
| Output removal or activity/desktop switch | Shown for one layout | Two virtual outputs, the probe panel and one added activity (`v06`); desktop round trip (`w22`). Hot-plugging a new connector, bars spanning outputs and desktop removal are untested. |
| Manual snap/maximize/fullscreen, placement memory | Open | P0 never admits a window, changes geometry or writes placement memory. |
| UI input and constrained layout | Open | P4 and P6. |

## Contract items in P0

| Minimum semantics (plan.md) | Probe |
|---|---|
| Explicit query/prepare/set intent | `query`, `prepare` and `validate`; no `set` yet. |
| Version, consumer and provider lifetime, request identity, state order; revision separate from completion | In target mode `prepare` and `validate` must be `version: 1`; queries, and every request in default mode, are not version-checked. Boot label and lease; epoch, alias and backend connection; request number; revision. No completion acknowledgement exists yet. |
| View identity checked by the provider | Desktop, activity and output IDs plus the native output object: a same-name output is a new object. |
| Prepared target stays inside KWin | Yes; frames carry only the opaque handle, scalar view IDs, the generation and the lease. |
| Same identity and payload is the same intent; serialized; busy outcome | Conflicting reuse is refused and a repeated preparation is never renewed; one slot, competitor `busy`. |
| Timeout is unconfirmed; no blind retry; a late update only if valid | Shown for queries only. |
| Bounds, early rejection, escaping | Target mode only: 16 widgets and 2048 characters, and malformed preparations and unknown intents are refused before any capture. The default reader has no bounds and ignores the intent. One active and one pending verification per consumer, bounded history. `JSON.stringify` embedding. |

## Evidence index

Cases are the unittest methods in `tools/tests/layout-control/` at that commit, counted from its
own files.

| Commit | Adds | Cases | Evidence (`p0/`) | Native outcome |
|---|---|---:|---|---|
| `f8b7b2b` | Specification, capability map and plan | 0 | Not in `p0/`: the scope folder's `accepted/`, `planning/` and `review/` | None (documents) |
| `f3e0f50` | Wake-up, two-widget correlation, refusal decoding, cached retirement frames, explicit inner results | 8 | `bootstrap`, `mailbox-visibility`, `first-transport-pass`, `registration-refusal` | `smoke6`, then `smoke8` after the `smoke7` red, pass first-slice; earlier attempts kept, none accepted |
| `7045b03` | Reload with a fresh query, unique shell destinations, identity alias, owner checks, wrong-backend rejection | 8 | `reload-red`, `reload-green`, `identity-alias`, `backend-fence`, `backend-fence-savepoint` | Red then green runs for reload, alias identity and the backend fence |
| `1d98b48` | `lifecycle.py`: one private bus across Plasma, then KWin and shell restarts | 26 | `lifecycle-first-restart`, `lifecycle-review-fixes`, `lifecycle-savepoint` | `lc-bus1` (private bus), `lc-restart1` and `lc-restart3` pass with the backend-fence seed (one bus, two backend and three shell connections); `lc-restart2` failure kept |
| `b137d56` | Owner loss invalidates without the final frame; wrapped D-Bus strings; receiver-recorded delivery | 38 | `silent-retirement-red`, `silent-retirement-first-attempt`, `silent-retirement-green`, `silent-retirement-receiver-proof` | `loss-F1`, `normal-F1` and `lc-loss1` pass; red and first attempts kept |
| `8a76135` | Newest queued state within one exchange | 45 | `reply-ordering-red`, `reply-ordering-green`, `reply-ordering-final-proof` | `order-F1`, `order-loss-F1` pass after the `order-R1` red |
| `3639779` | Query timeout without cancel, renumber or retry; valid late state | 61 | `query-timeout-red`, `query-timeout-green`, `query-timeout-final-proof` | `time-F1`, `time-F2` and their normal controls pass after the `time-R1` red; `lc-time1` passes |
| `cc850ff` | Focus observation through a keyboard query in the widget's popup | 71 | `focus-observation-proof` | Focus and normal runs of export11 and export12 pass |
| `e19a1c7` | Guarded-target core, unit-driven and default off | 80 | `target-guard-export14-proof` (`core-source`) | None claimed for the core alone |
| `4e9a86f` | Preparation fenced to its captured native context | 98 | `target-guard-first-attempt`, `target-guard-context-green`, `target-guard-export13-proof`, `target-guard-export14-proof` | `target-F2`, `target-G3` and the normal and timeout regressions pass; the first `target-G1` failure is kept |
| `9eaaff4` | Guard tests split into modules, all 98 cases kept | 98 | `test-split-proof` | None needed (test-only move) |
| `0b2fd06` | Retirement from a complete inventory, leases, busy replay refused | 122 | `consumer-retirement-proof` | `c2` passes after the `C1` failure; `n17`, `t17` regressions pass |
| `920c674` | Receipt checkers extracted, decisions unchanged | 122 | `receipt-extraction-proof` | `de18` passes its scope, using the diagnostic shell-first wrapper |
| `55a921f` | Owned shell stopped first; cleanup qualified independently | 150 | `teardown-baseline`, `teardown-diagnosis-proof`, `owned-cleanup-proof`, `owned-cleanup-publication-recovery` | Export22 runs `u22` to `y22` pass their six scope checks with cleanup; the export20 cleanup failure is kept |
| `8429e05` | Consumer replacement with provider reload; replayed frames and an obsolete preparation | 194 | `mixed-lifetime-proof` | `m03` passes `mixed-lifetimes`; `m01`, `m02` superseded |
| `e1977ac` | Output loss and activity switches | 238 | `view-loss-proof` | `v06` passes `view-loss`; `v01`, `v05` failures kept; `v02` to `v04` superseded |

## Qualification baseline

The latest native pass of each scope, all on image `1decadab4227…`. Every cvsession run listed also
passed the independent cleanup qualification.

| Scope | Run | Tree (commit) |
|---|---|---|
| `first-slice`, `reply-ordering` | `u22` | `32ca7a2b` (`55a921f`) |
| `query-timeout-late` | `v22` | `32ca7a2b` (`55a921f`) |
| `consumer-retirement`, after the guarded-target workflow | `w22` | `32ca7a2b` (`55a921f`) |
| `focus-observation` | `x22` | `32ca7a2b` (`55a921f`) |
| `silent-retirement` | `y22` | `32ca7a2b` (`55a921f`) |
| `mixed-lifetimes` | `m03` | `e1e9e51d` (`8429e05`) |
| `view-loss` | `v06` | `53fe9166` (`e1977ac`) |
| Process replacement (`lifecycle.py`, own receipt, no cleanup gate) | `lc-restart3`, `lc-loss1`, `lc-time1` | Plain-query seeds of the `7045b03`, `b137d56` and `3639779` slices |

Only `view-loss` has run natively at `e1977ac`, which changed `advanceTargetContext` for every
target mode. The six ordinary scope checks last ran at `55a921f` and `mixed-lifetimes` at
`8429e05`. Since `55a921f`, `provider.qml` gained 90 lines and lost 29, all mode-gated diagnostics
and source labels. The unit runners cover every mode. `v06` runs only the target prelude's first
preparation and validation before its own branch. The process-replacement runner last ran with a
`3639779`-slice fixture, before `55a921f` changed its bus helper (method errors are read from
stdout first, and a crashed helper stays a failure). It has never run a target-mode seed. In each
passing restart run `kamd` and the old shell exit 255 when the first KWin stops ("The Wayland
connection broke"), and `lc-restart1` also loses `kded`. The third shell then starts a new
activity manager through D-Bus activation, which the runner does not track.

## Defects, failures and limits

- The original simultaneous sweep aborts plasmashell in a Qt 6.11.2 path that matches the one fixed
  upstream for
  [QTBUG-149316](https://github.com/qt/qtbase/commit/91ec4c85d454802521c76ba861e24b82c9a3b636),
  with zero probe widgets and with the full probe (`p0/teardown-diagnosis-proof`). Its exact
  trigger and frequency are unproved. The fixtures stop the owned shell first; that ordering is
  not a Qt fix. The item is in [DEFERRED.md](../../docs/DEFERRED.md); re-entry needs an approved
  fixed-Qt environment.
- Before `55a921f`, successful runs still printed plasmashell teardown aborts
  (`p0/consumer-retirement-proof`). Qualification now fails on known fatal signatures, which does
  not establish warning-free logs or crash freedom in general.
- `v05` failed because a click raced the shell's activity switch, and plasmashell then aborted in
  the failure-path teardown (the D-Bus-loss class). The driver now waits until both widgets accept
  the switched context. The failure-path abort was not tested again.
- KWin's evacuation of the app and Plasma's move of the panel on output loss were observed on
  this image. They are not a guaranteed placement policy.
- `p0/view-loss-proof/RESULTS.md`, the `e1977ac` commit message and two comments in the hashed
  view-loss fixtures call the panel's two widgets "both bars", as the part page did until the
  commit before this receipt. The fixtures keep that wording so their seed hashes stay valid.
- No clean-LSP claim: host language tooling cannot resolve the image's KWin imports.

## Findings for P1

1. No query is version-checked, and default mode checks no request; only target-mode `prepare`
   and `validate` are checked. P1 can version and check every request.
2. The public epoch is the MD5 of the native ownership token. Nothing requires a published value
   derived from that credential; P1 can publish an independent random label.
3. Both directions are saved configuration, and saved fields survive restarts, so rejecting
   retained fields at start is mandatory. Natively that is shown for plain queries; for prepared
   intents it is shown only within one shell and KWin lifetime.
4. Saved requests are re-evaluated on every scan. A saved mutating request must take effect at most
   once per request identity, however often it is read again.
5. Publications are not awaited and the default reader is unbounded, an open G0 item above. P1
   must keep the read/publish pipeline bounded and serialized either way.
6. In the fixture the probe holds the fork's provider registration itself. In production the
   placement script owns that registration and `tiler.session`, so the provider logic belongs
   there, as P1's planned files already assume.
7. Output-loss placement was observed, not specified; consumers must not depend on it.

## Decisions for the owner

1. Is this transport the basis for P1: saved request and response fields, a sequence-less wake-up
   and `evaluateScript` on the captured unique shell connection? Each request costs one save and
   one wake-up. Each scan costs a shell-owner lookup (in target mode also a PID lookup), two shell
   script calls (read and publish) and one save per widget with a readable request, and each
   online frame costs its receiver two `GetNameOwner` calls. In target mode every context change
   adds a scan. In `v06`, 12 consumer requests and 16 wake-ups, the driver's included, came with
   39 publications to both widgets: 78 response saves. P1's checklist already asks to avoid
   redundant per-frame publication.
2. Does the identity-only alias, approved for P0 only, become the production owner fence? It
   fences provider lifetimes and does not authenticate the writer (transport item 7).
3. How should the open items be met? Some answers change the G0 definition and say so.
   - The bounded, serialized read/publish pipeline is in plan.md's G0 section. Fixing it in the
     probe is a P0 fixture change, for example waiting for each publication to finish before the
     next read and bounding the default reader. Accepting it as a P1 requirement instead changes
     the G0 definition.
   - Updates from the existing shortcut are plan.md G0 item 3. They need the placement script to
     publish, which P0 excludes, so proving them in P1 changes the G0 definition.
   - Keyboard entry after panel focus, probe widgets on two bars, restarts with target-mode
     fixtures and a refused backend stay within P0 fixture scope. How to give the panel keyboard
     focus in the isolated session is not yet established, and an absent backend also needs a
     stock-KWin test image.
   - Action acknowledgements and timeouts are G0 work in testing.md and the proof records, not in
     plan.md or todo.md. Deferring them to P5 appears consistent with both (todo.md's P0
     "timeout/late reply cases" do not say whether they include mutations); testing.md would then
     be corrected. plan.md's G0 section also says to stop if the candidate cannot satisfy the
     accepted specification, which bears on whether a transport-level acknowledgement belongs in
     G0. Kept in P0, the
     probe could call the native functions the placement script uses: `createTile` and
     `admitTile` return result codes synchronously, and `admitTile` needs the provider token,
     which the probe discards after hashing. The probe would then admit windows, which its own
     contract forbids (`provider.qml`, testing.md), and the placement script's session policy
     would still be untested. A probe-owned simulated mode would exercise only the transport part:
     plan.md allows a stand-in only to match an observed API and forbids building UI on a
     transport that only works in a stand-in.
   - Fair arbitration and a mixed shell/KWin replacement matrix are G0 work only in testing.md and
     the proof records; moving them to P7 would mean correcting testing.md. Competing-bar ordering
     is in todo.md's P0 list, so moving it would change the G0 definition.
4. Before sign-off, should every scope be run natively again at the final G0 tree?

Recommended order: answer 1 to 4 first. The P0 fixture cases that plan.md and todo.md place in
G0 come next. A refused backend and keyboard focus of the panel have no test at any level, but
each first needs a way to produce that state in the isolated session. Probe widgets on two bars,
the pipeline fix if decision 3 keeps it in G0, and a current target-mode seed through
`lifecycle.py` extend existing mechanisms; the restart case would cover query, inventory and
lease bootstrap, but not prepared intents across a restart, because the runner has neither an
input driver nor a controlled app. Acknowledgement and timeout work follows decision 3. In P0 it
would exercise the transport part of "Timeout followed by late confirmation", and with the
native-call option also the native result codes; qualification stays with the real lifecycle
suites. If decision 4 is yes, the sweep runs at the final tree, and the final receipt replaces
this one.
