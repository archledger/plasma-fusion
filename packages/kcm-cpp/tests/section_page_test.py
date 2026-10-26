#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Verify the real KCM shows only the selected group and keeps its settings across navigation."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
TITLES = [
    ["Style", "Accent color", "Glass and motion", "Icons"],
    ["Dock and top bar", "Launcher", "Desktop"],
    ["Window buttons", "Windows", "Tablet", "Touchpad gestures"],
    ["Lock & Login", "Battery"],
    ["Start over"],
]


def run_preview(section, *args):
    """The navigation report, the time the preview took and its stderr; the screenshot must exist."""
    with tempfile.TemporaryDirectory(prefix="pf-kcm-sections-") as directory:
        page = Path(directory) / "page.png"
        started = time.monotonic()
        result = subprocess.run([sys.executable, str(HERE / "offscreen_preview.py"), str(page), "dark",
                                 "--navigation", "--section", str(section), *args], capture_output=True,
                                text=True, timeout=30, check=False)
        seconds = time.monotonic() - started
        assert result.returncode == 0, f"the preview exited {result.returncode}\n{result.stderr}"
        assert page.is_file(), "the preview quit before its screenshot\n" + result.stderr
    for line in result.stdout.splitlines():
        if line.startswith("REPORT_NAVIGATION "):
            return json.loads(line.removeprefix("REPORT_NAVIGATION ")), seconds, result.stderr
    raise AssertionError("the preview printed no navigation report\n" + result.stdout + result.stderr)


def preview(section, *args):
    report, _, stderr = run_preview(section, *args)
    assert "pending" in report and "stepErrors" in report, report
    assert not report["stepErrors"], f"navigation steps failed: {report}\n{stderr}"
    assert not report["pending"], f"navigation steps did not finish: {report}"
    return report


def check_report_ordering():
    """The report and the quitting screenshot wait for late steps; a hung or failing step is named."""
    # Every later action of the steps comes after the report's (1 s) and the screenshot's (1.2 s)
    # own times, as on a starved event loop.
    result = preview(0, "--width", "400", "--focus-switch", "--scroll-roundtrip", "--rapid-switch",
                     "--step-delay", "1500")
    assert result["focus"]["tabIntoSection"] and result["focus"]["backtabToNavigation"], result["focus"]
    assert "after" in result["scroll"] and "after" in result["rapid"], result
    print("PASS the report and the screenshot wait for late navigation steps")
    report, seconds, _ = run_preview(0, "--width", "400", "--focus-switch", "--step-hang", "focus",
                                     "--report-deadline", "2")
    assert report["pending"] == ["focus"] and report["stepErrors"] == {}, report
    assert report["focus"].get("tabIntoSection") is not None, report["focus"]
    assert seconds < 12, seconds
    print("PASS a step that never finishes is reported as pending after the deadline")
    report, seconds, stderr = run_preview(0, "--width", "400", "--focus-switch", "--step-fail", "focus")
    assert list(report["stepErrors"]) == ["focus"] and report["pending"] == [], report
    assert "--step-fail focus" in report["stepErrors"]["focus"], report
    assert "tabIntoSection" not in report["focus"], report["focus"]
    assert "Traceback" in stderr, stderr
    assert seconds < 12, seconds
    print("PASS a failing step is reported at once and its later actions are skipped")


def main():
    check_report_ordering()
    for section, titles in enumerate(TITLES):
        result = preview(section, "--width", "1100")
        assert result["available"], "section navigation is missing"
        assert len(result["labels"]) == 5
        assert result["selected"] == section
        assert result["titles"] == titles, result
        assert not result["compact"]
        assert result["warnings"] == [], result["warnings"]
        print("PASS section", section, titles)
    result = preview(4, "--width", "400", "--section-roundtrip", "--state",
                     "needsSave=true", "dockSize=2", "glass=1", "lockNotifications=false")
    assert result["compact"] and result["selected"] == 4
    assert result["state"]["needsSave"] is True
    assert result["state"]["dockSize"] == 2
    assert result["state"]["glass"] == 1
    assert result["state"]["lockNotifications"] is False
    assert result["pendingVisible"] is True
    print("PASS narrow navigation retains settings and pending Apply state")
    result = preview(1, "--width", "900", "--height", "400", "--scroll-roundtrip",
                     "--state", "needsSave=true", "errorText=Test error", "infoText=Test information")
    assert result["scroll"]["before"] == 220
    assert abs(result["scroll"]["after"] - result["scroll"]["before"]) <= 1, result["scroll"]
    assert result["errorVisible"] and result["infoVisible"] and result["pendingVisible"]
    assert result["warnings"] == [], result["warnings"]
    print("PASS section scroll and global messages survive navigation")
    result = preview(1, "--width", "900", "--height", "400", "--rapid-switch")
    assert result["rapid"]["before"] == 220
    assert result["rapid"]["after"] == result["rapid"]["before"], result["rapid"]
    print("PASS rapid section switches preserve each section's scroll position")
    for width in (900, 400):
        result = preview(0, "--width", str(width), "--focus-switch")
        assert result["focus"]["visible"], result["focus"]
        assert result["focus"]["after"] == result["focus"]["before"], result["focus"]
        assert result["focus"]["tabIntoSection"], result["focus"]
        assert result["focus"]["backtabToNavigation"], result["focus"]
        print("PASS hidden settings and Tab/Backtab traversal at width", width)
    result = preview(2, "--width", "900", "--font-pt", "19.5")
    assert result["compact"] and result["selected"] == 2
    assert result["warnings"] == [], result["warnings"]
    result = preview(2, "--width", "2000", "--font-pt", "19.5")
    assert not result["compact"] and result["selected"] == 2
    assert result["warnings"] == [], result["warnings"]
    print("PASS native KDE platform-font scaling chooses a fitting navigation surface")


if __name__ == "__main__":
    main()
