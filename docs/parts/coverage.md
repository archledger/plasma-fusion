# Part: test coverage, regression tests and the test policy

How much of the code the automated tests run, per language; what they do not run and why; what
it would take to reach 80 %; which bug fixes got a regression test; and the policy for tests.
Measured 2026-10-02. Python, shell and JavaScript at ee8d9d2 (this branch; its product code is
that of 37a4d82), in a fresh fedora:44 container set up with `--deps`, as the workflow does. The
compiled parts at 223520d: the decoration in such a container, the settings module and the
navigation effect in the build container of `tools/container/Containerfile` (Plasma 6.7.5) with
gcovr added; a later run of all three in fresh fedora:44 containers gave the same figures.
Written for the OpenSSF Best Practices silver criteria `test_statement_coverage80`,
`regression_tests_added50`, `automated_integration_testing` and `test_policy_mandated` (project
15168).

## Files

| File | Purpose |
|---|---|
| `tools/tests/coverage.sh` | runs the tests under the coverage tools and writes the reports and the tables below |
| `tools/tests/coverage_summary.py` | turns the tools' reports into `summary.md` and `summary.json`: per language, per area, product code, maintainer tools and test tooling apart |
| `.github/workflows/coverage.yml` | the same in Fedora 44 on GitHub, weekly and by hand; the tables go to the job summary, the reports to an artifact |

## Running it

On Fedora 44, as root in a container (it installs packages):

```
podman run --rm --security-opt label=disable -v "$PWD:$PWD:ro" -v "$PWD/build:/out" -w "$PWD" \
  registry.fedoraproject.org/fedora:44 bash -c \
  'dnf install -y -q git-core && tools/tests/coverage.sh --deps scripts &&
   tools/tests/coverage.sh --out /out/coverage scripts'
```

`--deps PART` installs what a part needs (the tools, the build requirements of
`packaging/plasma-fusion.spec.in`, and for `cpp:PACKAGE` the part's spec through `dnf builddep`).
The parts are `scripts` (Python, shell and JavaScript in one pass, about 4 minutes) and
`cpp:decoration-cpp`, `cpp:kcm-cpp`, `cpp:navigation-cpp` (a build with `--coverage`, from under
a minute to about 4 minutes each, plus the installation). Results go to `build/coverage` unless
`--out` says otherwise: `summary.md`, `summary.json`, each test's output in `logs/`, and the
tools' own reports (`python/html`, `shell/merged`, `js/lcov.info`, `cpp-PACKAGE/gcovr.*`). The
exit status is 0 when the measurement finished, also when a test failed; the summary lists every
test's exit status.

## What is measured, and how

| Language | Tool (FLOSS) | Unit | What runs |
|---|---|---|---|
| Python | coverage.py 7.13.5 (`python3-coverage`) | statements | every Python process the tests start: `COVERAGE_PROCESS_START` and the `.pth` file the package installs |
| Shell (bash) | kcov 43 | lines kcov counts as code | every bash script the tests start (kcov sets `BASH_ENV` and traces with `PS4`) |
| JavaScript | node 22's own coverage (`--experimental-test-coverage`, V8) | code lines (blank and comment-only lines left out) | `node --test` over `packages/*/tests/*.test.js` |
| C++ | gcov (GCC 16) and gcovr 8.6 | lines | the part's tests, built with `--coverage -O0` |
| QML | not measured; qoverage can instrument most of it (see "QML") | | |

The tests run for `scripts`, all without a desktop session:

- `tools/build.sh`: every part with its built-in checks (colour contrast, GTK stylesheets, package
  structure, the lints, the weather and power-tier widget tests, the app icon tests), as the RPM
  build runs it;
- `generators/plymouth/build.sh` (the boot splash theme and `tests/check_theme.py`);
- `tools/checks/tests/run.sh` (the lints' self-tests);
- `tools/device/tests/gate-unit.sh` (the login check, 137 checks);
- `packages/powerfx/tests/offline.sh` (the power tiers service against mock D-Bus services);
- `generators/cursors/tests/test_cursors.py`, `generators/decoration/tests/check_aurorae.py`,
  `generators/plasma-style/tests/validate.py`, `generators/icons/validate.py` over the built themes;
- `node --test` over the JavaScript unit tests.

For `cpp:PACKAGE`: `ctest` (it finds no tests: no `CMakeLists.txt` in the repository calls
`add_test`), and for the decoration `tests/pfdeco-preview`, which loads the built plugin with a
mock KWin bridge, renders its scenes and runs 199 checks per colour scheme (dark and light;
exit status 1 on a failed check).

Details that change the numbers:

- The file list is `git ls-files`: a file no test starts counts with all of its statements.
- Three groups are counted apart (`coverage_summary.py`, `TEST_RE` and `MAINT_RE`): **product
  code** (what `tools/build.sh` runs and what the packages install), **maintainer tools**
  (programs run by hand to regenerate committed tables, fonts and previews:
  `generators/icons/make_*.py`, `coverage_report.py`, `generators/fonts/make_static.py`,
  `generators/look-and-feel/previews.py`; and the package build scripts: `packaging/build-rpm.sh`,
  which the build workflow also runs, and the compiled parts' `build-rpm.sh` and
  `container-build.sh`), and **test tooling** (everything below a `tests/`, `test/` or
  `vsession/` directory, `tools/tests/`, `tools/vsession/`, `tools/container/`, and the checking
  aids a person runs by hand to compare built output with the design boards or to measure it:
  `generators/cursors/sheet.py`, `generators/icons/compare_boards.py`,
  `packages/decoration-cpp/tools/shadow-alpha.py`, `sheet.py` and `run-preview.sh`, and
  `tools/device/power-ab.sh`).
- Product code includes the build and lint scripts (`tools/build.sh`, `tools/build.d/`,
  `tools/build-lib/`, `tools/checks/`, `generators/plymouth/build.sh`, `BUILD_RE`). Running the
  build is one of the tests, so they run almost in full; the summary also gives the product
  figures without them.
- `gate-unit.sh` and `offline.sh` start their subject with `env -i`, which would drop the coverage
  hooks. `coverage.sh` puts a wrapper named `env` first in `PATH` that keeps the hooks' variables
  for `env -i` children and is the real `env` otherwise.
- Tracing makes bash slower, so checks that wait a fixed time can fail under kcov, and the weekly
  summary will often list them as failed. In the three fresh fedora:44 runs for this page, on a
  shared machine with load averages from about 4 to 19, `offline.sh` failed "service: bash plus
  three gdbus monitor processes" (counted 1.5 s after the start) every time (78 of 79 pass; an
  earlier run passed it), and `gate-unit.sh` failed "timing: median under 50 ms" in two of them
  (136 of 137 pass). The build workflow runs `gate-unit.sh` without tracing; no other workflow
  runs `offline.sh`.
- Python passed to `python3 -` in a heredoc, and JavaScript in a heredoc named JS, has no file:
  coverage.py and node cannot report it, and kcov does not count heredoc lines. It is in no
  denominator. The summary counts it apart ("Code inside shell scripts (not measured)"): in
  product code, 468 Python statements in 20 blocks and 96 JavaScript code lines in 2 blocks. Of
  the Python, 268 statements are in five blocks of `tools/device/fusion-config.sh` and 8 in
  `tools/system/plymouth-install.sh`, which no test runs; the other 192 are in the build and lint
  scripts, which the build runs. Of the JavaScript, 80 lines are the power tiers widget script
  (`SHELL_JS` in `packages/powerfx/plasma-fusion-powerfx`) and 16 the tiling script in
  `fusion-config.sh`. Counted as product code, Python would be between 82.2 % (5,990 of 7,287,
  no block counted as run) and 84.8 % (6,182 of 7,287, every block of the build and lint
  scripts counted as run in full), and JavaScript between 13.2 % (176 of 1,338) and 19.1 % (256
  of 1,338, the widget script counted as run in full). Code passed with `python3 -c` is not
  counted at all.
- The weather card's test used to build `weather.js` into a `new Function()`, which V8 cannot map
  to a file; it now loads it with `vm.runInThisContext` under the file's URL (223520d). The power
  tiers widget script (`SHELL_JS` in `packages/powerfx/plasma-fusion-powerfx`) is still built that
  way by `packages/powerfx/tests/widgets.test.js`; it is one of the heredocs above.
- gcovr keeps one entry per compiled function a line belongs to, so a line shared by two variants
  of a function (a destructor's) is counted twice in its own totals; the summary counts each
  source line once (decoration: 1,226 of 1,359 here, 1,229 of 1,364 in `gcovr.txt`).

## Results (2026-10-02)

| Language | Product code | Maintainer tools | Test tooling | All |
|---|---|---|---|---|
| Python, statements | 87.8 % (5,990 of 6,819) | 0.0 % (0 of 693) | 7.5 % (424 of 5,632) | 48.8 % (6,414 of 13,144) |
| Shell, lines | 31.4 % (1,167 of 3,714) | 0.0 % (0 of 142) | 12.0 % (604 of 5,015) | 20.0 % (1,771 of 8,871) |
| JavaScript, code lines | 14.2 % (176 of 1,242) | - | 84.0 % (326 of 388) | 30.8 % (502 of 1,630) |
| C++, lines | 35.2 % (1,226 of 3,479) | - | - | 35.2 % (1,226 of 3,479) |
| QML | not measured: 212 files, about 31,800 code lines (16 files, about 3,200 lines, kept from plasma-desktop's Folder View: `UPSTREAM-FILES`) | - | not measured: 20 files, about 850 code lines | not measured: 232 files, about 32,600 code lines |

The test tooling column includes `tools/tests/coverage_summary.py` (371 statements) and
`tools/tests/coverage.sh` (91 lines), which the measurement itself does not run.

Over the four measured languages, product code: 8,559 of 15,254 statements or lines run (56.1 %;
the units differ per tool, so this is a rough figure). Product code includes the build and lint
scripts, which run whenever the build runs: without them, shell is at 22.3 % (728 of 3,263) and
Python at 87.5 % (5,718 of 6,536). With the maintainer tools counted as product code, Python is
at 79.7 % (5,990 of 7,512); with the hand-run Python checking aids counted as well (514
statements, none run), at 74.6 % (5,990 of 8,026). The QML is the largest body of code, about
twice the product code of the four measured languages together, and no test measures it yet.

### Python, product code by area

| Area | Files | Statements | Run | % |
|---|---|---|---|---|
| generators/icons | 31 | 3,111 | 3,011 | 96.8 % |
| generators/plasma-style | 2 | 755 | 736 | 97.5 % |
| generators/plymouth | 2 | 618 | 569 | 92.1 % |
| packages/appicons | 1 | 467 | 268 | 57.4 % |
| generators/cursors | 3 | 335 | 307 | 91.6 % |
| packages/color-schemes | 1 | 320 | 290 | 90.6 % |
| tools/checks | 2 | 283 | 272 | 96.1 % |
| generators/decoration | 1 | 247 | 244 | 98.8 % |
| tools/device | 1 | 239 | 0 | 0.0 % |
| generators/wallpapers | 1 | 231 | 219 | 94.8 % |
| packages/keyboard | 1 | 128 | 0 | 0.0 % |
| generators/look-and-feel | 1 | 53 | 52 | 98.1 % |
| packages/gtk | 1 | 32 | 22 | 68.8 % |

### Shell, product code by area

| Area | Files | Lines | Run | % |
|---|---|---|---|---|
| tools/device | 7 | 2,215 | 537 | 24.2 % |
| tools/system | 4 | 586 | 0 | 0.0 % |
| tools/build.d | 21 | 365 | 364 | 99.7 % |
| packages/powerfx | 1 | 262 | 191 | 72.9 % |
| tools/pen | 1 | 122 | 0 | 0.0 % |
| tools/build-lib | 1 | 46 | 40 | 87.0 % |
| packages/power | 1 | 40 | 0 | 0.0 % |
| packages/compat | 1 | 38 | 0 | 0.0 % |
| tools (build.sh) | 1 | 23 | 18 | 78.3 % |
| tools/checks | 1 | 11 | 11 | 100.0 % |
| generators/plymouth | 1 | 6 | 6 | 100.0 % |

In `tools/device`: `fusion-config.sh` 0 of 1,119, `fusion-restore.sh` 0 of 203,
`gate/plasma-fusion-gate.sh` 537 of 687 (78.2 %), the profile backup and lock screen scripts 0 of
206.

### JavaScript, product code by area

| Area | Files | Code lines | Run | % |
|---|---|---|---|---|
| packages/look-and-feel | 5 | 539 | 0 | 0.0 % |
| packages/plasmoids | 6 | 519 | 176 | 33.9 % |
| packages/kwin | 1 | 184 | 0 | 0.0 % |

`weather.js` is the only product file a node test loads: 176 of 191 code lines (92.1 %).

### C++, by part

| Part | Lines | Run | % | Test |
|---|---|---|---|---|
| decoration-cpp (`src/`) | 1,359 | 1,226 | 90.2 % | `pfdeco-preview`, dark and light |
| kcm-cpp (`src/`) | 1,345 | 0 | 0.0 % | none runs without a Plasma session |
| navigation-cpp (`src/`) | 775 | 0 | 0.0 % | none runs without KWin |

### QML

The QML is not measured yet, but a FLOSS tool can instrument most of it, so the criterion applies
to it as well:

- qoverage (https://github.com/SanderVocke/qoverage, GPL-3.0, v0.1.14 of April 2026; `pip
  install qoverage`, with Qt's `qmldom` bundled) instruments QML files so that a run reports the
  lines it reached. In a fedora:44 container, `qoverage instrument -p packages -o DIR` instrumented
  216 of the 224 QML files under `packages/` (the QML of 37a4d82; this branch changes none). It
  could not parse 8: the dock's `main.qml`, the launcher's `LauncherCard.qml`, `NavGrid.qml`,
  `ResultsList.qml` and `TabletSheet.qml`, the clock's `WidthBudget.qml`, the quick settings'
  `NotificationCard.qml` and the lock screen's `PowerButton.qml`. Its README calls it pre-alpha,
  counts only lines, counts a declarative object only by its declaration line when it is created,
  does not instrument imported JavaScript files and lists false negatives as a known issue. No
  test has run the instrumented files yet, so there is no QML figure.
- Qt 6.11 ships no coverage tool. `qmltestrunner` runs tests and `qmlprofiler` records timings;
  neither reports which statements ran.
- The Qt Group's Coco lists QML among its languages, but it is a commercial product, not FLOSS
  (https://www.qt.io/quality-assurance/coco).
- Most of the QML runs only inside `plasmashell`, KWin or the lock screen greeter. The tests that
  load it offscreen (`packages/common/tests/offscreen.sh` and `icontile.sh`,
  `packages/kwin/tests/offscreen/`, `packages/lockscreen/test/`) reach a small part of it; the
  rest runs in the private-session scenarios on the ThinkPad or in the Plasma test containers
  (docs/parts/testing.md, docs/parts/containers.md), which nothing instruments.

## What the tests do not run, and why

- **The per-user installer and its undo** (`fusion-config.sh`, `fusion-restore.sh`,
  `previous-theme.py`, `pen-defaults.sh`, `backup-profile.sh`, `restore-profile.sh`,
  `lockscreen-enable.sh` and `-disable.sh`; 1,650 shell lines and 239 Python statements, plus
  268 Python statements in `fusion-config.sh`'s heredocs that are not counted). They
  change a live Plasma session through `kreadconfig6`, `kwriteconfig6`, `busctl`,
  `plasma-apply-*` and plasmashell's scripting. The private-session suites run
  `fusion-config.sh` (`tools/tests/icons`, `tools/tests/matrix`, `tools/tests/perf`, the gate
  scenarios in `tools/device/tests/vsession/`, which also run `fusion-restore.sh`), on the
  ThinkPad or in the Plasma test containers, without coverage.
- **The root scripts** (`tools/system/`: greeter and Plymouth install and removal, 586 lines).
  They change `/etc` and `/usr/share/plymouth`; `generators/plymouth/tests/vmtest.sh` tests the
  boot splash in a throw-away VM on the test device, outside this measurement.
- **Device helpers**: the charge limit (`plasma-fusion-charge-limit`, sysfs thresholds through
  pkexec), the LibreOffice scale guard (asks KScreen), the keyboard layout tool
  (`plasma-fusion-keyboard-keys`, only compiled by the build).
- **The parts of the app icon tool that react to the system** (`plasma-fusion-app-icons`: the
  watch loop, Flatpak paths, the renderer it did not pick): 199 of 467 statements.
- **The GTK stylesheet check** (`packages/gtk/check_css.py`): 10 of 32 statements not run. It
  also skips itself without a word when GTK's base typelibs (`cairo-1.0`, `xlib-2.0`) are missing:
  in a container installed without weak dependencies it was skipped, and 20 statements were not
  run.
- **JavaScript that runs inside Plasma**: the desktop layout and top-bar scripts (plasmashell's
  scripting API), the dialog-attach KWin script, and the launcher, clock and folder helpers that
  QML imports.
- **The settings module and the navigation effect** (C++): the settings module is driven by
  `packages/kcm-cpp/tests/kcmctl` only inside private sessions; the navigation effect needs a
  running KWin.
- **Maintainer tools** (693 Python statements, 142 shell lines): run by hand to regenerate
  committed files, some of them from the installed system (`make_capture.py` reads Breeze,
  `make_mimetable.py` shared-mime-info), and the package build scripts, which the build workflow
  runs (`packaging/build-rpm.sh`) or a person runs (the compiled parts' scripts).

## Work to reach 80 % (estimates)

Per language, product code. A day is a working day of one person.

- **Python** (87.8 %, above 80 %; 82.2 to 84.8 % with the Python in heredocs counted). To keep it
  there as code grows: a test for `previous-theme.py` with a throw-away HOME, like `gate-unit.sh`
  (about 1 day); a test for `plasma-fusion-keyboard-keys` against a copy of plasma-keyboard's layout
  files (half a day); the app icon tool's watch loop (inotify on the application directories) over
  temporary directories (1 day). Counting the maintainer tools, a job that runs them and compares
  their output with the committed tables (`capture.json`, `outlines.json`, `glyphs.json`,
  `mimetable.json`) would cover them and check that the tables are current (1 to 2 days).
- **Shell** (31.4 %; 80 % needs 2,972 of 3,714 lines, 1,805 more). A unit harness for
  `fusion-config.sh` and `fusion-restore.sh` like `gate-unit.sh`: a throw-away HOME and stubs for
  `busctl` (plasmashell's scripting), `plasma-apply-*` and `kwriteconfig6` that record their calls
  (about 3 to 5 days for about 75 % of those 1,322 lines; it would also run the 268 Python
  statements in `fusion-config.sh`'s heredocs, which only moving them into files lets coverage.py
  count); the `tools/system` scripts in a container with stubs for `plymouth-set-default-theme` and
  `dracut` (2 days, about 450 of 586 lines); the pen, profile, lock screen, charge limit and
  LibreOffice scripts against fake files and commands (2 days, about 330 of their 406 lines); the
  gate engine from 78 % to 90 % (half a day). In all about 7 to 10 days. A quicker but partial step:
  run the private-session suites in the Plasma test containers with kcov's `BASH_ENV` hook, since
  they already run `fusion-config.sh --install`.
- **JavaScript** (14.2 %; 80 % needs 994 of 1,242 code lines, 818 more). Node tests with a fake
  scripting runtime for the layout scripts (`packages/powerfx/tests/fake-shell.js` already fakes
  desktops and panels): about 450 of their 526 lines, 2 days; unit tests for `launcher.js` and
  `formats.js`: about 180 lines, 1 day; the attach KWin script against a fake `workspace`: about 150
  lines, 1 day; the icon tables and `FolderTools.js` (kept from plasma-desktop, by its copyright
  line; it reads `Kirigami.Units`, so it needs a stub): about 100 lines, half a day. Each test must
  load its file under its URL, as the weather test now does.
- **C++** (35.2 %; 80 % needs 2,784 of 3,479 lines, 1,558 more). The decoration is at 90.2 %, but
  only this measurement and `packages/decoration-cpp/tools/run-preview.sh` (by hand, on the
  ThinkPad) run `pfdeco-preview`: registering it with `ctest` would let the `compiled` workflow
  run it on every change to the decoration (half a day). The settings module: `kcmctl` offscreen
  in CI with a throw-away HOME and a stand-in for plasmashell's D-Bus scripting, covering load,
  save, defaults and every property (3 to 5 days, about 65 to 75 % of its 1,345 lines). The
  navigation effect: `kwin-devel` 6.7.5 ships no test files (`rpm -ql kwin-devel`), so either the
  private-session scenarios run in the Plasma test containers with a `--coverage` build (gcov
  writes its data when KWin exits cleanly), or the parts that do not need KWin are split out and
  unit-tested (3 to 5 days). Even then 80 % needs both the settings module and the effect above
  about 75 %.
- **QML** (not measured; product QML is about twice the product code of the four measured
  languages together, see "Results"). First, qoverage under the offscreen QML tests
  (`packages/common/tests/offscreen.sh` and `icontile.sh`, `packages/kwin/tests/offscreen/`,
  `packages/lockscreen/test/`) in the Plasma test container: about 1 to 2 days, for a first
  figure. Then the private-session scenarios (`tools/tests/`, `packages/*/tests/vsession/`) with
  the instrumented QML installed in the Plasma test containers, since most of the QML runs only
  inside plasmashell and KWin: about 3 to 5 days to wire up. How close that comes to 80 % is not
  known until it is measured; the 8 files qoverage cannot parse stay unmeasured until qoverage
  parses them or they change. Until the QML is measured, 80 % over all of the project's code
  cannot be shown.

## Regression tests for the bugs fixed in the last six months

The repository's history starts on 2026-09-29, so the last six months are all 144 commits (to
37a4d82). A commit counts as a **bug fix** when its subject or first paragraph says that something
behaved wrongly before it and the commit corrects it: a crash, an error, a wrong result or
display, a performance or memory problem, a build or packaging failure, a breakage with a newer
Plasma, or a platform defect Plasma Fusion now works around. New behaviour, tuning to a design
decision, documentation and test-only changes do not count. Fixes to the test suites themselves
(5417df4, and the teardown and portal fixes in 19ca2cb and d99756b) are left out; the snap flyout
fix in d99756b counts among the fixes in passing below. The unit counted is the commit, not the
bug: a commit that fixes several bugs counts once (a8559a3 lists five), and two commits for one
bug count twice (cc1bce8 and 4166eed are one crash).

A fix **has a regression test** when an automated check in the repository, run without a person,
fails if the bug comes back: a check in `tools/build.sh` or the RPM build, a unit test, or a
scripted private-session scenario that asserts its results. "Verified" means it was run here
against the code with the fix taken out.

Result: **9 of 58 bug-fix commits have a regression test (15.5 %)**. Counting also the 20 feature
commits that fix something in passing (five of them with a test): 14 of 78 (17.9 %). Below the 50 %
the criterion asks for.

| Commit | What was wrong | Regression test |
|---|---|---|
| 0918220 | bold synthesised over the variable fonts; a second launcher pin for a filled slot | none |
| 3a27b3f | a Global Theme switch reset the user's font size and cursor | yes: `tools/tests/matrix` configuration M24, check `lnfswitch` (fonts, cursor and buttons kept through Light and Dark), added in 19ca2cb; private sessions; not re-run here |
| b69fe19 | `fusion-config.sh` over SSH read the wrong configuration cascade | none |
| a8559a3 | settings module: stale QML cache, row pitch, failed apply, focus, sunset style | none (the test change only limits what the tests stop) |
| 207d2d5 | `greeter-apply.sh` stopped with an empty cursor theme | none |
| 282b1a5 | the package lacked the Plymouth theme its installer needs | yes: the spec's `%files` names `plasma-fusion/plymouth/`, so the RPM build fails without it (a packaging check) |
| 31affe9 | libinput offered a mirroring left-handed mode for the X13 pen | none |
| d4afee8 | the dock resized its panel about 30 times a second under the pointer | none: the performance gate's row `sweep_panel_resizes` (19ca2cb) has a budget of 0 but no value in `baseline.json`, so it fails the gate only with `--strict-budget` |
| af0bb47 | the system card redrew the desktop every 2 s while covered or locked | none: the row `idle_fps_covered` is in the same position |
| f33435c | a missing compiled decoration left KWin on its built-in title bars | yes: `gate-unit.sh` cases "p: plugin missing", same commit; verified (3 checks fail before the fix) |
| 0efb34f | the top bar a pixel too tall after the first font change | none |
| cc1bce8 | plasmashell crash when the global menu returned to its full view | none (the private-session runs in the message are not in the repository) |
| 4166eed | the same crash, from Qt's GridLayout | none (its `menu-refresh` hook is used by no committed scenario) |
| 071734d | two top bars when the check ran before the layout loaded | none (the matrix checks for a missing bar, not a second one) |
| 7fe9a1c | "Cannot read property 'pal' of null" from notification buttons | none |
| a41cdc4 | short swipes stopped showing the dock; keyboard panels in the switcher | none |
| 8aa4bcc | no on-screen keyboard on the lock screen after locking with a key | none |
| a4c70f7 | plasma-keyboard's accent pop-up stopped held keys from repeating | none |
| ec674e4 | swipes from the bottom missed KWin's 8 px touch edge | none |
| bfbcfd6 | short flicks went home; the on-screen keyboard stayed up with a hardware keyboard | none |
| d4b4a15 | a deprecated Qt call (build warning) | none (the `compiled` workflow does not fail on warnings) |
| e329c8f | LibreOffice drawn twice too big on a 100 % screen next to a scaled one | none |
| 2dd6a8a | the home indicator over apps' status bars; taps swallowed by the touch zone | none |
| 051ed19 | a pen drag selected text and could not scroll in tablet posture | none |
| b48b571 | the first-use card listed outdated gestures | none (the scenarios were only changed to hide the card) |
| bbe9ebc | the RPM build stopped on the unpackaged LibreOffice guard | yes: `%check` tests that it is installed and executable, same commit, and `rpmbuild` fails on unpackaged files |
| 2bf3833 | the on-screen keyboard stayed over the home screen and at the next lock | none |
| 01d143a | tablet panels ended on fractional pixels at 4/3 | none |
| 05ada50 | panel sizes were not redone after a scale change | none |
| ab23491 | a Qt shadow leak: plasmashell grew about 0.4 MiB per rotation | none (measured by hand, 300 rotations) |
| f77f10e | a velocity spike made slow drags look like flicks | none |
| fe4a0f8 | KWin scripts failed to load with KWin 6.8 | none |
| ceb1014 | launcher pins and short names missing with Plasma 6.8 | none |
| a697493 | the lock shell failed to load with Plasma 6.8 | none |
| 183a760 | the navigation effect stayed unloaded after the installer turned it back on | none |
| c505983 | a pen press and hold opened no menu over the shell | none |
| 2674ba7 | a binding loop in the Alt+Tab cards | none |
| de9f1b9 | with only a pen there was no way out of a full-screen app | none |
| 04c5dc2 | taps between the bell and the screen corner went nowhere | none |
| 028500b | pins beyond the first home page were hidden; page dot targets too small | none |
| 70b5a39 | the keyboard button could not hide the on-screen keyboard | none |
| 043270c | the global menu was rebuilt on every sheet focus | none |
| b8b4319 | the dock stayed visible over apps in tablet posture | none |
| a44573b | a dock revealed by touch never hid again | none |
| 58d7583 | a home gesture with no app left the sheet open and logged a TypeError | none |
| 34d73bb | tablet home-screen widgets kept their landscape places in portrait | none |
| 1adb5d2 | an error when the widget layout key was set at start-up | none |
| 8903811 | a long press between dock icons put the panel into edit mode | none |
| d184d4f | KWin kept running the previous navigation QML after an update | none |
| b77ab97 | windows that bring their own position were not maximized in tablet posture | none |
| ba03afd | picking a split app in the switcher broke the split | none |
| 944478a | switching familiar icons off replaced the theme's links with copies | yes: the link cases of `packages/appicons/tests/designed_test.py`, added in da23db6, run by `tools/build.sh`; verified |
| dd26503 | build requirements missing from the specs (NumPy, Breeze) | yes: the build workflow (5026210) installs the spec's requirements and a few check tools in a clean Fedora 44, so a requirement the spec forgets fails it |
| 193e1aa | a non-executable script with a shebang failed rpmlint and the package build | yes: rpmlint in `packaging/build-rpm.sh`, run by the build workflow, which found it (a packaging check that existed before) |
| cab79f6 | KMail lost its tile to the Account Wizard; app-only icon names got colour tiles | none |
| f602ca0 | apps whose entry names a generic icon (KDebugSettings) showed a bare glyph | yes: `packages/common/tests/icontile.sh`, same commit; verified in the Plasma test container (with the old `FusionIconTile.qml` the lookup gives `debug-run`) |
| 7518778 | a charge limit did not stay where TLP manages the thresholds | none |
| a95f707 | familiar mode drew tiles under names the theme hands back to Breeze | yes: `designed_test.py`, same commit; verified |

Feature commits that fix something in passing (counted only in the second figure): 2dd5355
(pixel ratio from the screen), 9cae5cb (accent palette announced too early), ec997f9
(`backup-profile.sh` started display programs over SSH), f662575 (a press that slid off maximize
opened the layouts: tested by `pfdeco-preview`, same commit), 871ecb1 (typing into a hidden
password field), fce9608 (the clock shifted; settings pages showed the first entry), ac2aa8a (a
global menu crash), a04bc82 (KWin crash when quitting in tablet posture), 8fa94c2 (the launcher
key did not reopen), c40d66b (settings pages showed the first entry), 3693b33 (the power service
unit was looked up in an empty folder: the same commit added a `%check` line to the spec that
tests the unit is installed in that folder, so the RPM build fails without it; a packaging check),
321228a (the log-out cancel area exposed to screen readers: the same commit made the
accessibility lint stop the build; with `Accessible.ignored` taken out of `Logout.qml`,
`a11y-lint.py` reports the cancel area and exits 1; verified), 3e9b751 ("Setting initial
properties failed"), e7316d4 (errors from removed notification rows), 2bc6cf1 (a synthesised
pointer move showed the prompt), a8f233a (a tap on the page dots also hit the page), 1a3022c (an
"off" action for pop-ups already off), 3fd0e69 (the split handle appeared late), da23db6 (a glyph
sheen step; an old icon backup put over a newer one: tested by `designed_test.py`, same commit),
d99756b (the snap layouts flyout was not under the maximize button when the window buttons are on
the left: tested by the flyout checks of `packages/kwin/tests/vsession/scenario-kwin2-a.sh` for
the compiled decoration with left buttons and the Aurorae -Left theme, same commit; private
sessions; not re-run here).

## Test policy

Proposed for the maintainer's adoption; `CONTRIBUTING.md` points here.

1. **New functionality.** A change that adds or changes behaviour MUST add a test for it to an
   automated suite in the same pull request, and the pull request names the test. Automated
   suites: the checks `tools/build.sh` and the RPM build run, the unit tests
   (`tools/device/tests/gate-unit.sh`, `packages/*/tests/`, `tools/checks/tests/run.sh`), and the
   scripted private-session scenarios in the repository that assert their results
   (`tools/tests/`, `packages/*/tests/vsession/`). Behaviour that only a person can judge, such as
   a look against the design boards, is said so in the pull request, with the screenshots.
2. **Bug fixes.** A fix MUST come with a test in one of those suites that fails without the fix,
   unless the bug cannot be reproduced without hardware or inside Plasma itself; then the pull
   request says why.
3. **Coverage.** The `coverage` workflow measures the suites weekly. A change should not lower a
   language's product-code figure above without a reason given in the pull request.
