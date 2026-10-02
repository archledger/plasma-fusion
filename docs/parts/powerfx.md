# Part: power tiers (`plasma-fusion-powerfx`)

A small user service that makes the desktop lighter only when the battery needs it, and gives every
value back afterwards (EFFECTS.md section 8 with its seven listed changes, owner decisions E2 and E3,
work package POWER-1). Power saver keeps the glass and the animations and slows the background work;
only at 10 % battery or less does the glass turn solid and dock magnification pause. Animations are
never shortened unless the user asks for it.

Status: built, tested offline (`packages/powerfx/tests`) and on the ThinkPad in private sessions
(o1pw-tiers2, o1pw-unit2 under a real `systemd --user`, o1pw-idle3 with the CARD-1 system card), see
"Verification". The POWER-1 acceptance is met. Not installed or enabled anywhere: DEVICE-1 installs
and enables it, the lead deploys. Last edited 2026-09-30 (builder `o1pw`, finished by the lead).

## Tiers

| Tier | When (the first that matches) |
|---|---|
| critical | on battery at 10 % or less, or UPower `WarningLevel` 4 (critical) or 5 (action) |
| saver | the `power-saver` profile, or on battery at 20 % or less |
| full | everything else |

The percentage is rounded first (10.4 % is critical, 10.6 % is not). `WarningLevel >= 4`, not 3:
the ThinkPad's UPower says "low" (3) at 20 % (`UsePercentageForPolicy=true`, `PercentageLow=20`), so
3 would make critical start at 20 % (EFFECTS 8.2, corrected in review).

| What | full | saver | critical |
|---|---|---|---|
| Fusion system card and dock `powerTier` | 0 | 1 (card interval x 2, one dock start-up pulse) | 2 (card x 4, no pulse) |
| Plasma's own system monitor widgets (`[Appearance] updateRateLimit`, any `org.kde.plasma.systemmonitor*`) | the user's | 2 x the user's (unlimited or under 1 s counts as 3 s) | 4 x |
| KWin blur (`kwinrc [Plugins] blurEnabled` + `unloadEffect`) | the user's | the user's | off, with `LighterOnCritical` |
| Dock `magnify` | the user's | the user's | false, with `LighterOnCritical` |
| `glass` of the Fusion dock, system card, quick settings, launcher | the user's | the user's | `solid`, with `LighterOnCritical` |
| `kdeglobals [KDE] AnimationDurationFactor` | the user's | the user's | at most 0.75, only with `ShorterAnimationsOnCritical` (0 stays 0, never longer) |
| Blur strength, noise, saturation | never touched | | |

Options (plasmafusionrc `[Power]`, written by the settings module): `LighterOnCritical` (default
true), `ShorterAnimationsOnCritical` (default false). With `[Effects] Glass=Solid` blur is off anyway
and stays off when critical ends.

## Files

| Repository | Staged (`tools/build.d/85-powerfx.sh`) | Installed |
|---|---|---|
| `packages/powerfx/plasma-fusion-powerfx` (bash) | `.local/libexec/plasma-fusion/plasma-fusion-powerfx` (0755) | per user `~/.local/libexec/plasma-fusion/` (fusion-config.sh `--install` copies `.local`); system package `/usr/libexec/plasma-fusion/` (PKG-1) |
| `packages/powerfx/plasma-fusion-powerfx.service` | `.config/systemd/user/plasma-fusion-powerfx.service` (0644) | per user `~/.config/systemd/user/`, written by `install_user_service` from the copy below (fusion-config.sh copies the other `.config` templates, also from `/usr/share/plasma-fusion/config`, but leaves user units to `install_user_service`: a package's older template there rewrote the unit and restarted the service at every rerun, 2026-10-02); optionally `%{_userunitdir}` (PKG-1) |
| (the same unit) | `.local/share/plasma-fusion/powerfx/plasma-fusion-powerfx.service` | where `fusion-config.sh` (`install_user_service`) looks for the unit in the build being installed and in `/usr/share`; without this copy a staged install placed the unit but did not enable it (found at PKG-1) |
| `packages/powerfx/tests/*` | not staged | tests (below) |

The unit finds the script with `ExecSearchPath=%h/.local/libexec/plasma-fusion:/usr/local/libexec/plasma-fusion:/usr/libexec/plasma-fusion:/usr/lib/plasma-fusion`
(systemd 250+; verified with systemd 259 in o1pw-unit2), so one unit file serves a per-user copy and
the system package (`/usr/lib/plasma-fusion` on distributions without `/usr/libexec`, such as Arch;
2026-10-02); the user's copy wins. `fusion-config.sh` and `fusion-restore.sh` search the same four
directories for the helper programs. `ExecSearchPath` also becomes the process's `PATH`; the
script appends `/usr/local/bin:/usr/bin:/bin:/run/current-system/sw/bin:/run/wrappers/bin` (the last
two: NixOS's system profile and setuid wrappers, where `/usr/bin` holds only `env`).

Installing enables nothing. Turn on: `systemctl --user enable --now plasma-fusion-powerfx.service`.

## Command line

```
plasma-fusion-powerfx                follow the power state (what the unit runs)
plasma-fusion-powerfx --apply TIER   apply full, saver, critical or auto once and exit
plasma-fusion-powerfx --status       power state, its tier, the options and the stored state
```

`--apply` exits 0 when applied, 3 when everything but the Plasma widgets was applied (plasmashell is
not running or has not loaded its layout; the running service sets them when it is back), 1 on an
error, 2 on a usage error.

## The unit

`PartOf=` and `WantedBy=graphical-session.target`; `After=graphical-session.target
plasma-workspace.target` (plasma-workspace.target orders after plasmashell and KWin, so at log-out
the service stops, and gives the values back, while both still run: the stop measured 254 ms);
`ConditionEnvironment=XDG_CURRENT_DESKTOP=KDE` (another desktop would otherwise get KWin's blur
switched in its files; checked against the manager's environment in o1pw-unit2); `Type=exec`;
`ExecStopPost=-plasma-fusion-powerfx --apply full`; `ExecReload=/bin/sh -c 'kill -HUP "$MAINPID"'`
(the shell's own kill: NixOS has no `/usr/bin/kill`; systemd passes `MAINPID` in the environment;
2026-10-02, a systemd 259 container with `/usr/bin/kill` moved away reloaded twice, the script
found in `/usr/lib/plasma-fusion`);
`KillMode=mixed` (SIGTERM to the script only: it finishes a change in progress, then stops its
monitors); `Restart=on-failure`, `RestartSec=5`; `Slice=background.slice`, `Nice=10`,
`MemoryMax=32M`, `NoNewPrivileges=yes`, `SyslogIdentifier=plasma-fusion-powerfx`.

## How it works

- **Inputs, event driven.** Three `gdbus monitor` processes: `net.hadess.PowerProfiles`
  (power-profiles-daemon and Fedora 44's tuned-ppd both own it; `ActiveProfile`), `org.freedesktop.UPower`
  (`OnBattery` on `/org/freedesktop/UPower`, `Percentage` and `WarningLevel` on the DisplayDevice)
  on the system bus, and `org.kde.plasmashell` on the session bus with an object path nothing uses,
  so only the lines about who owns the name arrive. The values are taken from the signal lines by
  bash itself (no process per event); UPower's periodic energy updates cost a few string matches.
  Events closer than 0.5 s are one change. A service that appears or goes away is read again with
  `busctl`; a missing service reads as balanced, on AC, 100 %.
- **Signals.** Bash runs a trap during `read` but goes on reading, so the SIGTERM and SIGHUP traps
  send SIGUSR1 to the monitor group, which writes a wake line. When one monitor ends (the bus went
  away) all end and the service exits 1; systemd restarts it after 5 s.
- **KWin part first.** The files are written before the D-Bus calls, so a KWin that is not running,
  or restarts, reads the tier's state. `unloadEffect blur` is needed besides `blurEnabled=false`:
  KWin's reconfigure only loads effects (EFFECTS E5, `EffectsHandler::reconfigure`).
- **Widgets, one writing call.** plasmashell's `evaluateScript` runs the widget script twice per
  change: first read-only (what would be written, and the new list of remembered values), which is
  stored, then once more to write. So a crash between the two never makes the service remember a
  value it wrote itself. Widgets are written only where a value differs (each written widget gets a
  `reloadConfig`). Session calls use `busctl --auto-start=no`: at log-out nothing is started again.
- **Remember and give back.** A value is remembered when the service first overrides it, in
  plasmafusionrc `[Power]`: never while it holds the service's value. It is given back when no tier
  overrides it any more, and only if it still holds the service's value; a change the user made
  meanwhile (magnification turned on at 8 %, blur turned on in System Settings, Glass set to Solid)
  stays.
- **plasmashell restart or late start.** A new owner of `org.kde.plasmashell` is given 2 s, then
  the widget part is applied again (up to 15 tries, 2 s apart, while it has not loaded a layout).
  New widgets (a layout reset) are remembered with their own values and set. A layout reset inside a
  running plasmashell keeps the same owner: the settings module's Reset (and `fusion-config.sh
  --reset-layout`) should `systemctl --user reload` the service (see "Needs").
- **Journal.** One line per tier change, `logger -t plasma-fusion-powerfx`, for example
  `tier critical (on battery, 8 %, warning level 1, profile balanced): blur off, 7 widget setting(s)`,
  and one when plasmashell came back and something had to be set.
- **Concurrency.** Every change holds `flock` on `$XDG_RUNTIME_DIR/plasma-fusion-powerfx-$UID.lock`;
  the running service compares with the stored state, so a manual `--apply` is followed too.

## State in plasmafusionrc `[Power]` (written by the service only)

| Key | Meaning |
|---|---|
| `Tier` | tier applied (written with `--notify`, for the settings module and quick settings) |
| `ShellTier`, `ShellLighter` | tier and light flag applied to the widgets (lag `Tier` while plasmashell is away) |
| `UserDockMagnify`, `UserGlass` | while overridden: the user's dock magnification (first dock) and glass level (registry keys) |
| `UserWidgetValues` | while overridden: every remembered widget value, `WIDGET-ID/key=value,...` |
| `ForcedBlur`, `UserBlurEnabled` | while blur is off by the service: the user's raw `blurEnabled` (`absent` when unset) |
| `ForcedAnimationDurationFactor`, `UserAnimationDurationFactor` | while the factor is capped: the value written and the user's (`absent`) |

After full only `Tier`, `ShellTier`, `ShellLighter` remain.

## Widget keys the service writes (owned by the widgets' lanes)

| Widget | Key | Type | Values |
|---|---|---|---|
| `org.plasmafusion.systemcard` | `powerTier` | Int, hidden, 0-2, default 0 | the card waits `updateInterval x (1, 2, 4)[powerTier]` (CARD-1) |
| `org.plasmafusion.dock` | `powerTier` | Int, hidden, 0-2, default 0 | start-up pulse 3 / 1 / 0 cycles (DOCK-2) |
| dock | `magnify` | Bool (exists) | false at critical |
| dock, systemcard, quicksettings, launcher | `glass` | **String**, hidden, default `full` | `full` / `reduced` / `solid` |

`glass` must be a String entry: `Applet.writeConfig` calls `setProperty` on the schema item, and an
Enum item would turn `"solid"` into 0. Until a widget declares a key, the service's write is a plain
config entry that nothing reads.

## Rollback

`systemctl --user disable --now plasma-fusion-powerfx.service` gives every value back (ExecStopPost).
Without systemd: `plasma-fusion-powerfx --apply full`. Then remove
`~/.config/systemd/user/plasma-fusion-powerfx.service` and
`~/.local/libexec/plasma-fusion/plasma-fusion-powerfx` (fusion-restore.sh, DEVICE-1). Worst case by
hand: `kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled --delete`,
`qdbus-qt6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect blur`, dock magnification on in its
settings.

## Verification

| Test | Where | Result |
|---|---|---|
| `packages/powerfx/tests/widgets.test.js`: the widget script against `fake-shell.js` (the scripting API as plasma-workspace 6.7.5 implements it): writes per tier, remembering, giving back, user changes, flag changes, new widgets, plan mode | laptop, node; also run by 85-powerfx.sh | 15/15 |
| `packages/powerfx/tests/offline.sh`: two private buses, `mock-power.py` (UPower, power profiles), `mock-session.py` (KWin effects, plasmashell via `fake-shell.js`), throw-away HOME: 14-case tier table, `--apply` each tier, kwinrc and kdeglobals byte for byte after full, options, user changes, missing plasmashell (exit 3, log-out case, next start), the running service (events, coalescing, plasmashell restart with a new dock, reload, UPower away and back, SIGTERM, dying bus), memory, CPU | laptop | 79/79 |
| `tests/vsession/scen-tiers.sh` (o1pw-tiers): real KWin and plasmashell with the Fusion layout, `--apply` saver/critical/full, then the service on a mock system bus | ThinkPad, 1920x1200 @4/3 | o1pw-tiers 27/29 (the 2 misses were test bugs: a function used in `bash -c`, a diff filter without KConfig group headers); after the fixes o1pw-tiers2 29/29 |
| `tests/vsession/scen-unit.sh` (o1pw-unit2): the unit under a second `systemd --user` (sudo `systemd-run`, Delegate, the user's SELinux context) with the session's HOME and buses | ThinkPad | 21/21 |
| `tests/vsession/scen-idle.sh` + `idle-frames.py` (o1pw-idle3): idle frames per tier, card visible, covered (Dolphin maximized), removed | ThinkPad, exclusive slot | acceptance met, table below |

Measurements (ThinkPad, private sessions):
- Blur unloaded 599 ms after the Percentage event (0.5 s of it is the coalescing window).
- Service: bash 4.3-4.6 MB RSS, its monitor subshell 2.8-3.0 MB, three gdbus 5.7-6.0 MB each; PSS
  about 3 MiB in total; the unit's cgroup 3.4 MB current, 5.7 MB peak (during a change).
- 0 CPU ticks in 30 s idle (o1pw-tiers) and in 20 s idle plus 10 UPower updates that change nothing
  (offline).
- Stop of the session target, ExecStopPost included: 254 ms. SIGTERM to exit: 1 ms idle.
- Idle frames per tier (o1pw-idle3, 1920 x 1200 at 4/3, 30 s per phase, the CARD-1 system card
  copied into the HEAD stage; the earlier o1pw-idle2 ran HEAD's card, which has no `powerTier` and
  keeps drawing under windows, and gave 0.63 / 0.60 frames/s visible / covered):

  | Phase | Frames/s | Longest burst | plasmashell CPU % | KWin CPU % | Limit |
  |---|---|---|---|---|---|
  | full, card visible | 0.100 | 1 | 0.47 | 0.07 | |
  | critical, card visible | 0.066 | 1 | 0.47 | 0.03 | pass (at most 0.15) |
  | critical, card covered | 0.033 | 1 | 0.37 | 0.03 | pass (at most 0.1) |
  | full, card covered | 0.033 | 1 | 0.33 | 0.03 | |
  | critical, no card | 0.000 | 0 | 0.37 | 0.00 | pass (at most 0.1) |
  | full, no card | 0.033 | 1 | 0.30 | 0.00 | |

### How to run

```
node packages/powerfx/tests/widgets.test.js
packages/powerfx/tests/offline.sh build/o1pw/off        # needs dbus-daemon, busctl, gdbus, kwriteconfig6, node, python3-gobject
# private sessions: seed = built stage at pf-stage, tools at pf-tools, packages/powerfx/tests at pf-powerfx
PFV_SCALE=1.3333333 build/lead/vslot.sh tools/vsession/remote.sh o1pw-tiers packages/powerfx/tests/vsession/scen-tiers.sh SEED 1920x1200 420
PFV_SCALE=1.3333333 build/lead/vslot.sh tools/vsession/remote.sh o1pw-unit packages/powerfx/tests/vsession/scen-unit.sh SEED 1920x1200 300
PFV_SCALE=1.3333333 PFV_CWD=out build/lead/vslot.sh --exclusive tools/vsession/remote.sh o1pw-idle packages/powerfx/tests/vsession/scen-idle.sh SEED+pfv-env 1920x1200 540
python3 packages/powerfx/tests/vsession/idle-frames.py vsession-out/o1pw-idle
```

scen-unit.sh starts a transient system unit `o1pw-um-*` with sudo and stops it at the end; after an
aborted run: `sudo systemctl stop o1pw-um-pfv-NAME.service; sudo systemctl reset-failed ...`, and
`chmod -R u+rwx /var/tmp/pfv-NAME/run/systemd` before removing the session directory (the manager
leaves mode-0 entries). The scenarios send the service's journal lines to `out/journal.log` (a
`logger` stand-in first in `PATH`); only scen-unit.sh's unit writes to the machine's journal.

## Deviations from EFFECTS.md 8.3 and PLAN.md POWER-1

- A value is remembered when the service first overrides it (entering saver for the monitor
  intervals, entering critical for blur, magnification, glass and the factor), not only "in the full
  tier". Same rule (never the service's own value), and a change the user makes in saver is kept.
- The unit finds the script through `ExecSearchPath` (per-user copy or system package) instead of
  a `%h` path, and has more than the spec's lines (see "The unit").
- `glass=solid` is written to the four Fusion widgets at critical (EFFECTS 2's table), besides
  `powerTier` and `magnify` (PLAN's bullet).
- Plasma's own system monitors are held at 2x / 4x of the user's interval, remembered per widget.
- `busctl` instead of `qdbus` (always installed with systemd; `--auto-start=no`).
- Two `evaluateScript` calls per change: a read-only plan, then the one that writes.

## Known limits

- A layout reset inside a running plasmashell during saver or critical leaves the new widgets at
  their defaults until the next tier change, plasmashell start or `systemctl --user reload`.
- The system card reads `powerTier` since CARD-1 (af0bb47); the dock has no `powerTier` and no
  `glass` (DOCK-2), quick settings and the launcher no `glass` (QS-1, LAUNCH-1): until then only the
  blur and magnification parts of the tiers have an effect.
- A Glass change in the settings module while critical loads blur again (the service then leaves
  blur alone, since the user changed it); see "Needs".
- The service reacts to option changes at the next tier change or a reload, not by itself.
