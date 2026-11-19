<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Deferred and blocked work

Keep blocked work visible while independent, verified changes continue. This queue is not a waiver
of tests, compatibility, security, preservation requirements or review.

## Workflow

1. **Classify the stop.** Use `blocked` when a required dependency, safe design or validation is
   missing. Use `deferred` for an intentional scope or priority decision. Neither means complete.
2. **Create or link an issue.** Record the affected behavior, reproducible evidence, tested versions,
   rejected approaches, remaining uncertainty and acceptance criteria. Keep sensitive evidence
   private; public issues should contain only material safe to share.
3. **Record a re-entry condition.** Name the dependency or result that must change, and the first
   verification to run when it does. “Revisit later” is insufficient. Add the entry below with its
   last verification date; never imply an old test result is current.
4. **Continue independent work only.** Leave dependent tasks blocked. Test tooling, documentation or
   unrelated approved work can proceed if they do not rely on the missing behavior. A stub, skipped
   test, reduced threshold or changed default is not a substitute for the blocked implementation.
5. **Revalidate before resuming.** Check the live issue, actual source/dependency versions and the
   original failure case. Reopen design review if the proposed solution changes a contract. Keep
   owner authorization boundaries; this workflow grants no new deployment or publication rights.
6. **Close from evidence.** Mark the issue complete only after the implementation and required
   verification pass. Record the resolving change and final evidence, then move the row to the
   completed section without erasing its history.

For each entry, keep one authoritative issue rather than duplicating a full task list here.
Feature specifications and implementation plans still define what must be built and tested.

## Active queue

| Item | State / owner | Blocker and evidence | Re-entry condition and first check | Last verified |
|---|---|---|---|---|
| P0 single-panel prelude click timing | deferred / workspace-layout-control | The shared bridge prelude reads the holder's control point once and clicks it. A scripted panel floats by default and moves after its control first reports: in the single-panel modes' native runs for the two-bar change, the control's y went from 22 to 28. In the two-bar run `tg9` a click during that move reached the desktop and the case failed; [test evidence](parts/testing.md#workspace-layout-transport-probe-p0). The two-bar panels are now created non-floating. The single-panel modes keep floating panels and have not failed this way, because their clicks fell before or after the move. Which part of the move misroutes the click is not established. Tested in the Plasma test image with plasma-workspace 6.8.3, libplasma 6.8.3, KWin 6.8.2-3.fc44.pf5 and Qt 6.11.2. | The first single-panel `FAIL: focus popup not ready` whose control read was taken mid-move, or the next change to the shared prelude. Then create the probe panels non-floating there too, or click only after two equal control reports, and rerun every mode. | 2026-11-19 |
| P0 original concurrent-sweep control | blocked / workspace-layout-control | Installed Qt6.11.2 reaches the null-pending-call path identified by QTBUG-149316 ([upstream issue fix](https://github.com/qt/qtbase/commit/91ec4c85d454802521c76ba861e24b82c9a3b636)). Zero-probe/full-probe controls have matching normalized backtraces; [test evidence and limits](parts/testing.md#workspace-layout-transport-probe-p0). Ordered fixture shutdown does not qualify that concurrent path or fix Qt. | An independently approved fixed-Qt test environment; first rerun the frozen zero-probe/full-probe concurrent controls and inspect actual child statuses, retained crash diagnostics and final residuals. Do not weaken the ordinary fixture cleanup gate. | 2026-11-18 |

Dynamic tiling ships with 0.8.0 in the full profile (Fedora 44); on the stock profile it stays
unavailable, as KWin itself has no owner for it. Video wallpapers are a separate module, with no
dependency on tiling.

## Completed entries

| Item | Resolved by | Final evidence | Date |
|---|---|---|---|
| [#115: native ownership for dynamic tiling](https://github.com/archledger/plasma-fusion/issues/115) | The fork's native ownership ([archledger/kwin](https://github.com/archledger/kwin) PRs #8-#32, signed tag `v6.8.2-pf5`) and the placement script's tiler (#163, #164, #169, #170, #173, #176), shipped in the opt-in full profile ([ADR 0001](adr/0001-two-profile-distribution.md); #161, #166, #167, #171, #172) with 0.8.0 | The re-entry tests on the ThinkPad (`docs/issue115-reentry-tests.md`; the six-pass matrix on the packaged script, KWin's saved layouts and the shortcuts unchanged). NT08's session check in the full-profile VM: an orderly restart and a `kill -9` mid-session keep the placement file at P, leave no tree and crash nothing; the script unloaded mid-session crashed KWin until #173, and left the master off its float until the fork's `v6.8.2-pf4` (#174); records an earlier instance left are ended from `v6.8.2-pf5` and #176 (#175). ADR 0001's verification: the Copr builds, the VM lanes (`fresh`, `switch`), the ThinkPad lane with three reboots, `plasma-fusion status` in every state, and the security-cadence round (pf3 to pf4 in one dnf transaction) | 2026-11-14 |
| [#142: Fedora 44 Plasma 6.8.2 qualification](https://github.com/archledger/plasma-fusion/issues/142) | #150 (`1b48fa8`) and the owner-approved laptop update | The compiled parts pass their five ctest suites, and all six depth features pass their 174 checks on 6.8.2; `packaging/tested-versions.txt` is raised. The laptop runs Plasma 6.8.2 with stock KWin `6.8.2-3.fc44` and Plasma Fusion `0.6.0^266.git4fef0b5-1.fc44`; the login check recorded the versions as tested, the post-login run logged `versions=tested lock=tested; no change`, and the Fusion decoration, navigation effect, desktop and lock screen are active; no coredumps. See #142 for the final verification. | 2026-11-10 |
