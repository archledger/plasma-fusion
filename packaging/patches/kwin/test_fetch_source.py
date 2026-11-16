#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""fetch-source.sh against stand-ins for dnf, rpm and sleep (issue #203). Offline, so it also runs in
the lane's containers, which run this directory's tests before they build:
python3 -m unittest discover -s packaging/patches/kwin -v."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

FETCH = Path(__file__).with_name("fetch-source.sh")
VR = "6.8.3-1.fc44"
SRC = f"kwin-{VR}.src.rpm"

# dnf [--refresh] download --srpm --destdir=DIR SPEC: one step of $FAKE_PLAN per call, the last one
# repeating. "ok" writes the package asked for; "none" fetches nothing and exits 0, as dnf5 does when
# it knows the binary package and the mirror's source repository lacks its source package; "missing"
# fetches nothing and exits 1, as for a package it does not know at all; "other" and "binary" write a
# file under the name asked for that is another build, or a binary package. The file is a stand-in
# header that the rpm stand-in reads.
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
vr=${spec#kwin-}
header() { printf 'NAME=kwin\nVERSION=%s\nRELEASE=%s\nSOURCERPM=%s\n' "$1" "$2" "$3" >"$destdir/$spec.src.rpm"; }
echo "Updating and loading repositories:"
echo "Downloading Packages:"
case $step in
  ok) header "${vr%-*}" "${vr##*-}" '(none)' ;;
  none) ;;
  missing) echo "No package \"$spec\" available; You might want to use --skip-unavailable option." >&2; exit 1 ;;
  other) header 6.8.2 3.fc44 '(none)' ;;
  binary) header "${vr%-*}" "${vr##*-}" "$spec.src.rpm" ;;
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


class FetchSourceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name, text in (("dnf", DNF), ("rpm", RPM), ("sleep", SLEEP)):
            tool = self.bin / name
            tool.write_text(text)
            tool.chmod(0o755)
        self.plan = self.root / "plan"
        self.calls = self.root / "calls"
        self.sleeps = self.root / "sleeps"
        self.dest = self.root / "source"

    def fetch(self, *plan, args=None, wait=None):
        """Run the helper with dnf following PLAN; the result, dnf's calls and the waits asked for."""
        self.plan.write_text("".join(f"{step}\n" for step in plan))
        for log in (self.calls, self.sleeps):
            log.unlink(missing_ok=True)
        env = {**os.environ, "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}", "FAKE_PLAN": str(self.plan),
               "FAKE_CALLS": str(self.calls), "FAKE_SLEEPS": str(self.sleeps)}
        env.pop("PF_FETCH_WAIT", None)
        if wait is not None:
            env["PF_FETCH_WAIT"] = wait
        result = subprocess.run(["bash", str(FETCH), *(args if args is not None else [VR, str(self.dest)])],
                                capture_output=True, text=True, check=False, timeout=20, env=env)
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

    def test_a_download_that_exits_0_with_nothing_is_no_download(self):
        # The lane's failure in #203: dnf exits 0, there is no file. Each further attempt asks dnf for
        # fresh metadata, after waits that grow by 30 s, and the last one says what it was.
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

    def test_another_build_or_a_binary_package_under_the_name_is_refused(self):
        for step in ("other", "binary"):
            with self.subTest(step=step):
                result, calls, _ = self.fetch(step, args=[VR, str(self.dest), "2"])
                self.assertEqual(result.returncode, 3, result.stderr)
                self.assertEqual(len(calls), 2, calls)
                self.assertFalse((self.dest / SRC).exists(), "a refused file stays under the name asked for")

    def test_an_earlier_file_under_the_name_is_not_taken_for_this_download(self):
        self.dest.mkdir()
        (self.dest / SRC).write_text("NAME=kwin\nVERSION=6.8.3\nRELEASE=1.fc44\nSOURCERPM=(none)\n")
        result, calls, _ = self.fetch("none", args=[VR, str(self.dest), "1"])
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(len(calls), 1, calls)
        self.assertFalse((self.dest / SRC).exists())

    def test_the_attempts_are_bounded(self):
        for attempts, waits in (("1", []), ("3", ["30", "60"])):
            with self.subTest(attempts=attempts):
                result, calls, sleeps = self.fetch("none", args=[VR, str(self.dest), attempts])
                self.assertEqual(result.returncode, 3, result.stderr)
                self.assertEqual(len(calls), int(attempts), calls)
                self.assertEqual(sleeps, waits)

    def test_the_wait_step_can_be_set(self):
        for wait, waits in (("5", ["5", "10"]), ("0", ["0", "0"])):
            with self.subTest(wait=wait):
                result, _, sleeps = self.fetch("none", "none", "ok", args=[VR, str(self.dest), "3"], wait=wait)
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
            ([], None), ([VR], None), ([VR, dest, "2", "extra"], None),
            (["6.8.3", dest], None), (["6.8.3-1.fc44;id", dest], None), ([f"{VR} x", dest], None), (["-1.fc44", dest], None),
            ([VR, ""], None),
            ([VR, dest, "0"], None), ([VR, dest, "21"], None), ([VR, dest, "08"], None), ([VR, dest, "x"], None),
            ([VR, dest], "08"), ([VR, dest], "x"), ([VR, dest], "-1"),
        )
        for args, wait in cases:
            with self.subTest(args=args, wait=wait):
                result, calls, _ = self.fetch("ok", args=args, wait=wait)
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertIn("usage:", result.stderr)
                self.assertEqual(calls, [])
                self.assertFalse(self.dest.exists())

    def test_the_container_entry_points_fetch_through_it(self):
        # Both builds take the source package from the helper, keep dnf's output as download.log and
        # stop as a setup failure (status 3) when it is not there; none asks dnf directly any more.
        for entry in ("build-in-container.sh", "native-tests-in-container.sh"):
            with self.subTest(entry=entry):
                text = Path(__file__).with_name(entry).read_text()
                self.assertIn('bash /patches/fetch-source.sh "$vr" /root/source > /out/download.log || exit 3', text)
                code = [line for line in text.splitlines() if not line.lstrip().startswith("#")]
                self.assertEqual([line for line in code if re.search(r"\bdnf\b.*\bdownload\b", line)], [])


if __name__ == "__main__":
    unittest.main()
