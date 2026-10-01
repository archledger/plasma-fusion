# Part: lock screen (`org.plasmafusion.lockshell`)

The Plasma Fusion lock screen, built from the Lock board (`Lock.dc.html`, render `startup-3`) for the
idle screen and the Login board (`Login.dc.html`, render `startup-4`) for the unlock prompt. QML
only, no compiled code. It is a Plasma/Shell package that holds only `contents/lockscreen/`; every
other shell file falls back to `org.kde.plasma.desktop`. It is selected for the lock screen alone,
through `PLASMA_DEFAULT_SHELL` in KWin's environment, so plasmashell and its layout are untouched.

## What it looks like

**Idle** (Lock board; before any key press or pointer movement):

| Element | Board value | Implementation |
|---|---|---|
| Wallpaper | the lock wallpaper under `rgba(8,10,22,.22)` | greeter's `wallpaper` item + dim (`Backdrop.qml`); bright wallpapers get up to +30 % dim (see deviations) |
| Date | Manrope 20 px / 700, `#e8ebf4`, 92 px from the top | locale long date without the year (`Monday, 28 September` in en_GB) |
| Clock | Space Grotesk 148 px / 600, letter-spacing −0.02 em, line-height 1, text-shadow `0 2px 20px rgba(0,0,0,.35)` | `BigClock.qml`; 12-hour locales show AM/PM at 44 px beside it; both in proportion to the screen, `148 × clamp(min(W/1440, H/900), 0.7, 1.4)` (ADAPTIVE 5.10) |
| Hint pill | 320 × 48, radius 24, glass `rgba(14,18,34,.55)` + blur 24, 1 px `rgba(255,255,255,.14)`, 18 px lock icon, 14 px / 700 | `UnlockHint.qml` at 430/900 of the height |
| Notification cards | 400 × 56, radius 16, glass `.6`, 1 px `.1`, 8 px apart, 30 px app icon, name 800, 12 px `#b8bfd3` line, 11.5 px `#a3abc2` time | `NotificationCards.qml` at 620/900; one card per application, newest first, up to 3 (fewer when space is short) |
| Media card | 300 × 72 at 32/32, radius 18, 44 px icon, title 800, `Paused`, 38 px `#e8ebf4` play button | `MediaControls.qml` (MPRIS); album art or the player's icon; previous/next appear (card 348 px) when the player offers them |
| Status chip | 40 px at 32/32 right, radius 20, 14 px gaps: `EN` badge (11 px / 800, 1 px `.25` border, radius 5), Wi-Fi 17 px, battery 19 px + `82%` 700 | `StatusChip.qml`: keyboard layout (click/scroll switches when there are several), virtual keyboard toggle (only when KWin has an input method), plasma-nm connection state, battery with charge fill, bolt when plugged in, amber ≤ 30 %, red ≤ 10 % |

**Prompt** (after a key press, click or pointer movement; Login board styling). It comes in over 300 ms
(decelerating) and goes in 200 ms, both from the Motion tokens (Plasma's animation speed; reduced motion
switches at once). The first key goes into the password field and shows the prompt:

| Element | Board value | Implementation |
|---|---|---|
| Wallpaper | blur 20 px, zoom 1.08, `rgba(8,11,24,.5)` | one 1/8-size copy of the wallpaper, blurred once into a cached layer (`MultiEffect`, the look of the earlier FastBlur 72, radius in proportion to the screen) and cross-faded in with the 8 % zoom (EFFECTS 6.4); the dim is the board's 50 % on the dark wallpaper and rises for bright wallpapers until the backdrop is as dark as the board's (at most 90 %) |
| Clock | top left 32/28: Space Grotesk 28 px / 600 + date 14 px / 700 `#cdd3e4` on one baseline, 12 px apart | `SmallClock.qml` |
| Avatar | 112 px, `#7b5cd6`, first letter Space Grotesk 46 px / 700, 4 px `rgba(255,255,255,.14)` ring, shadow `0 20px 50px rgba(0,0,0,.4)` | `UserHeader.qml`; the account picture (`kscreenlocker_userImage`) replaces the letter when set |
| Name | Space Grotesk 28 px / 600 | full name, or the login name when there is none (no placeholder names) |
| Password pill | 340 × 48 (y 396 on the 900 px board), radius 24, `rgba(255,255,255,.1)`, 1.5 px `#5b9dff` + 4 px `rgba(91,157,255,.2)` halo when focused, bullets 16 px 0.2 em apart, 36 px reveal button `#cdd3e4`, 36 px `#2f6fdf` unlock button | `MainBlock.qml` + `PasswordField.qml`; the blues follow the user's accent (decision 3) |
| Hints | 12 px, 8 px inset: `Caps Lock is on` `#f2c38a` with arrow icon (left), `Use fingerprint` `#8ab8ff` 700 (right) | Caps Lock from `KeyState`; the fingerprint (and smartcard) hint only while that authenticator is available; once pam_fprintd sends its instruction (`noninteractiveInfo`, e.g. `Place your finger on …`) that text replaces `Use fingerprint`; its error text replaces it for a moment |
| PAM messages | (not on the board) | 13 px / 600 lines under the hints: prompts, info and errors of the PAM stack, including irlume face messages (`irlume: …`) and `Unlocking failed` |
| Power buttons | 44 px glass circles, 18 px icons, 11.5 px / 700 `#cdd3e4` labels, 18 px apart, 28 px above the edge | Sleep, Hibernate, Switch User (each only when the system allows it), bottom centre |

Notification cards, media card and status chip stay in the prompt state. Keyboard: Tab reaches the
reveal and unlock buttons, the power buttons, the layout badge, the virtual keyboard button and the
media buttons; focused controls get the Controls board's dark-scheme focus ring (2 px `#8ab8ff`, 2 px outside; a user
accent gets its own lighter shade). Screen readers hear every PAM message as it arrives (face and fingerprint
guidance, errors; `Accessible.announce`), and the full screen is named "Lock screen". Alt+P,
Alt+H, Alt+U keep the stock mnemonics. Escape hides the prompt and clears the password.

## Authentication contract (unchanged from Plasma 6.7.5)

`LockScreenUi.qml` keeps every handler, timer and call of the stock
`/usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml`:

* `authenticator` (PamAuthenticators): `onFailed(kind)` (only `kind == 0` shows `Unlocking failed`,
  starts the 3 s grace timer and the reject animation), `onSucceeded` (`Qt.quit()` only when
  `hadPrompt`, otherwise the explicit Unlock screen `NoPasswordUnlock.qml`), `onInfoMessageChanged`,
  `onErrorMessageChanged`, `onPromptChanged` (all into the message area through the stock
  `handleMessage` with repeat bounce), `onPromptForSecretChanged` (focus the field, hide the text),
  `respond(password)`, `startAuthenticating()` on every `uiVisible` change and after the grace
  timer; `noninteractiveError` and `noninteractiveInfo` for the fingerprint and smartcard hints
  (the stock lock screen ignores `noninteractiveInfo`; here pam_fprintd's instruction is shown).
* The unlock button and Return submit an **empty** field too: pam_irlume's `ondemand` mode starts a
  face attempt on an empty response (irlume `docs/DESKTOP-AUTH.md`).
* Wake rules (`onPressed`, second `onPositionChanged`, any key), `blockUI`, 10 s fade-out,
  3 s message removal, launch fade, blank cursor while idle, Escape handling.
* Root item: `viewVisible`, `notification`, `clearPassword()`, `notificationRepeated()`; OSD item
  `objectName: "onScreenDisplay"` (stock `LockOsd.qml`, unchanged); `PasswordSync` singleton for
  several screens; `VirtualKeyboardLoader` with `visibleBoundary`; `SessionManagement`
  (`onAboutToSuspend` clears the password); password field without undo, Ctrl+Shift+U clears,
  sensitive input-method hints, reveal only when `KAuthorized` allows `lineedit_reveal_password`.
* A QML load error still falls back to kscreenlocker's built-in lock screen (greeter behaviour);
  the package can never unlock without authentication (the greeter checks `isUnlocked()` on quit).

## Files

| Path | Purpose |
|---|---|
| `packages/lockscreen/org.plasmafusion.lockshell/metadata.json` | Plasma/Shell, API version 2, `X-Plasma-FallbackPackage: org.kde.plasma.desktop` |
| `…/contents/lockscreen/LockScreen.qml` | root (stock interface) |
| `…/LockScreenUi.qml` | behaviour (stock) + layout of both states |
| `…/MainBlock.qml`, `PasswordField.qml`, `UserHeader.qml`, `NoPasswordUnlock.qml` | the prompt |
| `…/BigClock.qml`, `SmallClock.qml`, `UnlockHint.qml` | clocks and hint pill |
| `…/NotificationCards.qml`, `LockNotifications.qml` (singleton) | notifications while locked (`WatchedNotificationsModel`, grouped per app) |
| `…/MediaControls.qml`, `StatusChip.qml`, `NetworkIndicator.qml` (loaded on demand, so a system without plasma-nm still locks) | bottom corners |
| `…/Backdrop.qml`, `GlassPanel.qml` | wallpaper blur/dim/zoom, frosted surfaces (blurred wallpaper through `Kirigami.ShadowedTexture`) |
| `…/PowerButton.qml`, `RoundButton.qml`, `FocusRing.qml`, `LineIcon.qml`, `PfStyle.qml` (singleton: colours, fonts, the boards' 24 px line-icon paths, date/time helpers; the accent from `FusionAccent`) | building blocks |
| `FusionMetrics.qml`, `Motion.qml`, `FusionAccent.qml`, `FusionTablet.qml` (installed copies of `packages/common/`, `tools/build-lib/shared-qml.sh`) | text scale, motion tokens, accent, KWin's tablet posture |
| `…/LockOsd.qml`, `PasswordSync.qml`, `qmldir` | stock |
| `…/config.xml`, `config.qml` | settings (below) |
| `packages/lockscreen/test/` | offscreen harness (`run.sh`: a private bus without service activation, `session-bus.conf`), mock authenticator and `org.kde.kscreenlocker` enum, mock MPRIS / notification server, `scenario-greeter.sh` (real greeter in a virtual session; usage in its header) (not installed) |
| `tools/build.d/90-lockscreen.sh` | validates metadata, required files and config.xml; installs into `$STAGE/.local/share/plasma/shells/org.plasmafusion.lockshell/` (31 files) |
| `tools/device/lockscreen-enable.sh`, `lockscreen-disable.sh` | select / deselect it for the user |

## Install and enable

1. Install the build (the package sits at `~/.local/share/plasma/shells/org.plasmafusion.lockshell/`).
   It is inert until enabled.
2. Enable, in the user's session:

   ```
   tools/device/lockscreen-enable.sh            # writes the drop-in, systemctl --user daemon-reload
   tools/device/lockscreen-enable.sh --check    # installed? enabled? active in the running KWin?
   tools/device/lockscreen-enable.sh --dry-run
   ```

   It writes `~/.config/systemd/user/plasma-kwin_wayland.service.d/plasma-fusion-lockscreen.conf`:

   ```
   [Service]
   Environment=PLASMA_DEFAULT_SHELL=org.plasmafusion.lockshell
   ```

   and prints that a re-login is needed. It refuses when the package is not installed and warns
   when `plasmashellrc [Shell] ShellPackage` is set (that key would take precedence).
3. Log out and back in. Disable with `tools/device/lockscreen-disable.sh [--remove-package]`
   (removes the drop-in, re-login again). `tools/device/backup-profile.sh` already saves that
   drop-in directory.
4. Emergency: if the lock screen ever misbehaves, `loginctl unlock-session <id>` from a TTY or SSH.

Why this works (kscreenlocker/KWin 6.7.5 sources): `ShellIntegration::defaultShell()` reads
`plasmashellrc [Shell] ShellPackage` with `$PLASMA_DEFAULT_SHELL` as default; KWin passes its own
start-up environment to the greeter (`wayland_server.cpp` → `KSldApp::setGreeterEnvironment`,
`ksldapp.cpp` `startLockProcess`); `kwin_wayland_wrapper` starts `kwin_wayland` with the unit's
environment. plasmashell reads the variable only from its own unit, so it keeps
`org.kde.plasma.desktop`. Condition: nothing may write `plasmashellrc [Shell] ShellPackage`
(the Global Themes do not).

## Settings

`kscreenlockerrc [Greeter][LnF][General]` (config.xml). The first three are Plasma's own keys and
stay editable in System Settings > Screen Locking > Appearance (that page shows the stock form,
since System Settings does not run with the variable):

| Key | Default | Effect |
|---|---|---|
| `alwaysShowClock` | true | show the clocks |
| `hideClockWhenIdle` | false | clock only on the prompt |
| `showMediaControls` | true | media card |
| `showNotifications` | true | notification cards (when false the lock screen does not even register as a notification watcher) |
| `showNotificationSummaries` | false | show the newest notification's title on its card (bodies and actions are never shown) |

Example: `kwriteconfig6 --file kscreenlockerrc --group Greeter --group LnF --group General --key showNotificationSummaries true`.

The lock-screen wallpaper is kscreenlocker's own setting (`kscreenlockerrc [Greeter]
WallpaperPlugin`, `[Greeter][Wallpaper][org.kde.image][General] Image=`), see "Needs".

## Verification

* `qmllint` (Qt 6.11.2) over all 24 QML files with the mock `org.kde.kscreenlocker` module: no
  warnings except the `i18n*()` context-object calls every KDE QML file has.
* `shellcheck` clean for the build and device scripts; `90-lockscreen.sh` run through `tools/build.sh`.
* Enable/disable scripts run in a sandbox HOME with a stub `systemctl` (the laptop's user manager
  was never touched): `--check`, `--dry-run`, enable, check, disable, refusal without the package.
* Offscreen harness on the laptop (`packages/lockscreen/test/harness.py`, PySide6, software scene
  graph, private D-Bus with a mock MPRIS player and a mock notification server that feeds the
  lock screen's watcher): idle, prompt with typed bullets, prompt with irlume-style PAM messages +
  Caps Lock + pam_fprintd instruction (`messages`), fingerprint mismatch (`fperror`), keyboard
  focus on the unlock button (`focus`), no-password Unlock screen, portrait 900 × 1440.
  `cd packages/lockscreen && QT_QPA_PLATFORM=offscreen dbus-run-session -- sh -c 'python3 test/mock_services.py mpris notify & m=$!; sleep 1; python3 test/harness.py OUT idle prompt messages fperror focus nopassword; kill $m'`
  (optional: `PF_WALLPAPER=<png>`, `PF_ICON_DIR=<stage>/.local/share/icons PF_ICON_THEME=PlasmaFusion-Dark`, `PF_SIZE=900x1440`, `PF_LOCALE=en_US`).
* ThinkPad, private virtual sessions `lk-1` … `lk-7` (`tools/vsession/remote.sh`, 1440 × 900,
  OpenGL on the Iris Xe), real `/usr/libexec/kscreenlocker_greet --testing` 6.7.5, PAM untouched,
  no password typed or submitted, each greeter run ≤ 40 s:
  * run 1 selects the package only through `PLASMA_DEFAULT_SHELL` (no `--shell`): loads, idle state;
  * run 2 wraps the same package in a test-only driver (private HOME only) that sets
    `uiVisible` after 7 s as a key press would: prompt state; the real PAM stack started;
  * run 3: en_US 12-hour clock with the light Plasma Fusion wallpaper (adaptive dim);
  * run 4: a nested headless `kwin_wayland --lockscreen` with `PLASMA_DEFAULT_SHELL` only in
    KWin's environment: the greeter KWin spawned (`--immediateLock`, not testing mode) loaded the
    package (log line from a test wrapper) — the enable mechanism works end to end.
  * Notifications were sent with `notify-send` to the session's plasmashell (with Do Not Disturb
    held so its pop-ups stay away); the cards came through `WatchedNotificationsModel`.
  * Greeter logs: no QML warnings or errors.
* Pixel comparison with the board renders (`pixel-compare-*.txt`): wallpaper, dims, glass fills,
  field, avatar, blur within 1–4 levels; date, clock, pill label, avatar letter, name and small
  clock ink boxes within 1–3 px; the clock `14:49` measures 359 px wide against the board's 363.

Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/lockscreen/`
(`greeter-idle-dark.png`, `greeter-prompt-dark.png`, `greeter-idle-light-wallpaper-12h.png`,
`side-by-side-idle-vs-lock-board.png`, `side-by-side-prompt-vs-login-board.png`,
`offscreen-prompt-pam-messages-capslock-fingerprint.png`, `offscreen-no-password-unlock.png`,
`offscreen-prompt-typed.png`, `offscreen-idle-software-rendering.png`,
`offscreen-portrait-900x1440-idle-and-prompt.png`, `greeter-and-envtest-log.txt`, pixel reports).

## Deviations from the boards

* The Lock board shows only the idle screen. The prompt follows the Login board (small clock top
  left, avatar, name, pill field, hints); it has no user row or session selector (a lock screen
  has one user; Switch User replaces them) and its power row offers the lock screen's actions
  (Sleep, Hibernate, Switch User) in the bottom centre, because the bottom corners hold the Lock
  board's media card and status chip. No Restart / Shut down: kscreenlocker offers none.
* Notification cards hide content by default: `New notification · hidden while locked` /
  `N new notifications · hidden while locked` (the board's Calendar card shows its text; that is the
  opt-in `showNotificationSummaries`, titles only). Only notifications that arrive after locking
  are known (WatchedNotificationsModel); the list is empty right after locking.
* `Use fingerprint` is a hint, not a link: kscreenlocker runs fingerprint authentication in parallel
  by itself. It appears only while the fingerprint authenticator is available (enrolled finger,
  active session), and pam_fprintd's own instruction (`Place your finger on …`) replaces it as soon
  as the module sends one, so the device's guidance stays visible.
* The prompt keeps the Lock board's bottom corners (media card, status chip with layout, network
  and battery) instead of the Login board's top-right status pills; there is no accessibility
  button (kscreenlocker offers no accessibility menu).
* A PAM message area (not on the boards) under the hints keeps fingerprint and irlume guidance and
  errors visible.
* 12-hour locales: `2:49` at 148 px with `PM` at 44 px (the board shows 24-hour time).
* The layout badge shows the layout's display name upper-cased; `EN` as on the board needs a
  label (`kxkbrc [Layout] DisplayNames=en,…`), otherwise it reads `US`.
* Status chip adds a virtual-keyboard button when KWin has an input method (the X13 Yoga in tablet
  mode); media card adds previous/next (348 px wide) when the player offers them.
* Bright wallpapers get up to 30 % extra dim while idle (measured from a 32 × 20 grab of the
  wallpaper's upper half when the wallpaper is ready, when it changes and when the prompt opens;
  no timer while locked) so the white clock
  stays readable, and up to 90 % dim behind the prompt so the Login board's white text and
  `#8f98b3` placeholder keep their contrast; the dark wallpaper keeps the boards' 22 % and 50 %.
* Software rendering (no OpenGL): no blur, glass fills 18 % more opaque, no text shadow.
* Qt's hinted text carries about 6 % more ink than the browser render of the board (measured on
  the pill label after the synthetic-bold fix in Review; it was 40 % before).
* The avatar colour is the board's `#7b5cd6` for every account; account pictures are used when set.

## Needs from other parts

* **Look-and-feel / device apply (`fusion-config.sh`, `fusion-restore.sh`)**: run
  `tools/device/lockscreen-enable.sh` when applying Plasma Fusion and
  `tools/device/lockscreen-disable.sh` when restoring; set the lock-screen wallpaper, for example
  `kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image` and
  `kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$HOME/.local/share/wallpapers/PlasmaFusion/"`
  (the dark images are the Lock board's); never write `plasmashellrc [Shell] ShellPackage`.
* **Foundation**: Manrope and Space Grotesk installed for the user (already done by `10-foundation.sh`).
* **Icons**: application icons for notification senders and media players (the PlasmaFusion
  themes already have Elisa, KMail, Merkuro, …).
* Optional: `kxkbrc DisplayNames=en` for the board's `EN` badge.

## Maintenance

LockScreenUi/MainBlock/MediaControls/NoPasswordUnlock are visual forks of Plasma 6.7.5's
lockscreen. After every Plasma feature release, diff
`/usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/` against 6.7.5 and carry over
contract changes (authenticator API, root properties, OSD, virtual keyboard), then re-run the
harness and a `kscreenlocker_greet --testing --shell <path>` check in a virtual session.

## Review (2026-09-29)

Adversarial review of the part as built, against the Lock and Login boards (source values and
renders), the 6.7.5 lock-screen QML, kscreenlocker/KWin sources and the ThinkPad's PAM stack.

### What was checked

* Build: `STAGE=<own stage> tools/build.sh` with every part (all 12 build scripts pass; the
  lockscreen installs 27 files); metadata, config.xml, shellcheck of the three scripts, qmllint
  (43 warnings, all `i18n*()` / KCM `parentLayout` context lookups, as before).
* Contract: every handler, timer and call of the stock `LockScreenUi.qml` / `MainBlock.qml` is
  present; `PamAuthenticators` signals in kscreenlocker 6.7.5 (`failed`, `succeeded`,
  `noninteractiveError`, `noninteractiveInfo`, `loginFailedDelayStarted`, prompt/info/error);
  the ThinkPad's `/etc/pam.d/kde` (`pam_irlume.so unseal ondemand` before `password-auth`) and
  `kde-fingerprint` (read only): irlume's `Password: ` probe is a secret prompt (focus only, as in
  stock), its `irlume: …` messages are interactive info/errors (message area), pam_fprintd talks
  through the noninteractive fingerprint authenticator.
* Enable route: `PLASMA_DEFAULT_SHELL` is read by kscreenlocker's `ShellIntegration::defaultShell()`
  and also by plasmashell's `ShellCorona::defaultShell()`; KWin passes its start-up environment to
  the greeter, Xwayland session scripts and helper dialogs only. `/etc/xdg/Xwayland-session.d`
  (at-spi, ibus-x11) exports nothing to the systemd/D-Bus activation environment, so plasmashell
  keeps `org.kde.plasma.desktop`. The ThinkPad session is systemd-started (`plasma-kwin_wayland.service`,
  main process `kwin_wayland_wrapper`), no `plasmashellrc [Shell] ShellPackage`.
* Integrated test: all parts built into one stage, private virtual sessions `rlk-1` … `rlk-8` on
  the ThinkPad (1440 × 900, OpenGL on the Iris Xe, blur), real `/usr/libexec/kscreenlocker_greet
  --testing` selected only through `PLASMA_DEFAULT_SHELL`, Plasma Fusion Dark (en_GB, layout label
  `en`) and Plasma Fusion Light (en_US, 12-hour, layout `us`) colour schemes, icons and Plasma
  style, lock wallpaper `PlasmaFusion`, MPRIS mock, notifications through the session's own
  plasmashell (`notify-send`, Do Not Disturb held). The prompt was shown by a test-only copy of
  the package in the private HOME that sets `uiVisible` after 5 s; nothing was typed or
  submitted; each greeter ran ≤ 12 s and none was left. Greeter logs: no QML warning (the driver's
  own `console.warn` line shows that warnings do reach the log).
  Reproduce with `packages/lockscreen/test/scenario-greeter.sh` (seed steps in its header).
* Offscreen harness (laptop): idle, prompt, messages, fperror, focus, nopassword — no QML errors.

### Fixed

| Severity | Finding | Fix |
|---|---|---|
| high | Every 700/800 text (date, pill label, card and media titles, power labels, status chip, fingerprint hint, small-clock date, avatar letter) rendered far heavier than the boards: both fonts are variable fonts with a light default instance, and Qt's FreeType engine synthesises bold on top of the named instance for any weight ≥ 700 below 64 px. Measured: `Font.Bold` 20 px Manrope carries more ink than the real ExtraBold; the pill label had 40 % more ink than the board. A fontconfig `embolden=false` rule does not help. | `font.weight: Font.DemiBold` + `font.styleName: PfStyle.bold / extraBold` (named instance, no synthesis; DemiBold is the fallback for other fonts). Pill label ink now +6 % (hinting), was +40 %. |
| high | Light scheme: behind the prompt the adaptive dim fell back to the board's 50 %, so the blurred light wallpaper stayed mid-grey: placeholder `#8f98b3` on the field 1.2:1 (board 4.6:1), date 2.9:1. | `Backdrop.promptDim`: 50 % on the dark wallpaper (unchanged), raised for bright wallpapers until the mean backdrop brightness reaches the Login board's (~0.11), at most 90 %. Light prompt now: placeholder 4.0:1, white text 16.6:1. First brightness probe at 0.4 s (was 1.5 s, visible flash). |
| medium | pam_fprintd's instruction (`PAM_TEXT_INFO` through the noninteractive authenticator, `noninteractiveInfo`) was never shown; only its errors were. | `FailableLabel` shows the authenticator's latest info text in place of `Use fingerprint` (cleared when the reader becomes unavailable); errors still replace it for a moment. Harness scenarios `messages` / `fperror`. |
| medium | Glass edges 20–35 levels brighter than the boards: Kirigami's bordered `ShadowedRectangle` leaves its fill out under the border, so the 10–14 % white edge sat straight on the blurred wallpaper (CSS draws the border over the background). | `GlassPanel` draws the fill without border and the edge as a separate rectangle over it; same for the power buttons and the password pill. |
| low | Focus ring used the accent `#5b9dff`; the Controls board's dark scheme uses `focus: #8ab8ff`. | `PfStyle.focusRing` `#8ab8ff`. |
| low | With `showNotifications=false` the lock screen still registered as a watcher with Plasma's notification server (the singleton was referenced unconditionally), so notification data still reached the greeter. | The singleton is referenced only when the cards are enabled; harness `PF_NOTIFICATIONS=0` shows no `RegisterWatcher`. |
| low | `lockscreen-enable.sh --check` reported "active: yes (the running KWin has it)" from the unit's `Environment=`, which changes on `daemon-reload` before any re-login. | Reads `/proc/<MainPID>/environ` of `plasma-kwin_wayland.service`; prints `unknown` when the unit is not running. Output format for `enabled:` unchanged (fusion-config.sh parses it). |

### Remains / notes

* Keyboard badge: KWin reports an empty short name when neither kxkbrc `LayoutList` nor
  `XKB_DEFAULT_LAYOUT` is set, and then the badge is hidden (graceful). The ThinkPad's KWin has
  `XKB_DEFAULT_LAYOUT=us`, so its lock screen shows `US`; `EN` needs `kxkbrc [Layout]
  DisplayNames=en` (optional, apply stage).
* The ThinkPad locale is en_US: 12-hour clock with a 44 px `PM` (review-greeter-idle-light-en_US.png).
* Live pam_fprintd / irlume messages on real hardware are still unobserved (the virtual session is
  not the active seat, so fprintd is unavailable; typing is not allowed). The message paths are
  covered by the harness.
* Killing the test greeter while PAM waits logs `QEventLoop: Cannot be used without
  QCoreApplication` from the PAM worker (teardown, not QML).
* The synthetic-bold problem affects every Qt text in Plasma Fusion that asks for Manrope or
  Space Grotesk at weight ≥ 700 below 64 px (reported to the lead for the other parts).

Evidence (`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-build/lockscreen/`):
`review-greeter-{idle,prompt}-dark.png`, `review-greeter-{idle,prompt}-light-en_US.png`,
`review-side-by-side-idle-vs-lock-board.png`, `review-side-by-side-prompt-vs-login-board.png`,
`review-text-weight-board-before-after.png`, `review-glass-edges-board-before-after.png`,
`review-light-prompt-before-after.png`, `review-offscreen-fingerprint-info-error-focus.png`,
`review-greeter-log-{dark,light}.txt`.

## Polish (2026-09-29)

See `docs/parts/polish.md`. No functional change: the `DemiBold` + style name approach picks the
right static files (Bold, ExtraBold, and Space Grotesk's new SemiBold file for the clocks); the
comment in `PfStyle.qml` now says so.

## LOCK-1 (2026-09-30)

Work package LOCK-1 of the one-pass plan (`/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-decisions/PLAN.md`;
EFFECTS 6.4, ADAPTIVE 5.10, TABLET 4.13, GAPS G23 and G25, BACKLOG S1), built by the lead directly.
Every PAM prompt and message path is as it was; `/etc/pam.d` was not touched.

### Changes

- **Backdrop** (`Backdrop.qml`): the greeter keeps drawing its wallpaper item underneath (z −1000).
  Both `FastBlur`s (Qt5Compat) are gone. One `ShaderEffectSource` (`live: false`, 1/8 of the
  screen's device pixels) copies the wallpaper when it is ready, when it changes (the image
  plugin's signals) and when the prompt opens; `MultiEffect` blurs it once at that size into a
  cached layer, which is drawn scaled up with smooth filtering and cross-faded in (`opacity` =
  prompt factor, the 8 % zoom as `scale`). The glass panels' `glassSource` is the same layer. The
  radius is the board's 72 px in proportion to `min(W, H)/900`, times 1.6 because `MultiEffect`
  blurs less than FastBlur for the same number (measured: sun edge 10–90 % 79–86 device px against
  FastBlur's 88–93). The brightness probe runs on the same events, never on a timer (G23).
- **Motion** (`LockScreenUi.qml`, S1): the prompt comes in over `scaled(surface, 1.2)` = 300 ms with the
  decelerate curve and goes in `popupIn` = 200 ms with the exit easing; the launch fade uses the
  300 ms token; the dim follows a new wallpaper with `surface`; power-button press scale from
  `pressScale`. All follow Plasma's animation speed; reduced motion switches at once.
- **First key**: the password field keeps the keyboard focus while the prompt is hidden, so the
  first key goes straight into it and the root's key handler never sees it. The prompt used to
  appear only because of `blockUI`, which needs a pointer resting over the screen; with no pointer
  there (touch-only tablet posture, a pointer on another screen) typing filled a hidden field. The
  stock 6.7.5 lock screen has the same handler. Now any typed text shows the prompt, and each key
  restarts its 10 s fade-out timer.
- **Proportional sizes** (ADAPTIVE 5.10): the big clock and AM/PM `× clamp(min(W/1440, H/900), 0.7, 1.4)`;
  prompt and notification width `min(400 × text scale, W − 64)` as before; blur radius above.
- **Tablet posture** (TABLET 4.13): `FusionTablet` (KWin's `TabletModeManager` over D-Bus, Kirigami
  until KWin answers) drives `FusionMetrics.tablet`. In tablet posture: the avatar, name and pill
  are centred at 38 % of the height (a third in portrait) and messages hang below without moving
  them; the pill is at least 48 px tall and at least 400 px wide (`W − 64` at most); its reveal and
  unlock buttons 44 px; power buttons 48 px; the status chip 48 px with a 48 px keyboard button.
  Independent of posture, the on-screen keyboard (the stock `VirtualKeyboardLoader`) now keeps
  the whole prompt, messages included, 24 px above it (`visibleBoundary`).
- **Accent** (decision 3): `PfStyle` takes the focus border, halo, unlock button, focus rings and
  the fingerprint hint from a `FusionAccent` on the lock screen (always the dark variant); the
  board's exact blues stay while the colour scheme's own Plasma Fusion blue is in effect.
- **Screen readers** (G25): every message `handleMessage()` receives (PAM prompts, info and errors,
  irlume face lines, `Unlocking failed`) and the fingerprint/smartcard authenticators' info and
  errors are announced (`Accessible.announce`, errors assertive) from the full-screen item, which is
  always visible, so they are heard with the prompt hidden too. The full-screen item is named
  "Lock screen" with the unlock hint as description.
- **Tooling**: `tools/checks/motion-lint.sh` accepts `motion.scaled(token, ratio)` and numbers in a
  comparison (fixture cases added); the harness installs the shared blocks through
  `shared-qml.sh`, reads the Plasma Fusion colour scheme through `kdeglobals` (`PF_SCHEME`,
  `PF_ACCENT=#rrggbb` for a user accent) and has two new scenarios, `timing` and `tablet`.

### Verification

- Offscreen harness (`test/run.sh OUT idle prompt messages fperror focus nopassword`): all states
  render, no QML warnings; red accent (`PF_ACCENT=#e0484e`): unlock button, focus ring and hint
  follow; portrait 900 × 1440 tablet and 2560 × 1600 idle; dark and light wallpaper at 4/3 and 1.325
  (`QT_SCALE_FACTOR`, 1920 × 1200 device pixels).
- T13 (`KDE_KIRIGAMI_TABLET_MODE=1 test/run.sh OUT tablet`) at 1440 × 900, 900 × 1440 and 1366 × 768:
  9/9 checks each: block centre within 0.5 px of 38 % (one third in portrait), pill 400 × 48,
  44 px pill buttons, 48 px power and keyboard buttons, and with the keyboard shown (450, 281 and
  427 px) the prompt bottom 24 px above it (at 1366 × 768 the prompt moves up 114 px).
- GPU A/B on the ThinkPad (private Wayland session 1920 × 1200 at 4/3, harness `timing` scenario full
  screen, mock authenticator, two rounds each, HEAD 024570a against this tree):

  | | HEAD | LOCK-1 |
  |---|---|---|
  | first key shows the prompt (no pointer over the screen) | no | yes |
  | first key echoed in the field | 5–7 ms | 8–11 ms |
  | reveal | 771–789 ms, 47–48 frames, 150–154 ms GPU | 292–310 ms, 18–19 frames, 49 ms GPU |
  | hide | 763–787 ms, 47–48 frames, 150–153 ms GPU | 173–188 ms, 11–12 frames, 30–31 ms GPU |
  | idle, 5 s (after start) | 11–13 frames, 31–37 ms GPU | 9–10 frames, 17–19 ms GPU |
  | prompt shown, 3 s (cursor blink) | 9–10 frames, 25.6 ms GPU | 9–10 frames, 20.8–21.0 ms GPU |

  (HEAD's prompt was opened by the harness after 0.5 s, as a click would, to compare the reveal.)
- Real greeter (`test/scenario-greeter.sh`, `kscreenlocker_greet --testing` 6.7.5 in private sessions
  `lk-gdark` and `lk-glight`, 1440 x 900, OpenGL, the package through `PLASMA_DEFAULT_SHELL`, PAM
  untouched, nothing typed): idle and prompt render in both themes with the cached blur and the
  board's blues from the real colour scheme; greeter logs without QML warnings.
- `motion-lint`: lock screen 0 findings (HEAD 3); `a11y-lint`: 0 (HEAD 1); qmllint (Qt 6.11.2, mock
  `org.kde.kscreenlocker`): only the `i18n*()` context-object warnings every KDE QML file has, plus the
  pre-existing `twinFormLayouts` one in `config.qml`; `90-lockscreen.sh` installs 31 files.

Not covered here (DEPLOY-1 hand check H8, a ship blocker): unlocking by typing on the real
on-screen keyboard in tablet posture, by fingerprint and by face; Orca reading the announcements.
Evidence: `/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-30-build2/LOCK-1/`.

## On-screen keyboard in tablet posture (TABLET2 P0, 2026-09-30)

DEPLOY-1 hand check H8 (unlocking by typing on the on-screen keyboard in tablet posture) could not
pass on Plasma 6.7.5. KWin hides the on-screen keyboard when the screen locks and shows it again
only when a text field asks for it after touch or pen input (`VirtualKeyboardMode` "non-mouse
input"). After locking with a key (Meta+L, the power button) the password field already has the
focus, so a finger tap never asked again. The stock keyboard button on the lock screen only moves
the layout on Wayland; it never asks KWin. Plasma 6.8 changes this upstream; until then:

- `LockScreenUi.qml`: `showKeyboard()` calls `forceActivate` on KWin's `org.kde.kwin.VirtualKeyboard`
  (`org.kde.plasma.workspace.dbus`, Wayland only, and only while KWin has an input method;
  Plasma Fusion sets one only in tablet posture). `forceActivate` shows the keyboard whatever the
  last input was, so only touch and pen call it: a `PointHandler` (touch screen and stylus) on the
  full-screen item, for the first tap while the prompt is hidden in tablet posture, which focuses
  the field and shows the keyboard; and the password field's new `touched()` signal. A mouse click
  shows the prompt without the keyboard. The keyboard button now shows or hides KWin's keyboard,
  and Escape hides it (`hideKeyboard()`, KWin's `active` property).
- In tablet posture the prompt stays up while text is typed or the keyboard is shown (`blockUI` no
  longer needs a hovering pointer, which a finger is not), and a lifted finger no longer counts
  as the pointer leaving (`onExited`).

### Verification

Private Wayland sessions on the ThinkPad (1920 × 1200 at 4/3, `PFV_LOCK=1`, the real 6.7.5 greeter,
KWin started with `PLASMA_DEFAULT_SHELL=org.plasmafusion.lockshell`, emulated touch through EIS,
nothing typed), in tablet posture, locked after a key press:

| | before (`lk10-old`) | after (`lk11`, `lk12`; `lk10-new` ran a first version) |
|---|---|---|
| first finger tap on the background | prompt, no keyboard | prompt and keyboard |
| second tap | no keyboard | keyboard stays |
| mouse click | | prompt, no keyboard |
| finger on the password field | | keyboard |
| 12 s with the keyboard shown | | prompt and keyboard stay |
| Escape | | keyboard hidden (the locker turns the screen off) |
| finger on the keyboard button | | keyboard |
| laptop posture, finger tap | | prompt, no keyboard (no input method) |

Emulated touch reaches the greeter only once its seat has touch: the test touchscreen exists only
while `pfinput` is connected, so the scenarios wait 1 s after connecting (`sleep 1` before `tap`).
Offscreen harness (`test/run.sh OUT`): all states render, no QML warnings; qmllint warnings
unchanged (19). Hand check H8 on the ThinkPad remains, now expected to pass. Evidence:
`/mnt/archledger-gp/artifacts/plasma-fusion/2026-10-01-tablet2/P0/`.

## Tablet posture: swipe up to unlock (TABLET2 L1, 2026-10-01)

Owner decision "phone-style lock screen" (TABLET2 section 0/3.5) and research round 2 (E-phone 4.3:
lock-screen actions need a deliberate gesture after iOS pocket-trigger complaints; notification
privacy). Laptop posture is unchanged.

- **Idle** (tablet posture): the big clock and date, the notification cards (app, count and time only;
  titles stay opt-in, `showNotificationSummaries` false, bodies never shown), media and status at the
  bottom corners, and **"Swipe up to unlock"** near the bottom (44 px above it) over a 120 x 5 home-pill
  handle, as on a phone.
- **A finger or pen tap** only nudges the hint (scale 1.06 and back, Motion press/toggle); it no
  longer raises the prompt and the on-screen keyboard (P0 did that on any tap), so touches in a bag
  stay harmless. Taps on the media buttons still work.
- **A swipe up** (96 px or 800 px/s; touch or pen; anywhere) shows the prompt; the clock and the hint
  follow the finger while it moves. The on-screen keyboard is requested when the prompt is 30 % in: a
  request while the field is still hidden got no keyboard from KWin (session l1a).
- **Hardware keys** show the prompt as before (no on-screen keyboard); biometrics are unaffected; the
  password field's own tap still asks for the keyboard (P0).
- **Pointer moves** count in tablet posture only when the pointer travels more than 8 px: Qt
  synthesises mouse moves around a touch (ignored for 600 ms around touch presses and releases), and
  KWin sends a pointer event at the screen centre when an input device is added (session l1d: the
  prompt came up before every test gesture). A mouse used in tablet posture still shows the prompt.

Tests: the offscreen harness's `tablet` scenario now checks the idle state first (hint text, 40-120 px
above the bottom, handle 120 x 5 at the bottom, prompt hidden; `tablet-idle.png`): 13/13 at 1440x900
and 900x1440. Private locked sessions (`build/l1/scen-l1.sh`, l1e/l1f; evidence
`artifacts/plasma-fusion/2026-10-01-tablet2/L1/`): tap and a 40 px swipe keep the idle screen and no
keyboard; a 260 px swipe shows the prompt with the keyboard (KWin `VirtualKeyboard.visible` true);
Escape blanks the screen as before; after waking, a hardware key shows the prompt with the typed
character and no keyboard; laptop posture: a click shows the prompt. **H8 hand check update**: in
tablet posture swipe up first, then type on the on-screen keyboard.
