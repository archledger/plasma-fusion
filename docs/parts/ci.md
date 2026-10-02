# Part: continuous integration and repository automation

What runs on GitHub for `archledger/plasma-fusion`, what the repository settings are, and what to
do when one of them speaks up. Set up 2026-10-01 (CI) and 2026-10-02 (automation).

## Workflows (`.github/workflows/`)

| Workflow | When | What |
|---|---|---|
| `commits` | every push to `main`, every pull request | Each commit has exactly one `Signed-off-by` (DCO), no other trailer, and no message that names an AI product or agent |
| `reuse` | push, pull request | REUSE 3.3 compliance (`reuse lint`) |
| `build` | push, pull request | fedora:44: lint self-tests, the login-check unit tests, the noarch RPM (`packaging/build-rpm.sh`, `%check`, rpmlint), RPM as an artifact |
| `compiled` | changes to the compiled parts, weekly | navigation effect, decoration, settings module: `dnf builddep`, cmake, ctest, against Fedora 44's Plasma (**stable**) and against KDE's Plasma beta packages (**beta**, the `@kdesig/kde-beta` Copr; may fail without failing the run: an early warning for the next Plasma release) |
| `workflow-audit` | changes to workflows | zizmor (security) and actionlint (correctness) over the workflows |
| `codeql` | push, pull request, weekly | CodeQL over the workflows, the C++ parts (without building), the shell's JavaScript and the Python tools; results in the Security tab |
| `plasma-watch` | daily 06:25 UTC, by hand | Fedora 44's versions (stable updates and updates-testing) of the packages the login check watches, against `packaging/tested-versions.txt`; opens or updates one issue labelled `plasma-update` when Fedora has a newer one |
| `scorecard` | push to `main`, weekly, branch-protection changes | OpenSSF Scorecard: findings in the Security tab, published score for the README badge |
| `labeler` | pull requests | labels by the parts a pull request changes (`.github/labeler.yml`: icons, shell, kwin, settings, theme, boot, system, packaging, design, docs, ci) |

Every action is pinned to a commit hash with its version in a comment; every job starts with a
read-only token and widens only what it needs (`issues: write` for the watcher's issue,
`pull-requests: write` for the labeler, `security-events`/`id-token` for Scorecard). The labeler
uses `pull_request_target` to label pull requests from forks; it checks nothing out and runs no
code from the pull request (zizmor's warning about the trigger is suppressed there, with that
reason).

## Repository settings

- Secret scanning and push protection: on.
- Dependabot alerts and security updates: on. Version updates for the workflows' actions:
  `.github/dependabot.yml` (weekly, a release proposed after 7 days, CodeQL's actions grouped).
- Code scanning: the `codeql` workflow (Actions, C/C++, JavaScript, Python; GitHub's default setup
  is off, because a workflow pins and audits the action like the others and Scorecard sees it), plus
  Scorecard's results.
- Private vulnerability reporting: on; `SECURITY.md` says how to report.
- Ruleset `main`: the branch cannot be deleted or force-pushed; changes come through pull requests
  with one approval and the checks `DCO and attribution`, `REUSE compliance` and
  `plasma-fusion RPM (Fedora 44)` passing. Repository admins bypass it: the maintainer pushes to
  `main` directly, as before, and a deliberate history fix stays possible (as on 2026-10-02).
  Dependabot and outside contributions go through reviewed pull requests.
- Discussions: on (questions and ideas; issues stay for defects).
- Social preview: the dark desktop board (`design/previews/Main.webp`, cropped to 1280x640).

## When something speaks up

- **A Dependabot pull request** fails `commits` until its commit carries the maintainer's
  `Signed-off-by`: reword the commit (a plain message saying what moved and why, one trailer),
  force-push the pull request branch, merge when green.
- **A `plasma-update` issue**: Fedora 44 has a newer Plasma or Qt than Plasma Fusion is tested on.
  The test machines hold Plasma at 6.7.x (`/etc/dnf/libdnf5.conf.d/90-plasma-fusion-hold-plasma-6.8.conf`).
  Build the compiled parts against it (the `compiled` beta job shows the first breakage), test a
  private session (docs/parts/testing.md), fix, then raise the lines in
  `packaging/tested-versions.txt` and lift the hold. The issue is closed by hand.
- **The `compiled` beta job fails**: the next Plasma release breaks a compiled part. Not urgent
  while the hold is in place; the log names the API.
- **A code scanning or Scorecard alert**: Security tab; fix or dismiss with a reason.
