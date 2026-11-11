<!-- SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com> -->
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Architecture decision records

An ADR records one decision that shapes how Plasma Fusion is built, packaged or distributed:
the context, the decision, what it rules out and how it is verified. Day-to-day plans live in
[`docs/PLAN.md`](../PLAN.md) and [`docs/parts/`](../parts/); an ADR is for the choices that outlive
them.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-two-profile-distribution.md) | Two distribution profiles: stock and full | Accepted |

A new ADR is a pull request against `main`:

- One file, `NNNN-short-slug.md` with the next free number; no renumbering later.
- Sections: title, status, context, decision, consequences, verification. Anything a reader needs
  to check the decision against reality belongs in the text, with links.
- Status is `Proposed` while the pull request is open and `Accepted` (dated) once it merges. A
  later ADR that replaces it marks both: the old one `Superseded by NNNN`, the new one
  `Superseding NNNN`. Decisions are not edited in place after acceptance; a changed decision gets
  a new ADR.

ADR text is documentation (CC-BY-SA-4.0, like the other project documents); the licence is in the
repository's [`LICENSES/`](../../LICENSES/) directory.
