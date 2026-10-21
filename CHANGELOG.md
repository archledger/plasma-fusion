<!--
SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Changelog

Newest first. Each release lists the Plasma series it was tested with and the systems it supports.

## Unreleased

- **Boot splash on Ubuntu 26.10:** `plymouth-install.sh --select` now also installs Plymouth's text
  plugin (`plymouth-label-ft`; Debian: `plymouth-label`) where the system's Plymouth needs it:
  without it, Plymouth's script plugin crashed as the splash started and the boot showed a
  backtrace instead (Plymouth after 24.004.60; found on a real boot in the release VMs).
- **Installer on Debian, Ubuntu and KDE neon:** the package steps wait (up to 10 minutes, as apt
  says) while another package manager holds dpkg's lock, instead of failing at once; unattended
  upgrades, which catch up at a random time in the first hour after a boot, made an install fail
  that way in the release tests. `apt-get update` is tried three times, 15 s apart.
- **Boot splash beyond Fedora:** `sudo /usr/share/plasma-fusion/tools/system/plymouth-install.sh
  --select` now also works on Arch, Debian testing, Ubuntu 26.10 and KDE neon: it finds the
  system's initramfs builder (dracut, mkinitcpio or initramfs-tools) and how it selects a theme
  (`plymouth-set-default-theme`, or the `default.plymouth` alternative on Ubuntu and KDE neon),
  installs Plymouth's script plugin with the system's package manager where it is missing, adds
  the `plymouth` hook on Arch through a drop-in of its own, and keeps a copy of each image it
  rebuilds. When the kernel command line lacks `splash`, it says so and how to add it, and leaves
  the boot loader alone. `plymouth-uninstall.sh` puts the previous theme back. The installer offers
  the step on those systems too.
- **Login screen for SDDM:** the Login board's screen as an SDDM theme for the systems whose
  display manager is SDDM (Ubuntu 26.10, Debian testing, Arch or NixOS with SDDM): the clock and
  date, the sign-in card, the user row with "Other user", the session pill and the power buttons,
  on the pre-blurred Dusk Ridge treatment. `sudo
  /usr/share/plasma-fusion/tools/system/greeter-apply.sh` chooses it where SDDM is the display
  manager, the way System Settings' Login Screen (SDDM) page does, so the page can choose another
  theme again; `greeter-restore.sh` undoes it and keeps a theme chosen since. On NixOS:
  `programs.plasma-fusion.sddm = true`. `plasma-fusion status` says whether SDDM uses it. Keyboard
  users can choose accounts, sessions and layouts, reveal a password and activate power actions;
  the username prompt is labelled and password undo is blocked. Where SDDM uses Qt's virtual
  keyboard (its default; Debian, Ubuntu, KDE neon) it no longer covers half the screen at once: the
  accessibility button at the top right opens it. User photos are round.
- **Saved app pairs:** two apps side by side can be saved as one icon on the home screen: "Save
  pair" under their card in the app switcher. A tap on the pair opens both apps side by side, in
  the split they were saved with; holding it offers Swap Sides, Keep in Dock and Remove Pair. A
  pair kept in the dock opens the same way.
- **Title bars back after tablet posture:** an app opened in tablet posture, then taken out of
  full screen or put in a half, had no title bar after folding back into a laptop; it has its
  title bar again, unless one of your window rules (or a system-wide one) removes it.
- **Full screen off takes a half:** in tablet posture, switching Full screen off in the app's card
  puts it in the free half instead of leaving it floating out of reach; the other half then offers
  your apps or open windows.
- **Drag an app to a side:** in tablet posture, hold the app's name in the top bar for a moment
  and drag it down: drop it on the left or right third and it takes that half, in the middle and it
  is full screen, at the bottom and it goes home; a quick sideways flick of the name puts it in that
  half at once.
- **An app for the other side:** in tablet posture, with one app in a half and nothing beside it,
  the rest of the screen offers your apps (home apps first, then all apps A to Z) instead of a home
  page cut off under the app; tap one and it opens beside the first.
- **Copy text no longer stuck:** when copy text's own selection could not open a window on any
  screen, copy text did nothing from then on until the next login. It now uses Spectacle's
  selection that time, as when KWin refuses the pictures, and tries its own again the next time.

## 0.6.0 (2026-10-18)

Tested with Plasma 6.7 (6.7.5 on Fedora 44, Ubuntu 26.10 and NixOS; 6.7.4 on Debian testing) and
Plasma 6.8 (6.8.0 on Arch and KDE neon; the 6.8 beta, 6.7.91, on Fedora 44).
Packaged as before for Fedora 44 and 45 (Copr), Arch (AUR), Ubuntu 26.10 (PPA), Debian testing and
KDE neon (.deb) and NixOS (flake), now as six packages: Quick Look and copy text's selection are
packages of their own, which the main package recommends and the installer installs. On an
untested Plasma series the parts that depend on Plasma internals stay off until an update.
Known: on Plasma 6.8.0 with KDE Frameworks 6.31 (Arch, KDE neon), KDE's file indexer can crash over
and over once a file is added to the home folder, with or without Plasma Fusion (KDE bug 524392);
the bug's workaround is a `kde-baloo.service` override with `QT_QPA_PLATFORM=offscreen`.

- **The installer brings Quick Look and copy text's selection too:** `install.sh` installs all six
  packages, and `install.sh update` from an earlier release adds the two new ones.
- **No half-updated Plasma from the installer:** on KDE neon, Debian and Ubuntu, when installing
  Plasma Fusion would also upgrade part of Plasma (the system is behind the release's packages),
  the installer now stops and says to update the system first. Before, on a KDE neon still at
  Plasma 6.7.5, it left Plasma half on 6.8.0 and the desktop shell did not start.
- **`plasma-fusion status` names every compiled part:** Quick Look and copy text's selection now
  show with what they were built against, as the decoration, the settings page and the tablet
  gestures did.
- **Copy text's selection shows at once:** with the new `plasma-fusion-copytext` package (the main
  package recommends it), Meta+Shift+T and the copy-text buttons show Plasma Fusion's own selection
  in about a tenth of a second instead of Spectacle's in one to two and a half seconds: the screen
  stays still under a light veil, the box drawn around the text copies it as the drag ends, and Esc
  or a click ends it. It starts on the first copy text and then waits with no window and no CPU.
  Without the package, or where KWin does not allow it the screen's picture, copy text uses
  Spectacle's selection as before.
- **A copy-text button in the top bar:** one click on the button before the clipboard, then a box
  drawn around text on the screen, and the text is on the clipboard, as with Meta+Shift+T; it can be
  turned off in the widget's settings ("Copy text button").
- **Copy text in one movement:** drawing the box around the text now copies it and closes the
  selection as the drag ends, without Enter or a double-click, as copy-text tools such as NormCap
  do; Spectacle's own setting for its screenshots stays as it is.
- **Copy text from the clipboard:** the clipboard pop-up (the top bar's clipboard button, Meta+V)
  has a copy-text button next to Emoji: select an area of the screen and its text is on the
  clipboard, as with Meta+Shift+T, one click from the top bar.
- **The island's own glyphs for Plasma's notices:** the keyboard layout, the touchpad, the power
  mode, Do Not Disturb, Night Light, the on-screen keyboard, sleep blocked and the time zone now
  show in the island with its own line glyphs (the keyboard, the touchpad, the gauge, the bell,
  the moon, the on-screen keyboard, Keep awake's cup, the clock), crossed out when off, instead of
  Plasma's icons; a newly chosen output device that is muted shows the crossed-out speaker.
- **Volume, brightness and Plasma's notices in the island:** while the top bar is hidden, what
  Plasma's own pop-up would show (the volume, the microphone, the brightness, the keyboard layout,
  the touchpad, the power mode and the rest) shows in the island at the top instead, and Plasma's
  box two thirds down the screen does not. With the bar shown, Plasma's box as before.
- **The island's icon:** a login over SSH or an app without an icon now shows its kind's glyph in
  the island, not a blank page.
- **No errors when bars are removed:** removing the top bars while quick settings was still asking
  KWin about the on-screen keyboard (as an import does) logged errors; it no longer does.
- **Snap sizes after an update:** updating in a running session now moves Meta+Left/Right to the
  snap sizes at once. Before, the setup started the snap script again, KWin ran the older one, and
  the keys stayed KWin's quick tile.
- **Gestures and the snap script:** the Touchpad gestures group on the Plasma Fusion settings
  page says when the Plasma Fusion Snap Layouts script, which does the gestures, is turned off,
  and where to turn it on.
- **Hide the top bar, and the island:** the Plasma Fusion settings page has "Hide the top bar
  automatically" (off by default). The bar slides away so a maximized window has the whole screen,
  and comes back when the pointer touches the top. While it is hidden, a black island at the top
  centre, after Apple's Dynamic Island, shows what uses the camera, the microphone or the screen,
  a screen recording, a Keep awake timer or the music playing; a click opens it in place. In a
  full-screen window only the privacy dots show; in tablet mode the bar always shows.
- **Dock on the left or right:** the Plasma Fusion settings page has Dock position (Bottom, Left,
  Right). On a side the dock stands upright, 16 px from the screen's edge, magnifies along it and
  opens its name pill, previews, menus and the launcher beside it. In tablet mode it is at the
  bottom and goes back to its side after.
- **Window count in the dock:** while an app's windows are grouped, the marks under its icon count
  them, up to three: dots for a running app, the accent pill first for the active one.
- **Dock size and window grouping:** the Plasma Fusion settings page has Dock size (Small, Medium
  as before, Large) and "Group an app's windows": off, each window has its own icon, side by
  side where the app is pinned. The magnified icon size is now a step (+8 or +14 px) that follows
  the dock's size.
- **Touchpad gestures you set:** the Plasma Fusion settings page has a Touchpad gestures group:
  three fingers up, down, left and right and four fingers pinched in and spread out can each
  open Overview, show the desktop, open the grid of desktops, All windows, the launcher, quick
  settings, notifications or snap layouts, or do nothing. By default three fingers up open
  Overview and down show the desktop, as before, four fingers pinched in open the launcher and
  spread out show the desktop. Where KWin also uses a gesture (three fingers sideways with
  several desktops in a row), the row says so and both happen. "Keep desktops in one row" (on,
  as the setup arranges them) leaves three fingers up and down to the group.
- **Export and import your settings:** the Plasma Fusion settings page has "Export my settings…"
  and "Import settings…". The file holds the page's settings and your panels: the top bar and dock
  with their widgets, the widgets' settings and keyboard shortcuts. Importing asks first, then puts
  them in place of yours; panels of screens the computer does not have go to the first screen when
  there is room, and widgets that are not installed are left out (the page says which).
- **Dock on every screen:** a new switch in the Plasma Fusion settings, under "Top bar on every
  screen", gives each screen a dock of its own that shows that screen's windows. It is off by
  default (one dock, as before).
- **Snap sizes from the keyboard:** pressed again, Meta+Left and Meta+Right step a window through
  half, a third and two thirds of that side of the screen, then back to half; with a screen on that
  side, the step after two thirds moves the window there, as before. `plasma-fusion setup` moves
  Meta+Left/Right to the new actions (on an update, only while KWin's quick tile still holds them).
- The dock's menu has **End Task…** for an app that does not answer: after a confirmation the app
  is asked to quit and, if it is still running 3 seconds later, ended. The desktop's own windows
  have none.
- The Plasma Fusion settings page has a **Launcher** group: recent files under the pinned apps, the
  Recent chip (recently and often used apps) and the Places chip can each be turned off. The
  launcher's own settings have the same switches.
- New **live chips** at the start of the top bar's right cluster: a chip shows while an app uses
  the microphone or the camera, shares the screen or controls the computer, while someone is signed
  in over SSH, while Spectacle records the screen (with the time and a stop button) and while a
  timed Keep awake runs (the time left). A click on the chips opens a panel that names the apps,
  with Mute, Stop sharing and End. Nothing in use: the bar is as before. `plasma-fusion setup`
  adds them to existing top bars once.
- Snapped windows now meet with no gap between them: two halves side by side, or four quarters,
  fill the screen edge to edge. A gap can still be set in the snap script's settings (System
  Settings, Window Management, KWin Scripts, Plasma Fusion Snap Layouts), from 0 to 48 px.
- New **Quick Look**: select files in Dolphin and press Space to see what is in them without
  opening them - pictures (moving ones play), PDF documents, text and code with its colours, songs
  and videos, and a folder's size; any other file shows its thumbnail. The arrow keys go through the
  selected files, Enter opens the shown one, and Space or Esc closes the preview. "Quick Look" is in
  the context menus of Dolphin and the desktop too. It is the new `plasma-fusion-quicklook` package,
  which the main package recommends; with it, `plasma-fusion setup` gives Space in Dolphin to Quick
  Look ("Select Files and Folders" keeps its toolbar button), and `plasma-fusion restore` gives it back,
  as does the next `plasma-fusion setup` once the package is removed. Ctrl+C copies the selected text.
- **Copy text from the screen** (Meta+Shift+T, and the button next to the screenshot button in Quick
  Settings) now takes one step: select an area and its text is on the clipboard, with a
  notification - no Spectacle window, no Extract Text click, no screenshot left behind. The text is
  read with Tesseract in the languages chosen in Spectacle's settings. It needs the `tesseract`
  command (Fedora `tesseract`, Debian and Ubuntu `tesseract-ocr`, Arch `tesseract`; the packages
  recommend it); without it, or while Spectacle is open, the key opens Spectacle's area selection
  as before. `plasma-fusion update` switches the key over.
- **Notifications**: in the quick-settings sheet and the tablet Notification Centre, a new
  notification whose text wraps no longer has the row under it drawn over its bottom (a group's
  header over a card, or one card of a group over another), also after the sheet is opened again.
  In the Notification Centre, rows now move without the slide animation.
- New KWin script **dynamic workspaces** (`plasmafusion-workspaces`), off until you turn it on in
  System Settings > Window Management > KWin Scripts: workspaces come and go as you need them, the
  way GNOME does it. There is always one empty workspace at the end - move a window there, or open
  one on it, and the next one appears - and an empty workspace goes once nothing shows it, without
  cutting the switch animation short. Workspaces it adds are called "Workspace N" and keep their
  numbers in order; names you or the Fusion setup gave are never changed, and "Always keep the
  first workspaces" keeps as many as you like (for example the setup's Work, Design, Media and
  Chat). The top bar's workspace dots follow along. While it is on, the Fusion setup creates no
  workspaces of its own.
- **Snap groups**: after you choose a zone in the snap layouts flyout (Meta+Z, or holding the
  maximize button), every other empty zone of that layout offers your other windows in turn - the
  quarters, the 2:1 split and the thirds now fill like the halves did. The windows you snap
  together form a group: they minimize and restore together, and activating one (from the dock or
  Alt+Tab) brings the whole arrangement back. A window that leaves its zone leaves the group.
- New KWin script **window placement memory** (`plasmafusion-placement`, on with the Fusion
  setup): each app's window is remembered where and as big as you left it, and opens there
  again - the desktop's most-duplicated open wish (bug 15329). A spot on a screen that is gone
  is left to KWin's placement, a second window of an app is not stacked exactly on the spot the
  first one holds, a KWin window rule that forces a window's position still wins, and System
  Settings > Window Management > KWin Scripts offers "Remember size" and a list of apps to leave
  alone (app ids or window classes). The memory lives in `~/.config/plasmafusion-placementrc`.

## 0.5.0 (2026-10-12)

Tested with Plasma 6.7 (6.7.5) and the Plasma 6.8 beta (6.7.91 on Fedora 44 and Arch).
Plasma 6.8 support comes from that beta testing; anything Plasma 6.8.0 final needs will come in a
follow-up release.
Packaged as before for Fedora 44 and 45 (Copr), Arch (AUR), Ubuntu 26.10 (PPA), Debian testing and
KDE neon (.deb) and NixOS (flake); on an untested Plasma series the parts that depend on Plasma
internals stay off until an update.

- A **clipboard sheet** in Quick Settings, opened by the clipboard button and **Meta+V**, replaces
  Klipper's pop-up: Klipper's history, newest first, with search (every word, as plain text),
  images and copied files, the stock Clipboard widget's stars (shared with it), Edit, QR code,
  Klipper's actions, Remove and Clear all (with Klipper's confirmation; starred entries stay).
  Choosing an entry puts it on the clipboard and the on-screen display says to press Ctrl+V
  (pasting by itself would need a new privilege on Wayland). An Emoji button opens Plasma's emoji
  selector. Meta+V comes with the Windows-style shortcut set, which takes only that key from
  Klipper's "Show Clipboard Items at Mouse Position"; setups an earlier release made with that set
  get it once at the update, while Klipper still has it. `--keep-shortcuts` leaves it with Klipper
  and `plasma-fusion restore` gives it back.
- **Quick Settings can be edited**: the pencil in the sheet's header (in the tablet row in tablet
  posture) shows a remove badge on every tile and a tray of hidden tiles below. Drag a tile by mouse
  or touch to move it, or press Ctrl with the arrow keys; remove it with its badge or Delete, add it
  back from the tray, or Reset to defaults. The order is the same in every Quick Settings widget on
  every screen, and the sheet stays one page. Tiles that appear only when they apply (Disks &
  Devices, Wi‑Fi hotspot, Charge limit, Tablet mode) still do; a hidden one never shows. A tile
  added in a later release appears after the tile it follows by default, wherever that tile now is.
- The notification history in Quick Settings and in the tablet Notification Centre is **grouped by
  app**, as in Plasma's own applet: an app's header with Configure and Close Group, its two newest
  notifications and "Show N More". Notifications show their **images** (beside the text, in the
  body, and a preview of a linked file such as a screenshot, which opens it), can be **answered in
  place** when the app offers an inline reply, and have a **Configure** button for the app's
  notification settings. A finished file copy offers **Open** and **Open Containing Folder**, a
  failed one says why, and a running one can be paused and resumed where the app allows it. Cards
  work from the keyboard: Return runs a card's action, Delete closes it, and the Notification
  Centre's card menu also opens with a right click or the Menu key.
- **Do Not Disturb** offers Plasma's durations: for 1 or 4 hours, until this evening, until tomorrow
  morning, until Monday (on Fridays and Saturdays) or until turned off. Its "Until" time follows
  the clock (a Do Not Disturb until Monday showed just "On"), and it names the application that
  turned it on ("While Kdenlive is active").
- The **Power mode** tile has a chooser behind its chevron, as Plasma's Power and Battery widget:
  the daemon's profiles with the active one checked, Performance listed as unavailable with the
  reason while the computer is on a lap or too hot, and the applications holding a profile. A click
  on the tile now switches between Balanced and the last other profile instead of cycling, so going
  from Balanced to Power saver no longer passes through Performance.
- **Keep awake** can run for 1 hour, 4 hours or until a chosen time, besides until turned off; the
  tile and the status pill's tooltip show the time left. The timer runs with the sheet closed; like
  Plasma's own Keep awake, it ends when plasmashell restarts.
- An open vault, queued print jobs, presentation mode or a second screen, and the input-method
  switch show their stock items in the top bar while they are active, and hide again when passive,
  still without the tray's expander arrow. Before, they were hidden even while active. Existing
  layouts get this without a reset.
- Optional **system meters** for the top bar: the processor load, the memory in use, the download
  and upload rates and the processor temperature, in a pill drawn like the status pill, with a
  pop-up for a few more values and System Monitor. They are off: turn them on with "System meters
  in the top bar" in the Plasma Fusion settings, or add "Plasma Fusion System Meters" from Add
  Widgets, and choose the meters in its settings. They read Plasma's own sensors, read nothing
  while an active full-screen window covers the bar, the screen is locked or the bar has no room
  for them, and update half as often in power saver and a quarter as often on a nearly empty
  battery.
- The launcher has a **Recent** chip with the apps used last and the most used ones ("Recently
  used", "Often used"), from the same history as Kicker's, and a **Places** chip with the file
  manager's places, the removable drives (a click mounts and opens one) and the recent folders, as
  in Kickoff's Places tab. Both work with the keyboard like the categories.
- Hiding an app in the launcher works: its menu offers Kicker's Hide Application and, for the apps
  of that list, Unhide Applications in this Submenu. Before, neither appeared and the hidden list
  had no effect. The launcher's settings list the hidden apps with a Show button each and Show All.
- **Alt+F2** opens KRunner again, with all of its search plugins; Meta+S, Meta+Space and Alt+Space
  still open the launcher. The update gives the key back once, while the launcher still has it and
  KRunner has no key; `plasma-fusion restore` undoes it. The launcher's search ends with "Search …
  in KRunner", which opens KRunner with the same query. The dock's Search button now opens the
  launcher's search, like the search keys (before, KRunner, with other plugins); KRunner can still
  be chosen in the dock's settings.
- The dock shows the **progress of file transfers** on the app's icon: a copy in Dolphin, a download
  or any other job Plasma's notifications track, as the stock task manager does.
- The lock screen offers **Restart** and **Shut Down** next to Sleep, Hibernate and Switch User,
  wherever the session may restart or shut down (the log-out screen's rule). Both ask first and
  stay off while a program holds logind's block on shutdown; the question names no program or user,
  since anyone at the locked screen can open it (KDE wishlist 336369).
- On Plasma 6.8 the lock screen offers the other ways to unlock the system has (**smartcard,
  fingerprint, face, security key**) as links under the password field; the way used last time is
  kept, and one that stops working falls back to the password with a message. Before, the password
  was forced. It also asks the greeter to authenticate again while the prompt is shown, so a quick
  key press after locking no longer leaves the password field unanswered, and Restart and Shut Down
  are translated there.
- With two or more screens on Plasma 6.8, the first correct password unlocks: the screen locker
  crashed while closing and locked once more, and one screen showed no wallpaper.
- On Plasma 6.8 the log-out screen shows its buttons on the screen with the pointer only and moves
  them with it, as Plasma 6.8 does, without its errors about the screen size.
- Snapping recognises KWin's quick tiles without relying on their number or order (ready for
  Plasma 6.8's tiles), and the snap preview no longer starts processes inside KWin each time it
  appears.
- **Meta+Shift+T**, and a button next to the screenshot button in Quick Settings, copy text from the
  screen: Spectacle's area selection opens, and Extract Text copies the text. The key is set only
  when nothing else uses it; restoring removes it.
- Scrolling a page no longer changes the volume, the keyboard layout or the workspace when the wheel
  is still turning as the pointer passes over the top bar's status or clock pill; turning the wheel
  after resting on a pill works as before.
- The Quick Settings sheet fits its content again. On the first opening after login the page was
  drawn 14 px too low and its last row of tiles, or a page's button, was cut off; after a scale
  change, or a notification that came or went while the sheet was closed, it opened at its old
  height.
- Meta+N (the notification list) works right after the setup; before, it did nothing until the
  next login.
- The tablet home screen's edit mode is seen by the desktop again, which keeps the widgets' tap area
  up to date while they move, and plasmashell no longer logs "ReferenceError: homeLoader is not
  defined" at every start in tablet posture.
- The clock's settings open without warnings in the log, and Apply on one of its pages no longer
  writes back a value that another page, or the widget itself, changed while the page was open.
- On Plasma 6.8, Plasma no longer crashes again and again at login after a monitor with a top bar
  was unplugged: the tablet-mode script, the Plasma Fusion settings page and `plasma-fusion setup`
  leave panels whose screen is gone alone (reading their size crashed plasmashell 6.8), and
  `plasma-fusion setup` no longer takes such a layout for a foreign one and resets it. Plasma Fusion
  0.4.x has the same crash on Plasma 6.8. The tablet panel sizes are applied again when plasmashell
  answers late at login.
- The Plasma Fusion settings page waits up to 25 s for the Plasma shell instead of 5 s: right after
  the shell restarts, "Top bar on every screen" and the system meters switch no longer report "Did
  not receive a reply" for a change that is made, and the page keeps drawing and shows it is busy
  while it waits.
- A timed Do Not Disturb no longer ends while Plasma itself holds it for a full-screen window or
  mirrored screens: Plasma's own Notifications applet ends a timed one, and Quick Settings only sets
  the time (it also refuses a time already past).
- After a restart, Quick Settings on several screens take the shared settings changed last, not
  those of whichever widget loaded first.
- `plasma-fusion update` no longer undoes what you changed in the layout: a top bar you made
  translucent ("Solid top bar next to windows" off), a tray item you set to "Always shown", a pen
  menu you removed and a desktop you switched stay as they are, and an update that has nothing to
  migrate no longer restarts the Plasma shell (which also ended Keep awake). Disks & Devices turned
  back on in the tray stays on after the update that first hid it.
- A Glass level or dock magnification chosen in the Plasma Fusion settings while the battery is
  nearly empty is now what the widgets and blur get when the battery recovers; before, they got
  the level from before and blur could stay off.
- Top bars added for a newly connected screen, by "Top bar on every screen", by `plasma-fusion setup
  --screens` and by Add Panel follow the Glass level and "Solid top bar next to windows" (with Glass
  Solid or High contrast their Notification Centre was blurred), and a layout rebuilt by the setup
  or by System Settings' Global Theme follows them and "Top bar on every screen" too. Top bars
  added in power saver or on a nearly empty battery get the lighter tier at once.
- The on-screen keyboard stays available after an update when its policy is "On touch".
- "Reset Fusion layout" gives the pen menu Meta+Shift+W only when it had it, and `plasma-fusion
  restore` frees the keys of widgets the restored layout does not have.
- A swipe from the right edge in tablet posture opens Quick Settings on the touch screen, and no
  request opens it on every screen at once any more.
- The desktop's CPU and memory card shows memory in binary units as System Monitor does ("6.1 /
  15.3 GiB"), like the new system meters; before, it showed GiB labelled "GB" with the total
  rounded up, so a full memory read "15.3 / 16 GB" next to 100 %.
- Uninstalling restores the login screen also when Plasma Fusion's look was written without its
  mark (into a file that had a [Greeter] group, or rewritten since by the Login Screen settings),
  and `plasma-fusion restore --help` shows its usage instead of the whole script.
- Glass set to Solid in the Plasma Fusion settings (also chosen by High contrast, and by the power
  service on a nearly empty battery) now reaches the tablet launcher sheet and the Notification
  Centre: they show a plain tint instead of the blurred wallpaper. Before, the setting was written
  to the widgets but neither of them read it.
- The Overview hot corner turned on in the Plasma Fusion settings (or under System Settings >
  Screen Edges) stays on when the setup runs again; before, every run without `--hot-corner`
  turned it off.
- Do Not Disturb "Until tomorrow" chosen after midnight ends at 06:00 that morning, not at 06:00 the
  day after (29 hours from 01:00).
- The dock's window previews no longer flicker and restart their live thumbnails whenever a
  window title or the active window changes while they are shown (a terminal printing, a browser
  loading a page): only the card that changed is updated.
- Uninstalling with the installer also puts back the login screen and removes the boot splash when
  Plasma Fusion's root tools applied them, before the packages go; before, the login screen was
  left pointing at the removed theme and wallpaper. The installer offers the login screen step only
  where plasma-login-manager is installed (not on SDDM systems, where the tool stops).
- Quick settings, its tablet policy and the pen menu run a command again when the same one is still
  running, and every caller gets its answer: before, the second run was dropped, and at start-up in
  tablet posture one of the two reads of the window mode and the tablet mode never answered.
- The settings dialogs of quick settings and the dock open without warnings in the log again, and
  Apply in quick settings' dialog no longer writes back a value another part changed while it was
  open (the airplane-mode radios, the glass level).

## 0.4.0 (2026-10-09)

Tested with Plasma 6.7 (6.7.5) and the Plasma 6.8 beta (6.7.91 on Fedora 44 and Arch), like 0.3.1.
Packaged as before for Fedora 44 and 45 (Copr), Arch (AUR), Ubuntu 26.10 (PPA), Debian testing and
KDE neon (.deb) and NixOS (flake); on an untested Plasma series the parts that depend on Plasma
internals stay off until an update.

- Updating now replaces the desktop's QML at the next login. The Fedora packages of 0.3.0 and
  0.3.1 gave their files the same time stamps, and Qt reuses its compiled copy of a QML file while
  the file's time stamp is unchanged: after updating from 0.3.0, KWin and Plasma kept running
  0.3.0's snap script and dock, so 0.3.1's snap-edge and Calendar tile fixes did not take effect.
  Every QML and JavaScript file now carries a time stamp derived from its content, in the Fedora
  and Debian packages; the next update also replaces the compiled 0.3.0 copies 0.3.1 users still
  run.
- `plasma-fusion restore` (the uninstaller's first step) returns once the restarted shell is up, as
  the setup does: logging out right after it no longer brings kded and the portals back during the
  teardown, where a portal crashed (seen on Arch with Qt 6.12).
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
- Quick Settings lists **VPN** connections (including WireGuard) on the network page: a click
  connects or disconnects. On a computer without Wi‑Fi the Wi‑Fi tile opens the VPN list.

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
