# Governance

How Plasma Fusion is run: who decides, who does what, and what happens if the maintainer stops.
Last checked against the repository and its GitHub settings on 2026-10-02.

## Model

Plasma Fusion has a single maintainer, who makes the decisions. Anyone may propose a change; the
maintainer accepts or declines it and says why.

- **Proposals** come as issues (defects), GitHub Discussions (questions and ideas) or pull
  requests ([`CONTRIBUTING.md`](CONTRIBUTING.md)). Security problems go privately
  ([`SECURITY.md`](SECURITY.md)).
- **Visual decisions** follow the design boards in [`design/`](design/README.md): they set every
  colour, size and drawing. A change to the look starts with a change to the board.
- **Recorded decisions:** decisions with lasting effect are written down where the work happens:
  the tables "Decisions" and "Owner decisions" in [`docs/PLAN.md`](docs/PLAN.md), the part pages
  in [`docs/parts/`](docs/parts/), and the pull request that made the change.
- **Plans:** [`docs/ROADMAP.md`](docs/ROADMAP.md) says what the maintainer intends to do, and not
  do, in the next year.
- **Disagreement:** say so in the issue or pull request. The maintainer has the final word and
  explains it there.
- **Changing these rules:** a pull request that edits this file.

## Roles and responsibilities

| Role | Who today | Responsibilities |
|---|---|---|
| Maintainer | Wisbendji Fimerlus ([@archledger](https://github.com/archledger)) | Decides what goes in and what the project does next. Reviews and merges pull requests. Triages issues and Discussions. Keeps `main` building and the checks green. Handles the `plasma-update` issues, Dependabot pull requests and code scanning alerts ([`docs/parts/ci.md`](docs/parts/ci.md), "When something speaks up"). Keeps the documentation current. Enforces the [code of conduct](CODE_OF_CONDUCT.md); conduct reports go to the address in it, and today the maintainer is the only person who reads them. |
| Security contact | the maintainer | Reads private vulnerability reports, answers within a week, fixes, publishes advisories and credits reporters ([`SECURITY.md`](SECURITY.md)). |
| Reviewer (code owner) | the maintainer ([`.github/CODEOWNERS`](.github/CODEOWNERS)) | Approves pull requests. The ruleset on `main` needs one code owner's approval after the last push ([`docs/parts/ci.md`](docs/parts/ci.md), "Repository settings"). |
| Release manager | the maintainer | There are no releases yet (see "Releases" below). |
| Repository owner (GitHub admin) | the maintainer's personal account `archledger`, the only collaborator | Repository settings, the ruleset, security settings, advisories, deleting or transferring the repository. |
| Contributor | anyone | Follows [`CONTRIBUTING.md`](CONTRIBUTING.md): one subject per change, the coding standards, tests for new behaviour, a DCO sign-off on every commit, an SPDX header or `REUSE.toml` entry for new files. |
| Reporter | anyone | Reports bugs as issues, security problems privately. |

The maintainer may push to `main` directly: repository admins bypass the ruleset
([`docs/parts/ci.md`](docs/parts/ci.md)). Changes from anyone else, including Dependabot, go
through reviewed pull requests with the required checks.

## Releases

There are no releases and no version tags yet (checked 2026-10-02); the first, 0.2.0, is being
prepared. Until it is out the supported version is `main` and the packages built from it
([`SECURITY.md`](SECURITY.md)). Releases are signed `vX.Y.Z` tags; their files are listed in a
`SHA256SUMS` signed with the same key, F350 5339 8E3C 80FE 2089 1B82 C10B 8492 BD7F 30C6
([`.github/release-signing-key.asc`](.github/release-signing-key.asc)), which the installer pins and
the AUR package names. How to check a signature is in
[`docs/parts/installer.md`](docs/parts/installer.md); how a release is made, in
[`docs/RELEASING.md`](docs/RELEASING.md).

## Continuity

### Today

One person holds every role above. The GitHub repository belongs to the maintainer's personal
account, which is its only collaborator (checked 2026-10-02). Nobody else can merge a pull request,
close an issue, publish a release, change a repository setting or read a private vulnerability
report. The bus factor is 1.

If the maintainer stopped, the code would stay usable: it is free software (GPL-2.0-or-later, with
the artwork and documentation under CC-BY-SA-4.0; see the README's Licence section) and anyone may
fork it. The project itself would stop: its issues, pull requests and security reports would go
unanswered. The project does not yet meet the requirement that it can go on within a week after
losing one person.

### What is needed

1. **A second trusted person**, chosen by the maintainer, with:
   - write access to the repository (to triage and close issues, merge pull requests and publish
     releases) and an entry in `.github/CODEOWNERS`, so their approval counts;
   - the right to merge without the maintainer's approval when the maintainer is gone (today only
     the owner bypasses the ruleset on `main`);
   - admin rights: on a personal account only the owner has them, so this needs the repository in
     a GitHub organization with both people as owners;
   - their own signing key for releases and tags, once releases are signed.
2. **A GitHub successor** for the `archledger` account (account settings, "Successor settings").
   A successor can archive or transfer the account's public repositories after GitHub's deceased
   user process, which takes 7 to 21 days; it is a fallback, not a replacement for item 1.
3. **Shared access to the project's other entries:** the OpenSSF Best Practices entry (project
   15168) lets its owner give other people edit rights.
4. **Sealed keys and a will.** The Best Practices criterion also allows a project run by one
   person to leave the keys and passwords it needs with a trusted person in a sealed form (a
   lockbox), with a will that gives that person the rights to carry on. This cannot cover the
   GitHub login itself: GitHub's terms let a login be used by one person only
   ([Terms of Service, B.3 "Account Requirements"](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service#3-account-requirements)).
   It can cover the other keys, such as a release signing key once there is one, and the written
   permission to continue the project; the repository itself still needs item 1.

Who the second person is, and when these steps happen, is the maintainer's decision. This section
will name them once they have agreed.
