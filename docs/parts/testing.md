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

Status: built and run on HEAD 282b1a5 (the staged HOME tree is byte-identical to the deployed
3a27b3f and to b69fe19); reviewed and fixed afterwards (see "Review" at the end), re-run on the
282b1a5 stage and on HEAD 31affe9 and d4afee8. Not a deployable part: nothing here touches the
real session. Work package TEST-1 (2026-09-30) added the session-slot lock, the teardown fix,
more harness options, the matrix, the band test and new gate rows; see "TEST-1 (2026-09-30)".
Last edited 2026-09-30.
Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/tests/` (review:
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
| `tools/tests/perf/pfstat.py`, `winmon.js`, `analyze_ab.py` | copied from `2026-09-30-research/perf-measure/scripts/` (pfstat also records other virtual sessions on the host) |
| `tools/tests/perf/gate.py` | metrics per run, median over runs, budget and baseline verdicts, table, exit status |
| `tools/tests/perf/budget.json` | section 7 budget and the noise margin of every metric |
| `tools/tests/perf/baseline.json` | stored baseline (282b1a5 stage, 1920x1200 at 4/3; per metric the quiet runs; see "Performance" below) |
| `tools/vsession/{vsession.sh,remote.sh,pfinput.py}` | backward-compatible additions (below) |
| `tools/tests/matrix/{run.sh,body.sh,mx.py,check.py,configs.txt}` | adaptive matrix (TEST-1): driver, in-session walk, per-configuration steps, layout judge, the configurations |
| `tools/tests/perf/{band.sh,scen-band.sh,band.py}` | rubber-band selection with 20/60/100 icons (S5): driver, scenario, table and verdict |
| `tools/tests/lib/slot-test.sh` | self-test of the slot lock semantics on a private lock directory |

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

The table has one row per metric: the median over the runs (min..max), the section 7 budget and
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
noisy windows. Budget failures do not fail the gate by default because most rows fail today (see
the baseline below); the gate stops things from getting worse, `--strict-budget` is for when M4/M5
have landed. When the host's packages differ from the baseline's the gate prints a note: re-record
the baseline after a Plasma, KWin, Qt, Mesa or kernel update.

Metrics: idle frames/s, idle CPU of plasmashell, KWin and the whole session, idle plasmashell GPU,
dock sweep CPU of plasmashell and KWin and plasmashell GPU, plasmashell PSS and session PSS after
settle, plasmashell GEM after settle, after the first launcher open (growth) and after one round of
use, KWin RSS with two windows, launcher first frame and animation end, quick settings first frame,
Alt+Tab first frame and animation end, Overview late frames per cycle. Not encoded from section 7:
the frame-time rows (render p95 during pop-up animations, overview render p95, missed vblanks,
GUI-thread time per frame), quick settings "first frame at most 50 ms after the release" (only
"not slower than stock" is), and the device-only and desktop-file rows.

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

Teardown (`vsession.sh`). At the end of the scenario, or at its time limit (the scenario shell gets
SIGTERM; `timeout` stops everything 30 s later), every process of the session except KWin, the
processes that started it and its children (the bus daemon, Xwayland) gets SIGTERM while KWin
still runs, SIGKILL after 5 s, and the sweep repeats for services the bus started meanwhile.
Before, the portal frontend re-activated `xdg-desktop-portal-kde` after KWin had gone, and the
new instance aborted with a core dump (4 of 27 dock runs). The sweep selects processes by their
`XDG_RUNTIME_DIR` (the session's `$PFV/run`), so it can never reach the logged-in session.
`out/teardown.log` lists what was stopped.

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
reused. Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build/tests/review-rts/`.

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
