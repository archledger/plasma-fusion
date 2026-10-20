<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The SDDM login screen

Status: built, contract/behavior-tested and rendered under `sddm-greeter-qt6` in a container (the Login
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
missing optional modules, and the versioned import also loads under a Qt5 greeter, where an
unversioned `import QtQuick` fails (sddm/sddm#1975 is that failure at a real login screen).

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

`packaging/install-tree.sh --sddm build/sddm/plasmafusion` (alongside its stage and Plymouth
arguments) installs it as `share/sddm/themes/plasmafusion`. Every channel passes the output root
to the builder and the resulting theme directory to the installer. NixOS sets the wallpaper to
`/run/current-system/sw/share/plasma-fusion/backgrounds/dusk-ridge-dark-login.png`, not `/usr/share`.
The theme is available for manual selection in the distribution's SDDM settings; automatic
apply/restore and the login check remain follow-up work. `tools/system/greeter-apply.sh` still
handles plasma-login-manager only. Installing this theme changes neither the active display
manager nor its authentication settings.

`sddm-greeter-qt6`'s flag is `--test-mode`; SDDM's theming document still says `--test`, which the
Qt6 greeter rejects.

## Tests

- `packages/sddm-theme/tests/contract_test.py` (CI, `tools/build.d/91-sddm.sh`): the metadata and
  `theme.conf` contract, every shipped file, the dependency-free QML (imports checked), a QML
  parse (`qmllint` when present), two builds byte-identical, and the actual builder call from
  every channel produces the installer's expected directory and NixOS wallpaper path.
  The suite also checks the Debian-family build dependencies against the behavior test's
  imported PySide6 modules; these distributions split QtCore/QtGui/QtQml/QtQuick/QtTest into
  separate packages and need `qml6-module-qtquick` for the theme's QML import.
- `QT_QPA_PLATFORM=offscreen python3 packages/sddm-theme/tests/behavior_test.py` (CI through the
  same build part): the staged `Main.qml` in a real `QQuickView`, SDDM-shaped model/proxy stand-ins
  and Qt key events. Tab reaches the layout, session, power and reveal buttons; Left/Right move
  account focus and Return/Space choose; session arrows, activation and Escape return focus to
  the pill. Other user has a visible Username prompt. Account changes and failed logins clear the
  password; undo/redo shortcuts cannot recover deleted input, including while it is revealed
  (the same policy as the lock-screen PasswordField). Power/authentication dispatch is recorded
  only by the stand-ins, never a daemon. QML warnings fail the suite.
  The empty password prompt remains visible on initial focus; explicit clears reset reveal as
  well as input. Twenty-account and long-name fixtures exercise the bounded, clipped horizontal
  account viewport, focus-following scroll, pointer dragging and a narrow screen. Captions elide
  within the avatar width while each account's accessible name stays complete; the card's full
  name is bounded by the card too.
  A sixteen-session fixture on a 480 px-high screen checks the vertically bounded session menu,
  focus-following scroll, pointer dragging and a long selected session name. Account, layout,
  session and daemon-provided text uses `Text.PlainText`, so HTML-like names are displayed
  literally. `loginFailed()` carries no reason: the theme reports "Login failed", not a guessed
  password diagnosis.
  Short-screen card/account positions also keep both groups clear of each other and the footer;
  normal-height layouts keep the board's y positions (210 and 600 at 900 px high).
  Password input requests the lock screen's sensitive/nonpredictive IME hints even while revealed;
  `clear()` resets both committed text and preedit composition. A protected field has a static,
  non-secret accessibility description (Qt 6.11.2 suppresses its attached name).
  Account selection clears the previous account's authentication feedback. Missing or invalid
  photo sources fall back to the account initial until the image reaches `Image.Ready`.
  Narrow footer layouts reserve a gap for the power buttons, and the open session menu stays
  above the entire footer rather than just above the shorter session pill.
  Model reset invalidates the selected session until delegates are rebuilt; the initial remembered
  session is honored, resets fall back to the first available entry, data changes refresh the label,
  and an empty model blocks login with "No sessions available". The live Repeater count is used
  rather than SDDM 0.21's `CONSTANT` count property.
  Full authentication instructions wrap, including unbroken text, and a bounded `MessageView`
  grows within the remaining card space. Overflow remains reachable by Tab, arrows and Page
  Up/Down (Home/End also work); long instructions, caps lock and Other user are covered together
  at 480 px height without covering account/footer controls. No elision discards the instruction.
  Every custom `Accessible.Button` handles the accessibility Press action as well as keys and
  pointer input; the suite invokes the real `QAccessible` action for layout, reveal, sign-in,
  sessions, accounts, Other user and all power controls.
  The username field disables automatic IME capitalization, the keyboard control announces the
  selected layout as its accessible description, and the reveal toggle exposes its checkable and
  checked state. Submitting an empty Other-user name reports "Enter a username", clears the
  stale password and refocuses the username field instead of appearing to do nothing.
  `theme.conf` sets `needsFullUserModel=false`: SDDM 0.21 otherwise walks the complete passwd
  directory (including large NSS directories). Other user covers accounts beyond the limited
  model, and the remembered account remains available as SDDM adds it explicitly.
- `tests/avatar_test.py` (the same CI build part): software-rendered pixel checks on the staged
  avatar through no-photo-to-photo and fill changes. Source and fill changes explicitly request
  a new mask paint. The source-switch case also passes on the prior Qt 6.11.2 component; the fill
  change reproduces stale mask corners without the repaint handler.
- The repository's QML checks (motion, a11y, id scope) cover the theme's files like every other
  part; the a11y check found the theme's ten unnamed interactive items before the first commit.

### Live upstream references for the safety and lifecycle rules

- [Qt 6.11.2 TextInput implementation](https://raw.githubusercontent.com/qt/qtdeclarative/v6.11.2/src/quick/items/qquicktextinput.cpp):
  masked modes already add sensitive hints; explicit flags preserve them when reveal selects Normal.
- [TextInput.clear()](https://doc.qt.io/qt-6/qml-qtquick-textinput.html#clear-method): use it instead of
  assigning empty text, because it also resets partial input from the IME.
- [Qt 6.11.2 accessibility implementation](https://raw.githubusercontent.com/qt/qtdeclarative/v6.11.2/src/quick/items/qquickaccessibleattached_p.h):
  `name()` returns empty for `passwordEdit`; the field retains a static description, and tests use
  its stable object name rather than dropping protected semantics to recover a label.
- [SDDM 0.21 SessionModel.cpp](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/greeter/SessionModel.cpp)
  and [header](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/greeter/SessionModel.h): directory
  changes reset the model, while `count` and `lastIndex` are declared `CONSTANT`.
- [Qt model-reset contract](https://doc.qt.io/qt-6/qabstractitemmodel.html#modelReset): previously read
  counts, indexes and role data are invalid after reset.
- [Text wrapping](https://doc.qt.io/qt-6/qml-qtquick-text.html#wrapMode-prop): `Text.Wrap` prefers word
  boundaries but also wraps overlong words, unlike `WordWrap` alone.
- [Image loading status](https://doc.qt.io/qt-6/qml-qtquick-image.html#status-prop): a nonempty URL
  does not imply a loaded photo; the initial remains available during Loading or Error.
- [Accessible press action](https://doc.qt.io/qt-6/qml-qtquick-accessible.html#pressAction-signal):
  `Accessible.Button` alone does not activate a custom item from a screen reader; every such
  control defines `Accessible.onPressAction`, and tests invoke that real Qt action.
- [SDDM GreeterApp partitioning](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/greeter/GreeterApp.cpp):
  `needsFullUserModel` defaults to true and rebuilds the model around the theme's choice; the
  Qt6 parser defines `test-mode`, not `test`.
- [SDDM UserModel enumeration](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/greeter/UserModel.cpp):
  without all users it stops at the avatar threshold and explicitly adds the remembered account.
- [Flickable](https://doc.qt.io/qt-6/qml-qtquick-flickable.html) and
  [Keys](https://doc.qt.io/qt-6/qml-qtquick-keys.html): the message's measured content height, clipped
  viewport and keyboard paging stay in core QtQuick; no optional controls module is required.

The current generic Qt reference identifies itself as 6.12.0. These longstanding APIs are checked
against the version-pinned 6.11.2 source and the actual 6.11.1/6.11.2 runtimes; no 6.12-only API is
used. IME hints are requests to the input-method implementation, not a claim about a particular
IME's dictionary storage. Tests use synthetic composition, never real credentials or a PAM stack.

## Verification

2026-10-20, the theme rendered under `sddm-greeter-qt6 --test-mode` in a throw-away Fedora 44
container with Xvfb at 1440 x 900 (no display manager touched any machine): the Login board's
composition and palette (the avatar, the pill field, the user row, the session pill, the clock),
the greeter's log empty. Mean RGB against `design/previews/Login.webp` (the board render, scaled
2:1): mid-left delta 0.0-0.3, the sun region 0.3-1.1, the far right 1.0 - the same "within 1/255"
band the plasma-login-manager preview reached (system.md); the top and bottom bands differ where
the board has its mock text and the power buttons the test mode does not report.
