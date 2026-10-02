# Part: continuous integration and repository automation

What runs on GitHub for `archledger/plasma-fusion`, what the repository settings are, and what to
do when one of them speaks up. Set up 2026-10-01 (CI) and 2026-10-02 (automation).

## Workflows (`.github/workflows/`)

| Workflow | When | What |
|---|---|---|
| `commits` | every push to `main`, every pull request | Each commit has exactly one `Signed-off-by` (DCO), no other trailer, and no message that names an AI product or agent |
| `reuse` | push, pull request | REUSE 3.3 compliance (`reuse lint`) |
| `build` | push, pull request | fedora:44: lint self-tests, the login-check unit tests, the noarch RPM (`packaging/build-rpm.sh`, `%check`, rpmlint), RPM as an artifact |
| `compiled` | changes to the compiled parts, weekly | navigation effect, decoration, settings module: `dnf builddep`, cmake with `CXXFLAGS=-Werror -Wno-error=deprecated-declarations` (a compiler warning fails the build, a deprecation stays a warning), ctest (see "Dynamic analysis" for the tests), against Fedora 44's Plasma (**stable**) and against KDE's Plasma beta packages (**beta**, the `@kdesig/kde-beta` Copr; may fail without failing the run: an early warning for the next Plasma release) |
| `workflow-audit` | changes to workflows | zizmor (security) and actionlint (correctness) over the workflows |
| `style` | push, pull request | Python: `ruff check` with `ruff.toml`; C++: `git clang-format` over the C++ lines the change touches, against `.clang-format` (KDE's style); shell: ShellCheck at severity warning (`tools/checks/shellcheck.sh`). See "Coding style" |
| `sanitizers` | changes to the compiled parts, weekly | the three compiled parts built with AddressSanitizer and UndefinedBehaviorSanitizer and their tests run, the random tests among them (a fixed seed on pull requests, a new seed and more runs weekly), so that a memory error, a leak or undefined behaviour fails the job (`tools/sanitizers/run.sh`). See "Dynamic analysis" |
| `codeql` | push, pull request, weekly | CodeQL over the workflows, the C++ parts (without building), the shell's JavaScript and the Python tools; results in the Security tab |
| `plasma-watch` | daily 06:25 UTC, by hand | Fedora 44's versions (stable updates and updates-testing) of the packages the login check watches, against `packaging/tested-versions.txt`; opens or updates one issue labelled `plasma-update` when Fedora has a newer one |
| `scorecard` | push to `main`, weekly, branch-protection changes | OpenSSF Scorecard: findings in the Security tab, published score for the README badge |
| `labeler` | pull requests | labels by the parts a pull request changes (`.github/labeler.yml`: icons, shell, kwin, settings, theme, boot, system, packaging, design, docs, ci) |

Every action is pinned to a commit hash with its version in a comment; every job starts with a
read-only token and widens only what it needs (`issues: write` for the watcher's issue,
`pull-requests: write` for the labeler, `security-events`/`id-token` for Scorecard). The labeler
uses `pull_request_target` to label pull requests from forks; it checks nothing out and runs no
code from the pull request (zizmor's warning about the trigger is suppressed there, with that
reason).

## Repository settings

- Secret scanning and push protection: on.
- Dependabot alerts and security updates: on. Version updates for the workflows' actions:
  `.github/dependabot.yml` (weekly, a release proposed after 7 days, CodeQL's actions grouped).
- Code scanning: the `codeql` workflow (Actions, C/C++, JavaScript, Python; GitHub's default setup
  is off, because a workflow pins and audits the action like the others and Scorecard sees it), plus
  Scorecard's results.
- Private vulnerability reporting: on; `SECURITY.md` says how to report.
- Ruleset `main`: the branch cannot be deleted or force-pushed; changes come through pull requests
  with one approval from a code owner (`.github/CODEOWNERS`), given after the last push, on a branch
  up to date with `main`, and the checks `DCO and attribution`, `REUSE compliance` and
  `plasma-fusion RPM (Fedora 44)` passing. Repository admins bypass it: the maintainer pushes to
  `main` directly, as before, and a deliberate history fix stays possible (as on 2026-10-02).
  Dependabot and outside contributions go through reviewed pull requests.
- Not required (yet): the `style` jobs (`Python style (ruff)`, `C++ style (clang-format, changed
  lines)`, `Shell (ShellCheck)`) report on every pull request, but a failure does not block the
  merge until they are added to the ruleset's required checks. They can be added as they are,
  because they run on every pull request. The `compiled` and `sanitizers` jobs must not be made
  required while their workflows have `paths` filters: a required check whose workflow did not run
  stays "Expected — Waiting for status to be reported", and every pull request that does not change
  a compiled part could not be merged.
- Discussions: on (questions and ideas; issues stay for defects).
- Social preview: the dark desktop board (`design/previews/Main.webp` scaled to 1024x640 and
  centred on 1280x640, each side filled with the board's edge colour row by row).
- OpenSSF Best Practices badge: passing, project 15168 (https://www.bestpractices.dev/projects/15168,
  registered 2026-10-02). Open items there: tagged releases (version tags, semantic versions,
  release notes: N/A until releases exist), broader automated tests, dynamic analysis (fuzzing).

## Coding style

The checks use tools that Fedora 44 packages (`ruff`, `git-clang-format`, `ShellCheck`) and run in
the `style` workflow on every pull request and push to `main`. They cover Python, C++ and shell.
QML, the language with the most files (232 tracked `.qml` files, against 149 `.sh`, 105 `.py` and
36 `.cpp`/`.h` when the shell check was added, 2026-10-02), has no style check yet: see **QML**
below.

**Python** follows the rules in `ruff.toml`, which are the rules the code already followed when the
check was added (2026-10-02): pyflakes (`F`) and pycodestyle's errors `E4`, `E7` and `E9` (the codes
the code's `# noqa` comments name), and lines of at most 160 characters, as in the C++ style.

- Not checked, because the code uses these forms on purpose: several modules on one import line
  (`E401`), several statements on one line (`E701`, `E702`), a lambda assigned to a name (`E731`), the
  names `l`, `I` and `O` (`E741`).
- Per file: the app tile batches (`generators/icons/apptiles/b_*.py`) import their drawing kit with
  `*` (`F405`) and keep SVG path data on one line per shape (`E501`), as do
  `generators/icons/art_files.py` and the contrast table of `packages/color-schemes/check_contrast.py`.
- Excluded for now, because open branches change these files and a style fix would collide with
  them: `packages/appicons/`, `packages/keyboard/plasma-fusion-keyboard-keys`, `packages/kwin/`,
  `packages/navigation-cpp/`, `packages/power/`, `packages/powerfx/`, `tools/device/`, `tools/system/`
  (`extend-exclude` in `ruff.toml`; remove a line once that work is merged). Checked without the
  exclusions on 2026-10-02, the only findings were two unused imports in
  `packages/kwin/tests/offscreen/keytest.py`, on `main`, `wip/fuzzing` and `wip/portability` alike.
  `wip/fieldlog` adds one more: a 192-character line in
  `tools/device/fieldlog/tests/fieldlog_test.py`; and its `tools/device/fieldlog/plasma-fusion-fieldlog`
  is a Python script without a suffix, which ruff checks only once it is in `extend-include`.
- Run it: `ruff check` in the top directory; `ruff check --fix` removes unused imports.

**C++** follows KDE's clang-format style: `.clang-format` is `kde-modules/clang-format.cmake` of
extra-cmake-modules 6.30, unchanged (MIT licence). The decoration matches it in full; the settings
module (79 places: one-line enums, line wrapping, the placement of raw-string scripts) and the
navigation effect (6 places: include order, line wrapping, a trailing space) do not yet. So that
these files are not reformatted while other branches change them, the `style` job checks only the
lines a change touches: `git clang-format --diff` against the pull request's base commit (for a
push to `main`, the previous tip), for `.c`, `.cc`, `.cpp`, `.cxx`, `.h`, `.hh`, `.hpp` and `.hxx`
files only (the style file also has rules for JSON, which the JSON files do not follow). A
reformatting of the two parts in one commit can follow once their open work is merged.

- Run it before committing: `git clang-format --diff main` shows what would change in the lines the
  branch touches; `git clang-format main` changes them in the working tree.
- Checked on 2026-10-02 with clang-format 22.1.8: no finding for this branch against `main`, none
  for `wip/split-pair` merged onto it (its navigation changes follow the style), a finding for a
  badly formatted line added to the decoration or to the settings module (only that line is
  reported), and no check of a changed JSON file.

**Shell** scripts pass ShellCheck at severity `warning` (errors and warnings; the `info` and
`style` notes are not enforced): `tools/checks/shellcheck.sh` checks every tracked `*.sh` file and
every file without a suffix that starts with a `sh` or `bash` `#!` line, following sourced files
(`-x`). A file that is only sourced names its shell with `# shellcheck shell=bash`; a warning that
does not apply is disabled on its line or for the file with `# shellcheck disable=SCxxxx` and the
reason in a comment. Layout (indentation, `set -euo pipefail` in scripts that run on their own)
follows the surrounding scripts; no formatter is enforced.

- Excluded for now, for the same reason and with the same list as `ruff.toml`: `packages/appicons/`,
  `packages/kwin/`, `packages/navigation-cpp/`, `packages/power/`, `packages/powerfx/`,
  `tools/device/`, `tools/system/`. On 2026-10-02 those paths held 37 scripts with 13 findings in 8
  files (7 sourced files without a shell, 4 `~` in quotes, 2 unused variables). The scripts the open
  branches add or change outside them pass.
- Run it: `tools/checks/shellcheck.sh` in the top directory (`--list` prints the scripts).
- Checked on 2026-10-02 with ShellCheck 0.11.0: 115 scripts, no finding.

**QML** has no enforced style yet. The QML follows the surrounding code (4-space indentation, no
tabs: on 2026-10-02, 306 of the 34136 indented lines of the tracked QML were not on a 4-space
step, most of them continuation lines). Before the parts, `tools/build.sh` runs the project's own
QML checks over `packages/`, `tools/checks/motion-lint.sh` (durations from the Motion tokens) and
`tools/checks/a11y-lint.py` (a name for every control), which are rules for motion and
accessibility, not a style guide. Qt's formatter `qmlformat` (6.11.2) would change 138 of the 204
QML files outside the excluded paths (2026-10-02), so enforcing it needs one reformatting commit
first, after the open branches are merged.

## Dynamic analysis

The `sanitizers` workflow runs `tools/sanitizers/run.sh` for each compiled part on pull requests
and pushes that change one, and every Wednesday. The script:

- builds the part with `CXXFLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1"`
  and `LDFLAGS=-fsanitize=address,undefined` (AddressSanitizer with LeakSanitizer, and
  UndefinedBehaviorSanitizer);
- checks with `readelf` that every plugin and program it built links the sanitizer runtime, so a
  build that dropped the flags fails instead of passing untested;
- checks that the part's tests are all registered (`tools/tests/ctest-required.sh`, which the
  `compiled` workflow runs too): CMake leaves a test out when `dbus-run-session` or the colour
  schemes are missing, and ctest would then pass with ECM's appstream test alone;
- runs the part's tests (ctest) with `ASAN_OPTIONS=halt_on_error=1:abort_on_error=1:detect_leaks=1:detect_stack_use_after_return=1:check_initialization_order=1:strict_init_order=1`
  and `UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1`: the first error of either sanitizer, or a
  leak at exit, fails the test. LeakSanitizer suppressions go in `tools/sanitizers/lsan.supp` (none
  so far).

The tests (also run by the `compiled` workflow, without sanitizers):

| Part | Test | What it runs |
|---|---|---|
| decoration | `pfdeco-preview-dark`, `pfdeco-preview-light` | `tests/pfdeco-preview` through `tests/run-checks.sh`: the built plugin with a mock KDecoration3 bridge, 134 checks per colour scheme (window states, hover and press, the snap-layouts trigger against a fake kglobalaccel, tablet-mode title bars against a fake KWin, short screens, the 200 % shadow) |
| decoration | `pfdeco-fuzz` | `tests/pfdeco-preview --fuzz` through `tests/run-checks.sh`: 200 random scenes. Each writes random values (valid, odd or none) for the configuration keys the decoration reads, picks random button lists, title font size, layout direction, tablet mode, window state and size, tile and screen, creates the decoration, applies up to 24 random input events and changes (hover, press, release, double click, wheel, resize, maximize, shade, palette, scale, configuration, buttons, font, tablet mode, screen), paints it and destroys it; checks that the borders stay finite and not negative |
| settings module | `kcmctl-load` | `tests/kcmctl` through `tests/run-kcmctl.sh`: the built module loaded as System Settings loads it, in a scratch HOME; every property read (53), the defaults applied in memory, every property read again; nothing is saved |
| settings module | `kcmctl-fuzz` | `tests/fuzz-kcmctl.sh`: 25 random rounds. Each writes `kdeglobals`, `kwinrc`, `plasmafusionrc` and `baloofilerc` with valid, odd and broken values (or leaves a key, a group or a file out), then drives the module through kcmctl with random commands (set with valid and invalid values, get, dump, load, save, defaults, the module's actions); checks that kcmctl exits normally and that every integer property stays in its range. The programs the module starts are stand-ins that exit with a random status, and kcmctl runs with only them on `PATH` |
| navigation effect | none yet | the job builds it with the sanitizers and runs only ECM's appstream test; it has no tests of its own |

The tests run offscreen, on a private D-Bus session without service activation
(`tests/session-bus.conf` of each part) and without display variables, in a scratch configuration
(and for the settings module a scratch HOME), so they reach no desktop session.

**Random tests.** `pfdeco-fuzz` and `kcmctl-fuzz` are generation-based random tests (fuzzing
without coverage feedback): a seeded generator (Qt's `QRandomGenerator` in the preview, bash's
`RANDOM` in the script) makes the inputs, so a seed repeats its run. `PF_FUZZ_SEED` (default 1) and
`PF_FUZZ_COUNT` (scenes or rounds) in the environment of ctest change them. Pull requests and pushes
run the default seed; the weekly and manual runs of the `sanitizers` workflow take a new seed and run
1000 scenes and 100 rounds. A failure prints its seed and scene or round; to repeat it:
`PF_FUZZ_SEED=<seed> PF_FUZZ_COUNT=<n> ctest --test-dir <build> -R fuzz --output-on-failure`.

**Coverage** of each part's own sources (`src/`) by its tests, with gcov (`--coverage -O0`, Fedora
44, Plasma 6.7.5, 2026-10-02; a header counted once; branches: taken at least once):

| Part | Tests | Lines | Branches |
|---|---|---|---|
| decoration | the preview checks | 1235 of 1370 (90.1 %) | 608 of 825 (73.7 %) |
| decoration | the preview checks and `pfdeco-fuzz` | 1281 of 1370 (93.5 %) | 658 of 825 (79.8 %) |
| settings module | `kcmctl-load` | 315 of 1374 (22.9 %) | 82 of 940 (8.7 %) |
| settings module | `kcmctl-load` and `kcmctl-fuzz` | 744 of 1374 (54.1 %) | 339 of 940 (36.1 %) |

What the tests do not reach: in the settings module, `src/shell.cpp` (the Plasma shell scripts for
the dock, the top bars, the desktop and the layout reset) stays at 49 of 405 lines, because no
Plasma shell answers on the tests' private bus; a stand-in `org.kde.plasmashell` for kcmctl would
reach it. The navigation effect has no tests (`packages/navigation-cpp/` has open work).

Run it locally in a Fedora 44 container (the source tree can stay read-only):

```
podman run --rm --security-opt label=disable -v "$PWD:/src:ro" registry.fedoraproject.org/fedora:44 \
  bash -c 'dnf install -y -q dnf-plugins-core rpm-build binutils libasan libubsan dbus-daemon &&
           dnf builddep -y -q /src/packages/decoration-cpp/*.spec &&
           /src/tools/sanitizers/run.sh /src/packages/decoration-cpp /tmp/build'
```

Results on 2026-10-02 (Fedora 44: GCC 16.2.1, Plasma 6.7.5, Qt 6.11.2, KDE Frameworks 6.30): all
three parts build instrumented; all tests pass with no sanitizer report. To make sure the setup
catches errors, a scratch copy of the decoration with planted errors (not committed) was built the
same way: a heap overflow and a use after free in `pfdeco-preview`, a signed integer overflow, a leak,
and a heap overflow in the plugin's `Decoration::init()`. Each one failed its test with the
matching report (UndefinedBehaviorSanitizer for the overflows, AddressSanitizer for the use after
free, LeakSanitizer for the leak).

The random tests, the same day: with the default seed, `pfdeco-fuzz` (200 scenes) and
`kcmctl-fuzz` (25 rounds) pass with no sanitizer report. Two errors planted where only inputs the
fixed tests never use reach them (not committed) were each found by the random test alone: a heap
overflow in the decoration's `createButtons()` for an `ExcludeFromCapture` button failed
`pfdeco-fuzz` in scene 1 with an UndefinedBehaviorSanitizer report while both preview tests passed,
and a heap overflow in the settings module's `loadConfigState()` for `[Input] TabletMode=off` failed
`kcmctl-fuzz` in round 2 while `kcmctl-load` passed.

## Warnings, build flags, debug information, repeatability, hardening

Checked on 2026-10-02 in Fedora 44 containers.

- **Warnings.** The CMake builds include KDE's compiler settings (`KDECompilerSettings`): `-Wall
  -Wextra -pedantic -Wcast-align -Wchar-subscripts -Wformat-security -Wpointer-arith -Wundef
  -Wnon-virtual-dtor -Woverloaded-virtual -Wvla -Wdate-time -Wsuggest-override -Wlogical-op
  -Wzero-as-null-pointer-constant -Wmissing-include-dirs`, with `-Werror=return-type
  -Werror=init-self -Werror=undef`. The three parts build with no warning at `RelWithDebInfo` with
  `-Werror`, with the sanitizers at `-O1`, and in their RPM builds; so does `wip/split-pair`'s
  navigation effect (`RelWithDebInfo` with `-Werror`). The `compiled` workflow now fails on any
  warning except deprecations.
- **Standard variables.** The parts are C++ only (`CC` and `CFLAGS` do not apply). CMake takes the
  compiler from `CXX` and starts its compiler and linker flags from `CXXFLAGS` and `LDFLAGS`;
  `KDECompilerSettings` only adds to them. A test build of the decoration with
  `CXX=/usr/bin/x86_64-redhat-linux-g++`, a marker define in `CXXFLAGS` and a marker option in
  `LDFLAGS` used that compiler and the define on all 8 compile lines and the option on the link
  line. The `sanitizers` job relies on this (its flags come only from `CXXFLAGS` and `LDFLAGS`,
  and its `readelf` check fails if they were dropped), and so do the RPM builds: Fedora's `%cmake`
  passes `%optflags` and `%build_ldflags` that way, and all 25 compile lines of the three spec
  builds carry `-fstack-protector-strong`, `-fcf-protection` and `-D_FORTIFY_SOURCE=3`.
- **Debug information.** The builds compile with `-g` (`RelWithDebInfo`, or Fedora's `%optflags`);
  nothing strips at install (`cmake --install`, no `install -s`). rpmbuild moves the debug
  information into `-debuginfo` and `-debugsource` packages (one `.debug` file per plugin, by
  build ID). The `plasma-fusion` package is noarch and has no binaries.
- **Repeatable.** Two `tools/build.sh` stages of `37a4d82`, built in two directories two minutes
  apart: 16226 entries each, identical contents, modes and link targets, and no build directory
  path in any file. The Python changes of the `style` work give the same stage. Two
  `packaging/build-rpm.sh` runs of one commit gave identical source tarballs and package payloads,
  but packages with different build times; `build-rpm.sh` now gives rpm the commit time as build
  time (`use_source_date_epoch_as_buildtime`) and a fixed build host name. Since then two runs in
  the same directory give bit-for-bit identical source and binary RPMs (at `57c8829`: the noarch
  RPM `plasma-fusion-0.1.0-155.git57c8829` had sha256 `7221579a0b38...` and the source RPM
  `5c9f220d3324...` in both runs). Run in two directories, the source RPM's header still differs:
  it keeps the expanded spec, which names rpmbuild's top directory (and the binary RPM's header
  records the source RPM's digest). The noarch RPM's payload is the same either way.
- **Repeatable, compiled parts.** The decoration's plugin at `57c8829`, built twice in one
  directory, was the same file each time (`RelWithDebInfo`: sha256 `c280f4dd...`; Fedora's
  `%optflags`: `a05c4f46...`; the same GNU build ID each time). Fedora 44's rpm takes
  `SOURCE_DATE_EPOCH` from the spec's changelog, but by default does not use it as the build time
  (`use_source_date_epoch_as_buildtime` is 0) and records the build container's host name. The container scripts
  (`packages/kcm-cpp/container-build.sh`, `packages/decoration-cpp/tools/container-build.sh`) now
  set both, and the decoration's source tarball has a fixed order, owner and time. Built twice from
  `35fe9e0` in `localhost/plasma-fusion-build:f44-6.7.5`, from two host directories (both mounted
  at `/work`, as `build-rpm.sh` does): every package came out identical, `plasma-fusion-settings`
  1.0.0-6 (binary `860b8c27...`, debuginfo, debugsource, source RPM `e25ff306...`) and
  `plasma-fusion-decoration` 1.0-3 (binary `3b602a36...`, debuginfo, debugsource). The navigation
  effect's scripts are not changed yet (`packages/navigation-cpp/` has open work).
- **Hardening.** The compiled parts' RPMs (built from their spec files) use Fedora 44's hardened
  flags: `-O2 -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS -fstack-protector-strong
  -fstack-clash-protection -fcf-protection`, linked with `-z relro -z now`. All three plugins have
  full RELRO (`GNU_RELRO`, `BIND_NOW`), a non-executable stack, the IBT and SHSTK property note,
  stack protector and fortified calls. `annocheck` (with the debug files) passes the decoration and
  the settings module; it fails the navigation effect's plugin on its run-path test only: the plugin
  carries `RUNPATH $ORIGIN/../../../../../lib64`, which Qt's `qt_add_qml_module` sets for a plugin
  installed below `<prefix>/qml`. Fedora's QML directory is `/usr/lib64/qt6/qml`, so it points to
  `/usr/lib64/qt6/lib64`, which does not exist. Configuring with `-DQT_NO_QML_PLUGIN_RPATH=ON` (Qt's
  switch for this) leaves it out, as a scratch build showed. Not changed here, because
  `packages/navigation-cpp/` has open work.
- **User services** (`packages/appicons/plasma-fusion-app-icons.service`,
  `packages/powerfx/plasma-fusion-powerfx.service`) run as the user without capabilities, with
  `NoNewPrivileges=yes`, `MemoryMax=`, `Nice=10` and `Slice=background.slice`. Not set yet, each to be
  tried in a real session because both services talk to D-Bus and write to the user's files
  (configuration, icons): `RestrictAddressFamilies=AF_UNIX` and `PrivateNetwork=yes` (neither uses the
  network), `LockPersonality=yes`, `RestrictRealtime=yes`, `RestrictSUIDSGID=yes`,
  `RestrictNamespaces=yes`, `SystemCallArchitectures=native`, `MemoryDenyWriteExecute=yes` (to be
  tested with the app icon service, whose Python uses ctypes), `ProtectSystem=strict` with
  `ReadWritePaths=` for the files each one writes, `PrivateTmp=yes`, `ProtectKernelTunables=yes`,
  `ProtectKernelModules=yes`, `ProtectControlGroups=yes`, `ProtectClock=yes`. In a user service the
  file system options need unprivileged user namespaces (systemd turns on `PrivateUsers=`).
  `systemd-analyze security --offline=true --user` rates both units 9.0; most of the items it counts
  are capability limits, which do not apply to a service without capabilities. The units were not
  changed here, because `wip/portability` changes them.

## When something speaks up

- **A Dependabot pull request** fails `commits` until its commit carries the maintainer's
  `Signed-off-by`: reword the commit (a plain message saying what moved and why, one trailer),
  force-push the pull request branch, merge when green.
- **A `plasma-update` issue**: Fedora 44 has a newer Plasma or Qt than Plasma Fusion is tested on.
  The test machines hold Plasma at 6.7.x (`/etc/dnf/libdnf5.conf.d/90-plasma-fusion-hold-plasma-6.8.conf`).
  Build the compiled parts against it (the `compiled` beta job shows the first breakage), test a
  private session (docs/parts/testing.md), fix, then raise the lines in
  `packaging/tested-versions.txt` and lift the hold. The issue is closed by hand.
- **The `compiled` beta job fails**: the next Plasma release breaks a compiled part. Not urgent
  while the hold is in place; the log names the API.
- **`style` fails**: for Python the log names file, line and rule; fix it, or, where the form is
  meant, add `# noqa: CODE` with the reason, as the code does elsewhere. For C++ the log shows the
  change clang-format wants; `git clang-format <base>` makes it in the working tree. For shell the
  log names file, line and ShellCheck code; fix it, or disable the code on that line with the
  reason (`# shellcheck disable=SCxxxx`).
- **`sanitizers` fails**: the failed test's output holds the sanitizer's report (kind of error and
  stack). Run the same build locally with the `podman` command under "Dynamic analysis"; for
  `pfdeco-fuzz` or `kcmctl-fuzz`, set the `PF_FUZZ_SEED` and `PF_FUZZ_COUNT` the log names. Fix the
  code, and add the case to the part's fixed checks when it is worth keeping. A leak inside a system
  library that Plasma Fusion cannot fix goes into `tools/sanitizers/lsan.supp`, with a comment
  saying why. A missing test (`ctest-required.sh`) means the build lacked `dbus-run-session` or the
  colour schemes.
- **`compiled` fails on a warning**: fix the warning; a deprecation from a Fedora update stays a
  warning and does not fail the build.
- **A code scanning or Scorecard alert**: Security tab; fix or dismiss with a reason.
