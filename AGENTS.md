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

## Hard rules (CI enforces them; never work around them)

- **One trailer per commit: the DCO.** Every commit carries exactly one
  `Signed-off-by: Wisbendji Fimerlus <archledger236@gmail.com>` (`git commit -s`) and no other
  trailer. A squash merge satisfies it only when the pull request body carries the trailer.
- **No AI attribution, anywhere in git or on GitHub.** Commit messages, branch and tag names,
  pull request and issue titles and bodies, review comments and release notes must not name or
  credit an AI agent, model or harness, must not link to AI products or sessions, and must not
  carry `Co-Authored-By`, `Generated-by`, `Claude-Session` or similar lines. This is a project
  rule checked by the `commits` workflow: the Signed-off-by trailer is the only one allowed.
- **Sign your commits.** The repository's history is signed; keep it that way.
- **Stay REUSE-compliant**: every new file gets an SPDX header or a `REUSE.toml` entry;
  `reuse lint` must pass.
- **Never weaken a check to pass.** Do not delete, skip or rewrite tests, add `qmllint`,
  ESLint or ShellCheck suppressions, loosen CI, or silence a warning at the source of the check.
  Fix the cause; if the check itself is wrong, say so with evidence in the pull request.
- **A behaviour change updates the same change's part page** in `docs/parts/` and needs a test
  that fails without it (the test policy is [`docs/parts/coverage.md`](docs/parts/coverage.md),
  "Test policy").

## Layout

| Path | What |
| --- | --- |
| `packages/` | the parts: `plasmoids/` (the bar and its widgets, dock, launcher, quick settings, meters, ...), `lockscreen/`, `kwin/` (the snap script and the effects), `decoration-cpp/`, `navigation-cpp/`, `kcm-cpp/` (the settings module), `power/`, `powerfx/`, `appicons/`, `keyboard/`, `gtk/`, `color-schemes/`, `look-and-feel/`, `plymouth/`, `compat/`, `common/` — each with its own `tests/` |
| `generators/` | the design sources: `plasma-style/`, `icons/`, `cursors/`, `wallpapers/`, `fonts/`, `decoration/`, `look-and-feel/`, `plymouth/` — the drawing pipeline from the boards |
| `tools/` | `build.sh` and `build.d/` (one script per part), `checks/` (the lints and their fixtures), `device/` (setup, restore, field log, gate — machine-facing tools), `tests/` (the packaging and release-VM harnesses), `plasma-fusion/` (the command-line tool) |
| `scripts/` | `install.sh` — the one-line installer (its test mode is also what the release VMs install from) |
| `docs/` | `PLAN.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `SECURITY-ASSURANCE.md`, `parts/*.md` (one page per part: architecture, tests, how CI runs), `RELEASING.md` |
| `design/` | the 25 design boards — the reference; the boards decide visuals, not the code |
| `packaging/` | `fedora/`, `arch/`, `debian/`, `nix/`, `check-version.sh`, `release-assets.sh` |
| `fuzz/` | the fuzz targets (`app_icons`, `keyboard_keys`, `previous_theme`) |

## Build and check (exactly these commands)

- `tools/build.sh [PART...]` — build all parts (or named ones) into a HOME tree under `STAGE`
  (default `stage/home`); it first runs the QML lints in `tools/checks/` (motion, a11y, id scope,
  calendar tile; `PF_LINTS=fail|warn|off`, default fail).
- `tools/checks/tests/run.sh` — the lints' own fixtures.
- `tools/checks/shellcheck.sh` — ShellCheck over every script.
- `ruff check` — Python, configuration in `ruff.toml`.
- `git clang-format --diff main` — C++, KDE's style (`.clang-format`).
- `packaging/check-version.sh` — `VERSION` against the spec, the PKGBUILD and the Debian changelog.
- A part's own suites, listed on its `docs/parts/<part>.md` page and run by CI: the QML suites are
  Python, run offscreen on a private bus exactly like CI —
  `cd packages/<...>/tests && QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 <suite>.py <stage-home>`
  (a plain `python3 <suite>.py` without the private bus is not a valid run); the JavaScript suites
  run with `node`; the C++ parts run their ctest suites, which CI runs under the `sanitizers`
  workflow's flags.
- Packaging a snapshot: `packaging/build-rpm.sh`; every other channel has a container-driven
  builder in `tools/tests/packages/`.

Run the checks a change touches locally before proposing it. CI runs all of them; a red check is
never waved through.

## Conventions

- English, plain sentences, **why-first comments**, wrapped at 100 columns; the style of the
  surrounding code wins. QML: 4 spaces. Shell: bash with `set -euo pipefail` and an SPDX header.
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

## Testing on a real desktop

- In a session, staged files take effect with `plasma-fusion update` and a shell restart
  (`systemctl --user restart plasma-plasmashell`); the login screen, splashes and fonts need a
  logout. `plasma-fusion status` reports what the running system has.
- Never drive the lock screen, log-out or power actions destructively on a machine you cannot
  recover unattended. The VM harnesses in `tools/tests/release-vm/` exist for that
  (`build-all.sh`, `run-all.sh`, `vmtest.sh`), and every release runs them on all systems.

## Releases

`VERSION` is the only version (the spec, the PKGBUILD and the Debian changelog follow it,
`check-version.sh`). The process — version bump pull request, the VM matrix on the merged commit,
the signed tag, release assets and the channels — is [`docs/RELEASING.md`](docs/RELEASING.md).
Do not tag, change packaging metadata or touch `.github/` release plumbing without following it.
