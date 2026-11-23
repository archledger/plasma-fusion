# Part: regression tests (icon positions, performance gate, harness)

Two regression gates that run from the laptop against the ThinkPad in private virtual sessions
(`tools/vsession`), and the harness additions they need:

- **Icon positions and session lifecycle** (`tools/tests/icons/`, BACKLOG M2): desktop icons must
  stay where the user put them through every screen and session event.
- **Performance gate** (`tools/tests/perf/`, BACKLOG M6): the BACKLOG section 8 measurements,
  compared with the section 7 budget and a stored baseline; non-zero exit on a regression.
- **Harness hygiene** (`tools/vsession/`, ADAPTIVE fix 21): new options and input commands, all
  off by default except a free-space guard that only stops a run on a nearly full disk.
- **Adaptive matrix** (`tools/tests/matrix/`, ADAPTIVE 11, TEST-1): one private session per
  configuration (sizes, scales, two outputs, lid, tablet, rotation) with layout assertions.
- **Rubber-band test** (`tools/tests/perf/band.sh`, BACKLOG S5): band selection over 20, 60 and
  100 desktop icons.
- **Depth features** (`tools/tests/depth/`, 2026-10-16): the session scenarios of the features
  that set Plasma Fusion apart, in one run with one summary, before every Plasma update and release
  ("Depth features" below).
- **Field log** (daily use on the laptop, apart from test noise): [fieldlog.md](fieldlog.md).

Status: built and run on HEAD 282b1a5 (the staged HOME tree is byte-identical to the deployed
3a27b3f and to b69fe19); reviewed and fixed afterwards (see "Review" at the end), re-run on the
282b1a5 stage and on HEAD 31affe9 and d4afee8. Not a deployable part: nothing here touches the
real session. Work package TEST-1 (2026-09-30) added the session-slot lock, the teardown fix,
more harness options, the matrix, the band test and new gate rows; see "TEST-1 (2026-09-30)".
Last edited 2026-10-25 (teardown under strict-mode scenarios).
Evidence: the tests build run of 2026-09-30, the maintainer's records (review:
`tests/review-rts/`).

## Files

| File | Purpose |
|---|---|
| `tools/tests/lib/common.sh` | laptop side: `hssh` (ssh with `ConnectTimeout=40`, one retry on a connection failure), `make_seed`, `host_state` (other sessions, load), `session_in_use` (a live session of that name on the host), `run_remote` (remote.sh with one retry when ssh failed before the session started), `host_cleanup` (stop a session by its runtime dir and remove its directory), `host_packages` (Plasma, KWin, Qt, Mesa, kernel and system-wide Fusion package versions), `host_coredumps` (journal core dumps whose environment names a session's runtime dir; needs journal access, the `test` user has it through `wheel`) |
| `tools/tests/lib/pfkwin.py` | in-session: runs a KWin script and prints what it reports (window list with type flags and geometry, outputs with work areas; `maximize CLASS`, `close CLASS`, `run JS`) through a private D-Bus object |
| `tools/tests/icons/run.sh` | M2 driver (three sessions, report, exit status) |
| `tools/tests/icons/scen-1.sh`, `scen-2.sh`, `scen-3.sh`, `lib.sh` | the three session scenarios and their shared helpers |
| `tools/tests/icons/icons.py` | in-session: state capture (plasmashell desktop scripting, KWin windows, StrutManager available rect, core dumps), drag plan, pattern check, per-step comparison |
| `tools/tests/icons/report.py` | laptop: table, screenshot comparison of the icon area, `summary.{md,json}` |
| `tools/tests/perf/run.sh` | M6 driver (quiet-host wait, N sessions, core dumps, gate) |
| `tools/tests/perf/scen-perf.sh` | in-session scenario (the perf-measure study's `scen-perf.sh`, Fusion arm, pointer targets read from the live dock and top bar) |
| `tools/tests/perf/pfstat.py`, `winmon.js`, `analyze_ab.py` | copied from the perf-measure research scripts of 2026-09-30, the maintainer's records (pfstat also records other virtual sessions on the host) |
| `tools/tests/perf/gate.py` | metrics per run, median over runs, budget and baseline verdicts, table, exit status |
| `tools/tests/perf/budget.json` | section 7 budget and the noise margin of every metric |
| `tools/tests/perf/baseline.json` | stored baseline (282b1a5 stage, 1920x1200 at 4/3; per metric the quiet runs; see "Performance" below) |
| `tools/vsession/{vsession.sh,remote.sh,pfinput.py}` | backward-compatible additions (below) |
| `tools/tests/matrix/{run.sh,body.sh,mx.py,check.py,configs.txt}` | adaptive matrix (TEST-1): driver, in-session walk, per-configuration steps, layout judge, the configurations |
| `tools/tests/perf/{band.sh,scen-band.sh,band.py}` | rubber-band selection with 20/60/100 icons (S5): driver, scenario, table and verdict |
| `tools/tests/lib/slot-test.sh` | self-test of the slot lock semantics on a private lock directory |
| `tools/tests/lib/teardown-test.sh` | self-test of `vsession.sh`'s teardown under a strict-mode scenario, with processes ending during the sweep (no session) |
| `tools/tests/depth/run.sh` | the depth features' check: the six features' session scenarios, their seeds, one summary |
| `tools/tests/depth/run-unit.sh` | its unit test with a stand-in session runner (CI `build`) |
| `tools/tests/kwin-backport/run.sh` | the optional KWin backport's session check: the placement scenarios on a stock and a backport test image, one summary (CI `kwin-backport`, docs/parts/ci.md "KWin backport lane") |
| `tools/tests/kwin-backport/run_test.py` | offline image-selection checks: the default stock image follows the supplied KWin RPM version, and an explicit image override is preserved; a KWin 6.8 session without a GPU gets the software render device |
| `tools/vsession/render-device.sh`, `tools/tests/lib/test_render_device.py` | choose a hardware or software render device, verify actual open access in the test context, and test missing-device, denied-open and wrapper-exit cases |
| `tools/tests/kwin-backport/verdict.py`, `verdict_test.py` | its pass rules and their unit test |
| `tools/tests/kwin-backport/native_compare.py`, `native_compare_test.py` | the backport's KWin suites judged against the stock build's (CI `kwin-backport`, native-compare), and its unit test |

## Running them

Both tests take a built HOME tree (`tools/build.sh` output). For a clean result, build it from a
snapshot of a commit, not from the working tree:

```
mkdir -p build/snap && git archive HEAD | tar -x -C build/snap
(cd build/snap && STAGE=$PWD/stage/home bash tools/build.sh)
bash build/snap/tools/tests/icons/run.sh --stage build/snap/stage/home --name icons-x   # ~4 min
bash build/snap/tools/tests/perf/run.sh  --stage build/snap/stage/home --name perf-x    # ~3 min per run, 3 runs
```

Session names must be unique per agent (the host directory is `/var/tmp/pfv-NAME`); both drivers
refuse to start (exit 2) while a session of that name has live processes on the host, because they
would share and finally delete its directory. An interrupted driver (Ctrl-C, SIGTERM) stops its
session by runtime dir and removes the host directory. Results go to
`build/tests/{icons,perf}/results/` unless `--work` says otherwise; `packages.txt` there records
the host's Plasma, KWin, Qt, Mesa, kernel and system-wide Plasma Fusion package versions (the
ThinkPad has the `plasma-fusion` RPM of 282b1a5 plus the decoration and settings RPMs in `/usr`;
the stage in `~/.local` overrides them package by package). Run the perf gate only when no other
virtual session is running (it waits up to `--quiet-wait` seconds, default 600, and judges every
metric's window for noise; only quiet windows count when there are any).

`--save-baseline` writes the file given by `--baseline` (default: `baseline.json` next to the
`run.sh` that runs, which is the snapshot's copy when run from `build/snap`). To update the
repository's baseline from a snapshot run, pass `--baseline <repo>/tools/tests/perf/baseline.json`.

### Workspace layout transport probe (P0)

`tools/tests/layout-control/` contains test-only KWin and applet fixtures, not the production
layout control. The accepted scope and remaining gates are in
[`tasks/workspace-layout-control/plan.md`](../../tasks/workspace-layout-control/plan.md), and the
phase where each open G0 item is met is in
[`g0-decisions.md`](../../tasks/workspace-layout-control/g0-decisions.md).
Nothing in these fixtures installs into the logged-in desktop.

The Python entry point remains `tools/tests/layout-control/test_prepare_seed.py`. Guard cases
live in `target_guard_tests.py`; consumer inventory, lease and retirement cases live in
`consumer_lifecycle_tests.py`; cleanup qualification/ownership cases live in `cleanup_tests.py`.
Combined lifetime, seed and raw-evidence cases live in `mixed_lifetime_tests.py`; output-loss and
activity-switch cases live in `view_loss_tests.py`; refused and absent native backend cases live in
`refused_backend_tests.py`; read/publish pipeline cases live in `pipeline_tests.py`; keyboard-entry
cases live in `keyboard_entry_tests.py`. They share
`qml_helpers.py` with the entry point. The driver
re-exports the classes, preserving existing class selectors and all cases. The support module
names deliberately do not match `test_*.py`, avoiding duplicate default discovery.
Cases make their scratch directories in the default temporary directory, which follows `TMPDIR`;
`ScratchDirectoryTests` rejects a directory fixed in the source, given to a tempfile function or
assigned to `tempfile.tempdir`: a string literal or a name only ever assigned string literals, as
the whole value, or inside a larger expression if one of those literals is absolute.
Package-aware imports also preserve `python3 -m unittest` with the entry file's path.
Target-mode seeds copy and hash `receipts.py`. The shell wait helpers and their Python tests
call its `target-reply` and `consumer-state` entry points. Complete-line event/native parsing is
shared, while each checker's existing correlation rules remain separate; this extraction does
not strengthen the older target checker or settle the production protocol.
Mixed-lifetime seeds additionally copy and hash `mixed_lifetime.py` and `mixed_scenario.sh`.
The scenario is sourced after the existing target/retirement prelude, keeping the main Bash
process responsible for its children and cleanup. Snapshot and partial runtime checks are the
same functions used by the final combined qualifier. View-loss seeds instead copy and hash
`view_loss.py`, `view_loss_scenario.sh` and the `mixed_lifetime.py` complete-line reader that
checker reuses; the mixed scenario itself is not copied. Refused-backend seeds copy and hash
`occupier.qml`, `refused_backend.py`, `refused_scenario.sh` and the same complete-line reader.
Pipeline seeds copy and hash `pipeline.py`, `pipeline_scenario.sh` and the same reader.
Keyboard-entry seeds copy and hash `keyboard_entry.py`, `keyboard_scenario.sh` and the same
reader.

Build `topbar kwin` into a private stage, then make a fresh seed under this worktree's `build/`:

```sh
python3 tools/tests/layout-control/test_prepare_seed.py
python3 tools/tests/layout-control/prepare_seed.py \
    --stage build/layout-control-stage --output build/layout-probe/seed-example
PFV_IMAGE="$IMAGE" PFV_DRI=1 tools/vsession/cvsession.sh \
    layout-control-example tools/tests/layout-control/scenario-bridge.sh \
    "$PWD/build/layout-probe/seed-example" 1440x900 180
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-example
```

`IMAGE` must identify an independently prepared, immutable fork test image. Use a new, short run
name each time: the existing harness puts it twice in a Unix socket path, which must fit 108
bytes including its terminator. The seed preparer refuses an existing output or an output
outside `build/`; it never copies live user configuration. The provider remains inactive without
`ProbeAuthorized=true` in its private KWin configuration.
Every fresh seed also copies/hashes `cleanup.py`, its existing `lifecycle.py` bus helpers and
the private-container marker in `pfv-env`. Old seeds without these inputs must not be reused.

The probe saves each request before waking KWin and records incoming frames separately from
accepted receiver memory. It checks native capability/refusal, two-widget delivery, graceful
retirement, alias release, reload with a fresh query, and rejection of a high-revision frame
claiming the wrong backend connection. Its identity-only alias exports no objects or methods.
The receiver checks the current KWin owner and the alias owner before accepting an online frame;
request and revision checks also run after those asynchronous lookups. Owner-loss events clear
state and advance the query generation even if the final frame never arrives. The current
in-flight verification is watched too, before its first binding is accepted. The workspace
decoder wraps string signal arguments; convert them to strings before comparing connection IDs.
The relevant version-matched APIs are
[the workspace D-Bus decoder and connection](https://invent.kde.org/plasma/plasma-workspace/-/tree/v6.8.3/components/dbus)
and [KConfigPropertyMap::writeConfig](https://invent.kde.org/frameworks/kconfig/-/blob/v6.32.0/src/qml/kconfigpropertymap.cpp).

To test loss without a final frame, create another fresh seed with an explicit fault:

```sh
python3 tools/tests/layout-control/prepare_seed.py --stage build/layout-control-stage \
    --output build/layout-probe/seed-loss --drop-retirement-frame
PFV_IMAGE="$IMAGE" PFV_DRI=1 tools/vsession/cvsession.sh \
    layout-control-loss tools/tests/layout-control/scenario-bridge.sh \
    "$PWD/build/layout-probe/seed-loss" 1440x900 180
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-loss --scope silent-retirement
```

The fault is off by default, recorded in the seed's KWin configuration and covered by its input
hashes. The fault case must prove alias disappearance, unchanged KWin connection, no received
offline frame, unknown receiver state with a newer query, and recovery with a new provider epoch.
Normal retirement still requires both cached frames to reach their intended live widgets, but
those frames cannot keep withdrawn state authoritative: receivers become unknown. An unconfirmed
read does not retarget the cached recipients to the connection that supplied it. A delivery
negative control swaps claimed consumers between receivers; the trace records the emitting
receiver's lifetime separately, so packet claims alone cannot satisfy delivery. The wrong-backend
injection permits legitimate queued replies to advance state, while asserting that no
wrong-owner or injected high revision is accepted. Event-routing unit tests execute the real
QML handler in Node, including wrapped strings and loss during an unbound verification; real
session tests remain necessary to validate D-Bus delivery and state transitions.

The normal scenario also sends a low/high/middle revision burst to each live widget. All six
frames must reach the intended receivers before any burst state is accepted, so the test
actually exercises the pending slot during asynchronous verification. The highest revision must
eventually be confirmed without changing the request or provider binding. Coalescing keeps the
highest pending state only within the complete consumer/request/epoch/backend/alias exchange;
revision watermarks do not hide a different exchange. The queue still has one active verification
and one pending packet.

```sh
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-example --scope reply-ordering
```

That scope requires `reply-ordering-result.json`; a first-slice receipt cannot certify it.
This covers same-exchange query-state ordering, not mixed-lifetime stress or production action
completion acknowledgements.

The query-timeout case uses a short client deadline and delayed native publication:

```sh
python3 tools/tests/layout-control/prepare_seed.py --stage build/layout-control-stage \
    --output build/layout-probe/seed-timeout --query-timeout-ms 200 --reply-delay-ms 2000
PFV_IMAGE="$IMAGE" PFV_DRI=1 tools/vsession/cvsession.sh \
    layout-control-timeout tools/tests/layout-control/scenario-bridge.sh \
    "$PWD/build/layout-probe/seed-timeout" 1440x900 180
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-timeout --scope query-timeout-late
```

The private query deadline defaults to 10000 ms and accepts 100–10000 ms. Reply delay defaults
to zero; the fault accepts up to 3000 ms and must exceed the chosen deadline. It cannot be
combined with `--drop-retirement-frame`: the scenario runs only one of the two cases. The seed
hashes both the provider configuration and client schema. Intervals follow
[Qt's one-shot Timer](https://doc.qt.io/qt-6/qml-qtqml-timer.html), not a real-time guarantee.
Timers are dynamically created with an explicit owner and captured request/destination; see
[Component.createObject](https://doc.qt.io/qt-6/qml-qtqml-component.html#createObject-method).
They do not repeat or poll. Confirmed replies, replacement queries and teardown cancel owned
client deadlines. Provider teardown cancels held publications, whose unique shell destination
is never resolved again when the delay expires.

The case captures the provider alias before creating widgets. Each live consumer must start
unknown, become unconfirmed once, and accept its valid late state on the same query and provider
lifetime. A timeout neither advances the query identity nor retries it. Outbound traces and
native wake counts prove that no automatic retry occurred. Wrong-request high revisions must
remain rejected after the valid late response. A dedicated receipt is required. These are
read-only query checks, not qualification of mutating-action cancellation, retries or outcome
acknowledgements.

The focus observation case uses opt-in diagnostic controls, not production layout-control UI:

```sh
python3 tools/tests/layout-control/prepare_seed.py --stage build/layout-control-stage \
    --output build/layout-probe/seed-focus --focus-probe
PFV_IMAGE="$IMAGE" PFV_DRI=1 tools/vsession/cvsession.sh \
    layout-control-focus tools/tests/layout-control/scenario-bridge.sh \
    "$PWD/build/layout-probe/seed-focus" 1440x900 180
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-focus --scope focus-observation
```

The seed copies and hashes the existing guarded `heldclient.py`; no shared helper is modified.
A controlled Wayland app is activated, the native applet popup takes focus, and EIS sends Space
to the focused control. The case requires the actual received key, a new correlated query, a
live retained eligible app, matching Qt/native output names and candidate clearing after close.
The key trace names its expected query generation before the
[deferred query](https://doc.qt.io/qt-6/qml-qtqml-qt.html#callLater-method).
One shell-log snapshot must show that receiver's key, matching outbound query and accepted state
in order. Native wake evidence must follow the pre-key log baseline; an older online response
cannot certify a newer key. Negative checker fixtures exercise this stale-snapshot case.
It records activation order instead of assuming that keyboard focus and KWin's active window
are identical. App classes stay in backend diagnostics; the client packet no longer includes
the old window identifier. Interactive test controls have explicit accessible names and use
native Qt controls/AppletPopup behavior.

This receipt establishes focus/event/output-name feasibility only. The retained observation
candidate is not a prepared token or guarded captured-view contract: focus-change/view-change
refusal, competing controls and output-object lifetime validation are exercised by the modes
below, and tiler integration belongs to P1. The diagnostic dimensions are not production design
values.

The separate `--target-probe` mode exercises non-mutating preparation and validation:

```sh
python3 tools/tests/layout-control/prepare_seed.py --stage build/layout-control-stage \
    --output build/layout-probe/seed-target --target-probe
PFV_IMAGE="$IMAGE" PFV_DRI=1 tools/vsession/cvsession.sh \
    layout-control-target tools/tests/layout-control/scenario-bridge.sh \
    "$PWD/build/layout-probe/seed-target" 1440x900 180
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-target --scope target-preparation
```

The default-off seed enables the diagnostic focus controls and requires normal transport.
The provider resolves the captured unique shell owner's PID through the existing session bus.
Only a non-normal shell applet popup, dock or desktop surface with that verified PID and the
intended native output may preserve the remembered eligible app. A class/app-id string is not
identity evidence. Native PID/type observations were checked in the private Wayland environment;
this is not an XWayland qualification.

The captured window, focus surface, desktop and output objects stay in KWin. A small diagnostic handle
binds one prepared slot to its shell connection, live widget ID and consumer lifetime. The
provider accepts only versioned `prepare`/`validate` intents, bounds the envelope and rows, rejects
conflicting identities and never renews a repeated preparation. Validation rechecks native state;
it is not a cached action acknowledgement. Focus, membership and view events invalidate the
reference and advance a bounded context generation rather than selecting another window. The
exact captured focus surface must remain live and focused: another shell popup or menu dismissal
also invalidates the preparation, not merely another application. The provider publishes read-only
view/context updates on those events. The menu request freezes the
confirmed provider incarnation, generation and desktop/activity/output IDs before its deferred
send. Every actual focus transition advances that generation, including before capture. The
first received popup input dispatches preparation against the frozen pre-opening context; opening
alone does not send it. Only the recorded single eligible-app/panel-to-popup handoff may bridge
one generation, with the same live candidate and view. Another popup, dismissal or return cannot
use that exception. The provider rejects a stale snapshot before choosing any target. Returning
to an earlier view cannot revive that intent. The accepted preparation context is separate from
the original immutable request and is used for validation. Loss of readiness retains only an
inert last-confirmed diagnostic snapshot so stale-handle rejection can be tested.
Preparation responses contain only intent, readiness, reason and
the handle; context frames contain only their required scalar view IDs and generation, never
window IDs, PIDs, classes or placement records. Each context also carries its consumer's public
freshness lease, not a native writer token or authentication credential. The client copies that
lease with the frozen menu, original request and accepted preparation contexts; a later update
cannot replace it in an outstanding intent. Each target frame also repeats the consumer's decided
completion, separately from the preparation (see the completion case below).

Target mode reads a complete native widget inventory separately from parsed requests. At most
16 widgets and 2048 characters per request are accepted. Unreadable requests leave their widgets
in the inventory with an unknown consumer. Truncation, malformed or inconsistent snapshots and
reader failures unconfirm records; they do not prove absence or free the slot. Only a complete
inventory can retire a missing widget or a confirmed replacement consumer. Inventory is reconciled
on the existing event-driven scans, not an idle polling timer.

The provider retains bounded request/payload/refusal history per current consumer, independently
of the single prepared slot. Repeating a refused preparation keeps its original reason, even
after the holder disappears or the view or focus changes; a new explicit intent is required.
A newer query from a confirmed consumer also advances its request sequence, so a delayed
earlier preparation cannot capture a window. Replacement or reappearance gets a distinct,
monotonically issued lease, so a saved old request cannot revive even if its boot label returns.
Lease exhaustion refuses rather than wrapping.

The native scenario uses the first Space to prepare and the second to validate the controlled app.
It then requires refusal after another app activates, a new explicit preparation followed by
close/refusal, and a desktop
leave/return followed by refusal of the old handle. Each reply must match the receiver, outbound
generation and the native verdict of the accepted revision. Unit cases also cover ineligible/spoofed
focus, destroyed wrappers, membership/activity loss and same-name output-object replacement.
Pre-capture focus/view races and immutable client snapshots also have regression coverage.
Pre-capture popup-to-popup, dismissal and return sequences are regression cases too. A
[window's active flag](https://doc.qt.io/qt-6/qwindow.html#isActive) includes its transient chain;
it is not used alone as the popup-input receipt.
Recorded frame centers are backend-only test input coordinates used to reactivate the controlled
app after close; they are never target/view identity or mode evidence.

The target scenario then prepares through the competing widget, requires a busy refusal, and
removes only the owned holder widget after checking its native ID and current consumer. It
enumerates native applets to confirm removal, wakes the provider and requires a newer accepted
revision that still refuses the same competing request. A new keyboard preparation must succeed
with the surviving consumer's unchanged lease. The checker correlates accepted state with the
exact native verdict revision; merely received or older frames cannot satisfy it.
[Widget::remove()](https://github.com/KDE/plasma-workspace/blob/v6.8.3/shell/scripting/widget.h)
is exposed as a slot; its
[implementation](https://github.com/KDE/plasma-workspace/blob/v6.8.3/shell/scripting/widget.cpp)
destroys the applet. The inventory comes from
[Containment::widgets()](https://github.com/KDE/plasma-workspace/blob/v6.8.3/shell/scripting/containment.cpp),
not the presence of saved request fields.

```sh
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-target --scope consumer-retirement
```

This requires `consumer-retirement-result.json`; the guarded-target receipt alone is insufficient.
It remains a one-slot diagnostic prototype, not the settled production protocol. Mixed lifetimes,
activity/output loss, a completion that newer state frames keep and competing requests from two
bars have their own modes below; fair arbitration belongs to P7, mutating action acknowledgements
and timeouts to P5 and existing-tiler integration to P1. No preparation or validation admits a
window, changes its geometry or writes placement memory.

Each publication is a shell script call (`evaluateScript`) that the shell serves on its main thread.
In the instrumented runs most took under 10 ms, but about one in ten took over 100 ms, up to 0.9 s,
and a click that follows a context change can be sent while the provider is still publishing it. A
pointer click sent while the shell was serving a publication usually lost its button events: 15 of
18 such clicks were lost, the button seeing only a late hover, and none of 157 clicks outside a
publication. A reproduction without the probe lost clicks the same way and traced it to the test
input: every `pfinput` run is its own EIS input client with its own pointer, and the session has no
other, so a shell busy with a script call when a run connects binds its pointer only after the
call, and nothing sent to the pointer before that reaches it; the late hover is the enter that
follows the bind. With one input client held connected for the run, every click sent during a call
arrived when the call returned. The probe itself has not run with a held pointer. Once a prelude
click with no read or publication outstanding lost its release instead: its hover arrived at once,
its press about 460 ms after it was sent, and its release never did. Untraced, it matches a
QtWayland defect ([the blocked queue](../DEFERRED.md)). The scenario works around the publication
case: before each Validate click that follows a context change, it waits until the provider has
observed the change, the receiver holds the provider's newest context and no read or publication is
outstanding. The checker reads the provider's generation and outstanding work from the same log
snapshot (`receipts.py target-settled`; the floor is the provider's context generation before the
change plus the generations the change advances). A read the provider has scheduled but not yet
started does not show in its log, so the wait cannot see one. With the wait no click was lost in 30
native target-mode runs; without it about one run in seven had lost one.

The bridge's target waits (for a reply, the consumer's context, a consumer state, the shell to
settle, the popup, the second app's activation and the owned consumer's removal) each check 40
times, 0.1 s apart. One that gives up prints a single FAIL line naming the wait, what it waited for
and the log that holds its last check's reason; the bridge runs under errexit, so that line is the
last the scenario writes (`TargetWaitTimeoutTests`).

The default-off `--mixed-lifetime-probe` mode composes these boundaries in one ordinary session:

```sh
python3 tools/tests/layout-control/prepare_seed.py --stage build/layout-control-stage \
    --output build/layout-probe/seed-mixed --mixed-lifetime-probe
PFV_IMAGE="$IMAGE" PFV_DRI=1 tools/vsession/cvsession.sh \
    layout-control-mixed tools/tests/layout-control/scenario-bridge.sh \
    "$PWD/build/layout-probe/seed-mixed" 1440x900 180
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-mixed --scope mixed-lifetimes
```

This implies the existing target/focus controls and rejects the other transport faults. After
the guarded-target and busy-retirement prelude, the driver preserves the surviving consumer,
creates one replacement widget and reloads only the provider. Native inventories and accepted
memory must show a new consumer lifetime/lease and provider epoch/alias, while the bus, backend
and shell connections remain unchanged. Unknown memory is observed before the deferred fresh
query; online evidence must follow its exact outbound query and native output attachment.

The driver then re-delivers one unmodified captured preparation frame to the replacement and
two explicitly labeled fence-isolation frames. One changes only the captured frame's surrounding
provider/query fields to exercise a retired consumer; the other retains the retired provider
but uses the survivor's current request and a high revision. These are controlled transport
faults, not new authoritative native acknowledgements. Every exact frame must reach its intended
live receiver, never become accepted state, and be followed by a newer genuine native response
on the unchanged exchange. That response must be received after the receiver's last late frame
and match its own `layout-probe-published` row (below); it drains asynchronous verification, and
an unchanged snapshot immediately after delivery cannot certify rejection.

The survivor's original preparation envelope is replayed once as a labeled driver fault. Its
exact native `consumer-not-current` refusal must reach that consumer. Restoring its current
read-only query is not an automatic consumer retry. Both live receivers must then confirm newer
genuine responses without lease or request replacement. Finally, actual focused Space input
through the replacement must produce one new explicit preparation of the controlled application.
The final native inventory and accepted states must still show both consumers and their leases.
The qualifier scans the retained accepted-state/outbound history, not only final state; hidden
query retries, reused leases, wrong application verdicts and mere success flags fail.
Every accepted packet is checked against the active request timeline, including transient states
later overwritten by recovery. Provider replacement permits exactly one next-generation query
per live consumer, with unknown observed before its deferred send and no unsolicited native
preparation before reload confirmation. The final explicit input is the only further exchange.
After the replay refusal reaches its consumer and the restore call completes, an exclusive
`mixed-restored-boundary.json` records complete-line shell/backend positions. Both recovery
acknowledgements must follow that boundary; an earlier queued reply cannot stand in for them.
Receipt precedes asynchronous receiver verification, so a post-boundary observation alone is
insufficient. Each recovery observation must match its exact receiver-bound receipt after the
boundary and a later native `layout-probe-published` row with the same widget, destination,
consumer, request, epoch and revision. That backend-only diagnostic, which also binds the
late-frame response, is enabled only for this mixed mode and does not add fields to the wire
packet. Thus a pre-restoration packet cannot qualify merely by completing verification or
arriving late after the marker.

This scope requires `mixed-lifetime-result.json`, the `mixed-*` phase/inventory/frame records,
complete shell/backend traces and the existing independent cleanup evidence. A target,
consumer-retirement or ordering receipt cannot stand in for it. The provider and consumer QML
behavior is reused unchanged. This is one captured-frame replay and competing-control
interleaving, not fair arbitration, a mixed shell/KWin process-replacement stress matrix,
actual activity/output-loss testing, mutating action completion or production tiler integration.
Output and activity loss have their own mode below; fair arbitration and the replacement matrix
belong to P7, mutating action completion to P5 and tiler integration to P1. This mode does not
clear G0/P1 or fix the Qt shutdown bug.

The default-off `--view-loss-probe` mode exercises real output-object loss and activity switches.
It needs two virtual outputs:

```sh
python3 tools/tests/layout-control/prepare_seed.py --stage build/layout-control-stage \
    --output build/layout-probe/seed-view --view-loss-probe
PFV_IMAGE="$IMAGE" PFV_DRI=1 PFV_OUTPUTS=2 tools/vsession/cvsession.sh \
    layout-control-view tools/tests/layout-control/scenario-bridge.sh \
    "$PWD/build/layout-probe/seed-view" 1440x900 240
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-view --scope view-loss
```

The mode implies the target and focus controls, rejects transport faults and cannot be combined
with `--mixed-lifetime-probe`. The driver branches right after the target prelude's first
explicit preparation and keyboard validation, while that validation is still live, and changes
only the private session:

1. `kscreen-doctor` disables the output holding the controlled app and the one probe panel,
   which carries both widgets. The retained validation names the removed output and must be
   refused `stale-context` without a context. KWin must evacuate the app, still alive, to the
   remaining output; the panel must follow, and both widgets must keep their consumer lifetimes
   and leases.
2. Re-enabling the output creates a new native output with the same name. The same retained
   envelope must stay refused in a newer context of that output. A fresh validation click that
   re-sends the old handle unchanged, apart from its request number, is refused too.
3. `AddActivity` creates a second activity. After a new explicit preparation and validation on
   the returned output, `SetCurrentActivity` switches away and back; that handle must be refused
   on both sides, including a fresh re-send after the return.
4. With the app remembered again on its own activity, the same control on the other activity
   opens its popup and sends a keyboard preparation. It must be refused without capturing the
   app, which is not part of that view.
5. A final explicit preparation on the original activity must succeed with a new handle.

The driver checks, rather than assumes, KWin's evacuation and restoration of the app and
Plasma's move of the panel; those were observed on the pinned image, not a guaranteed placement
policy. Clicks on the app follow a click on empty desktop, so each one is a real activation.
After an activity switch the next click waits until both widgets accepted the switched context;
one click that raced the shell's own switch handling opened no popup.

In this mode the provider adds a backend-only `layout-probe-view` record to every context
generation advance. It names the native source (`screens`, `current-activity`, `activities`,
`activation`, `window-output` and the other window, desktop and shell-identity events) and
whether a live preparation existed. Each screen entry says whether that native output object was
present when the provider started or appeared in an earlier record (a bounded history), so a
same-name replacement reports a new object rather than the name's old one. Whichever record
first lists the returned name must report it unknown, independent of event order. A diagnostic
reference to the last activated eligible app supplies its class, output, frame and view
membership; decisions never read it and it never enters a packet. The wake shortcut adds a
record without advancing the generation, and the driver uses it to read current geometry. Other
modes emit none of this, and the wire packets are unchanged.

`view_loss.py` binds each step to the complete shell/backend lines between an exclusive
`view-mark-*.json`, written before the native action, and the point where the step was confirmed
(`view-<step>.json`). Before disabling the output, the baseline step requires a ready native verdict
for the retained validation from a completed read that started after the last wake. A read in
flight at the wake cannot qualify, even if its verdict arrived after the wake; a later completed
read without a verdict does not undo one already confirmed. A required event must carry its own
native source, so a broken screens or activity handler cannot
hide behind a focus change. Each refusal must match its exact native
verdict, its actual receipt and accepted memory. The final check recomputes every step from its
window, requires the windows in order without overlap and audits the whole run. Every generation
advance appears once, in order, with a known source. Until the first output change only the
original validation may be re-confirmed. Afterwards readiness occurs only for the three explicit
recovery verdicts, each naming the live app within its own recovery's log span, so a recovered
handle re-confirmed after a later switch fails. Every accepted ready packet must match the exact
exchange of one of these verdicts or of a pre-change re-confirmation of the original validation
that the shell accepts before the output-loss refusal. The guarded consumer sends exactly its six
explicit requests, the read-only consumer sends no target
intent, and all accepted state keeps one provider lifetime and both leases. The checker writes
`view-loss-result.json` from its own check list, and only after this full check passes.

This scope requires `view-loss-result.json`, the view records and inventories, complete traces
and the independent cleanup evidence. It covers one private two-output layout and one added
activity on this image. Hot-plugging a new connector, bars spanning several outputs, desktop
removal, mutating action acknowledgements and production tiler integration remain untested, and
this mode does not clear G0/P1.

The default-off `--refused-backend-probe` mode exercises a refused native registration over the
plain transport, without target controls or transport faults:

```sh
python3 tools/tests/layout-control/prepare_seed.py --stage build/layout-control-stage \
    --output build/layout-probe/seed-refused --refused-backend-probe
PFV_IMAGE="$IMAGE" PFV_DRI=1 tools/vsession/cvsession.sh \
    layout-control-refused tools/tests/layout-control/scenario-bridge.sh \
    "$PWD/build/layout-probe/seed-refused" 1440x900 180
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-refused --scope refused-backend
```

The fork keeps one native provider slot. `TransientPlacementWriter::registerProvider` (tag
`v6.8.2-pf5`) returns a null UUID while another provider holds it or while the writer is busy, and
releases the slot when that provider object is destroyed; the script API returns an empty string
when there is no writer at all. The seed installs the test-only `occupier.qml` as a second KWin
script and starts only that one, so the slot is held before the probe exists, as when another
provider such as the placement script holds it. The occupier logs only its verdict and never
creates tiles, moves windows or writes configuration. The scenario branches before the startup
probe check, then:

1. loads the probe, whose registration is refused, and creates the two widgets; both must settle
   `unsupported`, and no capable state or frame may appear;
2. reloads the probe while the slot is still held; each consumer must drop the first lifetime's
   state, and the second refused lifetime must report a different provider label and alias;
3. unloads the occupier, which releases the slot;
4. reloads the probe, which is accepted; both widgets settle `online` with a third label.

Each load runs only the script it just loaded, through its own `/Scripting/Script<id>` object.
`Scripting.start` would re-read `[Plugins]` and unload a loaded script that is disabled there
(`Scripting::queryScriptsToLoad` in the fork), and this seed disables the probe, so the first
native run of the scenario, which called it, loaded the probe and destroyed it at once. KWin also
runs `Scripting.start` whenever its configuration changes, so a KWin reconfigure during the case
would unload the probe the same way; that fails the case, and nothing in it reconfigures KWin.
KWin numbers a script by the current script count, so the scenario waits until an unloaded probe
is really gone before loading the next one, and requires the numbers 1, 1 and 0: the occupier is
the only other script, until it is unloaded. A different number means the session holds other
scripts than assumed; the number may then also belong to one of them, whose object `run` would
reach instead.

The provider takes its public lifetime label from `newLifetimeLabel()` in `registerNative()`,
independently of the native token and of whether registration succeeded. Before this change the
label was the MD5 of the token, so every refused lifetime shared one label and alias name, as did
every lifetime on a KWin without the API. The ownership token is never kept, logged or published.

`refused_backend.py` binds each step to the complete lines between an exclusive
`refused-mark-*.json`, written before the native action, and the step's confirmation. The final
check recomputes every step and audits the run up to its last step: three initializations
reporting refused, refused and accepted, each with the fork's null-output `createTile` refusal
(`-1`); the occupier registered before the first and released between the second and third;
three distinct labels with identity names derived from them; capable state only in the accepted
lifetime; no consumer reporting a lifetime after it has reported a later one, also between the
steps' windows; and one backend connection. It writes `refused-backend-result.json` only after that
check. This scope also requires the independent cleanup evidence.

Three events can end a consumer's binding to the previous lifetime, and they race: its own
invalidation of the old alias, its acceptance of the old provider's `offline` frame, and the new
provider's first frame, which carries another label. The check accepts any of them. Whichever
won, each consumer must report `unknown` with no packet, log a fresh query and receive its matching
frame before accepting it, and never again report the previous label. The query must be newer
than its previous settled request. Before that drop a
consumer may still accept a newer frame of the previous lifetime: each provider publishes once
per wake, and a consumer verifies one frame at a time, so a step can be confirmed between two of
its acceptances. Such a row is accepted only with the previous lifetime's settled state, label,
alias, capability and request.

This covers a refused registration on this image. A KWin without the transient-tiling API and a
missing writer are covered by unit cases only. In the qualifying native runs every consumer left
each lifetime through its own alias invalidation and accepted every frame of a lifetime before the
next step's mark; the retirement-frame and new-label paths, and a frame accepted after that mark,
are covered by synthetic checker cases only. The consumers'
`unsupported` state is a transport observation; no UI exists yet, and this mode does not clear
G0/P1.

The read/publish pipeline is serialized in every mode. The provider starts a read only when no
read or publication is outstanding; a wake-up during either sets one pending flag, so several
wake-ups coalesce into one later read. The writer's completion or failure resumes the pipeline,
and a delayed publication (the query-timeout fault) that falls due during a read waits for that
read. In target mode a failed shell PID lookup invalidates the context without scheduling another
read; the next wake-up or context event reads again. Every mode's reader visits at most 16 widgets
of at most 2048 characters each and accepts
only a well-formed consumer and request; target mode applied these bounds before. The provider
logs `read started`, `read finished`, each publication it sends and each completion, so a native
run can replay the pipeline. Two limits remain. Retirement at teardown sends its offline frame at
once, even while a publication is outstanding. A publication the shell never answers holds the
pipeline until the D-Bus reply timeout ends it as a failure, which resumes it.

The default-off `--pipeline-probe` mode checks that order natively over the plain transport:

```sh
python3 tools/tests/layout-control/prepare_seed.py --stage build/layout-control-stage \
    --output build/layout-probe/seed-pipeline --pipeline-probe
PFV_IMAGE="$IMAGE" PFV_DRI=1 tools/vsession/cvsession.sh \
    layout-control-pipeline tools/tests/layout-control/scenario-bridge.sh \
    "$PWD/build/layout-probe/seed-pipeline" 1440x900 180
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-pipeline --scope pipeline
```

After the first online exchange and its identity checks, `pipeline_scenario.sh` writes an
exclusive mark and the number of wake-ups it fires, then sends 24 wake-ups concurrently and waits
only for those clients, each in turn, stopping there with a FAIL line unless all of them
succeeded. `pipeline.py` replays every pipeline event of the run up to the settled
step: no read may start while a read or publication is outstanding, at most one publication may
be outstanding, and every wake-up must be followed by a read, so coalesced wake-ups are told
apart from lost ones. Every wake-up of the burst must arrive, at least one must meet a busy
pipeline, and the burst must coalesce into fewer reads than wake-ups. Both consumers must end
online on their current request with a frame the provider published after the mark: the probe's
revision counter starts at zero and rises by one per message, so the publication lines' message
counts bound it. Each settled frame must also match the provider's own consumer, request, epoch
and revision record. A read or publication line the checker does not recognize fails the check. The
settled record keeps the counts of wake-ups, reads, publications and response saves.
`pipeline-result.json` is written only after that record is recomputed from the raw logs, and
this scope also requires the independent cleanup evidence.

With the previous provider and only the two read log lines added, the same scenario failed: a read
started while a publication was outstanding. Which stage a busy wake-up meets depends on timing: in
one passing run every busy wake-up arrived during a read, and in another four also arrived while a
publication was outstanding and were served by the next read. A delayed publication falling due
during a read and target-mode context scans are covered by unit cases. The same rules were also
replayed over the native logs of every other mode's regression run, one provider lifetime at a time
without the teardown retirement frames, with no violation. This mode shows serialization and
coalescing for one burst on one panel. It does not reduce how often a scan publishes, which the G0
decisions require of P1, and it does not clear G0/P1.

The completion that newer state frames keep is part of every target frame (G0 decisions, section 3).
When the provider first handles a consumer's `prepare`, that answer becomes the request's
completion: accepted with its handle, or refused with its reason. The provider keeps it for the
consumer's identity, lease and request number. Every later online frame for that consumer, lease and
number repeats it unchanged until the provider handles a newer request for that consumer, whatever
that frame's own answer is: a conflicting or malformed row at the same number carries it too. The
preparation remains the per-frame re-check: a later frame can report the target no longer valid, or
the context unavailable, while the completion still says the request was accepted. A refused
request's later identical preparations repeat the stored `stale-context` or
`popup-focus-unconfirmed` refusal, while handle exhaustion leaves the generic `refused` outcome.
The completion keeps the original decision. Until the provider handles a request, its frames
carry no completion: while
the context is unavailable, or while the provider does not know the consumer or its lease. A frame
for a request older than the newest one the provider has handled for that consumer carries none, and
neither do validations, queries and retirement frames. A newer valid query advances the confirmed
consumer's request watermark and drops the previous completion. After prepare 2 and query 3, a
replay of prepare 2 returns `stale-or-conflicting-request` without its old completion. The native
target verdict records the completion it published.

The default-off `--completion-probe` mode checks this natively in target mode:

```sh
python3 tools/tests/layout-control/prepare_seed.py --stage build/layout-control-stage \
    --output build/layout-probe/seed-completion --completion-probe
PFV_IMAGE="$IMAGE" PFV_DRI=1 tools/vsession/cvsession.sh \
    layout-control-completion tools/tests/layout-control/scenario-bridge.sh \
    "$PWD/build/layout-probe/seed-completion" 1440x900 180
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-completion --scope completion
```

The scenario branches after the holder's first accepted preparation, while its popup is still
open. `completion_scenario.sh` then:

1. closes the popup, a context change;
2. waits for the competitor's observation and focus control, opens its menu from the app and
   prepares there, which is refused as busy while the holder holds the slot;
3. closes that popup;
4. reopens the holder's menu from the app and creates a virtual desktop while the popup stays
   active, which makes the menu's captured context stale;
5. prepares there, which is refused for that stale context;
6. closes the popup.

Each step is marked before its action. `completion.py` replays every native verdict and received
frame up to each step, in a window with exactly one provider start, because verdicts do not name
their provider lifetime. A prepare's deciding answer must carry a completion that restates it, and
no answer given before the provider touches the consumer's record may introduce one. The checker
enforces that for an unknown consumer or lease, an older or conflicting request and a malformed
envelope, but not for an unavailable context: that answer looks like the unavailable refusal a
decided prepare gets when the provider runs out of handles, so for the holder and the competitor it
is the steps, which require the expected decisions, that rule it out. Every later verdict for that
consumer and request number, whatever its intent or answer, must carry the identical completion
until a verdict shows that the provider handled a newer request for that consumer, and every
received frame must carry exactly what its verdict published. The checker is stricter than the
provider in two respects: a consumer re-leased at its decided request fails it, and so does an older
row that drops its completion after a newer validation the provider handled but answered
`unavailable`, which happens only after handle exhaustion. It keeps the second on purpose: an early
unavailable answer to a validation gives the same verdict, and that one must not supersede the
decision. The steps require the newer frames those actions cause, each accepted from a publication
after the action. After the context change, a frame keeps the accepted completion while its
preparation reports the target no longer valid. The publication that decides the competitor's
refusal also carries a frame that keeps the holder's completion. After each refusal, a later frame
keeps it. `completion-result.json` is written only after every step record is recomputed from the
raw logs, and this scope also requires the independent cleanup evidence.

The previous provider published only the per-frame answer. Published as the completion, that answer
made the same scenario fail at the first context change: a completion changed after its decision. In
the passing run the stale refusal's preparation changed to `refused` on the next frame while its
completion kept `stale-context`. Natively this covers one holder and one competitor on one panel and
output: an accepted completion kept across context changes and another consumer's request, and busy
and stale-context refusals. A popup-focus refusal, an unavailable context, a replaced consumer, an
advanced request and a conflicting or malformed row at the decided number are covered by unit cases.
The completion lives in the provider's consumer record, so a provider restart or a shell replacement
does not carry it over; the consumer gets a new lease and must request again. It is not a mutating
acknowledgement, which belongs to P5, and this mode does not clear G0/P1.

Two bars, one on each output, compete for the provider's one slot in the default-off
`--two-bar-probe` target mode, which needs a session with two outputs:

```sh
python3 tools/tests/layout-control/prepare_seed.py --stage build/layout-control-stage \
    --output build/layout-probe/seed-two-bar --two-bar-probe
PFV_OUTPUTS=2 PFV_IMAGE="$IMAGE" PFV_DRI=1 tools/vsession/cvsession.sh \
    layout-control-two-bar tools/tests/layout-control/scenario-bridge.sh \
    "$PWD/build/layout-probe/seed-two-bar" 1440x900 240
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-two-bar --scope two-bar
```

The bridge puts each probe widget on its own panel instead of both on one. A scripted panel
starts on screen 0
([ScriptEngine::createContainment](https://github.com/KDE/plasma-workspace/blob/v6.8.3/shell/scripting/scriptengine.cpp)),
so the second is moved with its `screen` property, which
[Containment::setScreen](https://github.com/KDE/plasma-workspace/blob/v6.8.3/shell/scripting/containment.cpp)
passes to the shell to move the panel. That bar's consumer can send its first request for output 0
before it sees the move; it then refreshes once. Neither panel floats: a scripted panel floats by
default and moves into its floating position after its control first reports where it is, and a
click during that move reached the desktop instead of the control. The holder is the bar on the
first output: it prepares from the app there, as in target mode, and the scenario branches while
that accepted preparation is still its current request. `two_bar_scenario.sh` then:

1. closes the holder's popup and opens a second app, `pf.focus.beta`, on the other output, whose
   desktop it clicks first so that KWin places the app there;
2. opens the other bar's menu from that app and prepares there, which is refused as busy while the
   holder holds the slot;
3. with that popup still open, removes the holder's panel, found by its consumer, marks the logs
   and wakes the provider;
4. closes the popup, reopens the other bar's menu from its app and prepares again, a new explicit
   request.

`two_bar.py` replays every native verdict and received frame up to each step, in a window with one
provider start, and applies the completion rules to both bars. Each bar's output is the screen its
control last reported, and the two must differ. Once a bar's control has reported that output,
every frame the bar accepts with a view must carry that output's view, so a frame for the other
bar's view, or one view shared by both, fails; frames accepted before that report answer the
request the consumer sent before it saw the move. The other bar's busy refusal must be published
together with a frame that keeps the holder's accepted completion. The scenario marks the logs once
the holder's panel is removed. A scripted
[Containment::remove()](https://github.com/KDE/plasma-workspace/blob/v6.8.3/shell/scripting/containment.cpp)
destroys the panel, and the
[destruction](https://github.com/KDE/libplasma/blob/v6.8.3/src/plasma/private/applet_p.cpp)
signals it before deleting it, which
[removes it](https://github.com/KDE/libplasma/blob/v6.8.3/src/plasma/corona.cpp) from the
containments that the scripting
[`panels()`](https://github.com/KDE/plasma-workspace/blob/v6.8.3/shell/scripting/scriptengine_v1.cpp)
lists; the undo notification belongs only to a removal from the user interface. The scenario also
repeats the provider reader's walk after the removal and stops unless the holder's panel and widget
are gone. So no read started after the mark may answer the holder, while a read already under way
may. A read publishes before it logs its end, so every publication after the mark must come from
the latest read started before it, one that has not ended yet. A read that ends without publishing
answers nobody, so it is the first publication after the first read started after the mark that
must answer the other bar's refused request, before any context change since the refusal; the
other bar must accept a frame from that publication or a later one. The refused request must never
be answered ready again. This provider repeats the stored `busy` outcome then, and a prepare it
does not handle afresh is only re-validated, never prepared, so only the new explicit request is
accepted, with the native capture of `pf.focus.beta` on that bar's output and a frame carrying its
own view. Each retirement publication consumes one distinct read. `two-bar-result.json` is
written only after every step and the later complete log lines are checked, and this scope also requires
the independent cleanup evidence.

Three changed providers each made the same scenario fail at the step meant to catch them. One that
lets the other bar's prepare take the held slot failed at the competing request, which was not
refused as busy. One that gives every bar the active output's view failed at the first step, when
the other bar accepted the holder's view. One that retries a refused prepare by itself once the slot
is free, evaluating it again on each read and preparing it afresh while its exchange has no handle,
failed at the retirement step: it answered the busy request ready with `pf.focus.beta` while the
completion still said busy. Dropping the stored outcome alone does not do that, because a prepare
that is not handled afresh is only re-validated: in that run the busy request's later answers
changed to `consumer-retired` and then `stale-context`, still refusals, and the case passed.

Natively this covers two bars on two outputs of one session, one holder at a time, and a holder
that retires because its panel is removed. Two controls for the same view, on one panel, are the
holder and competitor of the target and completion modes. Fair arbitration between bars belongs to
P7 and double-toggle prevention to P5; this mode does not clear G0/P1.

Keyboard entry after panel focus has its own default-off `--keyboard-entry-probe` target mode:

```sh
python3 tools/tests/layout-control/prepare_seed.py --stage build/layout-control-stage \
    --output build/layout-probe/seed-keyboard --keyboard-entry-probe
PFV_IMAGE="$IMAGE" PFV_DRI=1 tools/vsession/cvsession.sh \
    layout-control-keyboard tools/tests/layout-control/scenario-bridge.sh \
    "$PWD/build/layout-probe/seed-keyboard" 1440x900 180
python3 tools/tests/layout-control/prepare_seed.py \
    --check-result vsession-out/layout-control-keyboard --scope keyboard-entry
```

The bridge branches once the controlled app is active and the focus consumer holds a context that
remembers it, before any pointer opens the popup. `keyboard_scenario.sh` first removes every panel
without a probe widget: plasmashell's 'Move keyboard focus between panels' shortcut (Meta+Alt+P)
focuses the first panel, which would otherwise be the session's default one. It then:

1. presses Meta+Alt+P, so the probe panel becomes the active window as a shell dock with the app
   still remembered; waits until the consumer holds the context after that activation; presses
   Space, which the panel's focused control takes to open the popup; and presses Space in the popup
   to prepare. The provider must prepare the remembered app, `pf.focus.alpha`, never the panel;
2. closes the popup and quits the app, so that the provider remembers nothing, and repeats the same
   keys from the desktop: the preparation must be refused with no target. With nothing remembered
   the popup's activation bridges no generation, so the request is refused as stale before any
   window is chosen (the native runs show `stale-context`); `target_guard_tests.py` covers that
   choice refusing a shell popup with nothing remembered.

A popup that opens from the app, or from one of the shell's dock or desktop surfaces, may bridge one
generation with the app the provider remembers (the handoff above). This mode exercises the dock
part of that rule natively. `target_guard_tests.py` covers both surfaces, two panels in a row, a
request from before the panel had focus, a dock the shell does not own, a dock on another output
and a panel with nothing remembered. The key on the panel waits for the consumer to hold the
panel's context because the popup's request carries the context the consumer held when its control
was activated, and an older one is refused as stale. The key in the popup deliberately has no
settle wait (`receipts.py target-settled`), which also waits out reads and publications: a key lost
while the shell serves a publication would show here. None has been: in the reproduction's traces
(target mode, above) the seat has its keyboard from the shell's start, so a key, unlike a pointer
event, never waits for the shell to bind a new device. `keyboard_entry.py`
recomputes each step from the raw logs, from a mark set before its shortcut: the panel's activation
as the shell's dock with the expected app remembered or none, then the popup with nothing activated
in between, the focus consumer's keyboard preparation after its popup took focus, and the
provider's first verdict for that request, given in that popup before anything else was activated.
That verdict decides the request's completion, which restates it (its reason, and a handle only when
it is ready) and which a frame the consumer accepted must carry. No verdict in the run may name
anything but the app or no target.
`keyboard-entry-result.json` is written only after that recomputation, and this scope also requires
the independent cleanup evidence. A provider without the dock and desktop part of the handoff
refused the first keyboard preparation as stale, and the case failed there.

This covers one output and one panel with two probe widgets, with keyboard focus given by the
shell's own shortcut. The menu's arrow keys, Return and Escape belong to P6's menu; this mode does
not clear G0/P1.

`--check-result` requires the explicit selected-scope receipt, successful inner scenario/session
codes and independent cleanup qualification. The wrapper's exit code alone is insufficient.
`reload-result.json` and
`identity-fence-result.json` record the additional assertions; none of these certifies full G0.
The silent-retirement scope requires its own receipt and cannot use the first-slice receipt.
Action completion/timeout behavior, target preparation and existing-tiler integration need their own
evidence.

The feature-owned cleanup helper captures the original direct shell child, its controller,
UID/start times, private HOME/runtime and current bus/backend/shell owners before the cases.
It refuses root, non-container, foreign or symlinked contexts. A later owner cannot replace that
capture. At successful case ends it rechecks the unique bus owner's PID and opens a
[process descriptor](https://docs.python.org/3.14/library/os.html#os.pidfd_open), rechecks the
identity after opening it, and sends one
[descriptor-bound SIGTERM](https://docs.python.org/3.14/library/signal.html#signal.pidfd_send_signal).
An exclusive request record is saved before signalling; an interrupted or concurrent attempt
cannot silently repeat the effect.
The descriptor wait is bounded; there is no by-PID/group fallback, escalation or retry. Bash,
the real parent, supplies the actual child wait status. The existing shared EXIT cleanup is
neither replaced nor suppressed and still runs after an error.
The shared fixture bus helper prioritizes qdbus's typed stdout method error over auxiliary
locale stderr; only `NameHasNoOwner` means withdrawal. Other bus failures still fail the run.
Signal-terminated helper commands remain failures even if they printed that error first.

`cleanup-identity.json`, `cleanup-request.json`, `cleanup-stopped.json` and
`cleanup-result.json` are separate from
functional state receipts. Every serialized process copy is type-validated independently;
numeric equality alone is insufficient. Qualification requires matching records, actual child
exit0, unchanged bus/backend identities, shell-owner withdrawal, successful inner/outer codes and a
completed sweep with no residuals or forced SIGKILL. Missing/partial evidence and known fatal
signatures in retained logs fail, including an abort that occurs despite functional0/0.
Nonfatal D-Bus/PipeWire warnings and bounded wait-loop assertion failures are not blanket errors;
this gate does not establish warning-free logs or universal crash freedom.

The original simultaneous-sweep controls reproduce the same normalized Qt D-Bus backtrace with
zero probe widgets and with the full probe. The affected Qt6.11.2 path matches
[QTBUG-149316's upstream fix](https://github.com/qt/qtbase/commit/91ec4c85d454802521c76ba861e24b82c9a3b636).
Shell-first cleanup is a fixture ordering correction, not a patched or tested Qt remedy.
The original concurrent-sweep failure remains separate negative evidence; its exact dependency
trigger and frequency remain unproved. See [the blocked queue](../DEFERRED.md).

`lifecycle.py` is the separate, P0-only process-replacement runner:

```sh
python3 tools/tests/layout-control/lifecycle.py --name layout-control-lc-example \
    --seed "$PWD/build/layout-probe/seed-example" --image "$IMAGE"
```

It requires a full 64-digit image ID, a private authorized seed and unused results. Its own
container has no network or inherited host bus/display, adds no capabilities, and removes KWin's
file capability only in its disposable overlay before running as `test`. A short fixed Wayland
socket name avoids the existing harness's doubled-path limit. It never changes `tools/vsession/`.
For the keyboard-entry probe, the preparation key waits for the focused item in the
current popup, not just its active window. The checker requires acceptance after that
key and matches its completion to the public handle returned by the first native
preparation, even if a later frame has rechecked it as no longer ready.

Both internal entry points require the disposable-container marker before any filesystem or
D-Bus side effect, not just matching HOME/runtime strings. Owner readiness uses one lookup and
retries only `NameHasNoOwner`; other bus errors remain failures.

The supervisor owns the private bus independently of KWin. It restarts Plasma, then KWin and its
shell, retaining the same HOME and bus. The receipt requires one bus UUID, two different backend
connections and three different shell connections. Each receiver must first trace unknown with
zero accepted frames, then bind a fresh response, and no receiver of one shell may reappear in a
later one; saved response fields must exist before the first restart. The replaced backend's alias
must disappear. These checks use
[D-Bus GetId and GetNameOwner](https://dbus.freedesktop.org/doc/dbus-specification.html#bus-messages-get-id),
not a process name or a generic service Boolean.

Results go to `vsession-out/<name>/`, with explicit `lifecycle-result.json`, per-process logs,
receiver observations, versions and child exit statuses. Cleanup stops only children it started
and the container ID created by that invocation; a stop it cannot confirm keeps the ID file and
fails the run, which reports PASS only after the stop. Container teardown also removes private
bus-activated services. Missing receipts, changed bus identity or reused connection identities
fail the run.

A target-mode seed runs the same restarts and adds the target bootstrap to the receipt
(`"mode": "target"`, check `target-bootstrap`):

```sh
python3 tools/tests/layout-control/prepare_seed.py --stage build/layout-control-stage \
    --output build/layout-probe/seed-lc-target --target-probe
python3 tools/tests/layout-control/lifecycle.py --name layout-control-lc-target \
    --seed "$PWD/build/layout-probe/seed-lc-target" --image "$IMAGE"
python3 tools/tests/layout-control/lifecycle.py \
    --check-result vsession-out/layout-control-lc-target
```

Each shell's two receivers count only once their frames carry a view context of their own provider
lifetime with a consumer lease. Leasing only consumers that a complete inventory confirmed is the
target-mode inventory rule above; this runner does not test it. Their frames carry neither a
preparation nor a completion, since a fresh receiver has only queried. No two receivers' leases are
the same; the restarted shell's receivers get later leases in the same provider epoch, and the
replacement KWin starts a new epoch. Once the first shell has exited, the saved response fields it
leaves must hold its receivers' leases (a query's saved request carries an empty lease key too, so
only responses count). The run keeps that configuration as `shell-1-appletsrc`, and the receipt
records the leases its responses hold. The second shell therefore starts with retained target frames
in its widgets' configuration. Before the third starts, the first KWin's teardown leaves its offline
frames, which carry no lease, in those fields, and that restart has no such control. The receivers
of both restarted shells still first trace unknown and bind only frames addressed to them, with new
leases. After the container exits, the runner rechecks the run from its files, as `--check-result`
also does without writing anything: the receivers recorded for each shell must be in its raw log,
have started unbound, name that shell's backend connection and give the receipt's leases; no receiver
may appear in two shells, the receipt's saved leases must be those of the kept configuration's
responses, and each KWin lifetime's log must pass the replay's serialization rules up to its
teardown, with at least one read and one publication. Stopping drops a queued delayed publication
and sends the offline frame even while a publication is outstanding, so nothing from the offline
frame on is replayed. A plain seed's receipt only adds `"mode": "plain"`; a receipt without a mode
still checks as plain.

In every target-mode restart run so far with the unchanged provider, its first reads after each
restart still saw the widgets' retained request fields, which name the previous shell's consumers.
Under the new shell those are new consumers and took the next leases, one per widget whose retained
request was read first, before the live receivers sent their own requests: two lease numbers skipped
at every restart. That order was observed, not guaranteed. Two changed providers failed the target
run: one that recognized consumers by widget instead of by consumer lifetime gave the restarted
shell's receivers the previous shell's leases ("two receivers got the same lease"), and one whose
wake-ups started a read while another was running passed in the container and failed the recheck of
the first KWin's log. Restarting the lease numbering with each shell is not reliably detected: while
the retained identities take the reused numbers first, the receivers' leases stay distinct and
later, and only a receiver whose own request reached the first complete read would get a reused one.
The runner has no input driver or controlled app, so no prepared intent crosses a restart here; a
refused intent across a provider reload with consumer replacement is the mixed-lifetime mode's case.

Wayland clients can exit when their compositor stops. This runner proves fresh bootstrap after
real replacement, not that an old widget survives compositor loss or invalidates correctly
without a retirement frame. Those lifecycle cases remain separate G0 obligations. Ordinary
missing-system-service warnings in a container are not evidence about the live desktop.

### Icon positions (M2): `tools/tests/icons/run.sh`

Options: `--stage DIR`, `--name NAME` (default `icons`), `--work DIR`, `--scale S` (default
1.333333), `--size WxH` (default 1920x1200), `--keep`, `--strict`.

1. **Session 1** (one output, 1920x1200 at 4/3, logical 1440x900): `fusion-config.sh --install`,
   12 files in `~/Desktop`, then with plasmashell stopped the primary desktop containment is
   switched to Folder View with the BACKLOG M1 settings (`plugin=org.kde.plasma.folder`, `url
   desktop:/`, `sortMode -1`, `arrangement 1`, `alignment 0`, `iconSize 2`, `labelWidth 1`,
   `textLines 2`, `previews true`, `popups false`, `toolTips false`, `selectionMarkers true`,
   `useTypeAhead true`, `locked false`). This is test setup only; the Global Theme and the layout
   script are not changed. Six files are dragged with real EIS pointer input into a non-default
   pattern (file01 to column 5, row 4; the others to (3,2), (8,1), (2,6), (10,7), (6,1)); the drag
   targets come from plasmashell's available rect (`/StrutManager`) and Folder View's cell formula,
   and the result is verified in the saved positions. That state is the baseline. Then, one step at
   a time: plasmashell restart, KWin reconfigure, scale 4/3 → 1 → 4/3, portrait (rotation left)
   and back, dock hidden by a maximised Konsole and shown again, dock set to auto-hide and back to
   "dodge windows".
2. **Session 2**: a new session on the same HOME (log out, log in).
3. **Session 3**: the same HOME with two outputs (docked laptop): check at login, disable the first
   output (lid closed), enable it again, disable the second (monitor unplugged).

After every step it records the containment's `positions` entry for the original resolution
(`1440x900`), `ItemGeometries-1440x900`, the live card geometries, KWin's window list and the core
dumps whose environment names the session, and takes a screenshot. The report compares the icon
area of each screenshot with the baseline screenshot.

Step result: **PASS** (the entry is byte-identical to the one before the step and every file keeps
its baseline cell), **REWRITTEN** (Plasma saved the entry again during the step, with a new
hash order or grid header, but every file keeps its cell and the icons look the same on screen),
**FAIL** (a file changed cell, the icons look different, a card moved, a pop-up stayed open or a
core dump appeared). The column "entry = baseline (bytes)" is the literal M2 acceptance (byte-
identical to the original). Exit status 0 without FAIL (`--strict`: every step PASS), 1 with a
FAIL, 2 when the setup failed (pattern not reached, a live session of the same name, or any of the
eleven steps without a result, e.g. because session 2 or 3 did not start). When session 1 fails,
sessions 2 and 3 are skipped (they would test a fresh HOME).

Limit: the drag targets assume Folder View's minimum cell width of 96 px (icon size 2, label width
1), which holds while `Kirigami.Units.gridUnit` is at most 20 px (fonts up to about 10.5 pt).
With a larger UI font the cells grow, the drags miss and the run stops with "pattern not reached"
(exit 2), not with a wrong result.

### Performance gate (M6): `tools/tests/perf/run.sh`

Options: `--stage DIR`, `--runs N` (default 3), `--name NAME` (default `perf`), `--work DIR`,
`--size`/`--scale` (default 1920x1200 at 1.333333, the ThinkPad panel at 4/3), `--baseline FILE`
(default `tools/tests/perf/baseline.json`), `--save-baseline`, `--label TEXT` (default the short
commit), `--strict-budget`, `--quiet-wait SEC`, `--app-icons familiar` (draw the familiar app icons
after the install; default `designs`, what the baseline was measured with), `--arm stock` (Fedora's
stock Plasma in the same session and scenario: no install, an empty HOME; the sweep crosses the
stock panel's task icons, x +10..+420, and "quick settings" is the system tray's expander, 150 px
from the panel's right end; no gate, the runs are kept). Stock against Fusion: run single sessions
of each arm in turn (stock, Fusion, stock, ...) under `vslot.sh --exclusive`, then
`tools/tests/perf/analyze_ab.py RUN_DIR...` prints the per-arm table. After the measured steps the
scenario opens quick settings once more for a screenshot (`qs-check.png`) of the target.

Each run is one session (the perf-measure method): `fusion-config.sh --install`, a fresh
plasmashell, KWin reconfigure, 30 s settle; idle 30 s with the pointer mid-screen; a 10 s dock
hover sweep across the dock's middle line (paced at 8 ms, but every motion also waits up to 10 ms
for KWin's events, so about 975 motions, 98 per second, as in the perf-measure study; the count
is recorded, and a sweep with fewer than 800 motions makes the sweep rows MISSING); the launcher
(Meta) three times; quick settings three times; Konsole and KWrite, Alt+Tab held 1.2 s three
times; Overview (Meta+W) three times. `pfstat.py` snapshots every session process around each
step (CPU ticks, PSS, i915 GEM and render-engine time from fdinfo); frame timing is KWin's own
per-frame CSV
(`KWIN_LOG_PERFORMANCE_DATA=1`, written to `out/` with `PFV_CWD=out`); window mapping times come
from `winmon.js`.

Launcher timing requires the structured window records emitted by `winmon.js`: one plasmashell
AppletPopup (window type 18) with positive dimensions per opening. The normal full-screen dimmer
and tooltips do not count. Missing, ambiguous or malformed card records invalidate the launcher
rows; all three openings in every usable run must be measured, not just whichever ones succeeded.
The A/B report also labels incomplete launcher aggregates `INVALID` and exits 1. The gate refuses
a requested run set containing an unusable run (for example, a missing input marker), rather than
dropping that run and saving a partial result.
The first-frame endpoint is the first output presentation whose composition starts after that
card maps. This is an **output-wide proxy**, not surface-specific presentation feedback; the
virtual backend uses synthetic presentation timestamps. It must not be described as the exact
instant the card reaches a physical display. The input marker still precedes Meta-down, not
Meta-release. These boundaries are unchanged by QML's own queued `frameSwapped` log.

Results store the launcher contract `applet-popup/output-composition-after-map/v1`. A baseline
without that exact contract is incompatible (exit 6), even if its numbers look plausible. Older
launcher values could select the dimmer and cannot be converted by changing their metadata.
Keep those files as historical evidence. Use `--baseline ''` for budget-only analysis, or record
a separately named baseline with matching inputs after validating the measurements.

The owner approved separate response ceilings on 2026-10-28, replacing the original 50 ms
mixed-opening budget:

| Metric | Per-run value | Absolute ceiling |
|---|---|---|
| `launcher_first_open_ms` | First opening's input-to-first-frame time | 150 ms |
| `launcher_cached_max_ms` | Slower of openings 2 and 3 | 80 ms |

For these two rows the budget verdict uses the **maximum across the selected runs**, not their
median. One slow first open or cached reopen must not disappear among faster observations.
The existing per-metric quiet-window selection still applies; a noisy-only result is labelled
as such, not proof of quiet performance. Relative regression checks still compare medians
against the baseline range with the existing noise margins. The table shows median and range
so both the typical result and the value tested against the ceiling remain visible.

The ceilings come from two completed, corrected-oracle campaigns on the ThinkPad at
1920x1200, scale 4/3: 12 first opens ranged from 113.393 to 142.540 ms, and 24 cached opens from
36.475 to 75.962 ms. These are provisional limits for that measured configuration, not a
physical-display latency guarantee or a percentile estimate. Passing them does not waive
memory, GPU, visual, functional or other failures.

Split response results also store `launcher_response_contract: first-open/cached-max-per-run/v1`.
A baseline lacking this contract or either requested response metric is incompatible (exit 6).
Reanalyze retained, valid card-aware raw runs into a **new** baseline file; do not relabel a mixed
summary, overwrite historical evidence or launch another benchmark just to convert its format.

The 300 ms settling budget is unchanged and still uses the median of the three openings per run.
Each card ID, mapping/timing result, first opening and cached-opening median remains available
in `per_run[].noise.launcher_timing`. The legacy mixed first-frame value remains a diagnostic in
`per_run[].metrics`, not a default budget row. First opening means after the fresh-session workload,
not cold filesystem caches. Animation settling remains an output-idle estimate, not a card-specific
animation-completion signal.

Offline oracle tests run in the build workflow and locally without a desktop:

    python3 -m unittest discover -s tools/tests/perf/tests
    node --test tools/tests/perf/tests/winmon.test.js

The table has one row per metric: the median over the runs (min..max), the applicable budget and
its verdict, the baseline median (min..max) and the baseline verdict. Noise is judged per metric
window (for example `idle0`..`idle1` for the idle rows): a run's window is noisy when `pfstat.py`
saw another virtual session with live processes at either end of it, or when the host spent more
CPU outside this session during it than 25 % of a core plus a quarter of the session's own CPU
(machine busy time from `/proc/stat` minus the session's process ticks; this catches sessions that
came and went inside the window, builds and the logged-in user; windows without another session
measured 4-14 %, windows next to one 33-235 %). A run's value counts for a metric only when its
window was quiet; when no run was quiet for a metric, all runs are used and the row says
"(noisy)". The CPU
outside and inside the session per window, the host's load, the other sessions before and after
each run and the host's package versions are stored with the result. A metric **regresses** when
its median exceeds the baseline's maximum by more than its noise margin, max(abs, rel × baseline
median) from `budget.json` (margins from the spread of the perf-measure runs); "better" is the
mirror image. A metric the baseline has but no run produced is **MISSING** (the launcher or quick
settings did not open, no KWin frame log, the sweep did not run) and fails the gate. Exit status:
0 no regression, 1 regression or MISSING (with `--strict-budget` also any budget failure), 2 setup
or internal error (also a `--baseline` file that does not exist; `--baseline ''` judges the budget
only), 3 no usable run, 4 the baseline is for another geometry, 5 worse than the baseline only in
noisy windows, 6 an incompatible launcher timing or response contract. Budget failures do not fail
the gate by default because most rows fail today (see
the baseline below); the gate stops things from getting worse, `--strict-budget` is for when M4/M5
have landed. When the host's packages differ from the baseline's the gate prints a note: re-record
the baseline after a Plasma, KWin, Qt, Mesa or kernel update.

Metrics: idle frames/s, idle CPU of plasmashell, KWin and the whole session, idle plasmashell GPU,
dock sweep CPU of plasmashell and KWin and plasmashell GPU, plasmashell PSS and session PSS after
settle, plasmashell GEM after settle, after the first launcher open (growth) and after one round of
use, KWin RSS with two windows, launcher first open, worst cached reopen and animation end, quick
settings first frame, Alt+Tab first frame and animation end, Overview late frames per cycle.
Not encoded from section 7:
the frame-time rows (render p95 during pop-up animations, overview render p95, missed vblanks,
GUI-thread time per frame), quick settings "first frame at most 50 ms after the release" (only
"not slower than stock" is), and the device-only and desktop-file rows.

### DRM counter availability

`pfstat.py` uses `drmstats.py` to sum the advertised memory regions, not only i915's `system0`.
This includes xe's `gtt` allocations. Duplicate descriptors are counted once per driver, PCI
device and client ID. Memory units are converted to KiB before the existing MiB presentation.
Shared memory is already part of the total; it is not added again. These are buffer allocations,
not a dedicated-VRAM measurement or memory that can be added to PSS without overlap.

Engine time is available only when all observed clients report nanoseconds. xe's cycle counters
are not nanoseconds, so its GPU-time rows remain unavailable rather than showing false zeros.
Missing counters, changed processes, decreases in a process's summed counter and non-positive
intervals also produce an unavailable time measurement. The snapshots retain process totals,
not individual client/engine counters: a client reset or disappearance can go undetected if
another counter's increase masks it. A supported counter explicitly reporting zero remains zero.
Memory counters without a unit are bytes, including nonzero values; engine time still requires
`ns`, as specified by the [DRM client-usage format](https://docs.kernel.org/gpu/drm-usage-stats.html#memory).
Comparisons must keep unavailable values separate from budget passes.
Old xe snapshots containing the previous parser's artificial zero values must be recollected;
they do not contain enough information for the analyzer to repair them after the fact.

`python3 tools/tests/perf/perf_test.py` tests i915 and xe fixtures, units, duplicate/device identity,
partial/missing/malformed counters, true zeros, process/counter resets, KWin time-per-frame
conversion, invalid intervals and table precision. KWin intervals are checked before frame rates
are calculated, so equal timestamps remain unavailable rather than causing division by zero. It
runs in the `build` workflow. The existing `tools/tests/perf/tests` suite also runs the real
A/B CLI on two synthetic sessions to check a mean of 0.5 late frames. Fractional counts are
printed as fractions instead of rounded to zero; the budget and its verdict are unchanged.
Nonintegral counts use a round-trip decimal representation, preserving small nonzero averages
and fractions near an integer. Other units keep their existing display precision.

## Depth features (2026-10-16)

The next queue's item 5 (approved 2026-10-16): reliability is part of a depth feature (the
2026-10-14 report: macOS 27's Spaces regressions dominated an otherwise rich release). Each
feature the queues added has a session scenario, run when it was built; `tools/tests/depth/run.sh`
runs them together against one built HOME tree, with one summary:

| Feature | Scenario |
|---|---|
| window placement memory | `packages/kwin/tests/vsession/scenario-placement.sh` |
| snap groups | `packages/kwin/tests/vsession/scenario-snapgroups.sh` |
| dynamic workspaces | `packages/kwin/tests/vsession/scenario-workspaces.sh` |
| copy text from the screen | `packages/copytext/tests/vsession/scenario-copytext.sh` |
| Quick Look | `packages/quicklook-cpp/tests/vsession/scenario-quicklook.sh` |
| live chips | `packages/plasmoids/org.plasmafusion.livechips/tests/vsession/scenario-livechips.sh` |

    tools/build.sh                                   # the HOME tree, stage/home
    cmake -S packages/quicklook-cpp -B build/ql && cmake --build build/ql
    cmake --install build/ql --prefix "$PWD/build/ql-install"
    tools/tests/depth/run.sh --quicklook build/ql-install        # the test host (ThinkPad)
    tools/tests/depth/run.sh --image localhost/plasma-fusion-test:f44-6.8beta --quicklook DIR  # the beta lane

- The test host needs what the test image has for the scenarios besides Plasma: Kate and Okular,
  Tesseract with its English data, wl-clipboard, dbus-python, PipeWire's Pulse server and tools,
  and Qt's `qml` tool for copy text's target window (`qml6` on Arch, `qml-qt6` from
  `qt6-qtdeclarative-devel` on Fedora; the scenario takes either). Without them the features fail
  where they need them (copy text logs `tesseract: command not found`). Nothing else may log in
  over SSH during a run: the live chips count the host's SSH logins.
- Every feature's seed is the HOME tree at `~/pf-stage` and `tools/` at `~/pf-tools`; the live
  chips' adds their stand-ins (`fake_status_items.py`, quick settings' `mock_power.py`) and the
  widget's debug rule (`~/.config/pfv-env`); copy text's sets `PLASMA_FUSION_COPYTEXT_NO_OVERLAY=1`
  there, as its scenario drives Spectacle's selection (on a test host with the
  `plasma-fusion-copytext` package the session bus would start the overlay instead: 9 checks failed
  on the ThinkPad on 2026-10-18, after DEPLOY-10; the overlay has its own scenario,
  `packages/copytext-cpp/tests/vsession/scenario-overlay.sh`); Quick Look's adds its install below
  `~/.local`, its
  service menu made executable there (KIO takes one outside the system directories only so;
  `cmake --install` writes it 0644)
  (`--quicklook`, required while Quick Look is among the features: tools/build.sh does not build a
  compiled part; for the beta lane, Quick Look built in the beta build image).
- The live chips' first check depends on the lane: on the test host the harness's own SSH login
  shows the SSH chip; a test container has no system bus and so no logind (podman's
  `/run/.containerenv` tells the scenario it is in one), where the widget shows no SSH chip. Qt's
  D-Bus helper reports no missing-bus error to QML, so that lane asserts the absent bus and the
  chip state rather than a logind diagnostic line, and the capsule and panel of step 4 come
  without the login.
- One run per work tree (a lock on it): a second run on the same tree is refused (exit 2), as it
  would delete or mix the first one's results; a container run also refuses while a container
  session of the same name (`pfv68-NAME-<feature>`) is running. Results a rootless container left
  (owned by subordinate ids, `cvsession.sh` copies them with `cp -a`) are cleared through podman's
  user namespace (`podman unshare rm`) when a plain `rm` cannot.
- The two lanes keep their own results: `build/tests/depth/host` and
  `build/tests/depth/container-<image>` unless `--work` says otherwise. The test image
  (`tools/container/test/Containerfile`) has what the six scenarios run besides Plasma: Kate,
  Okular and KCharSelect, Tesseract with its English data, wl-clipboard, dbus-python, and PipeWire
  with its Pulse server and tools.
- Results: `build/tests/depth/results/<feature>/` (checks, `scenario.log`, screenshots, logs,
  core dumps) and `summary.md` / `summary.json`. A feature passes only when its session ran to the
  end (`scenario rc=0` and `session rc=0` in `scenario.log`, so not stopped at its time limit, and
  the session runner succeeded), every check passed (at least one), and no core dump came from its
  session (on the test host `coredumps.json` must be there and empty). Exit 0 only when every
  feature run passed; 2 for a setup error: an option without its value, an unknown or empty
  `--features` list (a name is matched whole, as a fixed string: `[p]lacement` is unknown; a name
  given twice is refused, as its second run would replace the first one's results), or
  Quick Look among the features without `--quicklook`. Each session takes a
  session slot, the container lane's too.
- When: before a Plasma update is let onto the test machines (the plasma-watch issue names it) and
  before a release tag (docs/RELEASING.md, step 2), on the test host and on the beta container.
- GitHub's runners cannot run it (KWin's session screenshots need a GPU, docs/parts/containers.md);
  CI runs its unit test, `run-unit.sh`, with a stand-in session runner: every feature passing (exit
  0), Quick Look skipped without its install, a feature broken on purpose (exit 1, named in the
  summary), a feature without checks (exit 1), a session stopped at its time limit after passing
  checks (exit 1), a runner that fails after a complete-looking session, a core dump (exit 1),
  each feature's seed, chosen features only, relative `--stage`, `--quicklook` and `--runner`, an
  unknown feature, one given as a pattern (`[p]lacement`, `place.ent`) or twice, Quick Look's service menu
  executable in its seed, an empty feature list, Quick Look without its install and an option without its value
  (exit 2), `--help` printing the usage only, the two lanes keeping their own results, a second run
  on the same work tree refused while the first runs, and results the user cannot remove cleared
  through a stand-in `podman unshare`. Without
  any one of those rules its case fails.

## Touch latency scenario

`packages/kwin/tests/vsession/scenario-latency.sh` checks pointer and touch opens of the status
sheet, launcher requests and the clipboard shortcut. It keeps a no-input EIS connection with
touch capability alive before restarting plasmashell, through the final tap. The restarted
Wayland client can therefore bind `wl_touch` before the measured input begins.

Without a persistent device, a headless compositor can add touch capability at each `pfinput`
invocation and process the first down event before plasmashell's `get_touch` request. A release
arrives without its down, and Qt delivers no tap. This was reproduced on stock and backported
KWin 6.7.5; a Wayland trace showed only `wl_touch.up` for the failing taps. The scenario's keeper
sends no events, is stopped on normal completion, and belongs to the existing session teardown
on failure. It does not change touch handling in the shipped UI.

## Harness additions (`tools/vsession`)

All defaults keep the previous behaviour exactly: with none of the new variables set, a session
has the same environment, working directory, configuration and input as before (checked: one
plain session with the old and one with the new harness; plasmashell's environment keys, `SHELL`,
`LANGUAGE`, `PWD`, working directory, config keys and the pfinput log are identical, the
screenshot differs only in the panel clock). Each file was replaced by writing a temporary file
and renaming it.

| File | Addition | Default |
|---|---|---|
| `vsession.sh` | `PFV_TABLET=on\|off\|auto` (kwinrc `[Input] TabletMode`), `PFV_ANIM=FACTOR` (kdeglobals `[KDE] AnimationDurationFactor`), `PFV_FONT_PT=PT` (kdeglobals `font`, `menuFont`, `toolBarFont`, family kept; review: the family is read through the session's cascade, so a Global Theme's `kdedefaults` family is kept instead of becoming Noto Sans), written into the HOME before KWin starts with `kwriteconfig6` (offscreen) | unset: nothing written |
| `vsession.sh` | `PFV_LANGUAGE=LIST` and `PFV_SHELL=PATH` put `LANGUAGE` and `SHELL` into the session environment and (review) into the private bus's activation environment, so bus-activated services such as krunner get them too (Konsole's "SHELL is not set" warning, RTL runs); the names go through `$PFV/bus-env`, written only when set | unset: not in the environment, no `bus-env` |
| `vsession.sh` | `PFV_CWD=DIR` (relative to the run root): the session's working directory, e.g. `out` so KWin's `KWIN_LOG_PERFORMANCE_DATA` CSV is fetched with the results instead of landing in the host user's HOME | unset: the ssh login directory, as before |
| `vsession.sh` | scenario helpers `pfv_font PT`, `pfv_anim FACTOR`, `pfv_tablet MODE` (write with `--notify`, so the running KWin and Plasma apply it; needed after `fusion-config.sh`, which sets the fonts on its first run), `pfv_restart_shell [SETTLE_S]`; defined in the inner shell, not exported, so no program's environment changes | only exist |
| `remote.sh` | free-space and inode guard before a run: at least `PFV_MIN_FREE_MB` (2048) MiB in `/var/tmp`, `PFV_MIN_TMP_MB` (256) MiB in `/tmp`, `PFV_MIN_INODES_PCT` (10) % free inodes where the file system counts them (btrfs does not), and `PFV_MIN_LOCAL_MB` (512) MiB locally for the results; `PFV_NO_GUARD=1` skips it | on; it only stops a run on a nearly full disk |
| `remote.sh` | passes `PFV_TABLET`, `PFV_ANIM`, `PFV_FONT_PT`, `PFV_LANGUAGE`, `PFV_SHELL`, `PFV_CWD` on when set; `PFV_SSH_OPTS` adds ssh options (e.g. `-o ConnectTimeout=40`) to every ssh, scp and rsync | unset: the same command lines as before |
| `pfinput.py` | `keydown KEY`, `keyup KEY` (keys still held at the end are released before the client exits: KWin 6.7.5 crashes when an EIS client exits holding a key; key names are checked before anything is sent); `tap X Y [HOLD_S]` and `swipe X1 Y1 X2 Y2 [SECONDS]` (touch; requested from KWin only when used or with `PFINPUT_TOUCH=1`); `sweep X1 X2 Y SECONDS` and `mark LABEL` (from the perf study's pfperf.py; about 98 motions/s; review: marks without `PFINPUT_MARKS`/`PFPERF_MARKS` go to `$OUT` or `$PFV/out`, never to the working directory, which is the host user's HOME); optional `drag` arguments `STEPS STEP_S PRESS_HOLD_S DROP_HOLD_S` for slow drag-and-drop; 77 more key names (letters, digits, F1-F12, Delete, Home, End, ...) | existing commands unchanged |

Smoke run `ts-smoke1` (all options on): plasmashell had `SHELL=/bin/bash` and `LANGUAGE=ar`,
kwinrc `TabletMode=on` and KWin reported tablet mode, `AnimationDurationFactor=0`, the font at
12.75 pt; the helpers changed them at run time; taps and swipes reached KWin through the touch
device; a `keydown ctrl` left at the end was released ("releasing held key 29"); an unknown key
name stopped the client before it sent anything; no core dumps. `ts-tabnotify`: `pfv_tablet on`
and `off` switch KWin's `tabletMode` property at run time (false, true, false).

Not done from ADAPTIVE fix 21: adding a second output after login (the virtual backend has a fixed
output count; the M2 test uses `PFV_OUTPUTS=2` and disables/enables outputs instead) and the
virtual keyboard.

## TEST-1 (2026-09-30): slots, teardown, harness options and new suites

Work package TEST-1 of the one-pass plan. Builder `o1ts`; the lead took the lane over at 04:19Z
and finished it (review notes in `build/o1ts/REVIEW.md`).

Session slots. Every private session and container build is wrapped in the laptop's slot lock
`build/lead/vslot.sh` (N slots in `build/locks/slots`, 4 today; `--exclusive` takes every slot for a
performance measurement; `--build` is the single container-build lock). The drivers take it
themselves (`tools/tests/lib/common.sh`: `pf_vslot`, `slot_prefix`, `pf_locks_held`; a driver
started under `vslot.sh` uses the slot it runs in). The perf gate and the band test hold every slot
and the build lock for each run; started under a single slot they refuse (exit 2).
`remote.sh` refuses to start (exit 75) while the host user's inotify instances or watches are
above `PFV_INOTIFY_MAX_PCT` (75) % of the limit; the drivers retry such a start.
`slot-test.sh` checks the semantics on a private lock directory: a fourth session waits,
an exclusive run waits for all slots, builds run one at a time, and an inherited slot is
detected. Review: single-slot starters probed the exclusive lock with an exclusive `flock`, so two
starting at the same moment made one wait 10 s; `vslot.sh` now probes with `flock -s -n`.

Session logs (`vsession.sh`). KWin writes `kwin.log`; the session bus and its activated services
write `dbus.log`. Both files are collected after session cleanup; consumers must inspect both
for crashes. Separating the writers prevents a partial D-Bus prefix from corrupting a native
probe record. The shared runtime checker reads either format, and the thumbnail runner requires
the separate bus log. `python3 tools/tests/lib/test_session_logs.py` checks interleaved output,
late bus-service output, argument forwarding and successful/failing compositor exit statuses
without a session. `python3 packages/navigation-cpp/tests/test_runtime.py` checks crash detection
and missing/unreadable logs.

Teardown (`vsession.sh`). At the end of the scenario, or at its time limit (the scenario shell gets
SIGTERM; `timeout` stops everything 30 s later), plasmashell gets up to 5 s to exit before its
private D-Bus peers are stopped. Stopping them together led to a D-Bus assertion and an abort
during plasmashell exit (#217); a stuck shell still falls through to the general sweep. Then every
process of the session except KWin, the processes that started it and their children (the session
bus daemon, Xwayland) gets SIGTERM while KWin
still runs, SIGKILL after 5 s, and the sweep repeats for services the bus started meanwhile.
Before, the portal frontend re-activated `xdg-desktop-portal-kde` after KWin had gone, and the
new instance aborted with a core dump (4 of 27 dock runs). The sweep selects processes by their
`XDG_RUNTIME_DIR` (the session's `$PFV/run`), so it can never reach the logged-in session.
`out/teardown.log` lists what was stopped.

Teardown and the scenario's shell settings (2026-10-25). `vsession.sh` sources the scenario, so
what its preamble sets stays set in the session shell's EXIT trap. Most scenarios use
`set -euo pipefail`, many add an ERR trap and xtrace, and one also sets errtrace.

The sweep meets processes that end on their own. With errexit set, reading or signalling one that
just left ended the trap:

- before the first log line, if the failing read came before it: there was no `teardown.log`,
  and the session reported `session rc=1` after `scenario rc=0`;
- after the first SIGTERM round, if a failing `kill` came later: the log was partial, with no
  "done" line.

What was left then died in `vsession.sh`'s final SIGKILL sweep, not in an orderly teardown. Two
more settings could break the teardown:

- With errtrace set, the scenario's ERR trap would also report those failures. Without errtrace,
  bash keeps an ERR trap out of functions.
- The strict IFS idiom (`IFS=$'\n\t'`) would break the sweep's field splitting under `set -u`.

The teardown therefore makes the settings its own:

- `local -`, then `set +eEx +o pipefail`;
- the ERR trap cleared, and a default `IFS`;
- the ERR and TERM traps restored at the end.

A scenario that calls `cleanup` keeps its own settings.

`tools/tests/lib/teardown-test.sh [--rounds N]` checks this without a session. It runs the real
teardown functions, cut from `vsession.sh`, under three rotating preambles:

- plain `set -euo pipefail`;
- errtrace with an ERR trap and xtrace;
- that with the strict IFS idiom.

The shell holds session processes and short-lived ones that end during the sweep. Every round must
exit 0, end its log with "done; left: none", never run the ERR trap and leave no survivors. Two
mid-scenario `cleanup` calls, with and without errtrace, must leave the scenario's options,
pipefail, ERR and TERM traps and IFS as they were.

Results on the ThinkPad (Fedora 44, bash 5.3.9), 30 rounds each:

| Teardown | Plain errexit rounds | Errtrace and xtrace rounds | Strict-IFS rounds | Mid-scenario checks |
|---|---|---|---|---|
| Before the fix | 2 of 10 failed | passed | 10 of 10 failed | both failed |
| Errexit-only fix | passed | passed | 10 of 10 failed | both failed |
| Errexit, ERR trap and IFS fix | passed | passed | passed | both failed (TERM trap) |
| This version | passed | passed | passed | passed |

The errexit race depends on timing: an earlier errexit-only version of the test failed 19 of 30
rounds. Under xtrace the sweep is slow enough that the race was not met, so the errtrace and xtrace
rounds pass even before the fix. They still guard the ERR trap once the fix turns xtrace off. This
version also passed 120 of 120 rounds.

In real container sessions (KWin 6.7.5 and 6.7.91), a sourced strict-mode scenario had ended
unclean in 3 of 4 sessions. With the fix, every session ended clean:

- errexit-only fix: 6 of 6;
- the ERR trap and IFS fix: 4 of 4;
- this version: 4 of 4.

New harness options (defaults unchanged):

| Where | Addition |
|---|---|
| `vsession.sh` | `PFV_KDE_PROFILE=1`: Fedora's kde-profile layer in `XDG_CONFIG_DIRS` (plasma-keyboard is the input method, as in the ThinkPad's session) |
| `vsession.sh` | `PFV_XWAYLAND=1`: KWin with Xwayland; `DISPLAY` reaches the private bus |
| `vsession.sh` | `PFV_LOCK=1`: a lock-capable session (KWin without `--no-lockscreen`) and `pfv_lock`; pfinput refuses Return, Enter and `type` while it is locked, so no password can be submitted (pam_faillock counts against the host user) |
| `vsession.sh` | `pfv_rotate [OUTPUT] normal\|left\|right\|inverted` (kscreen-doctor inside the session) |
| `pfinput.py` | `hold X Y [HOLD_S]`, `hswipe X1 Y1 X2 Y2 HOLD_S` (edge swipe without fling), `mswipe N X Y DX DY [STEPS [STEP_S]]` (N fingers; KWin's touchscreen gestures need a physical output size, which virtual outputs lack), `type TEXT`; `PFINPUT_WAIT` (default 5 s) for KWin's input devices |

Suites:
- Matrix (`tools/tests/matrix/run.sh`): ADAPTIVE 11 subset (`configs.txt`), about 2.5 minutes per
  configuration, one slot each (`--jobs N`). `check.py` judges every step: widgets inside their
  screen and clear of panels and each other, panel applets inside their panel, pop-ups on the
  right screen, the configuration's settings, core dumps. Touch-target dumps need a
  `debugDumpTargets` hook in the widgets (the owning lanes; M11 reports them as NOT RUN).
  Results on the HEAD 3e950d4 stage: M03 PASS (61 checks), M10L PASS, M11 PASS (targets not run);
  M09 and M14 FAIL (quick settings pushed off the top bar in portrait with a global menu, ADAPTIVE
  fix 4), M10 and M18 FAIL (no top bar on the second output, decision 8), M18 also opens the
  launcher on output 1. M23 (two outputs, hotplug) FAIL on the same missing second top bar; M24 (12 pt font, Global
  Theme switch) PASS (74 checks). These are open work for the top-bar and layout lanes, not
  harness faults.
- Performance gate: new rows from EFFECTS 9.1 (idle with a maximized window over the cards,
  pop-up and overview render p95, pop-up late frames, dock-window geometry changes during the
  sweep, KWin GPU time per launcher frame with `--kwin-gpu`, which reads KWin's counters with
  `sudo -n`), the owner's E12/E13 exceptions as raised limits (shown as "25.9 (E12)"), and
  `--dock-magnify off` for the E12 reference. Validation run `perf-o1tsv-1` (d4afee8 + CARD-1,
  quiet): exit 0, no regression; covered idle 0.03 frames/s (budget 0.1), no dock-window resize
  during the sweep, overview render p95 13.6 ms (budget 12.5).
- Band test (S5): `band.sh` (each run holds every slot and the build lock), HEAD 3e950d4
  stage, 1920 x 1200 at 4/3, 3 s band sweeps. Quiet host, 2 runs (`o1ts-band2`), median
  plasmashell CPU / late frames: 20 icons 13.0 % / 30, 60 icons 25.5 % / 24, 100 icons 38.7 % / 38;
  KWin 8-11 %, render p95 about 4 ms. The 100-icon budget (at most 15 % plasmashell CPU, 0 late
  frames) fails, so the upstream Folder View fix that S5 asks about is needed (for the lead and the
  owner). An earlier run that overlapped two other sessions (`o1ts-band-1`) gave 33 % / 34.
- Icon positions: the suite now takes the desktop's Folder View from the layout when it has one
  (it writes the M1 keys itself otherwise) and runs an upgrade from an earlier build first
  (`--from-stage`, `--from-tools`: the earlier build is installed, then this one over it, and the
  panels, dock pins and cards must survive). Run `o1ts-icons` (HEAD 3e950d4 stage over the
  3a27b3f stage and tools): upgrade PASS (panels, dock pins and cards kept), 8 PASS, 3 REWRITTEN,
  0 FAIL of 11 steps, no core dumps; the same pattern as the 282b1a5 baseline run.

Not done in TEST-1:
- The unexplained 0.45-point idle plasmashell CPU of the top-bar widgets (BACKLOG M5 correction 9,
  `QSG_RENDER_TIMING=1`, `perf top -p`) is not profiled yet.
- A new baseline is recorded after DEPLOY-1 (the plan), with `--runs 5` on a quiet host.

## INT-1 (2026-09-30): fixes to the suites

- **Icons (`icons.py grid()`):** since LAYOUT-1 the layout ships the Folder View, which saves its
  positions before the dock has taken its room (header `10,9`: nine per column for the 866 px
  area). The drag plan took nine rows of 84 px from that header, while Folder View shows seven
  rows of 108 px in the 762 px available area, so the pattern was never reached (setup failure,
  exit 2; the same on the build before INT-1). Positions saved for a taller area are now re-flowed
  into the columns Folder View shows (same order) before planning. Result on 321228a: setup
  reached, 8 PASS, 3 REWRITTEN, 0 FAIL of 11 (as on 282b1a5).
- **Matrix (`check.py`, applets-in-panel):** a floating panel's frame sits `FLOAT_INSET` (16 px,
  the Plasma style's floating-hint-top-margin) inside its window, where the plain south frame
  keeps the dock's headroom; its applets start 16 px down. The check allowed only 0..thickness
  and failed every configuration on the dock (72 px panel, applet at 16..88). Now an applet may
  lie in 0..thickness + 16 of a floating panel, but not be thicker than the panel. Result: 18 of
  18 configurations PASS (M11's touch-target check NOT RUN, as before).

## Results on 282b1a5 (the deployed round-2 build)

### Icon positions

Runtime 3 min 40 s; the same result in two earlier runs on b69fe19. Review re-runs, same verdicts
(8 PASS, 3 REWRITTEN, 0 FAIL, no core dumps): the 282b1a5 stage with the lane's code (3 min 35 s)
and HEAD 31affe9 with the reviewed code (3 min 41 s). The per-stripe value in the header differs
between runs because each start saves whatever the positioner saw first (after the restart: 10,9
here, 10,7 in the review's 282b1a5 run and 10,9 on HEAD; second session: 10,8, 10,9 and 10,7).

| step | entry = baseline (bytes) | rewritten at this step | header (stripes, per stripe) | same cells | icons look the same | icons on | cards / ItemGeometries | pop-ups | core dumps | result |
|---|---|---|---|---|---|---|---|---|---|---|
| 02 plasmashell restart | no | yes | 10,9 (base 10,7) | yes | yes | Virtual-0 | yes / yes | none | none | REWRITTEN |
| 03 KWin reconfigure | no | no | 10,9 | yes | yes | Virtual-0 | yes / yes | none | none | PASS |
| 04 scale 4/3 → 1 → 4/3 | no | no | 10,9 | yes | yes | Virtual-0 | yes / yes | none | none | PASS |
| 05 portrait and back | no | no | 10,9 | yes | yes | Virtual-0 | yes / yes | none | none | PASS |
| 06 dock hidden by a maximised window | no | no | 10,9 | yes | yes | Virtual-0 | yes / yes | none | none | PASS |
| 07 dock auto-hide on and off | no | no | 10,9 | yes | yes | Virtual-0 | yes / yes | none | none | PASS |
| 08 second session, same HOME | no | yes | 10,8 | yes | yes | Virtual-0 | yes / yes | none | none | REWRITTEN |
| 09 second output at login | no | yes | 10,9 | yes | yes | Virtual-0 | yes / yes | none | none | REWRITTEN |
| 10 first output disabled | no | no | 10,9 | yes | yes | Virtual-1 | yes / yes | none | none | PASS |
| 11 first output enabled again | no | no | 10,9 | yes | yes | Virtual-1 | yes / yes | none | none | PASS |
| 12 second output removed | no | no | 10,9 | yes | yes | Virtual-0 | yes / yes | none | none | PASS |

What this means for the desktop-icons work:

- No event moved an icon, a card or left a pop-up; no core dump.
- The literal M2 acceptance (entry byte-identical to the original after every step) fails from
  the first plasmashell restart on. Every plasmashell start (restart, new session, login with a
  second output) saves the entry again: the order of the files changes (Folder View keeps positions
  in a `QHash`, whose order depends on a per-process seed) and the header's "per stripe" (rows per
  column) is often 9 or 8 instead of 7, when the positioner runs before the dock has reserved its
  88 + 16 px (a 900 − 34 px high area gives 9 rows of 96 px; with the dock it is 762 px, 7 rows of
  108 px). Screen events alone (reconfigure, scale, rotation, dock hiding, outputs) never rewrite it.
  This is the startup race KDE describes in bug 503500 comment 2; with 12 icons in the first 7 rows
  it is harmless, but an icon stored in row 8 or 9 of such a header could be moved by a later
  start. A test with icons in the last rows is the next step for the S9 fork decision.
- When the first output goes away, the whole primary desktop (icons, cards, top bar, dock) moves to
  the second output and stays there when the first returns (step 11); it comes back only when the
  second output is removed. The first output then shows an empty desktop.
- Positions are kept per resolution: after the scale and rotation steps the entry has
  `1440x900`, `1920x1200` and `900x1440` keys. `lastResolution` is the resolution of the last
  save: it stays `1920x1200` after scaling back to 4/3 and `900x1440` after rotating back, until
  the next start saves `1440x900` again.

Not covered in a virtual session: lock and unlock (the greeter needs PAM, which tests must not
touch), and the device-only events of M2 step 4 (suspend, lid, DPMS, real rotation).

### Performance

Baseline `tools/tests/perf/baseline.json`: six runs at 1920x1200, scale 4/3, 21:39-22:05 EDT. Per
metric only the runs without another virtual session in that metric's window count (idle rows: 1
run; the others 2-3). Other agents' sessions overlapped runs 1, 2 and all of the second batch
(`perf-dk-*`, the dock lane's own A/B measurements, 21:51-22:05; their numbers from that period saw
these sessions too). Load average 0.2-1.0; no core dumps.

| metric | 282b1a5 median (min..max) | budget | verdict | phase 1 (0918220), same geometry, n=1 |
|---|---|---|---|---|
| idle 30 s: frames/s | 1.23 (quiet run; 1.7-5.9 with other sessions) | ≤ 0.1 | FAIL | 2.00 |
| idle: plasmashell / KWin / session CPU % | 1.00 / 0.40 / 1.96 | ≤ 0.5 / 0.05 / 0.8 | FAIL | |
| idle: plasmashell GPU % | 0.16 | ≤ 0.02 | FAIL | |
| dock sweep: plasmashell CPU % | 41.0 (40.7..41.2) | ≤ 10 | FAIL | 36.1 |
| dock sweep: KWin CPU % / plasmashell GPU % | 18.1 / 4.50 | ≤ 9 / ≤ 0.5 | FAIL | |
| plasmashell PSS / session PSS after settle, MiB | 192 / 493 | ≤ 175 / ≤ 460 | FAIL | |
| plasmashell GEM after settle / first launcher open / one round of use, MiB | 133 / +75 / 238 | ≤ 70 / 30 / 170 | FAIL | 132 / +80 / 250 |
| KWin RSS with 2 windows, MiB | 303 | ≤ 255 | FAIL | 306 |
| launcher: first frame / animation done, ms | 47 / 264 | ≤ 50 / ≤ 300 | PASS | 46 / - |
| quick settings: first frame, ms | 179 | ≤ 186 | PASS | |
| Alt+Tab: first frame / animation done, ms | 253 / 487 | ≤ 233 / ≤ 420 | FAIL | |
| Overview: late frames per cycle | 4 | ≤ 2 | FAIL | 7 |

3 of 20 budget rows pass. The round-2 system card changes the idle picture: it redraws its value
text on every 2 s update and glides its bars (a 200 ms animation, 14 frames) when a bar moves 3 px
or more, so the idle frame rate follows the host's own CPU and memory activity (quiet run: single
frames every 2-2.5 s and two glides in 30 s, 1.23 frames/s; busier host: up to 5.9 frames/s). The
idle rows of `budget.json` therefore have wide noise margins (1 frame/s, about two extra glides in
30 s) until BACKLOG M5 lands; then re-record the baseline and tighten them.

Gate check on the same build: the second batch against a baseline of the first batch alone gives
"no regression" (exit 0). With the first version of the gate (noise per run, narrow idle margins)
it reported idle frames, idle KWin CPU and idle GPU as regressions; that is why noise is now judged
per metric window and a metric measured only next to another session is reported as "worse
(noisy)" (exit 5) instead of a regression.

A single noisy run on b69fe19 (same stage) during the development of the gate, with four other
sessions on the host, gave 5.82 idle frames/s, 38.5 % sweep CPU and 239 MiB GEM after one round.

**Review update (the table above is the build's; the stored baseline changed).** With the review's
noise rule (CPU outside the session per window, see the method above) the build's six runs had
only one run quiet in every window (ts-perf-3); ts-perf-2's sweep and launcher windows, counted as
quiet before, had 64 % of a core used outside the session. The baseline in
`tools/tests/perf/baseline.json` is now rebuilt from nine runs of the 282b1a5 stage (the build's
six and three review runs `rts-perfa-1..3`, 22:31-22:43 EDT), per metric from its quiet windows:
idle rows 1.23 frames/s, plasmashell 1.00 %, KWin 0.40 %, session 1.96 %, GPU 0.16 % (n=1);
sweep plasmashell 41.2 %, KWin 18.7 %, GPU 4.42 % (n=1); PSS 192 / 493 MiB (n=2); GEM 133 / +73 /
238 MiB (n=2-3); KWin RSS 306 MiB (n=3); launcher 51 ms / 235 ms (n=3); quick settings 183 ms
(n=5); Alt+Tab 255 / 489 ms (n=5); overview 3 late frames (n=3). Budget: 2 of 20 rows pass
(launcher animation, quick settings; the launcher first frame is 51 ms against 50). The old
baseline file is kept in the review evidence (`perf-282b1a5-review/baseline-before-review.json`).

The three review runs on 282b1a5 judged against the build's baseline: no regression; the idle rows
"worse (noisy)", exit 5 (1.6-4.0 frames/s, every idle window had another agent's session: the
dock lane's `perf-dk-*` and the lead's `ld-dk-func`). HEAD 31affe9 (text follows the font size)
against the rebuilt baseline, three runs 22:46-22:56 EDT: no regression, exit 0; idle 0.60
frames/s and plasmashell 0.73 % in the one quiet idle window, sweep 41.7 %, GEM after one round
240 MiB, launcher first frame 44 ms, quick settings 174 ms, Alt+Tab 260 / 519 ms (noisy), overview
2-7 late frames (noisy). In the third HEAD run no other virtual session was running, but the host
spent 48-148 % of a core outside the session during the Alt+Tab and overview windows (someone ran
`kscreen-doctor -j` and `plasmashell --version` over plain SSH at 22:56:10, which dumped core);
the build's rule would have counted those windows as quiet (its gate reported overview 2 late
frames, budget PASS). HEAD d4afee8 ("Magnify the dock without resizing the panel"), three runs
23:03-23:12 EDT, two of them quiet in every window: exit 0; dock sweep plasmashell 31.9 % (41.2)
and plasmashell GPU 3.28 % (4.42) are reported "better", KWin 15.6 % "same", everything else
"same"; the sweep line was checked on the end screenshot (y 848 is the icons' middle). No core
dump came from any review session.

## plasmashell SIGABRT cores in the Fedora test VMs (0.5.0)

Several 0.5.0 tracks saw plasmashell leave a SIGABRT core when it was stopped (log-out, a deploy's
or a test's restart) in the Plasma 6.7.5 VM. These are not crashes: Fedora's systemd ships
`/usr/lib/systemd/user/service.d/10-timeout-abort.conf` (`TimeoutStopFailureMode=abort`,
`TimeoutStopSec=40s` for user services), so a stop that takes more than 40 s ends with SIGABRT and
a core instead of SIGKILL. KCrash's handler is frame #2 of the main thread, under the place it
waited at. The cores of 2026-10-11/12 (VM 5, `coredumpctl info`, debug symbols of libplasma and
plasma-workspace) waited in three places, none in Plasma Fusion code:

- `QCoreApplication::aboutToQuit` -> `QSettings::~QSettings` -> `QSaveFile::commit` -> `fdatasync`
  (20:28), and during a start the QML loader thread in `CompilationUnit::saveToDisk` ->
  `fdatasync` while the main thread waits for it in `ShellCorona::createWaitingPanels` (20:30,
  21:07; the file being compiled was quick settings' `main.qml`, recompiled because the deploy had
  cleared `~/.cache/plasmashell`): writes to the VM's copy-on-write disk stalled while other VMs
  and builds ran on the host;
- at exit, `WaylandClipboard::~WaylandClipboard` (KGuiAddons 6.30) -> `QThread::wait` while its
  `ClipboardThread::run` waits for `s_clipboardLock` (02:42, a log-out, and 04:06, a restart):
  `WaylandClipboard::mimeData()` locks it and leaves the unlock to a zero timer, which never runs
  when the event loop ends first, so the thread can never finish. The caller is Klipper
  (`SystemClipboard::checkClipData`), which stock Plasma runs in plasmashell as well; quick
  settings uses Klipper's history model, not the clipboard itself.

On demand neither came back: six real log-outs (`org.kde.Shutdown.logout`, the clipboard just
changed), six restarts with the clipboard changing every 50 ms and three stops 3 s into a start
with a cleared QML cache stopped in 1-24 s, without a core. Before counting a plasmashell core as
a crash, check its signal and the journal: "State 'stop-sigterm' timed out. Aborting." precedes a
stop-timeout abort.

## Open items

- `SHELL` is set only with `PFV_SHELL=/bin/bash` (ADAPTIVE fix 21 asks for it by default). Turning it
  on by default changes every session's environment (Konsole would start bash instead of sh), so it
  is left to the lead to flip the default when no other agent is mid-run.
- The kdeconnect stub in `vsession.sh` is still ineffective: every session's bus log shows
  "Successfully activated service 'org.kde.kdeconnect'" and `/usr/bin/kdeconnectd` running (seen in
  `ts-proof-new` and the icon runs). Not changed here (it would change what a default session runs).
- No stock arm in the gate: it compares Fusion with its own baseline and the section 7 budget. The
  perf-measure study's interleaved stock/Fusion protocol (`analyze_ab.py`) still works on the raw
  run directories when a stock comparison is needed.
- The perf gate needs a quiet host. With several agents running sessions, a full 3-run gate took
  10-15 minutes including waits; other agents' measurements taken at the same time see these
  sessions as noise too. The review's two 3-run gates (22:31-22:43, 22:46-22:56) got no run that
  was quiet in every window: `--quiet-wait` only waits before a run starts. Many baseline rows
  rest on one quiet window (idle, sweep); re-record the baseline with `--runs 5` when the host is
  free (for example when no lane is measuring), and tighten the idle margins after M5.
- The quiet threshold (25 % of a core + 0.25 × the session's own CPU spent outside the session)
  comes from 12 runs on one host; kernel work done for the session (GPU submission, input) counts
  as "outside". Today it is about a fifth of the session's CPU (12 % beside 61 % during the
  sweep), so a regression that scales the session's work keeps the window quiet; if kernel work
  ever grew past the threshold, the row would read "worse (noisy)" (exit 5, not 0), so a real
  regression is still not reported as a pass.
- M2 on the device (suspend/resume, lid, DPMS, real rotation) and lock/unlock need the owner's
  go-ahead and the real greeter; not part of this test.

## Review (2026-09-29, adversarial review and fixes)

Everything was re-run from clean snapshots (`git archive` of 282b1a5, the deployed stage, and of
HEAD 31affe9 and d4afee8) with the lane's files copied over them; no result of the build was
reused. Evidence: the tests review-rts build run of 2026-09-30 (the maintainer's records).

Confirmed:

- The 282b1a5 stage is byte-identical to the deployed `build/lead/stage-3a27b3f/home`.
- `remote.sh` with `PFV_NO_GUARD=1` issues exactly the old command lines (ssh/scp/rsync replaced by
  logging stubs, old and new script compared); with the guard only the first ssh differs.
- A plain default session with the HEAD harness and one with the reviewed harness (`rts-proof`,
  same name, empty seed): plasmashell's and the scenario's environment, working directories,
  config files, the pfinput log, the run root's files and the host user's HOME are identical; only
  the bus address, KWin's random desktop ids, the four new (not exported) helper names and the
  panel clock differ.
- M2 on the 282b1a5 stage with the lane's code (`rts-icons-a`, 3 min 35 s): 8 PASS, 3 REWRITTEN,
  0 FAIL, no core dumps, the same verdicts as the build. The grid header after the first
  plasmashell restart was 10,7 here and 10,9 in the build's run: the per-stripe count saved at a
  start depends on whether the dock has reserved its space yet, so it varies from start to start.
- Upstream (plasma-desktop v6.7.5): positions are a `QHash<QString, GridPosition>` saved as compact
  JSON per resolution in `[General] positions` with a `numStripes, perStripe` header
  (`positioner.cpp` 1057-1078), Folder View's cell width is `max(iconWidth, 16 × (2 × labelWidth +
  4))` plus the spread remainder (`FolderView.qml` 747-770), `/StrutManager` exports both
  `availableScreenRect` overloads; KWin writes `kwin perf statistics OUTPUT.csv` into its working
  directory with the column order `analyze_ab.py` assumes (`renderloop.cpp` 131-141).
- `lastResolution` is the resolution of the last save, not the current one: after scale 1 → 4/3
  it stays `1920x1200`, after the rotation `900x1440`, until the next start saves again.

Found and fixed (severity; how it was shown):

| # | Severity | Problem | Fix |
|---|---|---|---|
| 1 | high | `pfinput.py mark` (and every `sweep`, which marks its motion count) without `PFINPUT_MARKS` wrote `marks.jsonl` into the working directory, which is the host user's HOME unless `PFV_CWD` is set. The build's own smoke run left `/home/test/marks.jsonl` on the ThinkPad at 20:52 (6 lines: t0, t1, alt-done, held-at-exit, sweep-events-97, sweep-done), although its report says nothing was left in `/home/test`. | marks go to `$OUT` or `$PFV/out`, or are not written; the stray file was copied to `review-rts/host-cleanup/` and removed by exact name (rollback: copy it back). |
| 2 | high | The perf gate passed (exit 0) when a measured feature broke: a metric the baseline has but no run produced was shown as "-" (a synthetic run in which the launcher and quick settings never opened: exit 0), and a run without KWin's frame log read as "idle 0.00 frames/s, PASS, better" (exit 0). | MISSING verdict, exit 1; frame metrics are unknown without a frame log; sweep metrics are unknown when the sweep sent fewer than 800 motions. |
| 3 | high | The M2 report passed (exit 0) when session 2 or 3 never ran: the table just had fewer rows (shown by deleting session 3's results: exit 0). | the report expects all eleven steps; a step without a result is a setup failure (exit 2); sessions 2 and 3 are skipped when session 1 failed. |
| 4 | medium | Noise was judged only at the two snapshots that bound a metric's window. In the build's six baseline runs, windows counted as quiet had 64 % (ts-perf-2 sweep), 64 % (ts-perf-2 launcher) and more of a core used outside the session; only ts-perf-3 was quiet throughout. | CPU outside the session per window (machine busy minus the session's ticks), noisy above 25 % + 0.25 × the session's own; stored per run; the baseline was rebuilt (see "Review update" under Performance). |
| 5 | medium | `--baseline` naming a file that does not exist: the gate silently judged the budget only (exit 0). A traceback in a run's analysis (e.g. an empty `arm.txt`) ended the gate with exit 1, which reads as "regression". | exit 2 for both; a broken run is skipped with its error, the others are judged. |
| 6 | medium | Two agents using the same `--name` (defaults `icons`, `perf`) would share one host directory, and the driver's final `rm -rf` would delete the other agent's running session. | the drivers refuse to start while a session of that name has live processes. |
| 7 | medium | The build's report says both drivers retry the connection once; only `hssh` did, a banner timeout in `remote.sh`'s first ssh failed the whole session. An interrupted driver left its session running until the timeout and ~100 MB in `/var/tmp`. | `run_remote` retries once when ssh failed before the session started and no process of it runs; INT/TERM trap stops the session by runtime dir and removes its directory. |
| 8 | low | `PFV_FONT_PT` read the family from `~/.config/kdeglobals` by absolute path, so a Global Theme's family in `~/.config/kdedefaults` became "Noto Sans" (seed with only a kdedefaults font: now `Manrope,12`). | read through the session's cascade. |
| 9 | low | `PFV_LANGUAGE`/`PFV_SHELL` did not reach the private bus's activation environment, so bus-activated services (krunner, portals) ran without them. | added to the activation environment when set (`rts-smoke`: krunner had `LANGUAGE=ar SHELL=/bin/bash`). |
| 10 | low | Results did not say what else the sessions ran: the ThinkPad has the `plasma-fusion` 282b1a5 RPM, the decoration and settings RPMs in `/usr`, and Plasma/KWin/Qt/Mesa updates shift every number. | `packages.txt` with every result; the gate stores it and notes a difference from the baseline's. |
| 11 | low | Wrong statements: "125 Hz" sweep (each motion waits up to 10 ms for KWin: ~975 motions in 10 s, as in the study); the header table shows 10,9 after the restart as if fixed; "lastResolution follows the current one"; overview late frames 4 (the baseline median was 3.5); `--save-baseline` writes the snapshot's copy when run from `build/snap`; `--runs` was not validated. | corrected in this document, `scen-perf.sh` and `pfinput.py`; `--runs` checked. |

Every harness change of the review was written to a temporary file in `tools/vsession` and
renamed into place after checking the live file was unchanged; the default-session proof above
was run after them.

Checked and left as they are (reasons):

- Icon drag targets assume a 96 px minimum cell (documented under the M2 method): a larger UI font
  makes the run stop with "pattern not reached" (exit 2), never pass wrongly.
- The kdeconnect stub is still ineffective (`Successfully activated service 'org.kde.kdeconnect'`
  and `/usr/bin/kdeconnectd` in the review's default sessions too); fixing it changes what every
  default session runs, so it stays with the harness owner.
- The frame-time rows of section 7 are not in the gate (listed under the metrics).
- Core-dump attribution needs journal access (`test` is in `wheel`); without it the lists would be
  silently empty.
- `SHELL` stays opt-in (`PFV_SHELL`), as the build decided.

Observed on the host during the review, not caused by it: at 22:56:10 EDT someone on the laptop
(SSH from the laptop) ran `kscreen-doctor -j` and `plasmashell --version` over plain SSH in the
host user's real runtime dir; both dumped core (SIGABRT), and the real session's plasmashell was
started again at 22:56:14. Other agents' sessions dumped `xdg-desktop-portal-kde` four times
(`perf-dk-new6`, `perf-dk-nomag`, `perf-dk-new10`, `perf-dk-nomag2`) and `plasmashell` once
(`rgt-ld0`, 22:16:44). None of the review's sessions (`rts-*`) produced a core dump.

For the dock owner (seen in the perf runs' `end.png`, not a test failure): with the pointer parked
mid-screen after Alt+Tab and Overview, most runs end with a "Downloads" tooltip still shown above
the dock and the dock visible over the KWrite window ("dodge windows" would hide it); the rest end
with the dock hidden. Seen on 282b1a5, 31affe9 and d4afee8 alike (`review-rts/dock-end-screens/`).
