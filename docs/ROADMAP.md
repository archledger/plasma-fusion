# Roadmap, October 2026 to October 2027

This is the maintainer's plan for the next year, written on 2026-10-02. It is a plan, not a
promise: priorities can change, and when they do this file changes with them. Ideas and requests
are welcome in GitHub Discussions; the way decisions are made is in
[`GOVERNANCE.md`](../GOVERNANCE.md).

## Where the project stands

- Experimental. Built for and tested on Fedora 44 KDE with Plasma 6.7.5, KDE Frameworks 6.30 and
  Qt 6.11, on two machines: a convertible (ThinkPad X13 Yoga Gen 4) and a laptop (ASUS Zenbook).
- No releases yet; the first, 0.2.0, is being prepared ([`RELEASING.md`](RELEASING.md)). Until
  then users build from `main` ([`README.md`](../README.md), "From the sources").
- One maintainer.

## Planned

### In the next weeks

1. **Plasma 6.8.** Plasma 6.8.0 is due on 2026-10-14. The test machines hold Plasma at 6.7 until
   Plasma Fusion is tested on 6.8 ([`docs/parts/ci.md`](parts/ci.md), "A `plasma-update` issue").
   The compiled parts are already built against KDE's beta packages every week (`compiled`
   workflow), and a test round on 6.7.91 found and fixed five breakages
   ([`docs/parts/containers.md`](parts/containers.md)). Then: test 6.8 in private sessions, raise
   [`packaging/tested-versions.txt`](../packaging/tested-versions.txt) and lift the hold.
2. **Split screen in tablet posture.** A split pair shown as one card in the app switcher (in
   navigation 0.1-7 since 2026-10-02; a touch check on the tablet is next). Then saved app pairs
   (one icon that opens both apps side by side) and an app picker in the free half after one app is
   tiled.
3. **Other distributions.** The login check and the installer read pacman, dpkg and Nix next to rpm
   and find helpers and data outside Fedora's paths (done 2026-10-02, tested in Arch and Debian
   containers and with a NixOS package list; not yet on a real Arch, Debian or NixOS desktop). Then
   packaging for Arch Linux (a PKGBUILD) and NixOS (a package and a module), and container builds
   for Arch and Debian unstable in CI. The aim is distributions with Plasma 6.7 or later: Arch
   Linux, Debian testing and unstable, NixOS unstable.
4. **OpenSSF Best Practices silver.** Style checks in CI, test coverage measurement (fuzzing of the
   Python tools' parsers runs since 2026-10-02), and the project documents: governance, code of
   conduct, architecture, this roadmap, the security assurance case
   ([`SECURITY-ASSURANCE.md`](SECURITY-ASSURANCE.md)). Also a known documentation defect:
   [`PLAN.md`](PLAN.md) and 27 of the part pages in [`docs/parts/`](parts/) cite paths on the
   maintainer's private share, which other readers cannot open. Those references are to be replaced
   with public text or removed.

### In the year

5. **Each Plasma release** after 6.8: build the compiled parts against KDE's beta packages, test,
   fix, then move the tested versions.
6. **Tablet typing.** Ctrl and Alt keys and cursor movement by dragging on the space bar for the
   on-screen keyboard, to be proposed to KDE's plasma-keyboard first. Esc, Tab and the arrow keys
   are already there ([`docs/parts/keyboard.md`](parts/keyboard.md)).
7. **Battery.** An overnight idle-power measurement on battery, glass on against solid, to decide
   the glass default on data (`tools/device/power-ab.sh` is ready).
8. **Login screen and boot splash elsewhere.** Login screen styling for SDDM next to
   plasma-login-manager, and the boot splash installer for mkinitcpio and initramfs-tools next to
   dracut.
9. **Upstream.** Send fixes found here to KDE where they belong, such as GTK font sizes that
   follow fractional Qt font sizes (kde-gtk-config).

## Not decided yet

The maintainer has not decided these. This file will move them to "Planned" or "Not planned" once
they are decided.

- **A first release:** when it comes, the version scheme, release notes, and how version tags and
  release artifacts are signed ([`GOVERNANCE.md`](../GOVERNANCE.md), "Releases").
- **A second maintainer:** who it is, and when they get merge, release and admin rights
  ([`GOVERNANCE.md`](../GOVERNANCE.md), "Continuity").

## Deferred

Wanted, but put off for the reason given. They may come back later.

- **Pen:** a hover dot while the pen is near the screen in tablet posture. It needs a permanent
  KWin overlay effect, which costs GPU time.
- **Home screen:** folders and widget stacks. Of the home screen items, they have the least
  evidence that users need them; worth another look if pinned apps outgrow one page.

## Not planned

These are left out on purpose: the user research behind the tablet and desktop work (the
maintainer's notes, not in this repository) advised against them, they would break something that
works, or the platform does not allow them:

- web or advertising results in the launcher;
- depending on third-party Global Themes or widgets;
- GTK-NoCSD, touchegg, or TLP together with tuned-ppd;
- automatic reboots;
- removing options Plasma users already have;
- a new window-management model in laptop posture (in the style of Stage Manager): assisted
  snapping keeps improving instead;
- always-on display, one-handed mode, haptics, swipe-back from any edge, multi-page controls and
  handwriting-to-text, for now;
- a port to Plasma 6.6 or older (Debian 13, NixOS 26.05), unless the maintainer decides
  otherwise: the compiled parts and several widgets need Plasma 6.7 interfaces, so NixOS 26.05
  would need a backport of those widgets' QML and would run without the compiled parts;
- changes to the PAM stack, or switching Fedora's login manager to apply the look;
- a different layout for the login screen: the greeter's layout is compiled into
  plasma-login-manager, so Plasma Fusion styles it only.
