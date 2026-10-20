# SDDM login screen (Plasma Fusion)

<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

The Plasma Fusion login screen as an SDDM theme (docs/ROADMAP.md, "Login screen and boot splash
elsewhere"): the Login board (`design/boards/Login.dc.html`) drawn for the display managers that
run SDDM - Arch, Ubuntu 26.10, Debian testing, KDE neon and the NixOS module - next to the
plasma-login-manager styling in [`tools/system/greeter-apply.sh`](../../tools/system/greeter-apply.sh).

## What it is

`packages/sddm-theme/` is the theme source. `build.sh` stages it into a theme directory that
`sddm-greeter-qt6` can run (`sddm-greeter-qt6 --test-mode --theme <dir>`), and
[`packaging/install-tree.sh`](../../packaging/install-tree.sh) installs it as
`share/sddm/themes/plasmafusion`. This slice packages the theme for manual selection through
the distribution's SDDM settings. Automatic apply/restore and the login check are follow-up work;
`tools/system/greeter-apply.sh` still handles plasma-login-manager only.

The theme is plain QtQuick with the models and the proxy object SDDM provides
(SDDM `docs/THEMING.md`, v0.21.0): `sddm` (hostName, the power capabilities and methods,
`login(user, password, sessionIndex)`, `loginFailed`/`loginSucceeded`), `userModel`
(`name`, `realName`, `homeDir`, `icon`, `lastIndex`, `lastUser`), `sessionModel`
(`file`, `name`, `exec`, `comment`, `lastIndex`) and `keyboard` (the greeter's `KeyboardModel`:
`layouts[].longName`, `currentLayout`; as KDE's own theme uses it). It takes no dependency on
Kirigami or the Plasma QML components: a login screen must survive missing optional pieces.

## The board, and where it stops

The screen is the Login board at 1440 x 900: the pre-blurred Dusk Ridge treatment
(`dusk-ridge-dark-login.png`, blur 20 px at scale 1.08 with the 50 % veil - already baked into the
image the generator ships), the clock and date at the top left, the sign-in card centred at 520,210
with its 112 px avatar and pill password field, the user row at y 600, the session pill at the
bottom left and the three power buttons at the bottom right. Fonts are Manrope and Space Grotesk
(the parts' fonts package installs them system-wide).

Deviations from the board, all for want of an API in SDDM's greeter (`GreeterProxy.h` exposes only
hostName, the power capabilities, the power methods and `login()`; the `keyboard` model adds
`capsLock`, `numLock` and the layouts):

- the top right's accessibility button and Wi-Fi/battery pill are not drawn - SDDM exposes no
  accessibility service, no network and no battery to themes (the keyboard pill is drawn);
- "Caps Lock is on" IS shown (`keyboard.capsLock`); the row's "Use fingerprint" link is not - no
  biometric API (PAM may still unlock through its own stack);
- the user row's "Other user" opens the name field for a user not in the model (as KDE's theme
  does), which the board shows as a tile.

## Tests

- `tests/contract_test.py` (CI): the metadata and `theme.conf` contract (SDDM `docs/THEMING.md` and
  KDE's Breeze theme conventions), every referenced file exists in the staged theme, and the QML
  parses (`qmllint` when present), builds are reproducible, and each channel's actual builder
  invocation supplies the directory the installer expects (including the NixOS wallpaper path).
- `tests/behavior_test.py` (CI via `tools/build.d/91-sddm.sh`): the staged `Main.qml` on real QtQuick
  with SDDM-shaped model/proxy stand-ins, driven by Qt key events. Covers Tab, account arrows,
  session selection, keyboard layouts, power dispatch, Other user, failed login, password reveal
  and blocked undo. The stand-ins never authenticate or perform a power action.
- Input-method, model-reset and long-message regressions cover revealed-password hints,
  composition clearing, replacement/empty/recovered session models, and complete instructions
  reachable through the bounded keyboard-scrollable `MessageView`. `tests/avatar_test.py`
  checks photo-mask pixels. The part page links the live Qt/SDDM sources behind these choices.
- Assistive technology activates every custom button through the real Qt accessibility Press
  action. The theme also opts out of full passwd enumeration so large directory-backed user
  databases do not delay the greeter; Other user covers accounts outside the limited model.
  `build.sh`'s header uses the Qt6 greeter's `--test-mode` command. The username field blocks
  automatic capitalization, the layout pill announces its selection, the reveal toggle reports
  its checked state, and an empty Other-user submission gives an actionable message. Account
  tiles expose their selected state, and a passwordless account hides the password input and
  signs in without one. The metadata file's own data is CC0. Session choices announce selection,
  duplicate real names show the login name in the short tile caption, and both credential fields
  stay in the Tab chain. Failed Other-user logins return focus to the password, and staged QML
  mtimes derive from content so upgrades invalidate Qt's cache. A submitted credential is cleared
  and re-masked immediately; one pending request blocks duplicate submission and account/session
  changes until SDDM reports success or failure.
- The real `sddm-greeter-qt6 --test-mode` container render is recorded in
  [`docs/parts/sddm.md`](../../docs/parts/sddm.md). It is visual evidence, not an automated runtime
  scenario; the release-VM lane is follow-up work.

## Install and check

    packages/sddm-theme/build.sh build/sddm               # stage the theme (build/sddm/plasmafusion)
    sddm-greeter-qt6 --test-mode --theme build/sddm/plasmafusion   # see it (the Qt6 greeter, per
                                                           # --help; the docs say --test, which it rejects)

Installing the package does not change the active display manager, its theme or authentication
settings. SDDM's apply/restore integration has not landed yet.
