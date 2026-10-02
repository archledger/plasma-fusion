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
| `cflite-pr` | pull requests that change a fuzzed tool, `fuzz/` or `.clusterfuzzlite/` | ClusterFuzzLite: the fuzzers (below) for 5 minutes in all against the change; a crash fails the check |
| `cflite-batch` | Sundays 02:40 UTC, by hand | ClusterFuzzLite: the fuzzers for 30 minutes in all on `main`; builds up the corpus the pull request runs start from |

Every action is pinned to a commit hash with its version in a comment; every job starts with a
read-only token and widens only what it needs (`issues: write` for the watcher's issue,
`pull-requests: write` for the labeler, `security-events`/`id-token` for Scorecard, `actions: read`
for ClusterFuzzLite's corpus artifacts). The labeler
uses `pull_request_target` to label pull requests from forks; it checks nothing out and runs no
code from the pull request (zizmor's warning about the trigger is suppressed there, with that
reason).

## Fuzzing (`fuzz/`, `.clusterfuzzlite/`)

Set up 2026-10-02. The fuzzers run the runtime Python code that parses files other programs write,
on arbitrary input, and check properties beyond "no exception". Each is an atheris fuzzer that
loads its tool from the file that is installed (`fuzz/load_tool.py`: the tools have no `.py`
suffix, so `importlib`'s `SourceFileLoader`, with atheris' coverage instrumentation on the tool's
functions) and calls the pure functions the tool's readers use:

| Fuzzer | Tool | Input | Checked |
|---|---|---|---|
| `app_icons_fuzzer` | `packages/appicons/plasma-fusion-app-icons` | a desktop file's path below an applications directory (first line) and its bytes, which also stand for plasmafusionrc | keys and values stripped; a key seen twice keeps its first value; an icon only for a visible application; `app_tile_name` has no `-`; a name the tool builds fits in a file name; the mode is `familiar` or `designs` |
| `previous_theme_fuzzer` | `tools/device/previous-theme.py` | four files separated by NUL bytes: the user's KConfig files, kdedefaults, the previous Global Theme's `contents/defaults` and `metadata.json` | parsed values stripped text; a later value of a key wins; the package's defaults files, with the theme's name in their comment, read back as exactly the values the generator chose |
| `keyboard_keys_fuzzer` | `packages/keyboard/plasma-fusion-keyboard-keys` | plasma-keyboard's `symbols.qml` | either the reason the page was left alone, or Esc, Tab and the four arrows each added once, the trademark key removed once, the semicolon kept, two more long-press lists; no input slower than libFuzzer's timeout (exponential backtracking; a quadratic pattern needs longer inputs, which `packages/keyboard/tests/patch_test.py` times) |

Each has hand-written seeds in `fuzz/corpus/<fuzzer>/` (the cases fixed when the fuzzing was set
up among them) and a libFuzzer dictionary `fuzz/<fuzzer>.dict`. Setting it up found, and fixed
with tests: plasmafusionrc or `designed-apps.txt` with a byte that is not UTF-8 stopped the
familiar icon tool; a desktop id below Wine's nested start menu longer than a file name stopped
its refresh; a previous Global Theme whose `metadata.json` was not an object stopped "My previous
desktop", and a name with line breaks added lines to its defaults (on the old code the fuzzer
finds the first from an empty corpus within seconds). Local runs of 150 s each on the fixed code
(laptop, atheris 3.1.0, Python 3.14) found nothing further: 1.2 million inputs for the icons, 363
thousand for "My previous desktop", 15 million for the keyboard. The ClusterFuzzLite builds run
slower (Python 3.11 with AddressSanitizer preloaded: about 700, 430 and 10 000 inputs a second).

ClusterFuzzLite (`.clusterfuzzlite/`): `project.yaml` (`language: python`), a `Dockerfile` on
OSS-Fuzz's `base-builder-python` pinned by digest, and `build.sh`, which makes each
`fuzz/*_fuzzer.py` a PyInstaller package (`compile_python_fuzzer`) that ships the tool named in the
fuzzer's `TOOL` line as data at the same path (found below `sys._MEIPASS`), with the modules the
tool imports passed as hidden imports, next to the seed corpus and the dictionary. The workflows
use AddressSanitizer, which OSS-Fuzz requires for Python (address or undefined). The corpus lives
in the workflow artifacts (no storage repository); there is no corpus pruning or coverage job.

Run a fuzzer locally (scratch on disk under `build/`; new inputs go to the first directory, never
the seed directory):

    python3 -m venv build/fuzzing/venv && build/fuzzing/venv/bin/pip install atheris
    mkdir -p build/fuzzing/corpus/app_icons_fuzzer
    build/fuzzing/venv/bin/python fuzz/app_icons_fuzzer.py -max_total_time=120 \
      -dict=fuzz/app_icons_fuzzer.dict -artifact_prefix=build/fuzzing/ \
      build/fuzzing/corpus/app_icons_fuzzer fuzz/corpus/app_icons_fuzzer
    build/fuzzing/venv/bin/python fuzz/app_icons_fuzzer.py build/fuzzing/crash-...   # replay one input

The ClusterFuzzLite build, as the workflows run it (from a clean export of the tree: `COPY .`
takes `build/` along otherwise), then OSS-Fuzz's checks of the result and one fuzzer:

    podman build -f .clusterfuzzlite/Dockerfile -t plasma-fusion-cflite .
    mkdir -p build/fuzzing/out
    podman run --rm -e FUZZING_LANGUAGE=python -e SANITIZER=address -e FUZZING_ENGINE=libfuzzer \
      -e ARCHITECTURE=x86_64 -v "$PWD/build/fuzzing/out:/out:Z" plasma-fusion-cflite compile
    podman run --rm -e FUZZING_LANGUAGE=python -e SANITIZER=address -e FUZZING_ENGINE=libfuzzer \
      -e ARCHITECTURE=x86_64 -v "$PWD/build/fuzzing/out:/out:Z" gcr.io/oss-fuzz-base/base-runner test_all.py
    podman run --rm ... gcr.io/oss-fuzz-base/base-runner run_fuzzer app_icons_fuzzer -max_total_time=60

Done on 2026-10-02 with the pinned builder and base-runner `sha256:5a37678b9610…`: the three
packages build (about 30 MB each), pass `test_all.py` and run from their seed corpora.

The base image's digest is not updated by Dependabot (it watches the actions only); to move it:
`skopeo inspect --format '{{.Digest}}' docker://gcr.io/oss-fuzz-base/base-builder-python:latest`.

## Repository settings

- Secret scanning and push protection: on.
- Dependabot alerts and security updates: on. Version updates for the workflows' actions:
  `.github/dependabot.yml` (weekly, a release proposed after 7 days, CodeQL's actions grouped).
- Code scanning: the `codeql` workflow (Actions, C/C++, JavaScript, Python; GitHub's default setup
  is off, because a workflow pins and audits the action like the others and Scorecard sees it), plus
  Scorecard's results.
- Private vulnerability reporting: on; `SECURITY.md` says how to report.
- Ruleset `main`: the branch cannot be deleted or force-pushed; changes come through pull requests
  with one approval from a code owner (`.github/CODEOWNERS`), given after the last push, on a branch
  up to date with `main`, and the checks `DCO and attribution`, `REUSE compliance` and
  `plasma-fusion RPM (Fedora 44)` passing. Repository admins bypass it: the maintainer pushes to
  `main` directly, as before, and a deliberate history fix stays possible (as on 2026-10-02).
  Dependabot and outside contributions go through reviewed pull requests.
- Discussions: on (questions and ideas; issues stay for defects).
- Social preview: the dark desktop board (`design/previews/Main.webp` scaled to 1024x640 and
  centred on 1280x640, each side filled with the board's edge colour row by row).
- OpenSSF Best Practices badge: passing, project 15168 (https://www.bestpractices.dev/projects/15168,
  registered 2026-10-02). Open items there: tagged releases (version tags, semantic versions,
  release notes: N/A until releases exist), broader automated tests, dynamic analysis (fuzzing).

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
- **A ClusterFuzzLite failure** (`cflite-pr` or `cflite-batch`): the run's artifacts hold the
  input; replay it with the fuzzer locally (above), fix the tool with a test
  (`packages/appicons/tests/`, `tools/device/tests/previous_theme_test.py`) and add the input to
  `fuzz/corpus/<fuzzer>/`. A failed property that the tool does not promise is fixed in the
  fuzzer instead.
