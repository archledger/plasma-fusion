<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# AGENTS.md — working in this repository

Dense guidance for coding agents (and anyone automating changes) contributing to Plasma Fusion.
For the human process, read [CONTRIBUTING.md](CONTRIBUTING.md); for the deep context of each part,
read its page in [`docs/parts/`](docs/parts/) before touching it. This file adds what an agent
needs on top: the hard rules, the exact commands, and where the facts live.

## The project in one paragraph

A KDE Plasma 6 desktop built from the Plasma Fusion design concept (macOS, GNOME and Windows 11
ideas on Plasma's Global Theme structure): themes, widgets, KWin scripts and effects, a lock
shell, a launcher, a dock, installers and per-channel packaging, in one source tree. Plasma 6.7 is
supported; Plasma 6.8 is tested from the beta through the parts that do not exist in 6.7 (they
load only where the API is there). The code is GPL-2.0-or-later, art and docs CC-BY-SA-4.0, data
CC0-1.0, fonts OFL-1.1; the design boards in `design/` decide every colour, size and drawing.

## Hard rules (never work around them)

Some of these are checks (a red check blocks a merge); the rest are project policy even where no
checker sees them.

- **One trailer per commit: the DCO, in the author's own name.** Every commit carries exactly one
  `Signed-off-by` trailer — the *author's* name and email, which `git commit -s` fills in from the
  git configuration (for example `Signed-off-by: Jane Doe <jane@example.com>`). Commit under your
  own identity and never sign off as anyone else. No other trailer. The `commits` workflow counts
  the trailers of every proposed commit (and of a squash merge as the one commit it makes), so an
  unsigned commit fails before a merge.
- **No AI attribution, anywhere in git or on GitHub.** Commit messages, branch and tag names,
  pull request and issue titles and bodies, review comments and release notes must not name or
  credit an AI agent, model or harness, must not link to AI products or sessions, and must not
  carry `Co-Authored-By`, `Generated-by`, `Claude-Session` or similar lines. This is a project
  rule checked by the `commits` workflow: the Signed-off-by trailer is the only one allowed.
- **Sign your commits** (project policy; no workflow checks signatures). The repository's history
  is signed; keep it that way when you work in this repository's checkouts.
- **Stay REUSE-compliant**: every new file gets an SPDX header or a `REUSE.toml` entry;
  `reuse lint` must pass.
- **Never weaken a check to pass.** Do not delete, skip or rewrite tests, add `qmllint`,
  ESLint or ShellCheck suppressions, loosen CI, or silence a warning at the source of the check.
  Fix the cause; if the check itself is wrong, say so with evidence in the pull request.
- **Report security problems privately**: follow [`SECURITY.md`](SECURITY.md); never open a
  public issue for a vulnerability.
- **A behaviour change updates the same change's part page** in `docs/parts/` and needs a test
  that fails without it (the test policy is [`docs/parts/coverage.md`](docs/parts/coverage.md),
  "Test policy").

## Layout

| Path | What |
| --- | --- |
| `packages/` | the parts: `plasmoids/` (the bar and its widgets, dock, launcher, quick settings, meters, ...), `lockscreen/`, `kwin/` (the snap script and the effects), `decoration-cpp/`, `navigation-cpp/`, `kcm-cpp/` (the settings module), `power/`, `powerfx/`, `appicons/`, `keyboard/`, `gtk/`, `konsole/`, `ktexteditor/`, `color-schemes/`, `look-and-feel/`, `plymouth/`, `compat/`, `common/` — many carry their own `tests/`; the part's page in `docs/parts/` lists the part's tests (several parts have none, e.g. the navigation effect) |
| `generators/` | the design sources: `plasma-style/`, `icons/`, `cursors/`, `wallpapers/`, `fonts/`, `decoration/`, `look-and-feel/`, `plymouth/` — the drawing pipeline from the boards |
| `tools/` | `build.sh` and `build.d/` (one script per part), `checks/` (the lints and their fixtures), `device/` (setup, restore, field log, gate — machine-facing tools), `tests/` (the packaging and release-VM harnesses), `plasma-fusion/` (the command-line tool) |
| `scripts/` | `install.sh` — the one-line installer (its test mode is also what the release VMs install from) |
| `docs/` | `PLAN.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `SECURITY-ASSURANCE.md`, `parts/*.md` (one page per part: architecture, tests, how CI runs), `RELEASING.md` |
| `design/` | the 25 design boards — the reference; the boards decide visuals, not the code |
| `packaging/` | `fedora/`, `arch/`, `debian/`, `nix/`, `check-version.sh`, `release-assets.sh` |
| `fuzz/` | the fuzz targets (`app_icons`, `keyboard_keys`, `previous_theme`) |

If you are not sure where a task lives, the part pages map it: widgets and the shell are under
`docs/parts/shell-*.md` (top bar, dock, launcher, quick settings, meters); the theme, icons and
cursors have their generator pages (`plasma-style.md`, `consistency.md`, `icons.md`,
`app-icons.md`, `cursors.md`), wallpapers are `foundation.md`; packaging and installs are
`system.md`, `installer.md`, `nixos.md`;
the device scripts are `device.md`, the login check `gate.md`, the terminal and editor themes
and the shared foundations `foundation.md`, the test harnesses `testing.md` and `ci.md`, the VM
harness `release-tests.md`.

## Generated outputs: change the source, regenerate

Most of the drawings the desktop ships — the Plasma styles' SVGs, the icon themes, cursors,
wallpapers — are **generated** from the design boards (`design/boards/*.dc.html`) and the sources
in `generators/` (the wallpaper SVGs under `generators/wallpapers/svg/`); the build scripts write
them into the staged tree (`STAGE`), not into the source `packages/` directory (only some art,
such as the Global Theme previews, is committed). The part's page in `docs/parts/` names the
generator, its inputs, its command and its own tests (for example
`generators/plasma-style/gen_plasma_style.py` writes complete theme packages). Do not hand-edit
generated files: change the generator, regenerate, and run the generator's tests and the part's
suite over the output. Some files are deliberately kept by hand
(for example the Breeze fallback set) — the part page says which. The boards decide the style,
but part pages also define work derived in that style rather than drawn on a board (the derived
icon and cursor sets, documented deviations — docs/parts/icons.md and cursors.md): maintain those
as their pages prescribe, and do not invent values beyond the boards and those derived sets.

## Build and check (exactly these commands)

- `tools/build.sh [NAME...]` — build the staged parts into a HOME tree under `STAGE` (default
  `stage/home`); it first runs the QML lints in `tools/checks/` (motion, a11y, id scope, calendar
  tile; `PF_LINTS=fail|warn|off`, default fail). `NAME` is a script in `tools/build.d/`
  (`ls tools/build.d/` lists them); a name without one builds nothing and still exits 0. The
  three compiled parts (`decoration-cpp`, `kcm-cpp`, `navigation-cpp`) are CMake projects with
  ctest suites, packaged with `packaging/build-rpm.sh --compiled` — their part page has the
  details.
- `tools/checks/tests/run.sh` — the lints' own fixtures.
- `tools/checks/shellcheck.sh` — ShellCheck over every script.
- `ruff check` — Python, configuration in `ruff.toml`.
- `git clang-format --diff main` — C++, KDE's style (`.clang-format`).
- `packaging/check-version.sh` — `VERSION` against the spec, the PKGBUILD and the Debian changelog.
- A part's own suites, listed on its `docs/parts/<part>.md` page and run by CI: the QML suites are
  Python and run offscreen; the suite's usage comment or its part page names the exact command —
  several need a private bus
  (`cd packages/<...>/tests && QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 <suite>.py <stage-home>`,
  e.g. the quick-settings and dock suites), others run with `QT_QPA_PLATFORM=offscreen` alone
  (e.g. the calendar-date, backdrop-reload and wheel-guard checks). A bare `python3 <suite>.py`
  on a live display is never the right run. The JavaScript suites run with `node`; the C++ parts
  run their ctest suites, which CI runs under the `sanitizers` workflow's flags.
- Packaging a snapshot: `packaging/build-rpm.sh` (add `--compiled` to include the three
  compiled parts; the default builds the shared part only); the other distribution channels have
  container-driven builders in `tools/tests/packages/`. NixOS is the exception: it is the flake
  (`packaging/nix/`, checked with `nix flake check` locally — no CI job runs Nix —
  docs/parts/nixos.md).

Run the checks a change touches locally before proposing it. CI covers them (a red check is never
waved through), with one exception: `nix flake check` is local-only — no workflow runs Nix. The
Fedora jobs run in Fedora 44 containers, the package-channel jobs in a container of their target
system (Arch, Debian testing, Ubuntu, KDE neon) and several other workflows on Ubuntu runners; a
Fedora 44 KDE machine with `podman` can reproduce all of them except the VM harness, which needs
QEMU with KVM and the images its page describes. The compiled parts need the dependencies their
part page lists (`dnf builddep`).

## What every change arrives with

- A test in an automated suite that fails without the change — new behaviour and every bug fix
  ([`docs/parts/coverage.md`](docs/parts/coverage.md), "Test policy").
- The part's page in `docs/parts/` updated in the same change when behaviour changes.
- The checks that cover it run locally, with the commands and their results named in the pull
  request (the house style: what was verified, how, and what was not).
- One subject per pull request; commits with exactly one DCO trailer and a signature. The required
  checks are `DCO and attribution`, `REUSE compliance` and `plasma-fusion RPM (Fedora 44)`;
  changes to compiled parts also wait for `compiled` and, where it applies, `sanitizers`. The
  maintainer reviews and merges.

## Conventions

- English, plain sentences, **why-first comments**, wrapped at 100 columns; the style of the
  surrounding code wins. QML: 4 spaces. Shell: bash with `set -euo pipefail` and an SPDX header —
  except the scripts that are POSIX `sh` by contract: `scripts/install.sh` (parsed and tested with
  dash and BusyBox; docs/parts/installer.md) and the pacman hook
  `packaging/arch/plasma-fusion-rebuild` (ShellCheck reads its shebang). Keep their interpreters;
  never add `pipefail` to them.
- QML rules the lints enforce: no literal animation durations and no endless animations
  (`motion-lint`), every interactive item has an accessible name (`a11y-lint.py`), an `id` is used
  only inside the component that declares it (`id-scope-lint.py`).
- Commits: one subject each; a short imperative title, a blank line, a wrapped body that says why,
  then the DCO trailer. No tool banners, no emoji, no attribution lines.
- Keep diffs to the change: no unrelated cleanup, no reformatting of neighbours. Preserve public
  behaviour and user data formats unless the task changes them.
- Verify external facts (Plasma/KDE API shapes, package versions, upstream fixes) against the
  actual sources for the version at hand before relying on them; say what was verified and what
  is inference.

## Testing: offline first, then a session, a VM, or hardware

Prove the logic offline; use the lower rungs only for what genuinely needs a desktop.

1. **Offline** — the part's suites (`docs/parts/<part>.md`, `docs/parts/ci.md`), `tools/build.sh`
   with its QML lints, and the C++ parts' ctest suites. Nothing here touches a session; start
   here. (The separate regression harnesses — icon positions, the performance gate, the adaptive
   matrix — are [`docs/parts/testing.md`](docs/parts/testing.md).)
2. **An isolated session on this machine** — `tools/vsession/vsession.sh NAME SCENARIO [WxH]
   [TIMEOUT]` runs a headless Plasma session (its own D-Bus bus and Wayland socket; it never
   touches the logged-in desktop) and sources `SCENARIO`, a bash file, inside it; the scenario can
   `shot NAME` screenshots, and everything lands under `/var/tmp/pfv-NAME` (`PFV_BASE` overrides).
   `tools/vsession/cvsession.sh NAME SCENARIO SEED_DIR [WxH] [TIMEOUT]` runs the same scenario in a
   Plasma test container (the seed directory is required; build the image with
   `tools/container/test/build.sh BASE TAG`; the base images cover Fedora 44's Plasma and the beta
   COPR — docs/parts/containers.md), results in `./vsession-out/NAME`. This is the cheapest
   rung that shows QML under a real plasmashell and KWin.
3. **A VM** — `tools/tests/release-vm/`: provision a system once (`provision.sh`), drive it
   (`vm.sh create|start|wait|ssh|shot|stop`), run the end-to-end installer and login check
   (`vmtest.sh NAME LANE`), and the release matrix (`build-all.sh`, `channels.sh`, `run-all.sh`;
   docs/parts/release-tests.md). Use it for install, upgrade, uninstall and login paths, and for
   anything that ends the session — never experiment with a logout, lock screen or power action on
   a machine you cannot recover unattended.
4. **Real hardware** — a convertible or touch device answers what emulation cannot: touches, pen,
   postures, brightness, suspend, hotspots. The device scripts (`tools/device/`, the
   `plasma-fusion setup|update|status|restore` command, docs/parts/device.md) are built for that.
   To validate a freshly built `stage/home` there, **deploy it first**:
   `tools/device/fusion-config.sh --install stage/home`, then restart the shell
   (`systemctl --user restart plasma-plasmashell`). `plasma-fusion update` is for an installed
   package after an upgrade and does *not* deploy a stage; the login screen, splash and fonts
   need a logout. Take a screenshot for a visual change and read the journal
   (`journalctl --user -f`, `coredumpctl`) for errors. Leave the machine as you found it, and
   never leave a test in a state the next person cannot undo.

The test containers and the `compiled` workflow's beta build are the stable and beta Plasma
lanes; the release-VM harness runs each system's own (stable) Plasma. When a change touches a part
that depends on Plasma internals, test it on the series it is built for — the beta lane is the
container and compiled-build one.

## Releases

`VERSION` is the only version (the spec, the PKGBUILD and the Debian changelog follow it,
`check-version.sh`). The process — version bump pull request, the VM matrix on the merged commit,
the signed tag, release assets and the channels — is [`docs/RELEASING.md`](docs/RELEASING.md).
Do not tag, change packaging metadata or touch `.github/` release plumbing without following it.
