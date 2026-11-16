#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""fetch-source.sh, the patch lanes' source fetch, against stand-ins for dnf, rpm, sleep and podman
(issues #203 and #206). Offline: python3 packaging/patches/test_fetch_source.py (the build workflow
runs it)."""

import os
from pathlib import Path
import re
import shutil
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

    def test_version_releases_fedora_uses_are_taken(self):
        # The refusal of an architecture is of the last part only: a minor bump after the dist tag, a
        # pre-release and another distribution's tag are version-releases.
        for vr in ("6.8.3-1.fc44.1", "6.8.90-0.1.beta.fc45", "6.8.3-1.el10_1", "6.8.3-1.fc44.x86"):
            with self.subTest(vr=vr):
                result, calls, _ = self.fetch("ok", args=[NAME, vr, str(self.dest), "1"])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls[0].split()[-1], f"kwin-{vr}")
                self.assertTrue((self.dest / f"kwin-{vr}.src.rpm").is_file())

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
            # dnf reads NAME-VERSION-RELEASE.ARCH as that build for ARCH, and saves the source package
            # without the architecture: a file this never finds.
            ([NAME, f"{VR}.x86_64", dest], None), ([NAME, f"{VR}.aarch64", dest], None),
            ([NAME, f"{VR}.noarch", dest], None), ([NAME, f"{VR}.src", dest], None), ([NAME, f"{VR}.i686", dest], None),
            ([NAME, VR, dest, "0"], None), ([NAME, VR, dest, "21"], None), ([NAME, VR, dest, "08"], None),
            ([NAME, VR, dest, "x"], None),
            ([NAME, VR, dest], "08"), ([NAME, VR, dest], "x"), ([NAME, VR, dest], "-1"),
        )
        for args, wait in cases:
            with self.subTest(args=args, wait=wait):
                # Each case on its own: a case that wrongly fetches leaves the directory behind.
                shutil.rmtree(self.dest, ignore_errors=True)
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

    # dnf's download command, wherever a command starts ('$(dnf', ';dnf', '/usr/bin/dnf'), after any
    # options, their values or expansions (the helper's own 'dnf "${refresh[@]}" download'); not
    # 'dnf-command(download)', the capability plasma-workspace's dnf install line asks for.
    DIRECT_DOWNLOAD = r"(^|[\s;&|(/`])dnf5?(\s+[^\s;&|]+)*?\s+download(\s|$)"
    # rpm installing or upgrading (-i, -ivh, -U, --install, --upgrade; not a query such as -qi), and
    # its standard error thrown away.
    RPM_INSTALL = r"(^|[\s;&|(/`])rpm\s(.*\s)?(-(?![A-Za-z]*q)[A-Za-z]*[iU][A-Za-z]*|--install|--upgrade)(\s|$)"
    ERRORS_DROPPED = r"(2|&)>\s*/dev/null|>\s*/dev/null\s+2>&1|2>&-"

    @staticmethod
    def commands(text):
        """The lines that are not comments, with backslash-continued lines joined."""
        return [line for line in text.replace("\\\n", " ").splitlines() if not line.lstrip().startswith("#")]

    def test_the_patterns_tell_the_commands_apart(self):
        # The patterns the entry points are checked with, on the forms they have to tell apart.
        direct = ('dnf download --srpm "kwin-$vr"', 'dnf download -q --source "plasma-workspace-$vr"',
                  'dnf "${refresh[@]}" download --srpm x', 'dnf --refresh download x', 'dnf5 download x',
                  'src=$(dnf download --srpm x)', 'true;dnf download x', '/usr/bin/dnf download x',
                  'dnf --repo updates-source download x', 'cd /root && dnf download x')
        not_direct = ("dnf install -y -q rpm-build 'dnf-command(download)' 'dnf-command(builddep)' >/dev/null",
                      'bash /fetch-source.sh kwin "$vr" /root/source > /out/download.log || exit 3',
                      'dnf install -y rpm-build dnf5-plugins python3 > /out/dependencies.log 2>&1',
                      'dnf builddep -y "$spec" >> /out/dependencies.log 2>&1', 'dnf install x > /out/download.log')
        dropped = ('rpm -i --define "_topdir $top" "x.src.rpm" 2>/dev/null', 'rpm -i x.src.rpm 2> /dev/null',
                   'rpm -ivh x.src.rpm >/dev/null 2>&1', 'rpm -i x.src.rpm &>/dev/null', 'rpm --install x 2>/dev/null',
                   'rpm -U x.rpm 2>&-', '/usr/bin/rpm -i x 2>/dev/null')
        kept = ('rpm -i --define "_topdir $top" "plasma-workspace-$vr.src.rpm"', 'rpm -i x.src.rpm 2>>/out/rpm.log',
                "rpm -qa --qf '%{NAME}\\n' | sort > /out/packages.txt", 'rpm -qi kwin 2>/dev/null',
                'rpm -qpi x.rpm 2>/dev/null', "configure=$(rpm --define \"_topdir $top\" --eval '%{cmake_kf6}')",
                'dnf builddep -y -q "$spec" >/dev/null')
        for line in direct:
            self.assertRegex(line, self.DIRECT_DOWNLOAD)
        for line in not_direct:
            self.assertNotRegex(line, self.DIRECT_DOWNLOAD)
        for line in dropped:
            self.assertTrue(re.search(self.RPM_INSTALL, line) and re.search(self.ERRORS_DROPPED, line), line)
        for line in kept:
            self.assertFalse(re.search(self.RPM_INSTALL, line) and re.search(self.ERRORS_DROPPED, line), line)

    def test_the_container_entry_points_fetch_through_it(self):
        # Each keeps dnf's output as download.log and stops as a setup failure (status 3) when the
        # package is not there; none asks dnf directly, and none installs a package with rpm's errors
        # thrown away (plasma-workspace's 'rpm -i ... 2>/dev/null' made that failure silent, #206).
        for entry, line in self.ENTRY_POINTS:
            with self.subTest(entry=entry):
                code = self.commands((PATCHES / entry).read_text())
                self.assertIn(line, [command.strip() for command in code], "the fetch is a command, not a comment")
                self.assertEqual([c for c in code if re.search(self.DIRECT_DOWNLOAD, c)], [])
                self.assertEqual([c for c in code if re.search(self.RPM_INSTALL, c) and re.search(self.ERRORS_DROPPED, c)],
                                 [])

    def run_lane(self, script, args, temporary, through=None):
        """Run a lane's host script with a podman stand-in (it records its arguments and starts
        nothing); its result and podman's arguments, or None when no container was started. THROUGH:
        a symbolic link to the lane's directory to run the script by."""
        recorded = Path(temporary) / "podman.args"
        recorded.unlink(missing_ok=True)
        lane, name = script.split("/")
        directory = PATCHES / lane
        if through is not None:
            through.symlink_to(directory, target_is_directory=True)
            directory = through
        positional = [a for a in args if not a.startswith("--")]
        flags = [a for a in args if a.startswith("--")]
        result = subprocess.run(["bash", str(directory / name), *flags, str(Path(temporary) / "out"), *positional],
                                capture_output=True, text=True, check=False, timeout=10,
                                env=self.env(PODMAN_ARGS=str(recorded), PFV_DRI="0"))
        return result, (recorded.read_text().splitlines() if recorded.exists() else None)

    LANES = (
        ("kwin/build.sh", ["6.7.5-1.fc44"]),
        ("kwin/native-tests.sh", ["6.7.5-1.fc44"]),
        ("kwin/native-tests.sh", ["--stock", "6.7.5-1.fc44"]),
        ("plasma-workspace/build.sh", ["6.8.3-1.fc44", "44"]),
    )

    def test_each_lane_mounts_the_helper_into_its_container(self):
        # The helper has to be among the read-only mounts given before the image, at the path the
        # entry points call, also when the lane's directory is reached through a symbolic link.
        for script, args in self.LANES:
            for linked in (False, True):
                with self.subTest(script=script, args=args, linked=linked), \
                        tempfile.TemporaryDirectory() as temporary:
                    through = Path(temporary) / "lane" if linked else None
                    result, words = self.run_lane(script, args, temporary, through)
                    self.assertIsNotNone(words, f"{script} did not start its container: {result.stderr}")
                    image = next(i for i, word in enumerate(words) if word.startswith("registry.fedoraproject.org/fedora:"))
                    mounts = [words[i + 1] for i, word in enumerate(words[:image - 1]) if word == "-v"]
                    helper = [m for m in mounts if m.endswith(":/fetch-source.sh:ro,z")]
                    self.assertEqual(len(helper), 1, mounts)
                    self.assertEqual(os.path.realpath(helper[0].rsplit(":/fetch-source.sh", 1)[0]), str(FETCH))
                    self.assertTrue(Path(helper[0].rsplit(":/fetch-source.sh", 1)[0]).is_file(), helper[0])

    def test_plasma_workspace_refuses_a_build_it_cannot_fetch_before_starting_a_container(self):
        # Fedora's build, the release ending with its dist tag, is checked before the container starts
        # (as the KWin scripts check theirs): usage (64), not a fetch failure (3) after the container's
        # setup. The lane's own rebuild, the default where it is installed, is named as such.
        cases = (("6.8.3", "not a Fedora build"), ("6.8.3-1", "not a Fedora build"),
                 ("6.8.3-1.fc44.x86_64", "not a Fedora build"), ("-1.fc44", "not a Fedora build"),
                 ("6.8.3-1.fc44;id", "not a Fedora build"), ("6.8.3-1.fc44.pf1", "came from (6.8.3-1.fc44)"))
        for vr, says in cases:
            with self.subTest(vr=vr), tempfile.TemporaryDirectory() as temporary:
                result, words = self.run_lane("plasma-workspace/build.sh", [vr, "44"], temporary)
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertIn(says, result.stderr)
                self.assertIsNone(words, "a container was started")
                self.assertFalse((Path(temporary) / "out").exists(), "OUT_DIR was made")
        for vr in ("6.8.3-1.fc44", "6.8.3-1.fc44.1"):
            with self.subTest(vr=vr), tempfile.TemporaryDirectory() as temporary:
                _, words = self.run_lane("plasma-workspace/build.sh", [vr, "44"], temporary)
                self.assertIsNotNone(words, f"{vr} did not start the container")
                self.assertEqual(words[-1], vr)


if __name__ == "__main__":
    unittest.main()
