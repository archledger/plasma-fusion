# Plasma Fusion — build plan

Status as written on 2026-09-30. This paragraph is a dated snapshot and is not kept current: its
deployment facts are out of date, and the part pages in `docs/parts/` and the git history show the
current state. Phases 1 and 2 and round 2 are built and installed on the ThinkPad; of phase 3, the decoration and the settings module are installed as RPMs (the decoration is not selected yet). The real session runs d4afee8 (round 2 plus text scale and the dock rework, deployed 2026-09-30 02:56Z). The one-pass build (planned in the maintainer's notes, not in this repository) is under way: waves 0 and 1 and batch B0 are committed (CARD-1, BASE-1, POWER-1, KCM-1, DEVICE-1, TEST-1, DECO-1, STYLE-1; not deployed); the next lanes are KWIN-1, LAYOUT-1, LOCK-1 and PEN-1. Last edited 2026-09-30.

## Decisions

| Topic | Decision | Source |
|---|---|---|
| Test device | ThinkPad X13 Yoga Gen 4, `ssh thinkpad-fedora`, user `test`, Fedora 44, Plasma 6.7.5, KF 6.30, Qt 6.11.2 | user |
| Root on the ThinkPad | Allowed (passwordless sudo is intended). Back up first, record rollback. Never touch PAM (`/etc/pam.d`) or irlume. | user |
| Display scale | Exactly 4/3 on the ThinkPad panel (stored 1.3333333, ±1e-6; logical 1440x900), so board pixels map 1:1 to logical pixels. Design values are used as logical px. Set from inside the session (`kscreen-doctor output.eDP-1.scale.1.3333333333`) and checked in `kwinoutputconfig.json` and KWin `supportInformation`. Proven to stick in a private session (stored 1.3333333333333333, survives a KWin restart, the Display page shows 133.333 % and opening it changes nothing). The live session still runs 1.325 (origin unexplained) until DEPLOY-1 sets 4/3. | user ("adjust it so it matches the ThinkPad screen"); owner decision 1, 2026-09-30 |
| Compiled code | Phase 3, after the no-code desktop works: C++ KDecoration3 decoration and a Fusion KCM, built on the laptop in a Fedora 44 container. | user |
| Application style | Breeze + Fusion colour schemes first. `plasma-union` (6.7.5, in development) is evaluated per app before any session-wide switch. | research |
| Login screen | Stock plasma-login-manager greeter (its QML is compiled in). Fusion colours, Plasma style, fonts, cursor, icons and wallpaper installed system-wide and synced with "Apply Plasma Settings". No SDDM switch (PAM stack change). | research |
| Lock screen | Own Plasma/Shell package holding only `contents/lockscreen/`, selected with `PLASMA_DEFAULT_SHELL` in a `plasma-kwin_wayland.service` drop-in. PAM prompts, fingerprint and irlume face messages must keep working. | research |
| Build host | Everything is generated and packaged on the laptop (same Plasma/KF/Qt versions). Only artefacts go to the ThinkPad. | research |

## Owner decisions (2026-09-30)

The owner answered "all recommended" to `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-decisions/DECISIONS.md`: decisions 1-8 and every listed default. The build plan for these answers is `PLAN.md` in the same folder; each decision-dependent behaviour sits behind a config key.

| # | Topic | Answer |
|---|---|---|
| 1 | Display scale | exactly 4/3 (Decisions table above) |
| 2 | Tablet mode | apps full screen without title bars (large dialogs too); the dock hides over apps and comes back with a swipe up; "Windowed" per app in the window card, "Full-screen apps" in quick settings for all apps |
| 3 | Accent colour | every Fusion part follows it; boot splash and login screen stay blue |
| 4 | Snap layouts | on hold (about 0.5 s) or Meta+Z; a click always maximizes (`SnapLayoutsOnHover=false`) |
| 5 | Top bar next to a window | solid while a window is maximized or touches it, frosted over the desktop |
| 6 | Shortcuts | Windows-style set: Meta+Space, Meta+S, Alt+Space and Alt+F2 search in the Fusion launcher (KRunner no longer starts); Meta+A quick settings; Meta+N notifications; Meta+Up/Down maximize/restore (quick tile on Meta+Alt+Up/Down); Meta+Tab Overview; Meta+1..4 workspaces; Meta+Alt+1..9 dock apps |
| 7 | KDE Mail and Calendar | no apps were named, so KMail, KOrganizer and Akonadi stay unchanged (pins, autostart, calendar card click) |
| 8 | Second monitor | a top bar on every screen; dock, status icons, quick settings and desktop cards on the main screen; launcher and pop-ups on the active screen |

## Naming table (use these exact ids)

| Part | Id / directory name | Installed at (per user) |
|---|---|---|
| Global Theme, dark | `org.plasmafusion.dark.desktop` ("Plasma Fusion Dark") | `~/.local/share/plasma/look-and-feel/` |
| Global Theme, light | `org.plasmafusion.light.desktop` ("Plasma Fusion Light") | same |
| Global Theme, previous look | `org.plasmafusion.previous.desktop` ("My previous desktop": the look before the first `fusion-config.sh` apply, written by `tools/device/previous-theme.py`) | same |
| Colour schemes | `PlasmaFusionDark.colors`, `PlasmaFusionLight.colors` ([General] Name "Plasma Fusion Dark/Light"), `PlasmaFusionHighContrast.colors` (the settings module's high-contrast switch) | `~/.local/share/color-schemes/` |
| Plasma style | `plasma-fusion-dark`, `plasma-fusion-light` | `~/.local/share/plasma/desktoptheme/` |
| Icon themes | `PlasmaFusion` (light UI, inherits `breeze`), `PlasmaFusion-Dark` (dark UI, inherits `breeze-dark`) | `~/.local/share/icons/` |
| Cursor themes | `PlasmaFusion-cursors` (dark fill, default), `PlasmaFusion-Light-cursors` | `~/.local/share/icons/` |
| Window decoration (phase 1) | Aurorae v2 themes `PlasmaFusionDark`, `PlasmaFusionLight` (+ `PlasmaFusionDark-Left`, `PlasmaFusionLight-Left` for buttons on the left); kwinrc `library=org.kde.kwin.aurorae.v2`, `theme=__aurorae__svg__PlasmaFusionDark` | `~/.local/share/aurorae/themes/` |
| Window decoration (phase 3) | `org.plasmafusion.decoration` (KDecoration3 plugin, listed as "Plasma Fusion"); kwinrc `[org.kde.kdecoration2] library=org.plasmafusion.decoration` | `/usr/lib64/qt6/plugins/org.kde.kdecoration3/` (root, RPM `plasma-fusion-decoration`) |
| Settings module (phase 3) | `kcm_plasmafusion` ("Plasma Fusion" in System Settings > Appearance & Style; `kcmshell6 kcm_plasmafusion`) | `/usr/lib64/qt6/plugins/plasma/kcms/systemsettings/`, `/usr/share/applications/kcm_plasmafusion.desktop` (root, RPM `plasma-fusion-settings`) |
| Wallpapers | `PlasmaFusion` (Dusk Ridge; `images/` light, `images_dark/` dark) plus `PlasmaFusion-<Name>` for the other board palettes | `~/.local/share/wallpapers/` |
| Splash | inside both Global Themes (`contents/splash/Splash.qml`); ksplashrc `Theme=org.plasmafusion.dark.desktop` | — |
| Lock screen shell | `org.plasmafusion.lockshell` (Plasma/Shell, fallback `org.kde.plasma.desktop`) | `~/.local/share/plasma/shells/` |
| Window switcher | `org.plasmafusion.switcher` (KWin/WindowSwitcher) | `~/.local/share/kwin/tabbox/` |
| KWin script, snapping | `plasmafusion-snap` (Meta+Z snap layouts, fill-the-other-half); shortcut name `Plasma Fusion: Snap Layouts` | `~/.local/share/kwin/scripts/` |
| KWin script, dialogs | `plasmafusion-attach` (modal dialogs pinned under the parent's title bar) | same |
| KWin script, tablet | `plasmafusion-tablet` (tablet posture: full-screen apps, panels 44/80 px, dock hiding; shortcut "Plasma Fusion: Tablet Window Mode") | same |
| Plasmoid, top-left | `org.plasmafusion.appname` (logo button + active app name) | `~/.local/share/plasma/plasmoids/` |
| Plasmoid, top-centre | `org.plasmafusion.clockpill` (workspace dots + date + time) | same |
| Plasmoid, top-right | `org.plasmafusion.quicksettings` (status pill + quick-settings popup + notification list) | same |
| Plasmoid, launcher | `org.plasmafusion.launcher` (centred start menu; `X-Plasma-Provides: org.kde.plasma.launchermenu`) | same |
| Plasmoid, dock | `org.plasmafusion.dock` (Start/Search/Overview buttons, magnifying task list, Downloads, Trash) | same |
| Plasmoid, desktop card | `org.plasmafusion.weathercard` (current weather, today's high and low) | same |
| Plasmoid, desktop card | `org.plasmafusion.calendarcard` (this month; a click on a day opens KOrganizer) | same |
| Plasmoid, desktop card | `org.plasmafusion.systemcard` (processor and memory bars) | same |
| Plasmoid, pen | `org.plasmafusion.pen` (pen button in tablet posture, New note / Snip / Mark up / Whiteboard / pen settings; Meta+Shift+W) and its Xournal++ templates `plasma-fusion/pen/templates/{Note,Whiteboard}.xopp` | same; templates in `~/.local/share/plasma-fusion/pen/` |
| Layout templates | `org.plasmafusion.panel.topbar`, `org.plasmafusion.panel.dock` ("Add Panel" entries) | `~/.local/share/plasma/layout-templates/` |
| Power tiers | `plasma-fusion-powerfx` (program) and `plasma-fusion-powerfx.service` (user unit, enabled by `fusion-config.sh`) | `~/.local/libexec/plasma-fusion/`, `~/.config/systemd/user/` (system package: `/usr/libexec/plasma-fusion/`, `/usr/share/plasma-fusion/powerfx/`) |
| Konsole | `PlasmaFusionDark.colorscheme`, `PlasmaFusionLight.colorscheme`, profile `Plasma Fusion.profile` | `~/.local/share/konsole/` |
| Kate/KWrite | `Plasma Fusion Dark.theme`, `Plasma Fusion Light.theme` | `~/.local/share/org.kde.syntax-highlighting/themes/` |
| Plymouth theme (system, phase 2) | `plasma-fusion` (shipped as a source in `/usr/share/plasma-fusion/plymouth/`; installed and selected by `tools/system/plymouth-install.sh --select`; rollback `plymouth-set-default-theme -R bgrt`) | `/usr/share/plymouth/themes/plasma-fusion/` (root) |
| Fonts | Manrope (UI, variable), Space Grotesk (display, variable), OFL-1.1 | `~/.local/share/fonts/plasma-fusion/` |
| Login check (gate) | `plasma-fusion-gate.sh` (`login`, `check`, `deploy`, `notify`, `status`; from `tools/device/gate/`) | `~/.local/share/plasma-fusion/gate/` |
| Login check, env stub | `plasma-fusion-gate.sh` (runs the check before KWin starts, 4 s time limit) | `~/.config/plasma-workspace/env/` |
| Login check, notification | `plasma-fusion-gate-notify.service` (wanted by `xdg-desktop-autostart.target`) | `~/.config/systemd/user/` |
| Login check, state | `gate.log`, `gate/{tested,cache,off,saved,notify,notified,status}` | `~/.local/state/plasma-fusion/` |
| RPM packages | `plasma-fusion` (the data parts above in system paths: colour schemes, Global Themes, Plasma styles, widgets, layout templates, lock shell, icons, cursors, Aurorae themes, wallpapers, switcher, KWin scripts, Konsole and Kate themes, fonts, pen templates, the power-tiers program and unit; plus greeter and Plymouth sources, the per-user templates and the tools (with the login check) under `/usr/share/plasma-fusion/`; `packaging/build-rpm.sh`), `plasma-fusion-decoration` (`packages/decoration-cpp/tools/build-rpm.sh`), `plasma-fusion-settings` (`packages/kcm-cpp/build-rpm.sh`) | `/usr` (root) |

## New names and keys (one-pass build registry, 2026-09-30)

Copied from section 2 of `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-decisions/PLAN.md`. "Owner WP" is the work package there that creates the name or key; use these exact ids and keys.

| Kind | Id / key | Owner WP |
|---|---|---|
| KWin script | `plasmafusion-tablet` (shortcut "Plasma Fusion: Tablet Window Mode") | KWIN-1 |
| Plasmoid | `org.plasmafusion.pen` | PEN-1 |
| Global Theme | `org.plasmafusion.previous.desktop` ("My previous desktop") | gate lane / DEVICE-1 |
| Layout templates | `org.plasmafusion.panel.topbar`, `org.plasmafusion.panel.dock` (Plasma/LayoutTemplate, X-Plasma-ContainmentCategories=panel) | LAYOUT-1 |
| User services | `plasma-fusion-powerfx.service`; `plasma-fusion-gate-notify.service` (gate lane); `plasma-fusion-pen-garage.service` (only if V2 passes) | POWER-1, PEN-1 |
| Env script | `~/.config/plasma-workspace/env/plasma-fusion-gate.sh` | gate lane |
| Shared QML | `packages/common/{FusionMetrics,Motion,FusionTablet,FusionBackdrop,FusionAccent,FusionIconTile}.qml` (`FusionIconTile`: the neutral tile behind icons without a Fusion icon, used by DOCK-2 and LAUNCH-1) | BASE-1 (lead) |
| Build script | `tools/build.d/81-kwin-tablet.sh` (new; `80-kwin.sh` names each KWin script explicitly and belongs to KWIN-2) | KWIN-1 |
| Shared script | `packages/look-and-feel/common/contents/layouts/ensure-topbars.js` (plasmashell script; used by KWIN-2 hot-plug and `fusion-config.sh --screens`) | LAYOUT-1 |
| plasmafusionrc | `[Decoration] ButtonStyle`, `SnapLayoutsOnHover` (default becomes **false**); `[Effects] Glass=Full\|Reduced\|Solid` and `[Motion] PreviousAnimationDurationFactor` (as EFFECTS 2 and 7: "Reduce motion" has no stored flag, it shows `AnimationDurationFactor == 0`); `[Power] LighterOnCritical=true`, `ShorterAnimationsOnCritical=false`, `Tier`, `UserDockMagnify`, `UserGlass`; `[Tablet] GestureCardShown`, `RotationLocked`; `[Pen] GarageService`; `[Config] FusionConfigVersion` | DECO-1, KCM-1, POWER-1, DOCK-2, QS-1, PEN-1, DEVICE-1 |
| kwinrc | `[Script-plasmafusion-tablet] WindowMode=fullscreen\|windowed`, `DockHiding=dodgewindows\|none`, `EdgeLeft`, `EdgeRight`, `DialogPolicy=fullscreen\|framed`, `DisableWindowMove=false`; `[Plugins] plasmafusion-tabletEnabled` | KWIN-1 |
| plasmashell config | `[PlasmaFusion] tabletApplied` and the saved laptop panel values (TABLET 3.6) | KWIN-1 |
| Widget keys | dock: `magnify`, `magnifiedSize` (off/56/62), `homeIndicator`, `tabletTile`, `tabletShowDownloadsTrash`, `powerTier`, `glass`; systemcard: `updateInterval` (default 3000), `powerTier` (hidden), `glass`; quicksettings: `keyboardPolicy`, `openRequest`, `glass`; launcher: `openRequest`, `glass`; pen: `showButton`, `actions`, `garageAction`, `openRequest` | the widget's lane |

## Repository layout

```
design/boards/            the 25 design boards (.dc.html) — the reference for every value
fonts/                    Manrope, Space Grotesk (+ OFL.txt)
generators/<part>/        Python generators (stdlib + Pillow only; PySide6 allowed for QtSvg checks)
packages/<part>/          hand-written sources (QML, JS, metadata, .colors, profiles)
stage/home/               build output: a HOME tree (.local/share/..., .config/...) ready to rsync; git-ignored
tools/build.sh            builds every part into stage/home (each part: tools/build.d/<NN>-<part>.sh)
tools/vsession/           isolated virtual Plasma sessions on the ThinkPad for visual tests
tools/device/             backup, apply and restore scripts for the ThinkPad's real session
docs/                     this plan, per-part notes, deviations
```

Each part owns its own `generators/<part>/`, `packages/<part>/` and `tools/build.d/<NN>-<part>.sh`. A build script writes only below `stage/home/` in the paths listed in the naming table. No part edits another part's files.

## Visual testing

`tools/vsession/remote.sh NAME SCENARIO SEED_HOME [SIZE] [TIMEOUT]` (run under `build/lead/vslot.sh`, which holds a session slot) copies a HOME tree to `/var/tmp/pfv-NAME/home` on the ThinkPad, starts a private headless KWin (virtual output, OpenGL on the Iris Xe, blur available) with kactivitymanagerd, kded6 and plasmashell on a private D-Bus bus, sources the scenario, and copies screenshots and logs back to `./vsession-out/NAME/`. The scenario can call `shot NAME`, `evaljs FILE`, `qdbus ...`, `wait_for_name NAME`. It never touches the logged-in desktop. Use a unique NAME per agent.

Compare screenshots with the board renders in `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-design-source/renders/` (and the boards' source for exact numbers). Test at 1920x1200 with `PFV_SCALE=1.3333333` (the ThinkPad panel at 4/3, 1440x900 logical: the boards' size); `tools/vsession/vsession.sh` lists the other `PFV_*` options (tablet mode, two outputs, fonts, reduced motion).

## Phases

1. **Phase 1 — no compiled code, per user.** Colours, fonts, wallpapers, Plasma style, icons, cursors, Aurorae decoration, Global Themes with layout and splash, shell plasmoids, KWin switcher and scripts, lock-screen shell, Konsole/Kate themes, GTK overrides. Built and checked in virtual sessions, then applied to the ThinkPad's real session with a backup and restore script.
2. **Phase 2 — root on the ThinkPad.** System-wide copies for the login greeter, greeter settings, Plymouth theme (preview with `plymouthd --debug`, rollback `plymouth-set-default-theme -R bgrt`), missing apps for the Code and Notes slots (Kate, Marknote), optional plasma-union evaluation.
3. **Phase 3 — compiled.** C++ KDecoration3 "Plasma Fusion" decoration (14 px corners with clipping, per-state shadows, show-on-hover buttons, hover-hold on maximize for snap layouts) and a Fusion KCM (Appearance page), built in a Fedora 44 container on the laptop.

## Integration (INT-1, 2026-09-30)

The one-pass build's test gate, its results and the exceptions for the deploy: `docs/parts/integration.md`.

## Accepted deviations (known platform limits)

- Overview hides the top bar and dock (KWin's overview draws panels only as fading thumbnails).
- No tabs merged into title bars; no unified toolbar/title bar for QtWidgets apps.
- Stock OSD component: styled by the Plasma style, placed by KWin at 2/3 height instead of the bottom.
- Login screen layout stays the stock greeter layout (styling only).
- Plasmashell's own QMenu context menus keep Breeze's small radius until Union covers QtWidgets.
- The Aurorae title bars and the Plymouth boot splash stay blue (they cannot follow the accent colour).
- Stock system-tray items keep their 36 px targets (the Fusion widgets have 44 px in tablet posture).
- Two focus indicators show during keyboard navigation in a panel (Plasma's and the widget's own),
  kept in round 2 against GAPS G25.
- The Alt+Tab switcher keeps the board's full-screen dim: KWin's render time while it opens is about
  6 ms per frame against the 3.5 ms budget (3.7 ms without the dim; owner's choice, see
  `docs/parts/kwin.md`, KWIN-2).
