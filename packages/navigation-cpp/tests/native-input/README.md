<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
# Private navigation probe

This module is test-only. It is not built or installed by the navigation package.
Compile against the exact KWin source and development image used by the private
runtime, then copy it into that session's private QML import path.

```
cmake -S packages/navigation-cpp/tests/native-input -B build/navigation-input \
    -DKWIN_TEST_SOURCE=/path/to/matching/kwin -DCMAKE_BUILD_TYPE=Debug
cmake --build build/navigation-input
```

Copy `libnavigationprobe.so` and `qmldir` into
`org/plasmafusion/navigation/test/` below the private session's QML import root.
The matching KWin source provides test-only backend headers that are not installed
with the normal development package; no production symbol export is added.

`PF_NAV_PROBE_OUT` must name the private session's output directory. Without it,
the module does not register its test D-Bus object. The object is on the private
KWin session bus at `/PlasmaFusionNavigationTest`, interface
`org.plasmafusion.NavigationTest`.

The injected fixture calls `observe()` after the real Loader's completion hook.
The probe records initial native opacity and captures the first matching output
frame. A missing context, wrong render thread, mismatched framebuffer or failed
image write is a failure, never a later-frame fallback. Synchronous readback
perturbs rendering: these results are not latency or performance measurements.
The first-frame checker validates complete capture structure before issuing a
behavior verdict: exit 2 is an invalid capture, not an accepted baseline failure.
Pixel preservation applies to outputs present in the initial baseline. A newly
added output has no prior desktop image; its zero-opacity state is checked from
the first frame, and the hotplug scenario separately requires its desktop to
become mapped and visible.

`snapshot()` checks the actual active view and Qt focus object. Positive input
tests require a separately injected `TextInput` named `nativeProbeEditor` and
explicitly verify its focus before sending synthetic preedit/commit events and
keys. No text or input is sent to production UI controls. These are native Qt
routing tests, not physical IME or virtual-keyboard qualification.

`checkGuards()` checks null, unassociated-window and foreign-effect items without
changing the live effect's views. Do not load this module in the installed desktop.
The lifecycle fixture also observes the existing close timer at an owner change.
A transfer during closing must occur while that timer is still active; a later
ordinary reopen is not equivalent evidence.
