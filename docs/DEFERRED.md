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
| [#115: native ownership for dynamic tiling](https://github.com/archledger/plasma-fusion/issues/115) | Blocked / maintainer | Temporary custom-tree replacement changes manual membership and survives compositor restart; a narrow geometry-restore guard also misses native transitions. Native tests cover KWin 6.7.5 and 6.7.91 with Qt 6.11.2. | A reviewed native ownership/lifecycle design preserves the existing contracts. First reproduce the saved-tree and native Restore/fullscreen cases, then prove the proposed mechanism passes without a corrective geometry loop or persistent user-layout replacement. | 2026-10-23 |

Dynamic tiling remains unavailable while this entry is blocked. Diagnostic tests and documentation
do not count as an implementation. Video wallpapers are a separate module; this blocker neither
approves their specification nor creates a dependency on tiling.

## Completed entries

None recorded yet.
