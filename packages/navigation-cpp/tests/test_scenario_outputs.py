# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Failure-injection tests for the private-session output regression's oracle."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCENARIO = Path(__file__).parent / "vsession/scenario-outputs.sh"
DRIVER = r"""
OUT="$HOME/out"
mkdir -p "$OUT"
printf '0 0 none\n' > "$HOME/navigation-case"
: > "$HOME/active"
printf 'initial\n' > "$HOME/phase"
sleep() { :; }
kwrite() { :; }
shot() { :; }
qdbus() {
    if [[ "$*" != *activeEffects ]]; then echo true; return; fi
    local phase
    phase=$(cat "$HOME/phase")
    if [[ "$MODE:$phase" == escape-query-failure:escaped ||
          "$MODE:$phase" == removal-query-failure:removed ]]; then
        echo 'injected D-Bus failure' >&2
        return 42
    fi
    cat "$HOME/active"
}
pfinput() {
    if [[ "$*" == swipe* ]]; then
        if [[ "$(cat "$HOME/phase")" == escaped && "$MODE" == no-reopen ]]; then
            : > "$HOME/active"
        else
            echo plasmafusion_navigation > "$HOME/active"
        fi
        echo open > "$HOME/phase"
    else
        : > "$HOME/active"
        echo escaped > "$HOME/phase"
    fi
}
kscreen-doctor() {
    : > "$HOME/active"
    echo removed > "$HOME/phase"
    [[ "$MODE" == output-still-present ]] || touch "$HOME/removed"
}
source "$1"
"""
KWIN_STUB = """
import json
import os
from pathlib import Path
import sys

home = Path(os.environ["HOME"])
if sys.argv[1] == "windows":
    removed = (home / "removed").exists()
    if removed and os.environ["MODE"] == "output-query-failure":
        raise SystemExit(43)
    names = ["Virtual-1"] if removed else ["Virtual-0", "Virtual-1"]
    if removed and os.environ["MODE"] == "wrong-output-removed":
        names = ["Virtual-0"]
    print(json.dumps({"outputs": [{"name": name} for name in names], "windows": []}))
else:
    print(json.dumps({"id": "target", "output": "Virtual-0", "x": 300}))
"""


class ScenarioOutputsTests(unittest.TestCase):
    def run_scenario(self, mode):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            helper = home / "pf-tools/tests/lib/pfkwin.py"
            helper.parent.mkdir(parents=True)
            helper.write_text(KWIN_STUB)
            return subprocess.run(
                ["bash", "-c", DRIVER, "scenario-test", str(SCENARIO.resolve())],
                env={**os.environ, "HOME": tmp, "MODE": mode},
                capture_output=True, text=True, timeout=10,
            )

    def test_healthy_scenario_passes(self):
        result = self.run_scenario("healthy")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS: output removal closes the effect", result.stdout)

    def test_dismissal_query_errors_fail(self):
        for mode in ("escape-query-failure", "removal-query-failure"):
            with self.subTest(mode=mode):
                result = self.run_scenario(mode)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_second_open_fails(self):
        result = self.run_scenario("no-reopen")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_output_still_present_fails(self):
        result = self.run_scenario("output-still-present")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_output_query_error_fails(self):
        result = self.run_scenario("output-query-failure")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_removing_the_other_output_fails(self):
        result = self.run_scenario("wrong-output-removed")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
