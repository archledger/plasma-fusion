<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# G0 receipt: workspace layout transport

Status: **final, for the owner's review; G0 passes only with that review** ([todo.md](todo.md),
"Checkpoint G0"). Recorded on 2026-11-20 (UTC). The fixtures are those of signed local commit
`6e133be1a5a276c629378f5242f74e3b699b5bce` (tree `bc19d0922d0ea70c7c72265c3928814b54dc9c29`) on
`feat/workspace-layout-control`, the last G0 tree, and the final sweep ran on an exact export of
that tree. The commit that records this receipt changes documentation only. Nothing is pushed.

This receipt replaces the interim receipt of 2026-11-19 (commit `0d3d052`, kept in
`p0/g0-interim-receipt`). The interim left four decisions to the owner. On 2026-11-19 the owner
replied "Let proceed with your recommendation"; the agent's answers, adopted under that delegation,
are in [g0-decisions.md](g0-decisions.md). The owner's review of this receipt is the owner's first
review of those answers: the last section lists each one for confirmation, including the changes it
makes to the G0 definition, and the owner can revise any of them. [plan.md](plan.md)'s review
gate 2 covers "G0's real receipt and chosen contract" before production integration. Nothing here
starts P1, changes production code or clears G0 by itself.

## Reading the evidence

Evidence is kept in the project evidence store under
`artifacts/plasma-fusion/2026-11-17-desktop-workflow-scope/p0/`, one directory per step, written
`p0/<name>` below. Each directory has a manifest, `SHA256.json` or `SHA256SUMS`. On 2026-11-20
the 46 manifests of the directories that predate this receipt (4,516 entries) were recomputed from
their files on the storage host, with no mismatch or missing file. The only files they do not cover
are the three review notes the interim named: `p0/lifecycle-first-restart/REVIEW-1.md`,
`p0/lifecycle-review-fixes/REVIEW-2.md` and `p0/silent-retirement-green/REVIEW-3.md`. The final
sweep and that recheck are in `p0/g0-final-receipt`. Every directory from `p0/refused-backend-proof`
on has a `RESULTS.md` naming the commit, its exact tree, its native runs and its review, as the
interim's later directories do; the earliest are named by their red or green step and keep the
changed source as `changes-after-<commit>.patch`.

A native run is the real KWin fork and plasmashell in an isolated container session. Passing a
scope means `prepare_seed.py --check-result <run> --scope <scope>` succeeded: it needs the scope's
own receipt, zero inner scenario and session codes and, from `55a921f` on, the independent cleanup
qualification ([testing.md](../../docs/parts/testing.md#workspace-layout-transport-probe-p0)).
For the seven scopes from `mixed-lifetimes` on (`mixed-lifetimes`, `view-loss`, `refused-backend`,
`pipeline`, `completion`, `two-bar` and `keyboard-entry`) it also recomputes the scope's own claims
from the run's raw logs. The shared `roundtrip-native` check, and view-loss's `guarded-target`, stay
in-session checks wherever the shared startup check runs; the refused-backend mode skips that check,
and its checker recomputes the native results and receivers itself. For the seven earlier scopes
the scenario writes the receipt once its own checks inside the session have passed, and
`--check-result` checks only the receipt, the codes and the cleanup. The process-replacement runner
`lifecycle.py` writes its own
`lifecycle-result.json`; for a target-mode run its `--check-result` recomputes the receivers, the
leases, the kept leases and the pipeline replay from the run's logs and kept configuration, and for
a plain run it checks only the receipt. Bus and connection identities come from the receipt in both
modes. The runner is outside the cleanup qualification.

## Environment

- Image `localhost/pf-layout-probe:f44-pf5-20261117`, ID
  `1decadab422761dff57b8eda74596f1fd31bd020b4c6c0b4f110fa6fba9765a3`, built in `p0/bootstrap`.
  Recorded at the final sweep with `rpm -q` in the image: plasma-workspace 6.8.3-1.fc44,
  libplasma 6.8.3-1.fc44, kwin 6.8.2-3.fc44.pf5, qt6-qtbase 6.11.2-3.fc44, kf6-kconfig and
  kf6-kglobalaccel 6.32.0-1.fc44, python3 3.14.10-2.fc44 and mesa-dri-drivers 26.2.7-1.fc44.
- The existing `tools/vsession/cvsession.sh`, unchanged: private HOME, session bus and runtime
  directory, 1440x900 and `PFV_DRI=1`. All 12 of the final sweep's sessions record AMD Radeon
  (radeonsi, renoir), OpenGL ES 3.2, Mesa 26.2.7 and Linux 7.3.4-arch1-2 (`compositor.txt`). The
  view-loss and two-bar modes add `PFV_OUTPUTS=2`. `lifecycle.py` uses its own container. The
  final sweep ran on CPUs 8-15 under `nice -n 10`.
- Most scenarios, and `lifecycle.py`, add one probe panel with two probe widgets beside Plasma's
  default panel, and the mixed case adds its replacement widget to that panel. The two-bar mode
  adds one probe panel per output, and the keyboard-entry mode removes every panel without a probe
  widget. The zero-probe teardown controls add none.
- Every seed copies the placement script's `Tiling.js` from the stage `shipping-snapshot-17`
  (file dated 2026-11-17); the copy's SHA-256, `85012da2…` in all 16 of the sweep's seed
  manifests, equals that of `packages/kwin/scripts/plasmafusion-placement/contents/ui/Tiling.js` at
  `6e133be1` (`checks/tiling-identity.log` in `p0/g0-final-receipt`).

Not covered: KWin 6.8.3 (the fork has since been released as `v6.8.3-pf1`, while this image runs
`6.8.2-3.fc44.pf5`), Plasma 6.7, a stock KWin, XWayland, a fixed Qt, real hardware and the
logged-in desktop.

## The transport as built

Both ends are test fixtures in `tools/tests/layout-control/`: the KWin script
`plasmafusion-layout-probe` (provider, `provider.qml`) and the applet `org.plasmafusion.layoutprobe`
(consumer, `consumer.qml`). The provider stays inert without `ProbeAuthorized=true` in the seed's
private KWin configuration. The seed enables only the probe. The placement script does not run,
and the probe registers itself as the fork's tiling provider.

1. **Capability.** `Workspace.transientTiling().registerProvider()` returns the native ownership
   token; `capable` means it was accepted. The token only decides that: it is never kept, logged or
   published (`49c65f2`). The probe then registers a second object and calls `createTile` with a
   null output, and both must be refused (`competingProviderRejected`, refusal `-1`). These are
   self-tests of the native codes. A refused registration is covered natively: consumers settle
   `unsupported` (`p0/refused-backend-proof`).
2. **Request.** The consumer writes JSON to its `layoutRequest` field and saves it with
   `writeConfig()`, because desktop scripting reads the saved group, not the unsaved property map.
   Every request has the consumer's boot label and a request number. In target mode the consumer
   adds `version: 1`, the intent (`query`, `prepare` or `validate`), the output name, the handle,
   the frozen view context and its freshness lease. In target mode the provider checks the version
   only for `prepare` and `validate`: a request without an intent or with `query` is served as a
   plain query, and any other intent is refused as `malformed` before any capture. Default mode
   reads but ignores `intent` and `version`.
3. **Wake-up.** The consumer calls `invokeShortcut("Plasma Fusion: Layout Probe Wake")` on
   `org.kde.kglobalaccel` `/component/kwin`. The provider's `ShortcutHandler` has an empty
   sequence, so no key is bound, and starts a scan. In target mode every context change also
   starts a scan.
4. **Read.** Each scan looks up the current `org.kde.plasmashell` owner with `GetNameOwner` (in
   target mode also its PID with `GetConnectionUnixProcessID`) and calls `evaluateScript` on that
   unique name to read every probe widget's request. Every mode reads at most 16 widgets, requests
   of at most 2048 characters, and only a well-formed consumer and request number (`b960025`).
   Target mode also reads the complete inventory, and an incomplete read unconfirms records
   without retiring a consumer.
5. **Publish.** Every scan re-evaluates every saved request and publishes to every widget with a
   readable request, not only to the requester, through `evaluateScript` on the captured
   destination. The pipeline is serialized (`b960025`): a read starts only when neither a read nor
   a publication is outstanding, a publication stays outstanding until the shell's writer call
   reports success or failure, and wake-ups meanwhile coalesce into one later read. Data is
   embedded with `JSON.stringify`, and the shell's applet `writeConfig` saves each response.
6. **Identity.** Each provider lifetime holds the alias `org.plasmafusion.LayoutProbe.p<label>`,
   requested with `RequestName` flag 4 (do not queue) and released at teardown. It exports no
   objects or methods. The label is a fresh public lifetime label, the MD5 of a timestamp and four
   random numbers, independent of the native token (`49c65f2`); frames carry it as `epoch`. Before
   that, every refused lifetime shared one label, the MD5 of the null UUID.
7. **Acceptance.** A consumer accepts an online frame only for its own boot label and current
   request, and only after `GetNameOwner` shows that the current `org.kde.KWin` owner and the
   alias owner are the frame's backend connection. Request and revision order are checked again
   after those lookups. A `NameOwnerChanged` for the bound owner or alias, or for a frame being
   verified, clears state and sends a fresh query. This fences provider lifetimes; it does not
   authenticate the writer (decision 2).
8. **Retirement.** At teardown the provider publishes a cached `offline` frame to its last
   recipients. Receivers become unknown; the frame cannot keep state authoritative. A dropped
   retirement frame is covered too: consumers invalidate on the alias release.
9. **Deadlines.** Each query owns a one-shot deadline, 100 to 10000 ms and 10000 ms by default.
   Expiry reports unconfirmed. It does not cancel, renumber or retry the query.

In target mode a menu request freezes the confirmed provider lifetime, context generation and
desktop, activity and output IDs before its deferred send. The first popup input sends `prepare`
against that frozen context. Only one recorded handoff may bridge one generation: a popup that
opens from the remembered eligible app, or from one of the shell's own dock or desktop surfaces on
the popup's output while that app is remembered (`a5307ad`, the keyboard path). KWin keeps the
captured window, focus surface, desktop and output objects. Every focus, membership or view event
advances a bounded generation and invalidates the reference instead of choosing another window.
`validate` rechecks native state; it is not an acknowledgement. There is one prepared slot: a
competitor, from the same panel or another bar, is refused `busy`, each consumer's request and
refusal history is bounded, and a refused or busy request cannot become a later capture. Leases are
issued monotonically and exhaustion refuses. A shell surface counts only with the verified shell PID
and the intended native output.

A prepare's completion is decided once (`ee89f25`): when the provider first handles the request,
its answer, accepted with the handle or refused with the reason, becomes the request's completion,
and every later frame for that consumer, lease and request carries it unchanged. The frame's
`preparation` re-checks the target on every publication and is reported separately. In the final
sweep's keyboard-entry run, request 2 was decided ready at revision 11, and its next five frames
kept that completion while their preparation reported `stale-context` (`kwin.log:75-115`); request
3 was decided `stale-context`, and its next frame kept that while its preparation reported
`refused`.

A ready preparation received in the final sweep's target run, reformatted. The consumer's trace line
also adds its own `receiverBoot`, which is not on the wire and is omitted here.

```json
{
  "consumer": "1795136377362:0.6571302221531695",
  "epoch": "3ee98326b8e4572aad08e8c759c334ae",
  "revision": 9, "status": "online", "capable": true, "refusal": -1, "request": 2,
  "preparation": {"intent": "prepare", "ready": true, "reason": "",
                  "token": "3ee98326b8e4572aad08e8c759c334ae:1"},
  "completion": {"request": 2, "intent": "prepare", "accepted": true,
                 "token": "3ee98326b8e4572aad08e8c759c334ae:1", "reason": ""},
  "targetContext": {"epoch": "3ee98326b8e4572aad08e8c759c334ae", "generation": 4,
                    "desktopId": "60b4662d-a9ff-4c1d-8387-0915e6cb36d2",
                    "activityId": "b840e0e7-14d8-4230-9f32-82b9d692535a",
                    "outputName": "Virtual-0",
                    "consumerLease": "3ee98326b8e4572aad08e8c759c334ae:1"},
  "competingProviderRejected": true,
  "backendOwner": ":1.0",
  "identityName": "org.plasmafusion.LayoutProbe.p3ee98326b8e4572aad08e8c759c334ae"
}
```

Refusals have the same shape with `ready: false`, an empty token and a reason such as
`stale-context`, `busy`, `refused`, `consumer-not-current` or `malformed`. Frames carry no window
IDs, PIDs, app classes, titles or placement records.

## G0 obligations

The items are plan.md's G0 list as amended on 2026-11-19 (decision 3).

| Plan G0 item | Status | Evidence |
|---|---|---|
| 1. Wake-up dispatch into the real declarative script | Shown | Real wake-ups, two-widget correlation and the native codes (`first-slice`); 24 concurrent wake-ups served by a serialized pipeline (`pipeline`) |
| 2. Delivery to the intended live widget, fresh lifetimes, ordering | Shown, read-only and non-mutating | Receiver-recorded delivery to two widgets on one panel (`first-slice`, `silent-retirement`, `mixed-lifetimes`) and to probe widgets on two bars, one per output (`two-bar`); ordered, never-regressing state (`reply-ordering`); fresh receivers after every restart (`lifecycle.py`). The swapped-receiver negative control is an offline checker test. |
| 3. Native capability/refusal reporting | Shown as amended | A refused registration natively: consumers settle `unsupported` on fresh labels, and a later accepted lifetime goes online (`refused-backend`). An absent backend has unit cases only, which G0 accepts; a stock-KWin run waits for P7. Updates from the existing shortcut moved to P1. |
| 4. Invalidation on script disable/reload, shell restart, KWin owner replacement | Shown | Script unload and reload give a new lifetime and a fresh query, with and without the final frame (`first-slice`, `silent-retirement`); provider reload with consumer replacement rejects replayed frames and an obsolete preparation (`mixed-lifetimes`); `lifecycle.py` restarts Plasma, then KWin and its shell, on one private bus with plain and target-mode seeds, and every new receiver starts unknown and binds fresh. No live consumer sees an `org.kde.KWin` owner change: when the first KWin stops, the second shell's consumers invalidate on the alias release, then exit with their compositor ("The Wayland connection broke"), in every restart run of the final sweep; so the watcher's `org.kde.KWin` branch is unit-tested only. Prepared intents across a restart are unit-tested only too: the runner has no input driver or controlled app. |
| 5. No idle polling, reload as a command, per-action global reconfigure, daemon or new native RPC/object export | Holds in the fixtures | A source property, not a measurement: scans follow wake-ups and context events, deadlines are one-shot and the alias exports nothing. The pipeline run counts reads, publications and saves. |
| 6. A request completion, decided once and kept by newer state frames | Shown without a mutation | The holder's accepted completion survives a context change, a competitor's busy refusal and the holder's stale refusal (`completion`); the same rules across two bars (`two-bar`) and on the keyboard path (`keyboard-entry`). A completion lives in the provider's consumer record, so it holds within one provider and shell lifetime: after a provider restart or a shell replacement the consumer must request again under a new lease. |

On 2026-11-19 (decision 3) updates from the existing shortcut moved from G0 item 3 to P1, and G0
accepts unit evidence for an absent backend, with a native stock-KWin run in P7. Acknowledgements
and timeouts of mutations (P5), fair arbitration and the mixed shell/KWin replacement matrix (P7)
were G0 work only in testing.md and the proof records; testing.md was corrected, and plan.md and
todo.md never placed them in G0.

## Acceptance matrix in P0

| Case (plan.md) | P0 status | Evidence or gap |
|---|---|---|
| Cold start or shell restart with old saved fields | Shown without a mutation | Every new receiver traces unknown with zero accepted frames before a fresh bind, after Plasma and after KWin and shell restarts, with saved response fields present before the first restart; with a target-mode seed the second shell starts with the first shell's target frames in its widgets' configuration and still binds only frames addressed to it, with new leases (`lifecycle.py`). Prepared intents are refused across provider reload with consumer replacement (`mixed-lifetimes`); across a restart only in unit tests. No mutation exists to replay. |
| Stock/absent/disabled/refused backend | Disabled and refused shown; absent by unit cases | Unload leaves consumers unknown (`first-slice`, `silent-retirement`); a refused registration settles them `unsupported` (`refused-backend`); the absent-backend branches are unit cases (`49c65f2`). No stock-KWin image was run, and no UI exists yet. |
| Existing shortcut on/off | Moved to P1 | Needs the placement script's tiler. |
| Floating requested on B while A is tiled | Open | Needs mutating requests (P5). |
| Tiled transfer A→B with B refused | Open | Needs mutating requests (P5). |
| Keyboard entry after panel focus | Shown | Plasmashell's own Meta+Alt+P focuses the probe panel; Space opens the popup and Space prepares the remembered app, never the panel, and after the app has quit the same keys are refused, as `stale-context`, with no target (`keyboard-entry`). The dock branch of the handoff runs natively; the desktop branch has unit cases. One output and one panel; XWayland is not qualified, and the menu's arrow keys, Return and Escape belong to P1's menu. |
| App focus change/close/departure while menu open | Shown, non-mutating | Another app's activation, a close, a desktop leave and return, output removal and an activity switch each refuse the old handle (`target-preparation`, `view-loss`). |
| Two controls for one view; two bars for different views | Shown without a mutation | Two widgets on one panel: one prepared slot, and a competitor is refused `busy` and succeeds only after new explicit input once the holder is gone (`consumer-retirement`, `mixed-lifetimes`). Probe widgets on two bars, one per output: the other bar's prepare is refused `busy` while the holder's completion is kept, and after the holder's panel is removed a new explicit request from the other bar is accepted on its own output (`two-bar`). Fair arbitration (P7) and double-toggle prevention (P5) are untested. |
| Same provider/view, out-of-order replies | Shown for state and completion | Driver-injected low, high and middle frames never regress accepted state (`reply-ordering`); a decided completion is never lost or changed by newer frames (`completion`). Mutation acknowledgements are P5. |
| Timeout followed by late confirmation | Query part shown | With a configured publication delay: unknown, then unconfirmed once, then the valid late state on the same query and provider lifetime, with no retry (`query-timeout-late`). Mutating timeouts are P5. |
| Provider reload/disable, KWin owner replacement | Shown, with G0 item 4's limits | G0 item 4: no live consumer sees an `org.kde.KWin` owner change. |
| Output removal or activity/desktop switch | Shown for one layout | Two virtual outputs, the probe panel and one added activity (`view-loss`); a desktop round trip (`target-preparation`). Hot-plugging a new connector, bars spanning outputs and desktop removal are untested. |
| Manual snap/maximize/fullscreen, placement memory | Open | P0 never admits a window, changes geometry or writes placement memory. |
| UI input and constrained layout | Open | P4 and P6. |

## Contract items in P0

| Minimum semantics (plan.md) | Probe |
|---|---|
| Explicit query/prepare/set intent | `query`, `prepare` and `validate`; no `set` yet. |
| Version, consumer and provider lifetime, request identity, state order; revision separate from completion | In target mode `prepare` and `validate` must be `version: 1`; queries, and every request in default mode, are not version-checked. Boot label and lease; label, alias and backend connection; request number; revision; and a prepare's completion, decided once and kept apart from the revision. |
| View identity checked by the provider | Desktop, activity and output IDs plus the native output object: a same-name output is a new object. |
| Prepared target stays inside KWin | Yes; frames carry only the opaque handle, scalar view IDs, the generation and the lease. |
| Same identity and payload is the same intent; serialized; busy outcome | Conflicting reuse is refused and a repeated preparation is never renewed; one slot, competitor `busy`, also across two bars. |
| Timeout is unconfirmed; no blind retry; a late update only if valid | Shown for queries only. |
| Bounds, early rejection, escaping | Every mode: 16 widgets, 2048 characters and a well-formed consumer and request. Target mode also refuses malformed preparations and unknown intents before any capture. One active and one pending verification per consumer, bounded history. `JSON.stringify` embedding. |

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
| `0d3d052` | Interim G0 receipt | 238 | `g0-interim-receipt` | None (document) |
| `49c65f2` | Refused native backend; lifetime label independent of the native token; absent-backend unit cases | 275 | `refused-backend-proof` | `rg7` passes `refused-backend`; the pre-fix control `rr3` fails on a reused label |
| `3a58946` | G0 decisions record | 275 | `g0-decisions-proof` | None (documents) |
| `b960025` | Bounded, serialized read/publish pipeline with logged reads and publications | 308 | `pipeline-proof` | `pg2` passes `pipeline` (24 wake-ups, 2 reads, 2 publications); controls `pr1`, `pr2` fail |
| `ee89f25` | A prepare's completion, decided once and kept by newer frames | 357 | `completion-proof` | `cg3` passes `completion`; controls `cr1` to `cr3` fail on a changed completion |
| `6017dc3` | Probe widgets on two bars with competing requests | 406 | `two-bar-proof` | `tg11` to `tg16` pass `two-bar`; three of the four provider controls fail as designed, the fourth passes as documented |
| `b3be704` | `lifecycle.py` restarts with a target-mode seed | 432 | `restart-proof` | `t10` to `t12` and plain `p3` pass; controls `ri3` and `ru3` fail |
| `9f3c66e` | Settle wait before the Validate clicks after a context change (a test-side workaround) | 439 | `settle-proof` | 30 of 30 target repeats pass with the wait; regression `st02` passes 13 scopes |
| `a5307ad` | Keyboard entry after panel focus; unit cases for the dock and desktop handoff | 461 | `keyboard-proof` | `k03-1` to `k03-10` pass `keyboard-entry`; control `kr03-1` fails at its first step; regression `kb02` passes 14 scopes |
| `6e133be` | Test scratch directories follow `TMPDIR`; a check against fixed ones | 464 | `scratch-proof` | None needed (no native input changed) |

## Final native sweep

On 2026-11-20 from 00:57:53 to 01:02:24 (UTC), every scope and the process-replacement runner ran
once on `g0-final01`, an exact export of `6e133be1`: `git archive` of the commit, whose 1,499 files
all match their blobs; apart from the sweep's own seeds and runs, the only other files are the
bytecode caches its Python calls wrote. Image `1decadab4227…` by ID, 180 s per session, 240 s with
two outputs. Every scope passed `--check-result`, its cleanup qualification included, with inner
scenario and session codes of 0, and every `lifecycle.py` run passed the runner and its
`--check-result`, which recomputed the target run's receivers, leases and pipeline. Afterwards
`podman ps` listed no probe container. The logs are in `p0/g0-final-receipt`.

| Run (`layout-control-…-g0f1`) | Seed | Scopes | Result |
|---|---|---|---|
| `default` | default | `first-slice`, `reply-ordering` | PASS |
| `refused` | `--refused-backend-probe` | `refused-backend` | PASS |
| `pipeline` | `--pipeline-probe` | `pipeline` | PASS: 24 wake-ups, 23 of them during the read, 2 reads, 2 publications, 4 saves |
| `loss` | `--drop-retirement-frame` | `silent-retirement` | PASS |
| `timeout` | `--query-timeout-ms 200 --reply-delay-ms 2000` | `query-timeout-late` | PASS |
| `focus` | `--focus-probe` | `focus-observation` | PASS |
| `target` | `--target-probe` | `target-preparation`, `consumer-retirement` | PASS |
| `mixed` | `--mixed-lifetime-probe` | `mixed-lifetimes` | PASS |
| `view` | `--view-loss-probe`, two outputs | `view-loss` | PASS |
| `completion` | `--completion-probe` | `completion` | PASS |
| `two-bar` | `--two-bar-probe`, two outputs | `two-bar` | PASS |
| `keyboard` | `--keyboard-entry-probe` | `keyboard-entry` | PASS |
| `lc-plain` | default | process replacement | PASS: one bus, two backend and three shell connections |
| `lc-loss` | `--drop-retirement-frame` | process replacement | PASS: the same |
| `lc-timeout` | `--query-timeout-ms 200 --reply-delay-ms 2000` | process replacement | PASS: the same |
| `lc-target` | `--target-probe` | process replacement and `target-bootstrap` | PASS: the same; the three shells' receivers hold leases E1:1-2, E1:5-6 and E2:3-4, and the kept configuration E1:1-2, as in `p0/restart-proof` |

These 16 runs qualify this receipt; each step proof holds its slice's own GREEN and RED runs. One
pass per scope shows that the final tree passes each one, not how often a run fails: before the
settle workaround the target mode lost a click in about one run in seven, and in none of 30 runs
after it (`p0/settle-proof`).

## Defects, failures and limits

- The original simultaneous sweep aborts plasmashell in a Qt 6.11.2 path that matches the one fixed
  upstream for
  [QTBUG-149316](https://github.com/qt/qtbase/commit/91ec4c85d454802521c76ba861e24b82c9a3b636),
  with zero probe widgets and with the full probe (`p0/teardown-diagnosis-proof`). Its exact
  trigger and frequency are unproved. The fixtures stop the owned shell first; that ordering is
  not a Qt fix. The row is blocked in [DEFERRED.md](../../docs/DEFERRED.md); re-entry needs an
  approved fixed-Qt environment.
- Pointer button events lost or delayed ([DEFERRED.md](../../docs/DEFERRED.md), "P0 pointer
  button events lost or delayed"). In the target scenario's instrumented runs a click sent
  while the shell served a provider publication usually lost its button events: 15 of 18 such
  clicks, against none of 157 outside one (`p0/settle-proof`). Once, in a prelude click with no
  read or publication outstanding, the press arrived about 460 ms late and the release never did.
  Which layer drops them, KWin's delivery or Qt's in the shell, is not established. The target
  scenario waits before its Validate clicks after a context change, a test-side workaround, not a
  fix. Decision 1 makes these publications P1's transport (below).
- The shared prelude's single-panel click timing stays deferred
  ([DEFERRED.md](../../docs/DEFERRED.md), "P0 single-panel prelude click timing").
- Before `55a921f`, successful runs still printed plasmashell teardown aborts
  (`p0/consumer-retirement-proof`). Qualification now fails on known fatal signatures, which does
  not establish warning-free logs or crash freedom in general.
- `v05` failed because a click raced the shell's activity switch, and plasmashell then aborted in
  the failure-path teardown. The driver now waits until both widgets accept the switched context.
  The failure-path abort was not tested again.
- KWin's evacuation of the app and Plasma's move of the panel on output loss were observed on this
  image. They are not a guaranteed placement policy.
- `p0/view-loss-proof/RESULTS.md`, the `e1977ac` commit message and two comments in the hashed
  view-loss fixtures call the panel's two widgets "both bars". The fixtures keep that wording so
  their seed hashes stay valid; the two-bar mode is the case with two bars.
- The keyboard-entry mode covers one output and one panel, with focus given by plasmashell's own
  shortcut. The dock branch of the handoff runs natively; the desktop branch has unit cases only.
- With a target-mode seed, two lease numbers are skipped at every restart. By inference from the
  row counts and lease numbers, they went to the consumers named by the widgets' retained request
  fields, which the first reads after the restart still saw; the provider does not log consumer
  identities for queries. That order was observed, not guaranteed, and a provider that restarted
  its lease numbering with each shell would not be reliably detected (`p0/restart-proof`).
- The pipeline is shown for one burst of 24 wake-ups on one panel and output
  (`p0/pipeline-proof`). Busy wake-ups met an outstanding publication in `pg2`, but in the final
  sweep all 23 met the read. At teardown the offline frame is sent even while a publication is
  outstanding, and a publication the shell never answers holds the pipeline until the D-Bus reply
  timeout, which was not measured.
- The bridge's target waits print nothing on a timeout, so a failing run is located only by the
  last PASS line before it; naming the wait is a [todo.md](todo.md) follow-up.
- No clean-LSP claim: host language tooling cannot resolve the image's KWin imports.

## Findings for P1

1. No query is version-checked, and default mode version-checks no request: only target-mode
   `prepare` and `validate` are, though every mode drops malformed rows (`b960025`). P1 must version
   and check every request (decision 1).
2. The public label is now independent of the native token (`49c65f2`). P1 must do the same: a
   refused or absent backend must not share one label.
3. Both directions are saved configuration, and saved fields survive restarts, so rejecting
   retained fields at start is mandatory. Natively that is shown for plain queries and for the
   target bootstrap; for prepared intents only within one shell and KWin lifetime.
4. Saved requests are re-evaluated on every scan. A saved mutating request must take effect at most
   once per request identity, however often it is read again; the decided completion shows how an
   answer can stay fixed while validity is re-checked.
5. The probe's pipeline is bounded and serialized; P1 must keep it so, and publish only for a new
   request or changed state (decision 1). In the final sweep's pipeline run, 24 concurrent
   wake-ups, 23 of them during the read, were served by 2 reads and 2 publications, 4 saves in all.
6. A publication is an `evaluateScript` call that the shell serves on its main thread, and pointer
   clicks sent during one were usually lost in the test session (above). P1 relies on these
   publications while users interact with the panel, so that row's re-entry comes first: reproduce
   it without the probe and find the dropping layer.
7. The identity alias tells provider lifetimes apart, not scripts. P1 must keep a single
   publisher; a leftover probe or a second copy of the placement script would make consumers drop
   one lifetime and bind to the other on every frame (decision 2).
8. With nothing remembered, a popup's preparation is refused `stale-context`, because no handoff
   bridges the popup's activation, while a request carrying the popup's own context would reach
   the target choice and be refused there (unit cases; its reason, `no-target`, follows from the
   code), a path that has not run natively. No retry can succeed until an app has focus, so P1's
   menu should not present that refusal as retryable.
9. In the fixture the probe holds the fork's provider registration itself. In production the
   placement script owns that registration and `tiler.session`, so the provider logic belongs
   there, as P1's planned files already assume.
10. Output-loss placement was observed, not specified; consumers must not depend on it.
11. The image's KWin is `6.8.2-3.fc44.pf5`, and the fork has since been released as
    `v6.8.3-pf1`. P1's real-session work needs the transport rechecked on the fork it targets.

## Decisions for the owner to confirm

The four decisions were delegated on 2026-11-19 and answered in [g0-decisions.md](g0-decisions.md),
which gives the reasons; confirm or revise each.

1. **The transport is the basis for P1:** saved request and response fields, a sequence-less
   wake-up and `evaluateScript` on the captured unique shell connection. Its cost: each request
   costs one save and one wake-up; each scan, a shell-owner lookup (in target mode also a PID
   lookup), two shell script calls and one save per widget with a readable request; and each online
   frame, two `GetNameOwner` calls by its receiver. That is acceptable only if publications stay
   rare. The conditions are: publish only for a new request or changed state and count
   publications; keep the pipeline bounded and serialized; version and check every request; reject
   retained fields at start and apply a saved mutating request at most once per request identity;
   keep the provider logic in the placement script; and do not let consumers depend on the
   observed output-loss placement. **Risk for this decision:** in the test session, pointer clicks
   sent while the shell served a publication usually lost their button events (15 of 18), and the
   layer is unknown. If that holds outside the test session, users' clicks on panel widgets could
   be lost while P1 publishes. The fixtures only work around it.
2. **The identity-only alias becomes the production provider-lifetime fence,** not writer
   authentication: any unsandboxed session client can write a frame, as the probe's own injection
   tests do, and could equally drive KWin and the shell. Conditions: identity-only, requested
   without queueing and released at teardown, named from the independent lifetime label, and a
   single publisher.
3. **Where the open items are met.**
   - Changes to the G0 definition, which plan.md records: a request completion, decided once and
     kept by newer frames, is added (G0 item 6); updates from the existing shortcut move to P1; and
     an absent backend is accepted with unit evidence, with a stock-KWin run in P7, whose test image
     needs the owner's approval then.
   - Corrections to testing.md; only it and the proof records had placed these in G0, never
     plan.md or todo.md: acknowledgements and timeouts of mutations go to P5, and fair arbitration
     and the mixed shell/KWin replacement matrix to P7.
   - Kept in P0 and done: the bounded, serialized pipeline, a refused backend, probe widgets on two
     bars with competing requests, restarts with a target-mode seed and keyboard entry after panel
     focus.
4. **Every scope ran natively again at the final G0 tree** with the process-replacement runs, and
   this receipt replaces the interim one (above).

If all four stand, G0 passes with this receipt, and P1 can start on the conditions of decisions 1
and 2 and the findings above. If decision 1 is reversed, G0 returns a blocker for scope review, as
plan.md's stop rule says.
