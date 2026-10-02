# Part: field log (`tools/device/fieldlog/`)

A user service that records the problems Plasma Fusion meets in daily use and keeps them apart from
the noise of development. Built 2026-10-02 for the owner's laptop (UX5406S, Fedora 44, Plasma
6.7.5), which is used every day; the ThinkPad less. Not part of the RPM; nothing here changes the
desktop.

## Why

Crash and journal records on the development machines mix two worlds. On 2026-10-02 the laptop had
twelve core dumps before noon: ten bash SIGSEGV dumps of the login check's fake `rpm-crash`, run
with a cleared environment from a build directory by a test, and two python3 SIGABRT dumps from a
script in a coding agent's scratchpad. The one real problem of those days, a plasmashell SIGSEGV
in the global menu applet, happened on the ThinkPad and was found by hand. The field log keeps the
real ones (session and app crashes, restarts, Plasma Fusion QML errors, memory and CPU) where they
can be read in a minute a day, and lists development crashes last, separately.

## Install, status, remove

On the laptop, from the checkout (the tool copies itself, so the checkout can move on):

```
tools/device/fieldlog/plasma-fusion-fieldlog install --share /mnt/archledger-gp/artifacts/plasma-fusion/fieldlog
plasma-fusion-fieldlog status          # after install, from ~/.local/libexec/plasma-fusion/
```

`install [--share DIR]` copies the tool to `~/.local/libexec/plasma-fusion/plasma-fusion-fieldlog`,
writes `~/.config/systemd/user/plasma-fusion-fieldlog.service` from the template next to it (with
`--share`: `Environment=PF_FIELDLOG_SHARE=DIR`), then `systemctl --user daemon-reload`, `enable`
and `restart` of that unit only. It starts with every Plasma session (`WantedBy` and `PartOf`
`graphical-session.target`). `remove` stops and disables it and deletes the unit and the copy; the
recorded state stays. `digest [DATE]` writes and prints a day's digest (`today`, `yesterday` or
`YYYY-MM-DD`; default today). `systemctl --user reload plasma-fusion-fieldlog` (SIGHUP) rewrites
today's digest at once.

## Files

State in `${XDG_STATE_HOME:-~/.local/state}/plasma-fusion/fieldlog/` (private to the user: the unit's
`UMask=0077`):

| File | What |
|---|---|
| `events-YYYY-MM-DD.jsonl` | one JSON event per line, by local day; a crash goes to the day it happened |
| `digest-YYYY-MM-DD.md` | the day's digest (every hour, at midnight for the day that ended, when the service stops) |
| `crashes/<UTC time>-<exe>-<pid>.txt` | `coredumpctl info` (all threads) of each session and app crash, saved when the crash is seen, because core files rotate |
| `memsnap/<UTC time>-<process>.txt` | memory snapshots |
| `state.json` | the last core dump handled, the journal cursor, the login check log's offset, the last overhead |
| `run.lock` | one recorder per state directory |

Kept: 30 days (`PF_FIELDLOG_KEEP_DAYS`) and 100 MiB (`PF_FIELDLOG_MAX_MB`); over the size the oldest
memory snapshots go first, then saved crash texts, then old events and digests, never today's
events. Core files are never touched. With `PF_FIELDLOG_SHARE` a copy of each digest goes to
`DIR/digest-YYYY-MM-DD-HOST.md` (from a thread, so a hanging network mount does not stop the
recorder).

## What it records

Event kinds: `crash`, `restart`, `gone`, `login`, `logout`, `suspend`, `screen`, `lid`, `posture`,
`unit-failed`, `unit-exit`, `unit-restart`, `pf-error`, `pf-warning`, `gate`, `noise`, `resources`,
`memsnap`, `cpu-high`, `cpu-high-end`, `self`, `fieldlog-start`, `fieldlog-stop`, `fieldlog-error`.
An event with a key is written once a day; its repeats are counted in memory and written as one
line with `"repeat": true`, the count of repeats and the first and last time, every hour and when the
service stops (a killed service loses at most an hour of repeat counts, never a first occurrence).
Session, app and other crashes and memory snapshots are written with `fsync`.

### Crashes

Every minute `coredumpctl --json=short list --since=@LAST` (as the user, no sudo), and 3 s after
the journal shows a core dump record or a `plasma-*` unit's `code=dumped`. For each new dump its
journal record is read once (`journalctl -a -o json MESSAGE_ID=fc2e22bc... COREDUMP_PID=`): the
user can read the records of their own dumps (the user journal) and, in `wheel`, the system's.
Fields used: `COREDUMP_EXE`, `_CMDLINE`, `_CWD`, `_CGROUP`, `_ENVIRON` (names only),
`_SIGNAL_NAME`, `_PACKAGE_NAME/VERSION`, `_UID`, `_USER_UNIT`, `_TIMESTAMP` and the stack trace in
`MESSAGE`. The first rule that matches decides:

| Class | Rule |
|---|---|
| tooling | the cgroup is a container's (`libpod`, docker, `machine.slice`, ...) or the environment has `container=` |
| tooling | the executable, an interpreter's script (relative scripts resolved against the crash's working directory) or the absolute `argv[0]` lies in a development directory: a `build`, `build-*`, `_build`, `scratch`, `scratchpad`, `test(s)`, `testing`, `fixtures`, `.claude` or `worktrees` path component, a cargo `target/debug` or `target/release`, `/tmp/claude-*`, `/var/tmp/pfv-*` |
| tooling | `XDG_RUNTIME_DIR` is not `/run/user/UID` (a private test session) |
| session | the cgroup is the session's `user@UID.service/session.slice` or a `plasma-*.service` unit of the user manager (`background.slice/plasma-xembedsniproxy.service`, the Plasma Fusion units) |
| tooling | an agent marker in its environment: `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, `AI_AGENT`, `OPENCODE`, `CODEX_SANDBOX`, `CODEX_SANDBOX_NETWORK_DISABLED`, `GEMINI_CLI`, `CURSOR_AGENT` (more with `PF_FIELDLOG_MARKERS`) |
| tooling | a running process in the same cgroup is a coding agent (`claude`, `opencode`, `codex`, ...) or has such a marker (an agent's terminal tab keeps its tmux or podman processes there; the agent's own process has no marker, only its children) |
| session | a Plasma or Plasma Fusion component by name: plasmashell, kwin_wayland, ksmserver, kded6, kscreenlocker_greet, xdg-desktop-portal-kde, kglobalacceld, krunner, ksmserver-logout-greeter, xembedsniproxy, gmenudbusmenuproxy, kaccess, plasma-keyboard, Xwayland, DrKonqi, `plasma-fusion-*` |
| app | `app.slice` |
| other | anything else: system services, SSH logins, other users |

A session component started by the user manager keeps the session class even with a marker in its
environment (a marker there came through the manager's environment, for example after an
`import-environment`); the marker names are listed with it. Session and app crashes get
`coredumpctl info --since --until PID` saved in `crashes/` right away. The event keeps the top six
frames of the crashing thread without the crash handler (`KCrash`, `__restore_rt`, `raise`,
`abort`, Qt's `qAbort`/`qFatal` path) and a signature (executable, signal, three frames). Tooling
crashes are counted per executable, signal, rule and script, so ten runs of one test are one line
and a count.

### Session events

- **Restarts**: every minute the session's `plasmashell` and `kwin_wayland`: own uid, cgroup under
  `user@UID.service`, not a container, the one in `session.slice` first (and only that one once the
  session has shown it, so a copy started from a terminal or a test is not taken for it). A new PID
  (or start time) is a `restart`; none found is `gone`.
- **Logins and logouts**: `graphical-session.target` reached or stopped (user manager messages), and
  its `ActiveEnterTimestamp` when the service starts.
- **Suspend and resume**: the boot-time clock against the monotonic clock, checked on every wake-up;
  the sleep's length and its approximate start and resume.
- **Screens and lid**: `/sys/class/drm/card*-*/{status,enabled,dpms}` and
  `/proc/acpi/button/lid/*/state` every minute; the `plasmafusion-snap` KWin script's "screens
  changed" lines.
- **Posture**: the `plasmafusion-tablet` KWin script's "posture tablet|laptop" lines.
- **Units**: user manager messages for `plasma-*` units (Plasma's and Plasma Fusion's): failed with a
  result, the main process dumped core, exited non-zero or was killed by a signal other than
  TERM/INT/HUP/KILL/PIPE, restart scheduled; and `systemctl --user list-units --state=failed
  'plasma-*'` at start and every hour.

### Plasma Fusion errors

One `journalctl --user -f -a -o json --output-fields=...` (after the saved cursor when it is less
than 12 h old, else from now). Lines are filtered on their bytes before they are parsed (the
programs below and "plasma(-)fusion"); about 72,000 user journal lines a day on the laptop, most of
them container output, never reach the JSON parser.

- `pf-error` / `pf-warning`: warnings and errors (priority 4 or less; a JavaScript `TypeError`,
  `ReferenceError`, `SyntaxError` or `RangeError` counts as an error) of plasmashell, KWin, the
  lock screen greeter, System Settings, kcmshell6, ksmserver, kded6 and krunner whose `CODE_FILE` or
  text contains `plasmafusion`, `plasma-fusion` or `PlasmaFusion` (the `org.plasmafusion.*`
  plasmoids and modules, the `plasmafusion-*` KWin scripts, the theme). Keyed by process, file and
  line (`org.plasmafusion.dock/contents/ui/main.qml:88`, "user copy" for `~/.local`, else
  "system") and the normalised text.
- The Plasma Fusion tools (`plasma-fusion-*` journal identifiers or user units: app icons, power
  tiers): their stderr comes at info priority, so lines with `Traceback`, `...Error`, `error`,
  `failed` (not "failed 0"), `warning:`, `cannot` or `denied` count too. The charge limit's helper
  runs as root through pkexec and writes nothing to the user journal; its part in the user session,
  `ChargeLimit.qml` of the quick settings, is a Plasma Fusion file, so its QML warnings are kept as
  above.
- `gate`: each run of the login check from its log (`$XDG_STATE_HOME/plasma-fusion/gate.log`, read
  from the last offset; `PF_FIELDLOG_GATE_LOG` overrides) with its detail lines, and lines of a
  `plasma-fusion-gate` journal identifier; counted by normalised summary ("login: ... no change").
- `noise`: other plasmashell and KWin warnings, counted per day by process, Qt category and
  normalised text (numbers as N, hex as 0x..., quoted text with spaces or over 48 characters cut).
  Only that text is kept, never the line.

### Resources

Every 60 s for the session's plasmashell and kwin_wayland: `VmRSS`, `RssAnon` (`/proc/PID/status`)
and CPU (`utime + stime` from `/proc/PID/stat`). Per clock hour one `resources` event: samples, RSS
and RssAnon min/mean/max in MiB, CPU mean/max in % of one core. A jump of 60 MiB or more in RssAnon
or RSS between two samples writes a memory snapshot (at most one per process every 10 minutes, 12 a
day), as `build/watch/pf-watch.sh`'s `snap()`: `/proc/PID/status`, anonymous and resident KiB per
mapping kind from `smaps` (`[heap]`, `memfd:...`, anonymous mappings of 1 MiB or more and smaller,
files; files under the home folder grouped by their first two folders), the DRM clients from
`fdinfo` (i915/xe `drm-total-*`, `drm-resident-*`, engines) and the last minute of plasmashell and
KWin journal lines (normalised, every quoted string cut). KWin has a file capability, so its
`smaps` and `fdinfo` are not readable for the user; its snapshot has the status only. 60 % of a core
or more for two minutes is a `cpu-high` event, the end of it `cpu-high-end` (length, mean, max).
Every hour and at the end the tool records its own CPU (its process, the children it waited for,
the running journalctl) and RSS (`self`).

## Privacy

Local files only; the share copy is the digest alone and only with `--share`. Environments are read
in memory for the names of agent markers and the runtime directory; no value of them is written.
Window titles, notification texts and clipboard contents are not recorded: every kept text has the
home folder shortened to `~`, `caption`, `title`, `windowTitle`, `summary`, `body`, `text`,
`subject`, `clipboard`, `selection`, `password`, `token` and `secret` values cut (`key=value`,
`caption: value`, `key: "quoted"`), and quoted strings with spaces or over 48 characters replaced by
`"…"`; info lines (such as the launcher's "first results for ..." timing with the typed text) are not
kept at all, and in a memory snapshot every quoted string is cut. Saved `coredumpctl info` texts
contain the crashed program's command line, as coredumpctl prints it, and stay local.

## The unit

`tools/device/fieldlog/plasma-fusion-fieldlog.service`: `Type=simple`, `ExecSearchPath=
%h/.local/libexec/plasma-fusion:/usr/local/libexec/plasma-fusion:/usr/libexec/plasma-fusion` like the
units in `packages/`, `KillMode=mixed` (SIGTERM to the tool, which writes its counts, the digest and
stops journalctl), `Restart=on-failure`, `background.slice`, `Nice=10`, `IOSchedulingClass=idle`,
`MemoryMax=64M`, and the hardening that works in a user unit without a user namespace:
`NoNewPrivileges`, `LockPersonality`, `RestrictRealtime`, `RestrictSUIDSGID`, `RestrictNamespaces`,
`MemoryDenyWriteExecute`, `SystemCallArchitectures=native`, `SystemCallFilter=@system-service`,
`RestrictAddressFamilies=AF_UNIX`, `UMask=0077`. Tested with transient units on the laptop
(2026-10-02, systemd 259): with `PrivateTmp=yes` the user manager adds `PrivateUsers=yes`; then the
process's groups are `nobody` (no `wheel`, so no system journal) and other processes' `environ`
reads fail ("Permission denied"), which would break the cgroup check. `PrivateTmp`, `ProtectSystem`
and `ProtectHome` are therefore not set. With the options above `coredumpctl`, `journalctl --user`,
`systemctl --user` and `/proc/PID/environ` of other own processes work.

## Overhead

Budget: under 0.3 % of one core on average and under 40 MiB RSS. Measured on the laptop on
2026-10-02, 12:24-12:34 EDT: `run` for 10 minutes against the real user journal, a scratch
`XDG_STATE_HOME` (first run: today's core dumps from midnight), the process and its journalctl
sampled from `/proc` every 5 s:

| | CPU | RSS |
|---|---|---|
| start (reading today's 12 dump records) | 0.62 s | |
| the 595 s after it (tool, journalctl, coredumpctl every minute) | 0.47 s, **0.079 %** of a core | tool 21.4-21.6 MiB |
| the whole run, start and stop included | 1.14 s in 605 s, 0.19 % | journalctl 16.6-23.0 MiB (mostly mapped journal files) |
| the tool's own `self` event for the run | 0.082 % | 21.2 MiB |

A first run that reads a week of dumps (`PF_FIELDLOG_SINCE=2026-09-27`, 72 dumps, 36 crash texts
saved) took 5.1 s of CPU in a transient user unit with the service's limits and hardening
(`systemd-run --user -p MemoryMax=64M ...`); its memory peak reached the 64 MiB limit with journal
file cache (reclaimed; exit 0, the same classes as without the limits). Later starts go on from the
state and read only new dumps.

## Verification (2026-10-02)

- Tests: 19 PASS (`fieldlog_test.py`, about 10 s).
- The 10-minute run recorded: the start (plasmashell 1062963, KWin 2888, outputs, lid), the 12
  tooling crashes of the day in two lines and two repeat lines (python3 `approved_pick.py` from a
  scratchpad 2x at 07:44 EDT, bash `rpm-crash` from a build directory 10x at 11:21-11:38), two login
  check runs ("deploy: nothing to turn back on"), KWin "screens changed" 2x, 5 plasmashell warnings
  of 2 kinds, no Plasma Fusion error, restart, session or app crash. plasmashell RSS 255 / 281 / 327
  MiB and RssAnon 174 / 196 / 239 MiB (min / mean / max; +65 MiB in 10 minutes, never 60 MiB within
  one minute, so no snapshot), CPU 0.52 % mean, 1.4 % max; KWin RSS 87-98 MiB, CPU 4.5 % mean, 9.5 %
  max.
- The week's dumps (backfill from 2026-09-27): 2026-09-27 19:19-19:20 EDT a cascade of 30 session
  crashes from one KWin SIGSEGV (`iris_bo_map` in Mesa's iris driver while creating a context):
  plasmashell twice (SIGABRT in Qt's platform start without a compositor), plasma-keyboard,
  xembedsniproxy 8x, gmenudbusmenuproxy, kaccess, the logout greeter, DrKonqi's launcher 12x, the
  login greeter; with them two apps (Konsole, Discover). 2026-09-30 14:59 EDT a plasmashell SIGSEGV
  in Mesa's texture upload (`util_copy_box` from `u_default_texture_subdata`, render thread), the
  same frames as the container plasmashell crashes of 2026-10-01; ChatGPT and System Settings crashed
  as apps. Tooling: 15 dumps of test containers on 2026-10-01 (plasmashell 14, KWin 1), a cargo test
  binary, Python harnesses from scratchpads and `packages/lockscreen/test/`, a QML probe in `build/`.
- The service's hardening was checked with transient user units: `PrivateTmp=yes` dropped the
  groups to `nobody` and denied other processes' `environ`; the options in the unit kept
  `coredumpctl`, `journalctl --user`, `systemctl --user` and `environ` working.

## How the digest is read

`digest-YYYY-MM-DD.md`, newest first in the share. From the top:

1. **The table.** Session crashes in bold; when it is 0 and the Plasma Fusion error count did not
   grow, the day was clean. Tooling crashes are only a count here.
2. **Session crashes**, grouped by signature: process, signal, package and version, how many and
   when, the cgroup and the rule that classed it, the saved `crashes/` file(s), the core file's
   state at the time, any agent marker names, the restart that followed and the top five frames
   (demangled with `c++filt` when installed). The saved file has every thread; with the core still
   `present`, `coredumpctl debug PID` opens it. A crash in the session that a test caused would
   show a marker or a development path here; report anything else upstream or fix it.
3. **App crashes** and **other crashes**: the same format; apps that crash with KWin (Wayland
   reconnects) show at the same minute.
4. **Plasma Fusion errors and warnings**: count, first-last time, level, file and line, user copy or
   system package, the message. A new row after a deploy is the first thing to look at.
5. **Login check**: each run's summary with counts ("no change" is the normal login).
6. **Session events**: logins, plasmashell and KWin restarts (with "after its crash" when a session
   crash of the same process came within 3 minutes before), suspends, screen and lid changes, posture.
7. **Failed units**.
8. **Resources**: per process the hours sampled, RSS and RssAnon min/mean/max and CPU mean/max; the
   hour with the highest RssAnon; memory snapshots with their files; sustained CPU; the field log's
   own overhead.
9. **Other plasmashell and KWin warnings**: the 20 most frequent normalised texts; for trends only.
10. **Development crashes (tooling)**: count, time span, executable, signal, the rule and the
    command; not problems of daily use.

## Tests

```
python3 tools/device/fieldlog/tests/fieldlog_test.py -v
```

Standard library only; scratch in `build/fieldlog-tests/` (`PF_FIELDLOG_TEST_DIR`), removed after.
`fixtures/coredumps-2026-10-02.jsonl` holds the laptop's twelve records of 2026-10-02 (the python3
dumps at 11:44 UTC and the bash `rpm-crash` dumps at 15:21-15:38 UTC), exported read-only by
`tests/export-fixtures.py`, which keeps only the fields the tool reads and, of the environment, the
marker names (value 1), `XDG_RUNTIME_DIR`, the desktop, `PWD`, `HOME`, `LANG`, `LC_ALL` and `SHLVL`.
The tests:

- classification: the ten bash dumps (script in a build directory) and the two python3 dumps
  (script in the scratchpad; with that path removed, the marker) are tooling; a synthetic
  plasmashell crash shaped like the ThinkPad's (`/usr/bin/plasmashell`,
  `session.slice/plasma-plasmashell.service`, SIGSEGV in `QWidget::removeAction` from
  `AppMenuModel::removeSearchActionsFromMenu`) is session, also with a marker; app, app with a
  marker, container, private session, a cgroup shared with a marked process or an agent process,
  `background.slice/plasma-*.service` and DrKonqi, other; top frames and signatures;
- dedupe with counts across a restart of the service; the privacy filter; no environment value in a
  crash event;
- journal handling: Plasma Fusion warnings and errors with file and line, the tools' real lines (two
  routine ones not kept, the power tool's "Call failed" kept), noise counts, posture, screens, unit
  failures and dumps, logins; window titles, notification texts and the launcher's typed text never
  reach a file;
- the digest (order, counts, frames, restarts, resources, tooling last); retention by age and size;
  login check runs counted once when the check trims its log;
- `run` for 8 s with a fake `coredumpctl`, `journalctl` and `systemctl` on PATH, a fake `/proc` and
  `/sys` (`PF_FIELDLOG_PROC`, `PF_FIELDLOG_SYS`, `PF_FIELDLOG_CGROUP_ROOT`,
  `PF_FIELDLOG_INTERVAL=0.5`, `PF_FIELDLOG_RUN_SECONDS`): 12 tooling, 1 session and 1 app crash,
  two saved crash texts, a restart, a memory snapshot, a DPMS change, the gate run, the digest and
  its share copy, `status`; no `systemctl` call that changes anything;
- `install --share` and `remove` with a fake `systemctl`.

## Limits

- Suspend times are approximate (to the next wake-up of the loop, at most a minute).
- A crash whose journal record cannot be read (another user's, without `wheel`) is classed by its
  executable name only.
- Sustained CPU and memory jumps are seen at minute resolution.
- The global `noise` counts depend on Qt's message text; a Plasma update that rewords a warning makes
  a new row.
