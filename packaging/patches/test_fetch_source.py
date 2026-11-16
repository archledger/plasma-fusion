#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""fetch-source.sh, the patch lanes' source fetch, against stand-ins for dnf, rpm, sleep and podman
(issues #203 and #206). Offline: python3 packaging/patches/test_fetch_source.py (the build workflow
runs it)."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

PATCHES = Path(__file__).resolve().parent
FETCH = PATCHES / "fetch-source.sh"
NAME = "kwin"
VR = "6.8.3-1.fc44"
SRC = f"{NAME}-{VR}.src.rpm"

# dnf [--refresh] download --srpm --destdir=DIR NAME-VERSION-RELEASE: one step of $FAKE_PLAN per call,
# the last one repeating. "ok" writes the package asked for; "none" fetches nothing and exits 0, as
# dnf5 does when it knows the binary package and the mirror's source repository lacks its source
# package; "missing" fetches nothing and exits 1, as for a package it does not know at all; "other",
# "othername" and "binary" write a file under the name asked for that is another build, another
# package, or a binary package. The file is a stand-in header that the rpm stand-in reads.
DNF = r"""#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_CALLS"
destdir= spec=
for a in "$@"; do
  case $a in
    --destdir=*) destdir=${a#--destdir=} ;;
    -*|download) ;;
    *) spec=$a ;;
  esac
done
n=$(wc -l <"$FAKE_CALLS")
step=$(sed -n "${n}p" "$FAKE_PLAN")
[ -n "$step" ] || step=$(tail -n 1 "$FAKE_PLAN")
release=${spec##*-} rest=${spec%-*}
version=${rest##*-} name=${rest%-*}
header() { printf 'NAME=%s\nVERSION=%s\nRELEASE=%s\nSOURCERPM=%s\n' "$1" "$2" "$3" "$4" >"$destdir/$spec.src.rpm"; }
echo "Updating and loading repositories:"
echo "Downloading Packages:"
case $step in
  ok) header "$name" "$version" "$release" '(none)' ;;
  none) ;;
  missing) echo "No package \"$spec\" available; You might want to use --skip-unavailable option." >&2; exit 1 ;;
  other) header "$name" 6.8.2 3.fc44 '(none)' ;;
  othername) header another-package "$version" "$release" '(none)' ;;
  binary) header "$name" "$version" "$release" "$spec.src.rpm" ;;
esac
exit 0
"""

# rpm -qp --qf FORMAT FILE: FORMAT with each %{TAG} taken from FILE's TAG=value lines.
RPM = r"""#!/bin/bash
qf= file=
while [ $# -gt 0 ]; do
  case $1 in
    --qf|--queryformat) qf=$2; shift ;;
    -*) ;;
    *) file=$1 ;;
  esac
  shift
done
[ -f "$file" ] || { echo "error: open of $file failed: No such file or directory" >&2; exit 1; }
out=$qf
while IFS='=' read -r tag value; do out=${out//"%{$tag}"/$value}; done <"$file"
printf '%s' "$out"
"""

# sleep SECONDS: recorded, not waited.
SLEEP = r"""#!/bin/bash
printf '%s\n' "$1" >>"$FAKE_SLEEPS"
"""

# podman ARGS: recorded one per line, nothing started.
PODMAN = r"""#!/bin/bash
printf '%s\n' "$@" >"$PODMAN_ARGS"
"""


class FetchSourceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name, text in (("dnf", DNF), ("rpm", RPM), ("sleep", SLEEP), ("podman", PODMAN)):
            tool = self.bin / name
            tool.write_text(text)
            tool.chmod(0o755)
        self.plan = self.root / "plan"
        self.calls = self.root / "calls"
        self.sleeps = self.root / "sleeps"
        self.dest = self.root / "source"

    def env(self, **extra):
        env = {**os.environ, "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}", "FAKE_PLAN": str(self.plan),
               "FAKE_CALLS": str(self.calls), "FAKE_SLEEPS": str(self.sleeps), **extra}
        if "PF_FETCH_WAIT" not in extra:
            env.pop("PF_FETCH_WAIT", None)
        return env

    def fetch(self, *plan, args=None, wait=None):
        """Run the helper with dnf following PLAN; the result, dnf's calls and the waits asked for."""
        self.plan.write_text("".join(f"{step}\n" for step in plan))
        for log in (self.calls, self.sleeps):
            log.unlink(missing_ok=True)
        extra = {} if wait is None else {"PF_FETCH_WAIT": wait}
        result = subprocess.run(["bash", str(FETCH), *(args if args is not None else [NAME, VR, str(self.dest)])],
                                capture_output=True, text=True, check=False, timeout=20, env=self.env(**extra))
        calls = self.calls.read_text().splitlines() if self.calls.exists() else []
        sleeps = self.sleeps.read_text().split() if self.sleeps.exists() else []
        return result, calls, sleeps

    def test_fetches_the_package_asked_for(self):
        result, calls, sleeps = self.fetch("ok")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.dest / SRC).is_file())
        self.assertEqual(len(calls), 1, calls)
        words = calls[0].split()
        self.assertEqual(words[words.index("download"):], ["download", "--srpm", f"--destdir={self.dest}", f"kwin-{VR}"])
        self.assertNotIn("--refresh", words)
        self.assertIn(f"fetched {SRC} (attempt 1 of 4)", result.stderr)
        self.assertEqual(sleeps, [])

    def test_any_source_package_by_its_name(self):
        # The plasma-workspace lane's package (#206): the name is the helper's first argument, and the
        # check reads it back from the file.
        result, calls, _ = self.fetch("ok", args=["plasma-workspace", VR, str(self.dest)])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.dest / f"plasma-workspace-{VR}.src.rpm").is_file())
        self.assertEqual(calls[0].split()[-1], f"plasma-workspace-{VR}")
        self.assertIn(f"fetched plasma-workspace-{VR}.src.rpm (attempt 1 of 4)", result.stderr)

    def test_a_download_that_exits_0_with_nothing_is_no_download(self):
        # The lanes' failure in #203 and #206: dnf exits 0, there is no file. Each further attempt asks
        # dnf for fresh metadata, after waits that grow by 30 s, and the last one says what it was.
        result, calls, sleeps = self.fetch("none")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(len(calls), 4, calls)
        self.assertNotIn("--refresh", calls[0].split())
        for call in calls[1:]:
            self.assertIn("--refresh", call.split())
        self.assertEqual(sleeps, ["30", "60", "90"])
        self.assertIn(f"could not fetch {SRC}: 4 attempts found it on none of the mirrors", result.stderr)
        self.assertIn("updates-source", result.stderr)
        self.assertFalse((self.dest / SRC).exists())

    def test_the_message_names_both_causes_and_how_to_tell(self):
        # A build newer than the mirrors clears within the day; one the repositories no longer carry
        # never does (their updates keep only each package's newest build), and a lane's default, the
        # installed build, is that on a machine behind Fedora's updates. The message names both, and
        # the query that lists what the repositories carry, for the package asked for.
        result, _, _ = self.fetch("none", args=["plasma-workspace", "6.8.2-1.fc44", str(self.dest), "1"])
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("could not fetch plasma-workspace-6.8.2-1.fc44.src.rpm", result.stderr)
        self.assertIn("usually clears within the day", result.stderr)
        self.assertIn("no longer in Fedora's repositories, whose updates keep only each package's newest build",
                      result.stderr)
        self.assertIn("'dnf repoquery --srpm plasma-workspace' lists the builds they carry", result.stderr)

    def test_fresh_metadata_on_a_later_attempt_takes_it(self):
        result, calls, sleeps = self.fetch("none", "ok")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 2, calls)
        self.assertIn("--refresh", calls[1].split())
        self.assertEqual(sleeps, ["30"])
        self.assertIn(f"attempt 1 of 4: no {SRC} from this mirror", result.stderr)
        self.assertIn(f"fetched {SRC} (attempt 2 of 4)", result.stderr)
        self.assertTrue((self.dest / SRC).is_file())

    def test_dnf_failing_outright_is_status_3_not_dnf_s(self):
        result, calls, _ = self.fetch("missing")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(len(calls), 4, calls)

    def test_another_build_another_package_or_a_binary_package_under_the_name_is_refused(self):
        for step in ("other", "othername", "binary"):
            with self.subTest(step=step):
                result, calls, _ = self.fetch(step, args=[NAME, VR, str(self.dest), "2"])
                self.assertEqual(result.returncode, 3, result.stderr)
                self.assertEqual(len(calls), 2, calls)
                self.assertFalse((self.dest / SRC).exists(), "a refused file stays under the name asked for")

    def test_an_earlier_file_under_the_name_is_not_taken_for_this_download(self):
        self.dest.mkdir()
        (self.dest / SRC).write_text("NAME=kwin\nVERSION=6.8.3\nRELEASE=1.fc44\nSOURCERPM=(none)\n")
        result, calls, _ = self.fetch("none", args=[NAME, VR, str(self.dest), "1"])
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(len(calls), 1, calls)
        self.assertFalse((self.dest / SRC).exists())

    def test_the_attempts_are_bounded(self):
        for attempts, waits in (("1", []), ("3", ["30", "60"])):
            with self.subTest(attempts=attempts):
                result, calls, sleeps = self.fetch("none", args=[NAME, VR, str(self.dest), attempts])
                self.assertEqual(result.returncode, 3, result.stderr)
                self.assertEqual(len(calls), int(attempts), calls)
                self.assertEqual(sleeps, waits)

    def test_the_wait_step_can_be_set(self):
        for wait, waits in (("5", ["5", "10"]), ("0", ["0", "0"])):
            with self.subTest(wait=wait):
                result, _, sleeps = self.fetch("none", "none", "ok", args=[NAME, VR, str(self.dest), "3"], wait=wait)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(sleeps, waits)

    def test_dnf_s_output_is_standard_output_and_the_outcome_standard_error(self):
        # The callers keep standard output as download.log and show standard error in their log.
        result, _, _ = self.fetch("missing", "ok")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Downloading Packages:", result.stdout)
        self.assertIn(f'No package "kwin-{VR}" available', result.stdout)
        self.assertNotIn("fetched", result.stdout)
        self.assertIn("fetched", result.stderr)
        self.assertNotIn("Downloading Packages:", result.stderr)

    def test_usage_is_refused_before_anything_is_fetched(self):
        dest = str(self.dest)
        cases = (
            ([], None), ([NAME], None), ([NAME, VR], None), ([NAME, VR, dest, "2", "extra"], None),
            # A call from before the name was the first argument names no package; it stops here.
            ([VR, dest], None), ([VR, dest, "2"], None),
            (["", VR, dest], None), (["-kwin", VR, dest], None), (["kwin;id", VR, dest], None),
            (["../kwin", VR, dest], None), (["kw in", VR, dest], None),
            ([NAME, "6.8.3", dest], None), ([NAME, "6.8.3-1.fc44;id", dest], None), ([NAME, f"{VR} x", dest], None),
            ([NAME, "-1.fc44", dest], None), ([NAME, VR, ""], None),
            ([NAME, VR, dest, "0"], None), ([NAME, VR, dest, "21"], None), ([NAME, VR, dest, "08"], None),
            ([NAME, VR, dest, "x"], None),
            ([NAME, VR, dest], "08"), ([NAME, VR, dest], "x"), ([NAME, VR, dest], "-1"),
        )
        for args, wait in cases:
            with self.subTest(args=args, wait=wait):
                result, calls, _ = self.fetch("ok", args=args, wait=wait)
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertIn("usage:", result.stderr)
                self.assertEqual(calls, [])
                self.assertFalse(self.dest.exists())

    # The lanes: each container entry point fetches its package through the helper, and each script that
    # starts a container mounts the helper into it.
    ENTRY_POINTS = (
        ("kwin/build-in-container.sh", 'bash /fetch-source.sh kwin "$vr" /root/source > /out/download.log || exit 3'),
        ("kwin/native-tests-in-container.sh", 'bash /fetch-source.sh kwin "$vr" /root/source > /out/download.log || exit 3'),
        ("plasma-workspace/build-in-container.sh",
         'bash /fetch-source.sh plasma-workspace "$vr" /root > /out/download.log || exit 3'),
    )

    def test_the_container_entry_points_fetch_through_it(self):
        # Each keeps dnf's output as download.log and stops as a setup failure (status 3) when the
        # package is not there; none asks dnf directly, and none installs the source package with its
        # errors thrown away (plasma-workspace's 'rpm -i ... 2>/dev/null' made that failure silent, #206).
        for entry, line in self.ENTRY_POINTS:
            with self.subTest(entry=entry):
                text = (PATCHES / entry).read_text()
                self.assertIn(line, text)
                code = [code_line for code_line in text.splitlines() if not code_line.lstrip().startswith("#")]
                # The download command itself, after dnf and its options or expansions (the helper's own
                # 'dnf "${refresh[@]}" download'); not 'dnf-command(download)', the capability
                # plasma-workspace's dnf install line asks for.
                direct = r'(^|\s)dnf5?(\s+(-\S+|"[^"]*"|\$\S+))*\s+download(\s|$)'
                self.assertEqual([c for c in code if re.search(direct, c)], [])
                self.assertEqual([c for c in code if re.search(r"\brpm -i\b", c) and "2>/dev/null" in c], [])

    def test_each_lane_mounts_the_helper_into_its_container(self):
        # The scripts run with a podman stand-in that records its arguments and starts nothing: the
        # helper has to be among the read-only mounts, at the path the entry points call.
        runs = (
            ("kwin/build.sh", ["6.7.5-1.fc44"]),
            ("kwin/native-tests.sh", ["6.7.5-1.fc44"]),
            ("kwin/native-tests.sh", ["--stock", "6.7.5-1.fc44"]),
            ("plasma-workspace/build.sh", ["6.8.3-1.fc44", "44"]),
        )
        for script, args in runs:
            with self.subTest(script=script, args=args), tempfile.TemporaryDirectory() as temporary:
                recorded = Path(temporary) / "podman.args"
                output = Path(temporary) / "out"
                positional = [a for a in args if not a.startswith("--")]
                flags = [a for a in args if a.startswith("--")]
                subprocess.run(["bash", str(PATCHES / script), *flags, str(output), *positional],
                               capture_output=True, text=True, check=False, timeout=10,
                               env=self.env(PODMAN_ARGS=str(recorded), PFV_DRI="0"))
                self.assertTrue(recorded.exists(), f"{script} did not start its container")
                words = recorded.read_text().splitlines()
                mounts = [words[i + 1] for i, word in enumerate(words[:-1]) if word == "-v"]
                helper = [m for m in mounts if m.endswith(":/fetch-source.sh:ro,z")]
                self.assertEqual(len(helper), 1, mounts)
                self.assertEqual(os.path.realpath(helper[0].rsplit(":/fetch-source.sh", 1)[0]), str(FETCH))


if __name__ == "__main__":
    unittest.main()
