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
| None | - | - | - | 2026-11-14 |

Dynamic tiling ships with 0.8.0 in the full profile (Fedora 44); on the stock profile it stays
unavailable, as KWin itself has no owner for it. Video wallpapers are a separate module, with no
dependency on tiling.

## Completed entries

| Item | Resolved by | Final evidence | Date |
|---|---|---|---|
| [#115: native ownership for dynamic tiling](https://github.com/archledger/plasma-fusion/issues/115) | The fork's native ownership ([archledger/kwin](https://github.com/archledger/kwin) PRs #8-#32, signed tag `v6.8.2-pf5`) and the placement script's tiler (#163, #164, #169, #170, #173, #176), shipped in the opt-in full profile ([ADR 0001](adr/0001-two-profile-distribution.md); #161, #166, #167, #171, #172) with 0.8.0 | The re-entry tests on the ThinkPad (`docs/issue115-reentry-tests.md`; the six-pass matrix on the packaged script, KWin's saved layouts and the shortcuts unchanged). NT08's session check in the full-profile VM: an orderly restart and a `kill -9` mid-session keep the placement file at P, leave no tree and crash nothing; the script unloaded mid-session crashed KWin until #173, and left the master off its float until the fork's `v6.8.2-pf4` (#174); records an earlier instance left are ended from `v6.8.2-pf5` and #176 (#175). ADR 0001's verification: the Copr builds, the VM lanes (`fresh`, `switch`), the ThinkPad lane with three reboots, `plasma-fusion status` in every state, and the security-cadence round (pf3 to pf4 in one dnf transaction) | 2026-11-14 |
| [#142: Fedora 44 Plasma 6.8.2 qualification](https://github.com/archledger/plasma-fusion/issues/142) | #150 (`1b48fa8`) and the owner-approved laptop update | The compiled parts pass their five ctest suites, and all six depth features pass their 174 checks on 6.8.2; `packaging/tested-versions.txt` is raised. The laptop runs Plasma 6.8.2 with stock KWin `6.8.2-3.fc44` and Plasma Fusion `0.6.0^266.git4fef0b5-1.fc44`; the login check recorded the versions as tested, the post-login run logged `versions=tested lock=tested; no change`, and the Fusion decoration, navigation effect, desktop and lock screen are active; no coredumps. See #142 for the final verification. | 2026-11-10 |
