# Security assurance case

Why Plasma Fusion's security requirements are met, and where they are not yet. It covers what
users can and cannot expect, the threat model, the trust boundaries, the secure design principles
applied, the common weaknesses countered, input validation, and hardening. The claims point to
the files that show them. Written 2026-10-02 against `main` at 37a4d82; report problems as
[`SECURITY.md`](../SECURITY.md) says.

## 1. What users can and cannot expect

Plasma Fusion is a theme and shell for KDE Plasma 6 ([`ARCHITECTURE.md`](ARCHITECTURE.md)). Almost
all of it runs as the logged-in user inside Plasma's own processes. A few parts run as root, guard
the session or run before the desktop starts; those are what this case is about.

### You can expect

- **The per-user install stays in your HOME.** `fusion-config.sh` changes files in your HOME only,
  copies every file it may change to `~/.local/state/plasma-fusion/backup-<time>/` first, and
  `fusion-restore.sh` puts them back ([`parts/device.md`](parts/device.md)). `--dry-run` shows
  every change without making one.
- **Root only where it is needed, and only when you ask.** Apart from installing the packages,
  three things run as root: the charge-limit helper (through pkexec, section 3.1), and the two
  optional installers for the login greeter's look and the boot splash, which you start yourself
  with `sudo` (sections 3.4, 3.5). The packages have no install scripts, no setuid files and no
  system services (`packaging/plasma-fusion.spec.in`).
- **The lock screen does not decide who gets in.** The Plasma Fusion lock screen is QML that
  kscreenlocker's greeter loads; the password is checked by kscreenlocker and PAM, unchanged from
  Plasma 6.7.5. If the QML fails to load, kscreenlocker's built-in lock screen is used
  ([`parts/lockscreen.md`](parts/lockscreen.md), "Authentication contract").
- **Notifications stay private on the lock screen.** By default the lock screen shows one card per
  app with a count, no titles and never message text (`showNotificationSummaries` defaults to
  false; `packages/lockscreen/org.plasmafusion.lockshell/contents/lockscreen/config.xml`).
- **The boot splash never sees your disk passphrase.** Plymouth gives the theme script only the
  prompt and the number of typed characters (`pf_display_password(prompt, bullets)` in
  `packages/plymouth/plasma-fusion.script.in`).
- **No network traffic of its own, no telemetry.** Plasma Fusion's code opens no network
  connections. The weather card asks Plasma's own weather engine, and only after you pick a
  location (`packages/plasmoids/org.plasmafusion.weathercard/contents/ui/main.qml`).
- **On Fedora, after a Plasma update, the version-bound parts step aside.** After an update of
  Plasma, KWin, kscreenlocker, libplasma, KDecoration or Qt, the login check switches the
  version-bound parts off until the new versions are tested: KDE's own lock screen and Folder View
  desktop come back, the tablet gestures are off, and the compiled decoration is replaced by the
  Plasma Fusion Aurorae theme, which has no compiled plugin ([`parts/gate.md`](parts/gate.md)).
  The check reads the versions with `rpm` and Fedora's package names. Without `rpm` it records no
  versions, so it does not notice an update and switches nothing off; support for pacman, dpkg
  and Nix is roadmap item 3 ([`ROADMAP.md`](ROADMAP.md)).

### You cannot expect

- **Protection from programs that run as you.** Any program running under your account can change
  your Plasma Fusion files, including the lock screen QML in `~/.local/share`, which Plasma loads
  before the system copy. This is how Plasma works for every theme; Plasma Fusion adds no defence
  against it.
- **A password for the charge limit.** Whoever sits at the active local session can change the
  battery charge limit without a password, by design (section 3.1). Remote and inactive sessions
  cannot.
- **Signed releases or packages.** There are no releases yet, and the RPMs built by CI are not
  signed ([`GOVERNANCE.md`](../GOVERNANCE.md), "Releases"). Build from a source you trust.
- **Review by more than one person.** One maintainer writes and reviews every change
  ([`GOVERNANCE.md`](../GOVERNANCE.md)). There has been no outside security audit.
- **Support outside the tested platform.** Plasma Fusion is experimental and tested on Fedora 44
  with Plasma 6.7.5 only ([`README.md`](../README.md), "Status").
- **Fixes for KDE's own code.** Security problems in Plasma, KWin, kscreenlocker, PAM or Plymouth
  belong to their projects ([`SECURITY.md`](../SECURITY.md)).

## 2. Threat model

### What is protected

| Asset | Why it matters |
|---|---|
| The locked session | A locked screen must not open without authentication. |
| Passwords and passphrases | Typed into the lock screen and the boot splash prompt. |
| The system (root) | The helper and the root installers must not give a user more than they are meant to do. |
| The user's settings and files | The installer and the services edit many KDE files; a mistake must be undoable. |
| Being able to log in | The login check runs before the desktop starts; it must not block a login. |
| Private data on the lock screen | Notification contents of a locked session. |
| The source and the build | What users install comes from this repository and its CI. |

### Who might attack, and how

| Actor | Can | Wants |
|---|---|---|
| A1: another local user at the computer (a shared machine) | use the active session's polkit rights while at the console | root, or change of another user's files |
| A2: a remote or inactive session (SSH, a second seat) | run commands as some user | the charge-limit action, root |
| A3: someone at a locked screen or at the boot prompt | type, touch, plug in devices | get past the lock, read notifications |
| A4: a package or Flatpak with crafted metadata, or a USB device with a crafted name | supply `.desktop` files, icons, device names that Plasma Fusion reads | code execution as the user through those values |
| A5: a contributor or a pull request | propose code, open pull requests | get malicious code merged or run in CI with secrets |
| A6: a compromised upstream action or package | change what CI runs or builds with | tamper with the build or steal tokens |

Out of scope: a program already running as the user (it owns the session; section 1), root on the
machine, and defects in KDE's or the distribution's code.

## 3. Trust boundaries

Each boundary, what crosses it, and how it is guarded.

### 3.1 The charge-limit helper (user to root, through pkexec and polkit)

- The quick settings tile runs `pkexec /usr/libexec/plasma-fusion/plasma-fusion-charge-limit set N`
  (`packages/plasmoids/org.plasmafusion.quicksettings/contents/ui/services/ChargeLimit.qml`).
- The polkit action `org.plasmafusion.charge-limit` allows only that one program
  (`org.freedesktop.policykit.exec.path`) and only for the active local session: `allow_active=yes`,
  `allow_inactive=no`, `allow_any=no`
  (`packages/power/charge-limit/org.plasmafusion.charge-limit.policy`).
- pkexec starts it with a minimal environment. The helper sets `set -euo pipefail` and `LC_ALL=C`,
  accepts only `get` or `set` with a whole number from 50 to 100, refuses to write without root
  (exit 77) and while TLP manages the thresholds (exit 69), and writes only the
  `charge_control_*_threshold` files of built-in batteries (not of a pen or mouse battery)
  (`packages/power/charge-limit/plasma-fusion-charge-limit`).

### 3.2 The lock screen (the locked session)

- `kscreenlocker_greet` loads the QML of `org.plasmafusion.lockshell`; KWin starts it, with the
  shell chosen by `PLASMA_DEFAULT_SHELL` in KWin's environment only
  (`tools/device/lockscreen-enable.sh`).
- The QML keeps every authentication handler of Plasma 6.7.5's own lock screen; PAM decides
  ([`parts/lockscreen.md`](parts/lockscreen.md), "Authentication contract"). The QML cannot unlock
  on its own: the greeter checks the authenticator before it quits (same page).
- The password field keeps Plasma's rules: no undo, sensitive-data input-method hints, reveal only
  when KDE's `lineedit_reveal_password` permission allows it, cleared before the computer suspends
  (`PasswordField.qml`, `MainBlock.qml` and `LockScreenUi.qml` in
  `packages/lockscreen/org.plasmafusion.lockshell/contents/lockscreen/`).
- With notification cards switched off, the lock screen does not even register with the
  notification server ([`parts/lockscreen.md`](parts/lockscreen.md), review findings).
- Recovery if it ever misbehaves: `loginctl unlock-session` from a text console or SSH
  ([`parts/lockscreen.md`](parts/lockscreen.md)).

### 3.3 The login check (before the desktop starts)

- startplasma sources `~/.config/plasma-workspace/env/plasma-fusion-gate.sh` at every login and
  waits for it without a time limit. The stub therefore runs the check as its own process under
  `timeout -k 1 4`, with no input and its output discarded, and never exits the sourcing shell
  ([`parts/gate.md`](parts/gate.md), "When a login runs it").
- The check always exits 0, starts no GUI program and makes no D-Bus or systemd call at login
  (`tools/device/gate/plasma-fusion-gate.sh`, header). It records each change before making it,
  writes each file to a temporary file next to it and renames it over the original (permissions
  kept), and undoes a change only while the value is still the one it wrote (same file).

### 3.4 The boot splash installer (root) and the boot splash (early boot)

- `tools/system/plymouth-install.sh` is run by an administrator with `sudo`. It refuses unknown
  options, needs root (except `--dry-run`), does not install the script plugin with dnf while an
  offline update is scheduled, copies only `*.png`, `*.script` and `*.plymouth` files from the
  theme directory, installs a fresh copy and swaps it in, and restores the SELinux labels. With
  `--select` it first keeps the previous initramfs, theme name and `plymouthd.conf` for
  `plymouth-uninstall.sh`.
- The greeting name and the keyboard label it draws come from the account database and
  `/etc/vconsole.conf` and are filtered first (section 6). The greeting is drawn by
  `python3 -I -B`, which ignores the caller's Python environment, user site packages and the
  current directory. The keyboard label's short name is looked up in `evdev.xml` by a second
  Python call that has no `-I` (`python3 -`), so it also imports from the directory the tool was
  started in (section 7).
- In the initramfs the theme script only draws; Plymouth and systemd-cryptsetup handle the
  passphrase (section 1).

### 3.5 The login greeter styling (root writing into the greeter's home)

- `tools/system/greeter-apply.sh` runs as root but does everything inside the `plasmalogin`
  user's home as that user, through `setpriv --reuid ... --no-new-privs`, so a link planted there
  cannot make root write elsewhere. The KDE tools run with a cleared environment (`env -i`).
- `--display-from FILE` refuses a link and files over 1 MiB, reads the file as its owner, not as
  root, and accepts it only if it parses as KWin's output configuration. That parse
  (`display_summary`) runs `python3 -c` as root in the caller's directory, without `-I` and
  without `env -i` (section 7).
- Work directories come from `mktemp -d` with mode 0700; backups go to
  `/var/lib/plasma-fusion/greeter-backup-<time>/` with mode 0700; `greeter-restore.sh` puts them
  back.

### 3.6 User services (data from other packages)

- `plasma-fusion-powerfx` and `plasma-fusion-app-icons` run as the user with `NoNewPrivileges=yes`,
  a memory limit (32 MiB and 512 MiB), lower CPU priority and, for the icons, idle I/O priority
  (`packages/powerfx/plasma-fusion-powerfx.service`,
  `packages/appicons/plasma-fusion-app-icons.service`).
- The app icons service reads every installed app's `.desktop` file and icon, including Flatpaks
  and the user's own entries: data from any package (actor A4). Icon names that contain `/` are
  skipped, desktop ids have `/` replaced, files are copied without following links, and the
  drawing runs in a child process with time limits
  (`packages/appicons/plasma-fusion-app-icons`).

### 3.7 Shell widgets running commands

- Some widgets run KDE tools through Plasma's executable data engine, which passes a command line
  to a shell. Values that come from outside the widget are typed, allowlisted or quoted before they
  are put in a command (section 6). The settings module runs its tools with an argument list and
  time limits, without a shell (`PlasmaFusionKcm::runTool` in `packages/kcm-cpp/src/kcm.cpp`).

### 3.8 Compiled plugins inside KWin

- The window decoration and the tablet navigation effect run inside the compositor, which sees all
  input. They are small C++ plugins built on KDE's and Qt's libraries
  ([`ARCHITECTURE.md`](ARCHITECTURE.md), "Compiled parts"). The navigation effect stays idle when
  the running KWin is not the version it was built against
  (`packages/navigation-cpp/src/plugin/fusionnavigation.cpp`), and on Fedora the login check
  turns the version-bound parts off after a KWin update (sections 1 and 3.3).

### 3.9 CI and the supply chain

- Every GitHub Action is pinned to a commit hash; every workflow starts with a read-only or empty
  token and widens it per job only where needed; checkouts do not keep credentials
  (`persist-credentials: false`) ([`parts/ci.md`](parts/ci.md), `.github/workflows/`).
- The workflows are checked by zizmor and actionlint (`workflow-audit`), the code by CodeQL for
  Actions, C/C++, JavaScript and Python (`codeql`), the repository by OpenSSF Scorecard
  (`scorecard`). Dependabot proposes action updates after a 7-day cooldown
  (`.github/dependabot.yml`). Secret scanning and push protection are on.
- The labeler runs on pull requests from forks with a write token but checks out and runs nothing
  from the pull request (`.github/workflows/labeler.yml`).
- The `main` branch cannot be deleted or force-pushed; other people's changes need a pull request,
  a code owner's approval after the last push and three passing checks (DCO and attribution, REUSE,
  the RPM build) ([`parts/ci.md`](parts/ci.md), "Repository settings").
- The build fetches nothing but the distribution's packages named in the spec file
  (`packaging/plasma-fusion.spec.in`, `.github/workflows/build.yml`); the installed code downloads
  nothing.

## 4. Secure design principles applied

The principles of Saltzer and Schroeder, as the Best Practices criteria list them.

| Principle | Where |
|---|---|
| Economy of mechanism | The only part that runs as root in normal use is an 84-line shell script with two commands (`packages/power/charge-limit/plasma-fusion-charge-limit`). Everything else is themes, QML and small user services that Plasma loads in its usual places ([`ARCHITECTURE.md`](ARCHITECTURE.md)). |
| Fail-safe defaults | After an update the login check falls back to KDE's own lock screen and desktop and to the Plasma Fusion Aurorae decoration, which has no compiled plugin (`plasma-fusion-gate.sh`); a missing or unreadable version record counts as untested ([`parts/gate.md`](parts/gate.md)). This holds where `rpm` reports the versions (Fedora); without `rpm` the check does not notice updates yet (section 1). The polkit action denies remote and inactive sessions. Lock screen notification text is off by default. A QML error in the lock screen falls back to kscreenlocker's own. |
| Complete mediation | Every charge-limit change goes through pkexec and polkit, and the helper checks root and its argument itself on every call. |
| Open design | All code and all security measures are public in this repository; nothing depends on secrecy. |
| Separation of privilege | Reading the charge limit needs no privilege; writing needs pkexec ([`parts/charge-limit.md`](parts/charge-limit.md)). The greeter tool writes `/etc/plasmalogin.conf` as root but the greeter's home as the greeter user (`tools/system/greeter-apply.sh`). |
| Least privilege | The per-user install needs no root. The helper is one program for one action. The power tiers and app icons services run with `NoNewPrivileges=yes`. The greeter tool drops to the greeter user and to a file's owner to read it. CI tokens are read-only unless a job needs more. |
| Least common mechanism | Plasma Fusion adds no daemon shared between users and no system service; per-user state stays in each HOME ([`ARCHITECTURE.md`](ARCHITECTURE.md), "Where state lives"). |
| Psychological acceptability | Safe defaults need no setup; every change can be previewed (`--dry-run`) and undone (`fusion-restore.sh`, `greeter-restore.sh`, `plymouth-uninstall.sh`); the login check explains itself in a notification. |
| Limited attack surface | No network code, no listening sockets, no setuid files; the root parts run only when called. |
| Input validation with allowlists | Section 6. |

## 5. Common weaknesses countered

| CWE | Weakness | How it is countered |
|---|---|---|
| CWE-78 | OS command injection | Widgets put outside values into commands only typed (`setLimit(value: int)` in `ChargeLimit.qml`; integer device ids in `packages/plasmoids/org.plasmafusion.pen/contents/ui/services/PenDevice.qml`), allowlisted or single-quoted (`shellQuote` in `packages/plasmoids/org.plasmafusion.dock/contents/ui/main.qml`, `quote` in `packages/plasmoids/org.plasmafusion.quicksettings/contents/ui/services/TabletPolicy.qml`, `q` in `packages/plasmoids/org.plasmafusion.pen/contents/ui/PenSettings.qml`). Python tools never use `shell=True` or `os.system`; the settings module runs programs with an argument list. |
| CWE-20 | Improper input validation | Allowlists at each boundary (section 6). |
| CWE-22 | Path traversal | The app icons service skips icon names containing `/` and replaces `/` in desktop ids before using them as file names (`packages/appicons/plasma-fusion-app-icons`). |
| CWE-59 | Link following | The greeter tool works in the greeter's home as the greeter user and refuses a link for `--display-from`; the app icons service copies without following links. |
| CWE-250, CWE-269 | Unnecessary or badly managed privilege | Section 4, least privilege; the polkit action is bound to one program by `exec.path`. |
| CWE-862 | Missing authorization | Writing the charge limit needs polkit's `allow_active` and root in the helper. |
| CWE-377 | Insecure temporary files | `mktemp -d` with mode 0700 in the root tools; the login check writes its temporary file next to the target in the user's own directory and renames it. |
| CWE-400 | Resource exhaustion | Time limits on the login check (4 s), on child processes in the app icons service and on the settings module's tools; memory limits on the power tiers and app icons services; a 1 MiB limit on the display file the greeter tool reads. |
| CWE-426 | Untrusted search path | The helper is called by absolute path and started by pkexec with a minimal environment; the boot splash installer draws the greeting with `python3 -I`; the greeter tool runs the KDE tools with `env -i` and a fixed `PATH`. Not yet everywhere: two Python calls in the root tools have no `-I` and import from the current directory (section 7). |
| CWE-200, CWE-359 | Private information shown on the lock screen | Notification titles off and text never shown (`config.xml`); no notification watcher at all when the cards are off. |
| CWE-549 | Unmasked password | Lock screen and boot splash show bullets; the lock screen reveals the password only where KDE's permission allows it. |
| CWE-798 | Hard-coded credentials | None in the code; secret scanning and push protection on the repository. |
| CWE-829, CWE-1357 | Untrusted or unreliable third-party components | Actions pinned by hash, audited by zizmor, updated by Dependabot after a cooldown; the build uses the distribution's packages only. |
| CWE-1104 | Unmaintained third-party components | Dependabot for actions; the `plasma-watch` workflow opens an issue when Fedora 44 ships a newer Plasma or Qt than the tested one ([`parts/ci.md`](parts/ci.md)). |
| CWE-787, CWE-416, CWE-134 | Memory safety and format strings in C++ | The C++ parts are small and use Qt's containers and strings; their RPMs are built with Fedora's hardened flags (section 7); CodeQL scans the C++ code. Not yet fuzzed (section 8). |

## 6. Input validation at each boundary

Widget files named here without a path are under
`packages/plasmoids/org.plasmafusion.<widget>/contents/`; the helper is
`packages/power/charge-limit/plasma-fusion-charge-limit`.

| Boundary | Input | Check |
|---|---|---|
| Charge-limit helper (root) | the command and END | `get` or `set` only; END must match `^[0-9]{2,3}$` and lie in 50..100, else exit 64 (`plasma-fusion-charge-limit`); a leading zero still passes (section 7) |
| Quick settings to the helper | the limit | an `int` parameter (`ChargeLimit.qml`) |
| Quick settings, notifications | an app's desktop entry name, put into a `kwriteconfig6` command | must match `^[A-Za-z0-9._-]+$`, else nothing is written (`NotificationCentreContent.qml`, `setAppKey`) |
| Quick settings, light and dark | a Global Theme id from the configuration | reduced to `[A-Za-z0-9._-]` and checked against `plasma-apply-lookandfeel --list` before it is applied (`Backend.qml`) |
| Weather card | the configured weather source | at most 512 characters, three or four `|` fields, a provider name of `[a-z0-9_.-]`, the word `weather` (`isSafeSource` in `packages/plasmoids/org.plasmafusion.weathercard/contents/code/weather.js`) |
| Pen settings | the pen's device name from KWin (set by the device) | single-quoted; vendor and product ids are integers (`PenSettings.qml`, `PenDevice.qml`) |
| App icons service | `.desktop` files and icons of any package | only `[Desktop Entry]` keys are read; hidden and non-application entries skipped; icon names with `/` skipped; rendering in a child process with time limits |
| Boot splash installer (root) | options; the theme directory; the greeting name; the keyboard layout | unknown options refused; only three file types copied; the name has control and separator characters replaced and is drawn only if the font covers it (`generators/plymouth/greeting.py`, `clean`); the label is reduced to `[A-Z0-9+_()-]`, at most 6 characters |
| Greeter styling (root) | `--display-from FILE` | no link, a regular file, at most 1 MiB, read as its owner, must parse as a KWin output configuration |
| Login check | KDE configuration files and package versions | values compared with fixed Plasma Fusion ids; an unreadable record or a slow `rpm` (over 3 s) counts as untested ([`parts/gate.md`](parts/gate.md)) |
| Settings module | the user's choices | stored as enumerated names (for example the glass and button styles in `kcm.cpp`) |

## 7. Hardening

### In place

- polkit action limited to one program and the active local session (section 3.1).
- The power tiers and app icons services: `NoNewPrivileges=yes`, memory limits, `Nice=10`, the
  background slice, idle I/O for the icons service (section 3.6).
- Root tools: dropping to the greeter user or the file's owner with `setpriv --no-new-privs`,
  cleared environments for the KDE tools, isolated Python (`-I`) for the boot splash greeting,
  private temporary directories, dry-run modes, backups before every change and undo scripts
  (sections 3.4, 3.5).
- Compiled parts: the RPM spec files build with Fedora's `%cmake` macros, so the default Fedora 44
  flags apply: `-D_FORTIFY_SOURCE=3`, `-D_GLIBCXX_ASSERTIONS`, `-fstack-protector-strong`,
  `-fstack-clash-protection`, `-fcf-protection`, `-Werror=format-security`, position-independent
  executables, and `-z relro -z now` (`rpm --eval '%{optflags}'` and `'%{build_ldflags}'` on
  Fedora 44).
- The navigation effect's version check and the login check keep a mismatched compiled plugin
  from running against a newer KWin (section 3.8).
- The root tools, the charge-limit helper, `fusion-config.sh` and `fusion-restore.sh` stop on the
  first error (`set -euo pipefail`), as do 63 of the 82 tracked scripts with a bash shebang. Three
  installed helpers do not: the login check must always finish and exit 0 so a login is never
  blocked (`plasma-fusion-gate.sh`, no `set`), the power service must keep running and give
  values back (`set -u` only, `packages/powerfx/plasma-fusion-powerfx`), and the LibreOffice
  launcher uses `set -u` only (`packages/compat/plasma-fusion-libreoffice`). The other 16 are
  test, measurement and test-session tools with `set -u` or no `set` line.

### Missing (known gaps)

- The power tiers and app icons services have no systemd sandboxing beyond `NoNewPrivileges` and
  the limits (`ProtectSystem`, `ProtectHome`, `PrivateTmp`, `SystemCallFilter` and similar are not
  set). The login check's notification unit, `plasma-fusion-gate-notify.service`, which
  `tools/device/fusion-config.sh` writes, has neither `NoNewPrivileges` nor a memory limit.
- The app icons service parses SVG files from any installed package with QtSvg or rsvg-convert in a
  child process that has time and memory limits but no sandbox.
- Widgets build shell command lines for Plasma's executable engine; safety rests on the typing,
  allowlists and quoting of section 6, not on an argument-list API.
- The charge-limit helper accepts a leading zero (for example `050`): bash then reads the start
  threshold as an octal number, so `050` sets the start threshold to 35 instead of 45, and `080`
  stops with an error before anything is written. The value stays within the kernel's range and
  the tile never sends such a value, but the check should reject it.
- Two Python calls in the root tools run without `-I`: the keyboard label lookup in
  `tools/system/plymouth-install.sh` (`python3 -`) and `display_summary` in
  `tools/system/greeter-apply.sh` (`python3 -c`, also without `env -i`). For `-c` and `-`,
  Python puts the current directory first on its module path, so a `json.py` or an `xml/`
  package in the directory the tool was started from would be imported as root. Until `-I` is
  added, start these tools from a directory that no other user can write to.
- The login check finds the installed versions only with `rpm`. On a system without `rpm` it
  does not notice a Plasma, KWin or Qt update and leaves the version-bound parts on (section 1).
- The C++ plugins are not fuzzed and no test runs them under AddressSanitizer or
  UndefinedBehaviorSanitizer.
- Commits, tags and packages are not signed; the CI's RPMs are kept for 14 days as unsigned
  artifacts. The CI's Fedora container image is named by tag (`fedora:44`), not by digest.
- The maintainer, as the repository admin, can bypass the ruleset on `main`, and is the only
  reviewer ([`GOVERNANCE.md`](../GOVERNANCE.md)).

## 8. Assurance evidence and its limits

- **Tests:** the login check's unit tests (`tools/device/tests/gate-unit.sh`) and the lint
  self-tests run in CI on every push and pull request; the RPM build runs every part's checks and
  the spec's `%check` (`.github/workflows/build.yml`). Private-session tests of the lock screen,
  the shell and the tablet posture run outside CI, on the test machines and in containers
  ([`parts/testing.md`](parts/testing.md), [`parts/lockscreen.md`](parts/lockscreen.md)).
- **Static analysis:** CodeQL, zizmor, actionlint, shellcheck on the installed helpers during the
  build, OpenSSF Scorecard.
- **Not yet:** fuzzing, sanitizer runs, an outside review, a second maintainer. Section 7 lists the
  hardening still missing. This case is updated when a boundary or a measure changes.
