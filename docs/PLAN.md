# Plasma Fusion — build plan

Status: phase 1 (no compiled code) about to start. Last edited 2026-09-29.

## Decisions

| Topic | Decision | Source |
|---|---|---|
| Test device | ThinkPad X13 Yoga Gen 4, `ssh thinkpad-fedora`, user `test`, Fedora 44, Plasma 6.7.5, KF 6.30, Qt 6.11.2 | user |
| Root on the ThinkPad | Allowed (passwordless sudo is intended). Back up first, record rollback. Never touch PAM (`/etc/pam.d`) or irlume. | user |
| Display scale | Set the ThinkPad panel to 4/3 (1.3333, logical 1440x900) so board pixels map 1:1 to logical pixels. Design values are used as logical px. | user ("adjust it so it matches the ThinkPad screen") |
| Compiled code | Phase 3, after the no-code desktop works: C++ KDecoration3 decoration and a Fusion KCM, built on the laptop in a Fedora 44 container. | user |
| Application style | Breeze + Fusion colour schemes first. `plasma-union` (6.7.5, in development) is evaluated per app before any session-wide switch. | research |
| Login screen | Stock plasma-login-manager greeter (its QML is compiled in). Fusion colours, Plasma style, fonts, cursor, icons and wallpaper installed system-wide and synced with "Apply Plasma Settings". No SDDM switch (PAM stack change). | research |
| Lock screen | Own Plasma/Shell package holding only `contents/lockscreen/`, selected with `PLASMA_DEFAULT_SHELL` in a `plasma-kwin_wayland.service` drop-in. PAM prompts, fingerprint and irlume face messages must keep working. | research |
| Build host | Everything is generated and packaged on the laptop (same Plasma/KF/Qt versions). Only artefacts go to the ThinkPad. | research |

## Naming table (use these exact ids)

| Part | Id / directory name | Installed at (per user) |
|---|---|---|
| Global Theme, dark | `org.plasmafusion.dark.desktop` ("Plasma Fusion Dark") | `~/.local/share/plasma/look-and-feel/` |
| Global Theme, light | `org.plasmafusion.light.desktop` ("Plasma Fusion Light") | same |
| Colour schemes | `PlasmaFusionDark.colors`, `PlasmaFusionLight.colors` ([General] Name "Plasma Fusion Dark/Light") | `~/.local/share/color-schemes/` |
| Plasma style | `plasma-fusion-dark`, `plasma-fusion-light` | `~/.local/share/plasma/desktoptheme/` |
| Icon themes | `PlasmaFusion` (light UI, inherits `breeze`), `PlasmaFusion-Dark` (dark UI, inherits `breeze-dark`) | `~/.local/share/icons/` |
| Cursor themes | `PlasmaFusion-cursors` (dark fill, default), `PlasmaFusion-Light-cursors` | `~/.local/share/icons/` |
| Window decoration (phase 1) | Aurorae v2 themes `PlasmaFusionDark`, `PlasmaFusionLight` (+ `PlasmaFusionDark-Left`, `PlasmaFusionLight-Left` for buttons on the left); kwinrc `library=org.kde.kwin.aurorae.v2`, `theme=__aurorae__svg__PlasmaFusionDark` | `~/.local/share/aurorae/themes/` |
| Wallpapers | `PlasmaFusion` (Dusk Ridge; `images/` light, `images_dark/` dark) plus `PlasmaFusion-<Name>` for the other board palettes | `~/.local/share/wallpapers/` |
| Splash | inside both Global Themes (`contents/splash/Splash.qml`); ksplashrc `Theme=org.plasmafusion.dark.desktop` | — |
| Lock screen shell | `org.plasmafusion.lockshell` (Plasma/Shell, fallback `org.kde.plasma.desktop`) | `~/.local/share/plasma/shells/` |
| Window switcher | `org.plasmafusion.switcher` (KWin/WindowSwitcher) | `~/.local/share/kwin/tabbox/` |
| KWin script, snapping | `plasmafusion-snap` (Meta+Z snap layouts, fill-the-other-half); shortcut name `Plasma Fusion: Snap Layouts` | `~/.local/share/kwin/scripts/` |
| KWin script, dialogs | `plasmafusion-attach` (modal dialogs pinned under the parent's title bar) | same |
| Plasmoid, top-left | `org.plasmafusion.appname` (logo button + active app name) | `~/.local/share/plasma/plasmoids/` |
| Plasmoid, top-centre | `org.plasmafusion.clockpill` (workspace dots + date + time) | same |
| Plasmoid, top-right | `org.plasmafusion.quicksettings` (status pill + quick-settings popup + notification list) | same |
| Plasmoid, launcher | `org.plasmafusion.launcher` (centred start menu; `X-Plasma-Provides: org.kde.plasma.launchermenu`) | same |
| Plasmoid, dock | `org.plasmafusion.dock` (Start/Search/Overview buttons, magnifying task list, Downloads, Trash) | same |
| Konsole | `PlasmaFusionDark.colorscheme`, `PlasmaFusionLight.colorscheme`, profile `Plasma Fusion.profile` | `~/.local/share/konsole/` |
| Kate/KWrite | `Plasma Fusion Dark.theme`, `Plasma Fusion Light.theme` | `~/.local/share/org.kde.syntax-highlighting/themes/` |
| Plymouth (phase 2) | `plasma-fusion` | `/usr/share/plymouth/themes/` (root) |
| Fonts | Manrope (UI, variable), Space Grotesk (display, variable), OFL-1.1 | `~/.local/share/fonts/plasma-fusion/` |

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

`tools/vsession/remote.sh NAME SCENARIO SEED_HOME [1440x900] [TIMEOUT]` copies a HOME tree to `/tmp/pfv-NAME/home` on the ThinkPad, starts a private headless KWin (virtual output, OpenGL on the Iris Xe, blur available) with kactivitymanagerd, kded6 and plasmashell on a private D-Bus bus, sources the scenario, and copies screenshots and logs back to `./vsession-out/NAME/`. The scenario can call `shot NAME`, `evaljs FILE`, `qdbus ...`, `wait_for_name NAME`. It never touches the logged-in desktop. Use a unique NAME per agent.

Compare screenshots with the board renders in `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-design-source/renders/` (and the boards' source for exact numbers). The virtual output is 1440x900, the same size as the boards.

## Phases

1. **Phase 1 — no compiled code, per user.** Colours, fonts, wallpapers, Plasma style, icons, cursors, Aurorae decoration, Global Themes with layout and splash, shell plasmoids, KWin switcher and scripts, lock-screen shell, Konsole/Kate themes, GTK overrides. Built and checked in virtual sessions, then applied to the ThinkPad's real session with a backup and restore script.
2. **Phase 2 — root on the ThinkPad.** System-wide copies for the login greeter, greeter settings, Plymouth theme (preview with `plymouthd --debug`, rollback `plymouth-set-default-theme -R bgrt`), missing apps for the Code and Notes slots (Kate, Marknote), optional plasma-union evaluation.
3. **Phase 3 — compiled.** C++ KDecoration3 "Plasma Fusion" decoration (14 px corners with clipping, per-state shadows, show-on-hover buttons, hover-hold on maximize for snap layouts) and a Fusion KCM (Appearance page), built in a Fedora 44 container on the laptop.

## Accepted deviations (known platform limits)

- Overview hides the top bar and dock (KWin's overview draws panels only as fading thumbnails).
- No tabs merged into title bars; no unified toolbar/title bar for QtWidgets apps.
- Stock OSD component: styled by the Plasma style, placed by KWin at 2/3 height instead of the bottom.
- Login screen layout stays the stock greeter layout (styling only).
- Plasmashell's own QMenu context menus keep Breeze's small radius until Union covers QtWidgets.
