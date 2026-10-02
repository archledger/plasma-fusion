# Roadmap, October 2026 to October 2027

This is the maintainer's plan for the next year, written on 2026-10-02. It is a plan, not a
promise: priorities can change, and when they do this file changes with them. Ideas and requests
are welcome in GitHub Discussions; the way decisions are made is in
[`GOVERNANCE.md`](../GOVERNANCE.md).

## Where the project stands

- Experimental. Built for and tested on Fedora 44 KDE with Plasma 6.7.5, KDE Frameworks 6.30 and
  Qt 6.11, on two machines: a convertible (ThinkPad X13 Yoga Gen 4) and a laptop (ASUS Zenbook).
- No releases yet. Users build from `main` ([`README.md`](../README.md), "Quick start").
- One maintainer.

## Planned

### In the next weeks

1. **Plasma 6.8.** Plasma 6.8.0 is due on 2026-10-14. The test machines hold Plasma at 6.7 until
   Plasma Fusion is tested on 6.8 ([`docs/parts/ci.md`](parts/ci.md), "A `plasma-update` issue").
   The compiled parts are already built against KDE's beta packages every week (`compiled`
   workflow), and a test round on 6.7.91 found and fixed five breakages
   ([`docs/parts/containers.md`](parts/containers.md)). Then: test 6.8 in private sessions, raise
   [`packaging/tested-versions.txt`](../packaging/tested-versions.txt) and lift the hold.
2. **Split screen in tablet posture.** A split pair shown as one card in the app switcher (built,
   in review on a branch). Then saved app pairs (one icon that opens both apps side by side) and an
   app picker in the free half after one app is tiled.
3. **Other distributions.** The login check and the installer learn pacman, dpkg and Nix next to
   rpm, and find helpers and data outside Fedora's paths (under way on a branch). Then packaging for
   Arch Linux (a PKGBUILD) and NixOS (a package and a module), and container builds for Arch and
   Debian unstable in CI. The aim is distributions with Plasma 6.7 or later: Arch Linux, Debian
   testing and unstable, NixOS unstable.
4. **OpenSSF Best Practices silver.** Style checks in CI, test coverage measurement, fuzzing of the
   parsers in the Python tools (under way), and the project documents: governance, code of conduct,
   architecture, this roadmap, the security assurance case
   ([`SECURITY-ASSURANCE.md`](SECURITY-ASSURANCE.md)).

### In the year

5. **A first release.** Version tags, release notes and signed release artifacts. How they are
   signed is still to be decided ([`GOVERNANCE.md`](../GOVERNANCE.md), "Releases").
6. **A second maintainer** with merge, release and admin rights
   ([`GOVERNANCE.md`](../GOVERNANCE.md), "Continuity").
7. **Each Plasma release** after 6.8: build the compiled parts against KDE's beta packages, test,
   fix, then move the tested versions.
8. **Tablet typing.** Ctrl and Alt keys and cursor movement by dragging on the space bar for the
   on-screen keyboard, to be proposed to KDE's plasma-keyboard first. Esc, Tab and the arrow keys
   are already there ([`docs/parts/keyboard.md`](parts/keyboard.md)).
9. **Pen.** A hover dot while the pen is near the screen in tablet posture (deferred: it needs a
   permanent KWin overlay effect, which costs GPU time).
10. **Battery.** An overnight idle-power measurement on battery, glass on against solid, to decide
    the glass default on data (`tools/device/power-ab.sh` is ready).
11. **Login screen and boot splash elsewhere.** Login screen styling for SDDM next to
    plasma-login-manager, and the boot splash installer for mkinitcpio and initramfs-tools next to
    dracut.
12. **Home screen.** Folders and widget stacks, if pinned apps outgrow one page. Deferred: of the
    home screen items, they have the least evidence that users need them.
13. **Upstream.** Send fixes found here to KDE where they belong, such as GTK font sizes that
    follow fractional Qt font sizes (kde-gtk-config).

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
- a port to Plasma 6.6 or older (Debian 13, NixOS 26.05): the compiled parts and many widgets
  need Plasma 6.7 interfaces;
- changes to the PAM stack, or switching Fedora's login manager to apply the look;
- a different layout for the login screen: the greeter's layout is compiled into
  plasma-login-manager, so Plasma Fusion styles it only.
