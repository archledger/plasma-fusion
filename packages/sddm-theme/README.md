# SDDM login screen (Plasma Fusion)

<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: GPL-2.0-or-later
-->

The Plasma Fusion login screen as an SDDM theme (docs/ROADMAP.md, "Login screen and boot splash
elsewhere"): the Login board (`design/boards/Login.dc.html`) drawn for the display managers that
run SDDM - Arch, Ubuntu 26.10, Debian testing, KDE neon and the NixOS module - next to the
plasma-login-manager styling in [`tools/system/greeter-apply.sh`](../../tools/system/greeter-apply.sh).

## What it is

`packages/sddm-theme/` is the theme source. `build.sh` stages it into a theme directory that
`sddm-greeter` can run (`sddm-greeter --test --theme <dir>`), and
[`packaging/install-tree.sh`](../../packaging/install-tree.sh) installs it as
`share/sddm/themes/plasmafusion`. `tools/system/greeter-apply.sh` selects it for SDDM (and
[`greeter-restore.sh`](../../tools/system/greeter-restore.sh) puts the previous theme back).

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
  parses (`qmllint`/`qmlformat` when present).
- `tests/vsession/scenario-sddm.sh`: the theme under `sddm-greeter --test` in a private session on
  the ThinkPad, screenshots compared against `design/previews/Login.webp` (the plasmalogin
  greeter's preview harness shape, docs/parts/system.md).

## Install and check

    packages/sddm-theme/build.sh build/sddm/theme        # stage the theme
    sddm-greeter --test --theme build/sddm/theme         # see it without logging out

`greeter-apply.sh` (root) selects it on a system whose display manager is SDDM; on other display
managers it reports and changes nothing.
