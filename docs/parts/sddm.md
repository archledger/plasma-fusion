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

The theme imports only `QtQuick 2.15`, `QtCore` and its own files: a login screen must survive
missing optional modules, and the versioned import also loads under a Qt5 greeter, where an
unversioned `import QtQuick` fails (sddm/sddm#1975 is that failure at a real login screen). The
two optional modules each live in one file the theme creates with `Qt.createComponent` and a
status check - `CircularMask.qml` (`QtQuick.Effects`) and `VirtualKeyboard.qml`
(`QtQuick.VirtualKeyboard`): without the module the component reports an error status and the
theme goes on without that piece, where a `Loader`'s URL would print a warning at every start.

### Qt's virtual keyboard

SDDM's default `[General] InputMethod=qtvirtualkeyboard` (`Configuration.h`; Debian keeps the
default, Ubuntu and KDE neon set it, Fedora and Arch ship it empty) starts the greeter with
`QT_IM_MODULE=qtvirtualkeyboard`. With no `InputPanel` in the scene, Qt opens a keyboard window of
its own over the lower half of the screen as soon as a text field has focus - at once, since the
password field starts focused - covering the user row, the session pill and the power buttons (seen
on a real boot, Debian testing, 2026-10-21). On an X11 greeter the theme puts `VirtualKeyboard.qml`
(an `InputPanel`) in its scene, which takes the keyboard over; it shows only after the board's
accessibility button (top right, next to the layout pill: "On-screen keyboard", a checkable button)
and while Qt's input method asks for a keyboard, along the bottom, with the sign-in card moved above
it. KDE's Breeze theme does the same with a footer button. A Wayland greeter's keyboard is the
compositor's (Fedora runs KWin with `--inputmethod plasma-keyboard`), so there the theme adds none.

### The avatar

A user photo is cut to its disc by `MultiEffect`'s mask (`CircularMask.qml`). Rectangle's radius
rounds nothing of a child, this greeter's Canvas cannot draw an Image, and painting the photo's
square corners in the tile's fill fails because the tile is a disc: those corners lie on the
wallpaper and showed as a purple square on a real greeter (SDDM always provides a face icon, at
least its default face). Effects need the hardware scene graph; under the software one, or without
`QtQuick.Effects`, the photo is not drawn at all and the tile keeps its initial - never a square.

## The board, and where it stops

The screen is the Login board at 1440 x 900: the pre-blurred Dusk Ridge treatment
(`dusk-ridge-dark-login.png` - the generator bakes the board's blur 20 px at scale 1.08 with its
50 % veil), the clock and date at 32,28, the sign-in card centred at y 210 (the 112 px avatar, the
340 x 48 pill field with its show-password and sign-in buttons), the user row at y 600 with the
"Other user" tile, the session pill at 32 from the bottom left and the power buttons 32 from the
bottom right. Fonts: Space Grotesk and Manrope (the fonts part installs them system-wide).

Deviations from the board:

- the top right's Wi-Fi/battery pill is not drawn - SDDM exposes no network and no battery to
  themes; the accessibility button is drawn where Qt's virtual keyboard is available and opens it,
  the one accessibility aid a theme can offer (no accessibility service either);
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
  photo sources fall back to the account initial until the image reaches `Image.Ready` and the mask
  draws it (see "The avatar").
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
  The account tiles and Other user expose `Accessible.selected`. An account whose SDDM
  `needsPassword` role is false hides the password input, shows "No password required" beside
  its sign-in control, and submits an empty password; switching back to a password account
  restores the field. `metadata.desktop` carries CC0 for its own data while its `License` field
  still names the theme code's GPL-2.0-or-later.
  Session choices also expose their selected state. Account tiles whose real names collide add
  the login name to both the accessible name and the card identity; the 56 px tile caption shows
  the short login name itself so the distinguishing text is not elided away. Both credential
  fields are explicit Tab stops, so keyboard traversal returns to them after the layout, session
  and power controls. A failed Other-user login returns focus to the password field rather than
  the still-valid username.
  `theme.conf.in` is CC0 like other project metadata and configuration input; Debian's
  machine-readable copyright groups it with `metadata.desktop` under CC0.
  The staged theme gives every file a content-derived mtime within a bounded epoch. Qt's
  persistent QML cache keys on source time, so a single fixed date could make an upgraded Arch
  or NixOS system keep the previous compiled theme; identical content still yields identical
  bytes and times.
  Submitting captures the credential, clears and re-masks the field immediately, then holds one
  pending request: the card, account strip and session chooser stay blocked, with "Signing in…",
  until `loginFailed` or `loginSucceeded`. A slow PAM response cannot be resubmitted or have its
  displayed account/session changed underneath it. Every way of opening the session chooser,
  including Up/Down, shares the same guard. With no listed accounts, the fallback selects Other
  user through the normal activation path, so its prompt, selection ring and accessible state
  agree.
  SDDM gives each screen its own QQuickView/QML engine (and activates only the primary view), so
  per-view QML state cannot coordinate a login across screens. Only the current primary view
  accepts input; a secondary screen shows the same board but cannot start a competing
  authentication. `primaryScreen` is only a creation-time snapshot, so the theme polls
  `screenModel.primary` (a live getter) once a second; SDDM 0.21 never emits that model's
  `primaryChanged`, and the snapshot remains the fallback. If the primary monitor moves, the new
  view becomes interactive instead of every screen staying locked.
  The pending request itself is shared across those engines through a small `QtCore.Settings` file
  at `StandardPaths.GenericConfigLocation/plasmafusion-auth.ini`. Its category is keyed by the
  greeter's random `--socket` name (`sddm-<display>-<random>`, from `SocketServer.cpp`), so the
  screen engines of one greeter share it while another seat's greeter cannot. The submitting view
  stores its token, every live screen renews a heartbeat once a second, and a newly primary view
  cannot submit until the daemon result clears it. A surviving screen keeps renewing after the
  submitting screen's view is removed; the lock is reclaimed only when every view of that greeter
  is gone, and a restarted greeter starts with a new socket category. `QSettings::sync()` reloads
  changes made by another engine; the daemon still serializes the actual authentication, so a
  read-then-write race cannot start two PAM conversations. `QtCore` is a core Qt module (the Debian
  package declares `qml6-module-qtcore`); the theme imports only QtQuick, QtCore and its own files (and the two optional modules, each
  in its own file). A view that loses primary clears and
  re-masks the password and clears the typed Other-user name. An empty user model initializes
  Other user at load and on promotion, independently of input gating, so a view created secondary
  shows the correct prompt and accessible selection when it becomes primary. The pending lock is
  held until `loginFailed` or `loginSucceeded`; no local timer releases it, because SDDM neither
  answers nor cancels a request that is still running. While a request is pending, a
  `sessionModel` reset (SDDM watches the session directories) does not clear or resync the
  displayed session; the proxy already copied the submitted index into the login message, so the
  submitted label stays until the result and the deferred resync then adopts the rebuilt model.
  The keyboard-layout control follows the same input and pending guards.
  Selecting a listed account clears any previously typed Other-user name (including its IME
  composition); a failed login for that same Other-user identity keeps it. The password input
  fills its 48 px pill, so a click anywhere in the field row focuses it.
- `tests/avatar_test.py` (the same CI build part, software scene graph; and the build workflow
  under Xvfb with Mesa's llvmpipe, `PF_AVATAR_GL=1`): the staged avatar inside a disc on a dark
  wallpaper stand-in, as the card and the tiles show it. Nothing may be drawn outside the disc,
  with or without a photo; on OpenGL the photo shows inside it through the mask, in software it is
  not drawn and `ready` stays false. Against the corner-painting component the outside-the-disc
  check fails on both. The OpenGL run uses Qt's basic render loop: with the threaded one, the render
  thread destroying a removed mask's layer meets PySide6's destruction hook waiting for Python's
  GIL, which the test's thread holds while it waits for that sync - a harness deadlock (gdb), not
  a greeter's (a C++ program).
- `behavior_test.py` with stand-ins for `QtQuick.VirtualKeyboard` first on the import path (one
  with `InputPanel`, one without): a focused field alone does not open the keyboard; the
  "On-screen keyboard" button (accessibility action and Space) opens it along the bottom, moves
  the card above it with a credential field keeping the focus, reports its checked state and
  closes it again; without the module the theme loads with no keyboard, no button and no
  warning. On the offscreen (software) scene graph a loaded card photo keeps the initial.
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
  The model's `needsPassword` role comes from `UserModel.h`; the reference theme passes it to
  its account presentation, which is why a passwordless account has no password field.
- [SDDM reference theme](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/greeter/theme/Main.qml):
  `showPassword: model.needsPassword` and `sddm.login(model.name, password, sessionIndex)`.
  Our equivalent keeps a visible sign-in control and sends the empty password.
- [SDDM GreeterProxy](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/greeter/GreeterProxy.h):
  `login()` is asynchronous and results arrive as `loginFailed`/`loginSucceeded`; the theme holds
  one pending request until one of those signals and clears the submitted credential meanwhile.
- [SDDM per-screen views](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/greeter/GreeterApp.cpp):
  `addViewForScreen()` creates a separate `QQuickView` (own engine) per screen, shares the proxy
  and models, and activates only the primary view. Its `primaryScreenChanged` handler only
  re-activates; the `primaryScreen` context value is set once at view creation.
- [SDDM ScreenModel](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/greeter/ScreenModel.h):
  `primary` is a live property (0 for this view's screen, -1 otherwise). SDDM 0.21 declares
  `primaryChanged` but never emits it, so the theme polls the getter instead of binding to it.
- [SDDM Display authentication](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/daemon/Display.cpp):
  `startAuth` returns false with only a warning when another authentication is active; there is no
  immediate greeter reply. The theme therefore never unlocks a pending request locally; the shared
  lock and the daemon's serialization bound the handoff case.
- [SDDM Greeter launcher](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/daemon/Greeter.cpp)
  and [SocketServer](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/daemon/SocketServer.cpp):
  the greeter receives `--socket` with a per-greeter name (`sddm-<display>-<random>`), used as the
  shared lock's category so seats stay independent.
- [Qt Settings QML type](https://doc.qt.io/qt-6/qml-qtcore-settings.html) and
  [QSettings::sync()](https://doc.qt.io/qt-6/qsettings.html#sync): `Settings` (QtCore, since 6.5)
  persists the shared lock, and `sync()` reloads settings changed by another engine as well as
  writing changes. [StandardPaths](https://doc.qt.io/qt-6/qml-qtcore-standardpaths.html) supplies
  `GenericConfigLocation` for the theme's own file.
- [SDDM SessionModel](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/greeter/SessionModel.cpp)
  and [GreeterProxy](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/greeter/GreeterProxy.cpp):
  the model resets when the session directories change, while the proxy has already copied the
  submitted indexed session into the login message. The theme keeps the submitted label visible
  across that reset and resyncs after the result.
- [Accessible selection](https://doc.qt.io/qt-6/qml-qtquick-accessible.html#selected-prop): the
  remembered and currently chosen account, Other user and the chosen session expose their
  selected state.
- [Tab focus](https://doc.qt.io/qt-6/qml-qtquick-item.html#activeFocusOnTab-prop): `activeFocusOnTab`
  defaults to false; both raw TextInput credential fields opt in so they remain in the cycle.
- [Qt QML disk cache](https://doc.qt.io/qt-6/qmldiskcache.html): a compiled unit is only reused
  while the original source is unchanged; timestamp-based validation means one constant mtime
  can keep an older theme after an upgrade. The NixOS report
  [nixpkgs#541178](https://github.com/nixos/nixpkgs/issues/541178) describes exactly this stale
  SDDM greeter cache, so the staged files get content-derived times.
- [MultiEffect](https://doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html): `maskEnabled` with a
  layered `maskSource` cuts the photo to the disc; Qt 6.11 has no rounded-clip item, and Breeze's
  own avatar uses a compiled shader the theme's build has no compiler for.
- [Qt Virtual Keyboard's InputPanel](https://doc.qt.io/qt-6/qml-qtquick-virtualkeyboard-inputpanel.html)
  and KDE's Breeze login theme ([VirtualKeyboard.qml](https://invent.kde.org/plasma/plasma-workspace/-/raw/v6.7.5/lookandfeel/components/VirtualKeyboard.qml),
  [VirtualKeyboardLoader.qml](https://invent.kde.org/plasma/plasma-workspace/-/raw/v6.7.5/lookandfeel/components/VirtualKeyboardLoader.qml)):
  an `InputPanel` in the scene takes Qt's keyboard over; Breeze shows it only after its virtual
  keyboard button (`active: activated && InputMethod.visible`) and moves its content above it.
- [SDDM Configuration.h](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/common/Configuration.h)
  and [Greeter.cpp](https://raw.githubusercontent.com/sddm/sddm/v0.21.0/src/daemon/Greeter.cpp):
  `InputMethod` defaults to `qtvirtualkeyboard` and becomes the greeter's `QT_IM_MODULE`.
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

2026-10-21, the theme on a real boot in the release harness's Debian testing VM (sddm
0.21.0+git20260819, Xorg greeter, `InputMethod` at SDDM's default `qtvirtualkeyboard`, Qt 6.11.2 with
`qml6-module-qtquick-effects` and `qml6-module-qtquick-virtualkeyboard`), chosen by greeter-apply.sh:
the first boot showed Qt's keyboard window over the lower half of the screen and the card's photo
as a purple square. With `CircularMask.qml` and `VirtualKeyboard.qml` the whole board shows - round
photos on the card and the tiles, no keyboard until the accessibility button (reached with
Shift+Tab, opened with Space) puts Qt's keyboard along the bottom with the card above it; the
button closes it again. Choosing "Other user" (the photo removed, its mask destroyed, on the
greeter's threaded render loop) shows the prompt and takes typed text.
