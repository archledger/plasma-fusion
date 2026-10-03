# Contributing to Plasma Fusion

Plasma Fusion is maintained by one person. Bug reports, fixes and ideas are welcome. Everyone
taking part follows the [code of conduct](CODE_OF_CONDUCT.md); how decisions are made is in
[`GOVERNANCE.md`](GOVERNANCE.md).

## Reporting

- **Bugs:** open an issue with the Fedora and Plasma versions (`rpm -q plasma-fusion plasma-workspace`),
  whether the machine is in laptop or tablet posture, what you did, what you expected and a
  screenshot if it is visual.
- **Security problems:** do not open an issue; follow [`SECURITY.md`](SECURITY.md).
- **Questions and ideas:** GitHub Discussions.

## Changing something

1. Fork the repository and make a branch from `main`.
2. Read the part's page in `docs/parts/` first; the design boards in `design/` decide every colour,
   size and drawing.
3. Keep the change to one subject, following the coding standards below and the style of the
   surrounding code and comments. Update the part's page in `docs/parts/` in the same change when
   behaviour changes.
4. Run the checks that cover it:
   - `tools/build.sh` (every part, with its built-in checks) and `tools/checks/tests/run.sh`;
   - the coding style: `ruff check` for Python (`ruff.toml`), `git clang-format --diff main` for
     C++ (KDE's style, `.clang-format`) and `tools/checks/shellcheck.sh` for shell scripts; QML has
     no style tool yet and follows the surrounding code (4-space indentation). docs/parts/ci.md,
     "Coding style", says what they check;
   - the part's own tests (for example `tools/device/tests/gate-unit.sh`,
     `packages/common/tests/icontile.sh`, `packages/appicons/tests/*.py`), listed on its page;
   - new behaviour, and a bug fix, needs a test in an automated suite that would fail without it
     (the test policy in [`docs/parts/coverage.md`](docs/parts/coverage.md#test-policy)).
5. Give every new file an SPDX header or a `REUSE.toml` entry (`reuse lint` must pass).
6. Open a pull request against `main`. It needs the checks `DCO and attribution`,
   `REUSE compliance` and `plasma-fusion RPM (Fedora 44)` to pass; the maintainer reviews and
   merges it.

## Coding standards

Contributions follow these styles. Where a checker or formatter configuration is in the
repository, it is the exact rule; the build and CI run the checks listed in
[`docs/parts/ci.md`](docs/parts/ci.md).

- **Every file:** UTF-8 text with Unix line ends, indented with spaces. Comments say why, in plain
  sentences, wrapped at 100 characters. Files kept from upstream projects stay as they are.
- **Bash** (`#!/bin/bash`): clean under [ShellCheck](https://www.shellcheck.net/) at warning level
  (`shellcheck -S warning`). Start with `set -euo pipefail`; a script that must never stop on an
  error (such as the login check, which must always exit 0) says so in a comment instead. Quote
  every expansion, pass argument lists as arrays, run no data through `eval`, make temporary
  files with `mktemp`. Two-space indentation. A usage comment at the top that `--help` prints.
- **Python** (`python3`; the standard library and Pillow, PySide6 only where Qt must render):
  [PEP 8](https://peps.python.org/pep-0008/) for names, imports, spacing and four-space
  indentation. Comments and docstrings wrap at 100 characters; code lines stay within the line
  length of the checker configuration (most lines today are under 120). Run programs with
  `subprocess` and an argument list, never `shell=True`, with a timeout.
- **C++** (the compiled parts): the
  [KDE Frameworks coding style](https://community.kde.org/Policies/Frameworks_Coding_Style), as
  KDE's clang-format configuration
  ([KDEClangFormat](https://api.kde.org/ecm/kde-module/KDEClangFormat.html)) formats it. No new
  compiler warnings under `KDECompilerSettings`.
- **QML and JavaScript:** [Qt's QML coding conventions](https://doc.qt.io/qt-6/qml-codingconventions.html)
  as Plasma's own QML uses them, four-space indentation. Type function parameters. User-visible
  text goes through `i18n()`. Every interactive item has an accessible name
  (`tools/checks/a11y-lint.py`); animation durations come from the `Motion` tokens, never literal
  numbers (`tools/checks/motion-lint.sh`). Values from outside a widget that go into a command are
  typed, allowlisted or quoted ([`docs/SECURITY-ASSURANCE.md`](docs/SECURITY-ASSURANCE.md),
  section 6).
- **Commit messages:** see below.

These rules apply to new and changed code. Some existing code does not meet them yet and is
brought in line when it is changed (checked 2026-10-02):

- C++: all five C++ files of the settings module (`packages/kcm-cpp/`) and four files of the
  navigation effect (`packages/navigation-cpp/src/plugin/`) differ from KDE's clang-format; the
  window decoration (`packages/decoration-cpp/`) matches it.
- Bash: every script passes ShellCheck (`tools/checks/shellcheck.sh`, in CI); test scenarios that a
  test runner sources name their shell with `# shellcheck shell=bash`. The power service
  (`packages/powerfx/plasma-fusion-powerfx`) and the LibreOffice launcher
  (`packages/compat/plasma-fusion-libreoffice`) use `set -u` only, without a comment that says
  why. 16 test, measurement and test-session tools also run without `set -euo pipefail`.

## Commits

Every commit is signed off under the [Developer Certificate of Origin](https://developercertificate.org/):
`git commit -s` adds the line `Signed-off-by: Your Name <you@example.org>`. That line is the only
trailer a commit message carries; the commit check rejects other trailers (such as co-author
lines) and messages that name AI tools. Write what changed and why, in plain sentences.

Contributions are licensed like the files they change (see the README's Licence section).
