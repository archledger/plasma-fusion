<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Changelog

Newest first. Each release lists the Plasma series it was tested with and the systems it supports.

## Unreleased

- The clock calendar gains selected-day events, event dots, calendar-provider/resource settings,
  Open calendar and a native KOrganizer Add event action. Calendar apps continue to own sync,
  recurrence and reminders; the date grid remains usable without them.
- Quick Settings adds microphone/input volume and mute, input-device selection, and independent
  application playback/recording volume, mute and device routing in the Sound page.
- The clock offers optional seconds and searchable world-clock time zones, shown with their local
  dates in the calendar popup; the panel's system time zone remains unchanged.
- Quick Settings gains a **Keep awake** switch to manually block sleep and automatic screen
  locking until turned off. A coffee-cup indicator stays visible in the status pill while active;
  configured timeouts and other applications' inhibitors are preserved.
  Its chevron opens **Sleep blockers**: the applications blocking sleep or screen locking, their
  reasons, and a box to block or allow each request.
- **Disks & Devices** is back in the bar: while a USB drive, memory card, camera or phone is
  connected, a drive icon shows in the status pill and Quick Settings has a Disks & Devices tile and
  page to open, mount or safely remove it, with free space and the reason when removing fails. A
  new device opens the page, as Plasma's own Disks & Devices does (an option in the widget's
  settings). Before, the stock item was hidden and removable drives were not reachable from the bar.
- Quick Settings adds a **Wi‑Fi hotspot** tile on Plasma's own hotspot (the Networks applet's
  settings). It says why when the radio can't host one, for example when the only Wi‑Fi radio
  carries the connection; the Wi‑Fi page starts and stops it and shows its name and password.
- The dock shows **window previews**: resting on a running app shows its windows with live
  thumbnails; click a preview to switch to that window, or close it from there. An option in the
  dock's settings turns them off.
- A dock app that plays sound shows a small speaker on its icon; click it to mute or unmute the app
  (also **Mute** in its menu).
- The dock's app menu adds what Plasma's task manager offers: the app's own actions (such as
  Firefox's New Private Window), its **Recent Files**, **Move to Desktop**, **Show in Activities**
  and **More** window actions (Keep Above Others, Fullscreen, No Titlebar and Frame...). The
  launcher's item menu can **Keep in Dock** an app.
- Choosing an entry in the launcher's right-click menu (Pin, Unpin, an app's actions) did nothing;
  it now runs.
- With more than one screen, every screen's top bar now has the status icons, the bell and Quick
  Settings, not only the main one. Meta+A and a newly connected drive open Quick Settings on the
  screen you are using, and its settings are the same on every screen. Existing top bars on other
  screens get them at the next login; a status icon you remove from them stays removed.
- Switching off "Top bar on every screen" in the Plasma Fusion settings now lasts: before, the bars
  came back at the next screen change.
- The touch-gestures card closes when tablet mode ends before it was dismissed (it shows again the
  next time) instead of staying over the laptop desktop.
- On the tablet home screen, files on the desktop no longer show among the apps: the desktop's
  file layer stayed loaded after the first start. A file dropped there now offers widgets, as on a
  desktop without icons.
- Quick Settings keeps a volume set above 100 %: one scroll step on the status pill no longer
  lowers it to 100 %. With Plasma's "Raise maximum volume" the volume sliders now reach 150 %.
- Quick Settings' Wi‑Fi page has an **Airplane mode** switch, as Plasma's Networks widget: it turns
  Wi‑Fi, mobile data and Bluetooth off and back on.
- The keyboard layout badge in the top bar lists the layouts on right-click (or press and hold) to
  choose one, and the mouse wheel switches through them, as Plasma's Keyboard Layout widget.
- The launcher's account row opens a menu with Account Settings, **Switch User** and **Log Out**;
  where the computer can hibernate, the Sleep button's menu offers **Hibernate**.
- The Power mode tile explains itself as Plasma's Power and Battery widget: it skips Performance
  while the system holds it back (on a lap, too hot) and says why, names applications that requested
  a mode, and shows when a switch was refused.
- Quick Settings has a **Brightness** page (the chevron next to the brightness slider) with a
  slider for every display that can be dimmed and the **keyboard backlight**, as Plasma's Brightness
  widget.
- Quick Settings' Sound page has a menu on each device (the "⋯" button or right-click) to choose its
  **port** (speakers, headphones) and the sound card's **profile** (HDMI, analog, Pro Audio), as
  Plasma's Audio Volume widget.
- The media card in Quick Settings has a **seek bar** with the track's time and, when several
  players run, a row of the players to **choose one**, as Plasma's Media Player widget.

## 0.3.1 (2026-10-06)

Tested with Plasma 6.7 (6.7.5) and the Plasma 6.8 beta (6.7.91 on Fedora 44 and Arch), like 0.3.0.

- Snapped windows fill the work-area edges instead of leaving desktop strips around them. The
  configured gap remains between neighbouring windows, including the Meta+Z thirds and rows.
- The Calendar tiles' live date no longer stays on yesterday's date after the computer wakes from
  suspend: the midnight timer re-arms in short steps instead of one long interval (Qt timers pause
  across suspend). The launcher tile now also only keeps a timer while a Calendar tile needs one.

## 0.3.0 (2026-10-06)

Tested with Plasma 6.7 (6.7.5) and the Plasma 6.8 beta (6.7.91 on Fedora 44 and Arch).
Plasma 6.8 support comes from that beta testing; anything Plasma 6.8.0 final needs will
come in a follow-up release.

- The greeter's wallpaper can match the lock screen's treatment (`greeter-apply.sh --login-image
  dimmed`); the other choices are the Login board's blur with its veil (the default) and the same
  blur without it. The greeter's clock and layout stay compiled into plasma-login-greeter.
- The Plasma Fusion settings module gains an Icons section (Designed tiles / Real app icons) and a
  Lock & Login section (notification cards and titles on the lock screen). High contrast now reaches
  applications that follow the XDG settings portal, and the generated reference palette kits
  (`docs/parts/consistency.md`) let apps built on other toolkits match the theme.
- The live date patch on the Calendar tiles no longer shows as a seam: it paints the tile art's
  own colours. The launcher shows Merkuro Calendar's live date again (its app list had a typo),
  and GNOME Calendar keeps its own tile art: the patch only covers tiles that carry the art's
  fixed SEP 28.
- The dock shows one tile per app: on a system without a web browser, the Browser pin
  (`preferred://browser`) resolves to whatever handles HTML's `text/plain` parent type (Kate on a
  minimal install) and the dock showed two identical Kate tiles. A `preferred://` pin that
  resolves to an app pinned explicitly is hidden while the explicit pin stays; it reappears once
  the system has a real app for the role.
- Setup waits until plasmashell has finished redrawing before it restarts it: a shell stopped
  right after a live theme change could crash on exit while it still compiled the new theme's
  shaders (seen with Mesa's software renderer in virtual machines).
- On Arch, `install.sh uninstall` also removes the `plasma-fusion-debug` package that an AUR
  helper installs.
- Ready for Plasma 6.8 (tested with the 6.8 beta): menus and drop-down lists are readable in
  Plasma Fusion Light; the lock screen asks for the password even when the stock lock screen last
  unlocked another way; split screen from the home screen and the launcher works again; the dock's
  Meta+Alt+1..9 keys go through Plasma Fusion's own shortcuts; the tablet navigation starts from a
  defined state.
- The window decoration supports the shadow-only style of Plasma 6.8 when built against
  KDecoration 6.8: windows with the "Only shadow" window rule get the Plasma Fusion shadow and
  outline without a title bar, instead of falling back to the app's own decoration. Builds against
  Plasma 6.7 are unchanged.
- The log-out screen is Plasma Fusion's again on Plasma 6.8: 6.8's log-out greeter reads the
  log-out QML from the shell package, so the screen ships in the org.plasmafusion.lockshell shell
  package and the Plasma Fusion lock screen setup starts the greeter with that package through a
  per-user D-Bus service override. Plasma 6.7 is unchanged (its greeter reads the Global Theme).
- The launcher's Calendar tile shows today's month and day over the tile art (as the dock
  already did) instead of the art's fixed SEP 28.

## 0.2.0 (2026-10-03)

The first release. Tested with Plasma 6.7 (6.7.5 on Fedora 44, Arch, Ubuntu 26.10 and KDE neon,
6.7.4 on Debian testing).

- Packages for every system from one source and one version: `plasma-fusion` (themes, widgets,
  icons, fonts, KWin scripts, the setup tools) and the compiled window decoration, settings page and
  tablet navigation. Fedora 44 and 45: Copr `archledger/plasma-fusion`. Arch and derivatives: AUR
  `plasma-fusion`. Kubuntu / Ubuntu 26.10: `ppa:archledger/plasma-fusion`. KDE neon and Debian
  testing: the release's `.deb` packages. NixOS (unstable): the flake or the module.
- An installer for all of them: `curl -fsSL
  https://github.com/archledger/plasma-fusion/releases/latest/download/install.sh | sh`
  (docs/parts/installer.md). Release files are checked against the signed `SHA256SUMS`.
- The `plasma-fusion` command: `setup`, `update`, `status`, `restore`, `drop-user-copy`.
- The login check records only the tested Plasma series as tested: on a newer Plasma the parts
  that depend on Plasma internals stay off until a Plasma Fusion update, and a package update with
  new settings brings a notice to run `plasma-fusion update`.
- Running setup again keeps your light, dark or automatic choice.

Not covered: the boot splash and the login screen styling are for Fedora only; the tablet
navigation needs a rebuild after every KWin update (Copr and the PPA rebuild it, AUR users rebuild
the package; the login check keeps it off until then).
