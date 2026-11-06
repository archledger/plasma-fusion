<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Native dynamic tiling on custom KWin

Status: scope and first-milestone plan approved by the owner on 2026-11-02. Tracks
[#115](https://github.com/archledger/plasma-fusion/issues/115).

## Objective

Provide optional, per-workspace master-and-stack tiling through an explicitly selected custom
KWin build. Preserve the user's manual tile layout, shortcuts and original floating geometry.
Owning the compositor source removes the requirement to wait for an upstream API; it does not
remove the issue's preservation or lifecycle requirements.

The first milestone is a native ownership proof for one explicitly selected ordinary window.
It is not the complete tiler. Multi-window layout policy and settings follow only after that
proof passes its lifecycle and placement-memory checks.

## Baseline and evidence

- Fusion design work starts from `9270d3c581c2c302e3b7a253463bdd279bf92638`.
- Initial native target: Fedora 44, KWin 6.7.5, Qt 6.11.2, using the existing pinned builder and
  isolated ThinkPad test environment.
- The separately prepared `.pf2` package retains requestedGeometry and adds offscreen-view
  opacity handling. It contains no dynamic-tiling owner or earlier ownership experiments.
- Existing private prototypes provide regression fixtures, not code to import wholesale.
  Their removal and settling results must be revalidated against the selected implementation.
- Stock KWin remains the ordinary Fusion installation. Dynamic tiling must remain unavailable
  when the required native contract is absent or incompatible.

## Ownership and preservation contract

The implementation must define an explicit native ownership lifetime, rather than repeatedly
assigning geometry or replacing the persistent custom tree. Its exact internal API remains a
design question; no proposed method or property is treated as an existing KWin API.

1. Capture the original floating frame before adopting an eligible window. Initially reject
   already tiled, maximized, fullscreen or rule-constrained windows instead of changing them.
2. Keep transient automatic layout separate from saved custom layouts. Entering, leaving,
   unloading or restarting must not write an automatic tree into `kwinrc`.
3. While ownership remains active, returning from maximize or fullscreen returns to the managed
   tile. Explicit Restore, untile or owner disable ends ownership and restores the appropriate
   floating frame. A later manual move or resize must not be overwritten by an older baseline.
4. Native quick tiling and manual placement take precedence over automatic ownership. Preserve
   existing native/Fusion shortcut bindings, including intentionally unbound actions.
5. Define output-transfer coordinates explicitly. Moving to another output must not confuse
   a translated automatic rectangle with the original floating restore frame.
6. End or transfer ownership safely on output removal, desktop/Activity changes, window close,
   module unload and compositor restart. Invalidate references before their owners disappear.
7. Keep automatic rectangles out of floating-placement memory, including outstanding Wayland
   configure/ACK/commit sequences, release followed by close, and move during settling. Geometry
   equality and elapsed time are not proof that a client has settled.
8. If a placement is infeasible or denied by a rule, leave the window in a defined safe state.
   Do not retry through a corrective geometry loop.

## First milestone and exit gate

Implement only adoption, one managed rectangle, release and the native lifecycle needed to test
them. Use existing deterministic clients and manual-layout fixtures. Do not add settings UI,
master/stack algorithms, background scheduling or default shortcuts in this milestone.

The milestone passes only when the new implementation demonstrates:

- saved layout and unrelated windows unchanged during adoption, release and restart;
- original floating restoration and native transition behavior under settled and pending input;
- safe output/desktop removal and transfer, including callbacks that close a window;
- no automatic rectangle in placement memory, and legitimate later manual changes recorded;
- capability absence rejects adoption without changing stock behavior;
- clean teardown and no new memory-check findings relative to a matched baseline.

Untested cases remain open. Passing this milestone does not close #115. The full issue still
requires multi-window policy, Activity/work-area generations, infeasible-layout coverage and
the supported-version matrix.

## Source and test locations

- Native changes and regression tests belong in a separate KWin source worktree and patch series.
  Do not modify the active `.pf2` package build or the retained private experiments.
- Fusion integration belongs with `packages/kwin/scripts/plasmafusion-placement`, its tests under
  `packages/kwin/tests`, and the eventual native owner's package. Select the owner API before
  creating that package; do not expose provisional names as a public interface.
- Behavior documentation belongs in `docs/parts/kwin.md`. Update `docs/DEFERRED.md` from verified
  milestone results, not from the existence of a custom package.

Use the existing KDE C++ style, explicit ownership and scoped cleanup. Keep production changes
small and preserve public behavior outside the opt-in feature. Do not ship diagnostic control
interfaces or prototype instrumentation.

## Validation commands and environment

Native commands run inside the pinned, isolated builder with `KWIN_BUILD` set to the candidate's
private build directory, never against the running desktop. Verify the source and actual test
registration before execution; retain exact commands and input hashes with every run.

```sh
cmake --build "$KWIN_BUILD" --parallel 4 --target testTiles testXdgShellWindow \
  testQuickTiling testMoveResize testFractionalScaling testOutputChanges \
  testMaximized testScreenChanges
ctest --test-dir "$KWIN_BUILD" --output-on-failure --no-tests=error \
  -R '^kwin-(testTiles|testXdgShellWindow|testQuickTiling|testMoveResize|testFractionalScaling|testOutputChanges|testMaximized|testScreenChanges)$'
node packages/kwin/tests/placement.test.js
ruff check
git diff --check
```

These are planned validation commands, not new test results. Add fail-first native cases for
each changed contract and controls that distinguish the defect from a broken fixture. Run
Wayland and X11 behavior separately. Keep historical beta evidence distinct from fresh results;
do not claim beta support until the changed paths pass there.

## Boundaries and open design questions

- Always preserve the original experiments, exact patch provenance, failures and test assertions.
  Review native lifecycle changes independently before considering them installable.
- Never silently install custom KWin through a normal Fusion dependency or enable automatic tiling
  on stock KWin. No persistent custom-tree replacement, timing workaround or shortcut takeover.
- This design does not authorize publishing private security-sensitive material, new upstream
  submissions, public package releases, other-host installation or forced session interruption.
- Decide the smallest native owner/settling contract during design. Compare compositor-owned
  transient state with a tightly bound native module; either must satisfy the same invariants.
- Define which Activity transitions release ownership and which retain it before implementing
  those paths. Preserve the issue's requirement for per-workspace opt-in.

The owner's existing ThinkPad package-replacement approval remains a separate operation. A new
dynamic-tiling candidate must complete its own validation before any activation is proposed.
