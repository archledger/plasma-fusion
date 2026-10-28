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

### Draft blocker: keyboard focus after non-owner input

Focus is assigned to the owning view only when its Loader completes. KWin can later activate
an empty non-owning view after a click or touch on that output. That view has no Escape handler,
so this draft does not yet preserve dismissal after such input. Keep it blocked until keyboard
routing stays with the owner or dismissal is handled independently of the focused view.

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
As with `packages/apppairs/tests/vsession/make-seed.sh`, put the effect under
`~/.local/share/kwin/effects` and its native QML module under `~/pf-qml`, with `QML_IMPORT_PATH`
in the seed's `.config/pfv-env` naming that session's absolute `~/pf-qml` path.

Run one output with `0 0`; then two outputs with `0 0`, `1 0`, `0 2` and `1 2`. The regression
asserts that a slow swipe stays open, control windows remain unminimized, Escape reaches the
owning view, and disabling the owning output closes the effect. Repeat on both supported KWin
build/test images. This is an integration test, not an offline CTest: it needs a compositor,
virtual outputs and emulated native input. Do not run it against a logged-in desktop.

Before merging, extend the native regression to click and touch the empty non-owning output
after opening the switcher, then press Escape and require the effect to close. This sequence
is not covered by the current scenario. Rerun it and the existing matrix on both supported
KWin build/test images after fixing focus routing.
