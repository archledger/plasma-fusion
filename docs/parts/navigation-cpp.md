<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
# Native tablet navigation

`packages/navigation-cpp` is the KWin effect behind the bottom-edge home, app-switcher and
previous/next-app gestures. Its upstream origin, gesture thresholds and split-pair behavior are
documented in `packages/navigation-cpp/README.md`. It uses KWin's internal APIs and only starts
when its compiled KWin version matches the running compositor.

## Output ownership

KWin creates a `QuickSceneView` for every output, but the navigation state describes one gesture
and one task list. `FusionTouchBorder` reports the originating output before signalling that a
gesture is in progress. `FusionNavigationState.activeOutputName` keeps that output for the
gesture and the resulting open switcher. A shortcut activation chooses KWin's active output.

The effect's per-output root is a Loader. Only the owning output constructs a TaskSwitcher;
other outputs cannot initialize its shared indices, minimize their windows or close the effect
because their own task lists are empty. A new gesture on another output first ends the previous
view. Removing the owning output schedules deactivation, releasing input grabs without deleting
the scene reentrantly during KWin's screen-removal signal. The owning view receives keyboard focus
after it finishes loading.

This fixes the two-output case where a held swipe opened the switcher on one output and an empty
second output immediately closed it. It also prevents populated outputs from competing over the
same indices or minimizing unrelated windows.

### Keyboard dismissal after non-owner input

Focus is initially assigned to the owning view when its Loader completes. KWin can later activate
an empty non-owning view after a click or touch on that output. Every Loader remains a keyboard
focus scope with an Escape handler that calls the shared state's existing animated close path.
Only the owner loads a TaskSwitcher; the other outputs can dismiss it without constructing task
models or taking ownership. The loaded switcher's own Escape handler still handles owner input.

## Verification

Build with the matching existing build image, or the dependencies in the package's CMake file:

```
cmake -S packages/navigation-cpp -B build/navigation -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=ON
cmake --build build/navigation
DESTDIR="$PWD/build/navigation-install" cmake --install build/navigation
```

`packages/navigation-cpp/tests/vsession/scenario-outputs.sh` is an automated real-KWin regression.
It requires a private `tools/vsession` session, 1280x800 at scale 1, tablet mode on and a matching
navigation install in the seed. Copy the repository's tools to `~/pf-tools`. Put two integers in
`~/navigation-case`: target output index, and count of control windows on the other output.
An optional third field selects `none` (default), `click` or `touch` on the non-owning output.
As with `packages/apppairs/tests/vsession/make-seed.sh`, put the effect under
`~/.local/share/kwin/effects` and its native QML module under `~/pf-qml`, with `QML_IMPORT_PATH`
in the seed's `.config/pfv-env` naming that session's absolute `~/pf-qml` path.

Run one output with `0 0`; then two outputs with `0 0`, `1 0`, `0 2` and `1 2`. The regression
asserts that a slow swipe stays open, control windows remain unminimized, Escape closes the
switcher, and disabling the owning output closes the effect. Repeat on both supported KWin
build/test images. This is an integration test, not an offline CTest: it needs a compositor,
virtual outputs and emulated native input. Do not run it against a logged-in desktop.

For each two-output case, also run with the third field set to `click` and `touch`. The scenario
requires the switcher to remain open after that input, then close on Escape. This covers both
empty and populated non-owning outputs without relying on which scene has keyboard focus.

The scenario requires successful D-Bus queries for dismissal, a confirmed second opening before
output removal, and an output snapshot confirming that the owner was removed. Its offline
failure-injection checks need no compositor:

```
python3 packages/navigation-cpp/tests/test_scenario_outputs.py
```

## Remaining visual blocker

The window-state and dismissal checks do not establish visual passthrough on other outputs.
In the native two-output qualification, a non-owning output becomes black while navigation
is open, although its control windows remain unminimized. KWin still creates a scene view for
that output; leaving its Loader empty does not preserve the visible desktop. Keep this change
in draft until non-owner rendering is corrected and checked with before/after captures.
