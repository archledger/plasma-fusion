# Contributing to Plasma Fusion

Plasma Fusion is maintained by one person. Bug reports, fixes and ideas are welcome.

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
3. Keep the change to one subject, in the style of the surrounding code and comments.
4. Run the checks that cover it:
   - `tools/build.sh` (every part, with its built-in checks) and `tools/checks/tests/run.sh`;
   - the coding style: `ruff check` for Python (`ruff.toml`), `git clang-format --diff main` for
     C++ (KDE's style, `.clang-format`) and `tools/checks/shellcheck.sh` for shell scripts; QML has
     no style tool yet and follows the surrounding code (4-space indentation). docs/parts/ci.md,
     "Coding style", says what they check;
   - the part's own tests (for example `tools/device/tests/gate-unit.sh`,
     `packages/common/tests/icontile.sh`, `packages/appicons/tests/*.py`), listed on its page;
   - new behaviour needs a test that would fail without it.
5. Give every new file an SPDX header or a `REUSE.toml` entry (`reuse lint` must pass).
6. Open a pull request against `main`. It needs the checks `DCO and attribution`,
   `REUSE compliance` and `plasma-fusion RPM (Fedora 44)` and one approval.

## Commits

Every commit is signed off under the [Developer Certificate of Origin](https://developercertificate.org/):
`git commit -s` adds the line `Signed-off-by: Your Name <you@example.org>`. That line is the only
trailer a commit message carries; the commit check rejects other trailers (such as co-author
lines) and messages that name AI tools. Write what changed and why, in plain sentences.

Contributions are licensed like the files they change (see the README's Licence section).
