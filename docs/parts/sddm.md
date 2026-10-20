<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: GPL-2.0-or-later
-->

# The SDDM login screen

Status: built, contract-tested and rendered under `sddm-greeter-qt6` in a container (the Login
board's look; see "Verification"); not yet installed on a system or in the release VMs.
Source: [`packages/sddm-theme/`](../../packages/sddm-theme/).

Plasma Fusion styles plasma-login-manager through
[`tools/system/greeter-apply.sh`](../../tools/system/greeter-apply.sh); this part draws the same
Login board (`design/boards/Login.dc.html`) as an SDDM theme for the systems whose display manager
is SDDM - Arch, Ubuntu 26.10, Debian testing, KDE neon and the NixOS module (docs/parts/nixos.md).

## What SDDM gives a theme (verified against the source)

SDDM `docs/THEMING.md` and `src/greeter/` of sddm 0.21.0 (the version Fedora 44, Arch and Debian
ship): the greeter hosts the theme's `Main.qml` in a `QQuickView` sized to the screen
(`GreeterApp.cpp`: `SizeRootObjectToView`, per-screen geometry), so the root is an Item. The
context objects are `sddm`, `userModel`, `sessionModel`, `screenModel`, `keyboard`, `config`,
`primaryScreen` (`GreeterApp.cpp`'s `setContextProperty` block):

| Object | What the theme uses |
|---|---|
| `sddm` | `hostName`; `canPowerOff/canReboot/canSuspend/canHibernate/canHybridSleep`; `powerOff()/reboot()/suspend()/hibernate()`; `login(user, password, sessionIndex)`; `loginFailed()`, `loginSucceeded()`, `informationMessage()` (`GreeterProxy.h`) |
| `keyboard` | `capsLock`, `numLock`, `currentLayout`, `layouts` (`KeyboardModel.h`) - each a `KeyboardLayout` with `shortName`/`longName` (`KeyboardLayout.h`) |
| `userModel` | `name`, `realName`, `homeDir`, `icon`, `lastIndex`, `lastUser` (read in the delegates: the models are `QAbstractItemModel`) |
| `sessionModel` | `name`, `exec`, `comment`, `lastIndex` |
| `config` | this theme's `theme.conf` (`ThemeConfig`; `GreeterApp.cpp`) |
| `metadata.desktop` | `Type=sddm-theme`, `MainScript`, `ConfigFile`, `Theme-Id`; `QtVersion=6` chooses the Qt6 greeter |

The theme imports only `QtQuick 2.15` and its own `palette.js`: a login screen must survive
missing optional modules, and the versioned import also loads under a Qt5 greeter (the failure
behind the widely reported "Qt6 theme broke my login screen").

## The board, and where it stops

The screen is the Login board at 1440 x 900: the pre-blurred Dusk Ridge treatment
(`dusk-ridge-dark-login.png` - the generator bakes the board's blur 20 px at scale 1.08 with its
50 % veil), the clock and date at 32,28, the sign-in card centred at y 210 (the 112 px avatar, the
340 x 48 pill field with its show-password and sign-in buttons), the user row at y 600 with the
"Other user" tile, the session pill at 32 from the bottom left and the power buttons 32 from the
bottom right. Fonts: Space Grotesk and Manrope (the fonts part installs them system-wide).

Deviations from the board:

- the top right's accessibility button and Wi-Fi/battery pill are not drawn - SDDM exposes no
  accessibility service, no network and no battery to themes;
- the row's "Use fingerprint" link is not offered - no biometric API (PAM may still unlock through
  its own stack); the slot carries the login's messages (`sddm.informationMessage`, `loginFailed`)
  and `keyboard.capsLock` draws the board's "Caps Lock is on";
- the power buttons appear only where the daemon allows them (`canSuspend`/`canReboot`/`canPowerOff`),
  so `sddm-greeter-qt6 --test-mode` renders without them (it reports every capability false);
- the board's 12.5 px and 11.5 px labels are drawn at 13 px and 12 px (`font.pixelSize` is an int);
- with no users in `userModel` (a container, `--test-mode`) the card asks for a name, which the
  board shows as a user row.

## Install and check

    packages/sddm-theme/build.sh build/sddm        # stage the theme (byte-identical)
    sddm-greeter-qt6 --test-mode --theme build/sddm/plasmafusion

`packaging/install-tree.sh --sddm build/sddm` installs it as `share/sddm/themes/plasmafusion`;
`tools/system/greeter-apply.sh` selects it on SDDM systems (and `greeter-restore.sh` puts the
previous theme back). `sddm-greeter-qt6`'s flag is `--test-mode`; SDDM's theming document still
says `--test`, which the Qt6 greeter rejects.

## Tests

- `packages/sddm-theme/tests/contract_test.py` (CI, `tools/build.d/91-sddm.sh`): the metadata and
  `theme.conf` contract, every shipped file, the dependency-free QML (imports checked), a QML
  parse (`qmllint` when present), and two builds byte-identical - 26 checks.
- The repository's QML checks (motion, a11y, id scope) cover the theme's files like every other
  part; the a11y check found the theme's ten unnamed interactive items before the first commit.

## Verification

2026-10-20, the theme rendered under `sddm-greeter-qt6 --test-mode` in a throw-away Fedora 44
container with Xvfb at 1440 x 900 (no display manager touched any machine): the Login board's
composition and palette (the avatar, the pill field, the user row, the session pill, the clock),
the greeter's log empty. Mean RGB against `design/previews/Login.webp` (the board render, scaled
2:1): mid-left delta 0.0-0.3, the sun region 0.3-1.1, the far right 1.0 - the same "within 1/255"
band the plasma-login-manager preview reached (system.md); the top and bottom bands differ where
the board has its mock text and the power buttons the test mode does not report.
