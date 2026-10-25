#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Verify the real KCM shows only the selected group and keeps its settings across navigation."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
TITLES = [
    ["Style", "Accent color", "Glass and motion", "Icons"],
    ["Dock and top bar", "Launcher", "Desktop"],
    ["Window buttons", "Windows", "Tablet", "Touchpad gestures"],
    ["Lock & Login", "Battery"],
    ["Start over"],
]


def preview(section, *args):
    with tempfile.TemporaryDirectory(prefix="pf-kcm-sections-") as directory:
        result = subprocess.run([sys.executable, str(HERE / "offscreen_preview.py"),
                                 str(Path(directory) / "page.png"), "dark", "--navigation",
                                 "--section", str(section), *args], capture_output=True, text=True,
                                timeout=30, check=True)
    for line in result.stdout.splitlines():
        if line.startswith("REPORT_NAVIGATION "):
            report = json.loads(line.removeprefix("REPORT_NAVIGATION "))
            assert not report.get("stepErrors"), f"navigation steps failed: {report}"
            assert not report.get("pending"), f"navigation steps did not finish: {report}"
            return report
    raise AssertionError(result.stdout + result.stderr)


def main():
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
