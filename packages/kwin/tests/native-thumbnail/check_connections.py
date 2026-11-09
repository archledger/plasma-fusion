# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Validate the native probe's repeated open/close connection snapshots."""
import argparse
import json
from pathlib import Path
import re


def check(text, *, release_hidden=True):
    snapshots = re.findall(r"PFTHUMB BEGIN (open|closed)\n(.*?)PFTHUMB END \1", text, re.S)
    assert len(snapshots) == 24, f"expected 24 snapshots, got {len(snapshots)}"
    counts = {"open": [], "closed": []}
    for index, (state, body) in enumerate(snapshots):
        assert state == ("open" if index % 2 == 0 else "closed"), "snapshots out of order"
        assert "PFTHUMB MISSING" not in body, "target window missing"
        clients = re.findall(r"^PFTHUMB CLIENTS\b[^\n]*$", body, re.M)
        assert len(clients) == 1, "expected one client observation per snapshot"
        expected = 1 if state == "open" or not release_hidden else 0
        assert clients[0] == f"PFTHUMB CLIENTS {expected}", f"wrong {state} preview assignment: {clients[0]}"
        signal = re.search(r"signal: frameGeometryChanged[^\n]*\n(.*?)(?=signal:|SIGNALS IN)", body, re.S)
        assert signal, "geometry signal not present in native dump"
        count = signal.group(1).count("<functor or function pointer>")
        assert count > 0, "geometry dump contains no connections"
        counts[state].append(count)
    for state, values in counts.items():
        assert len(set(values)) == 1, f"{state} geometry connections accumulated: {values}"
    if release_hidden:
        assert counts["closed"][0] < counts["open"][0], "closing did not release geometry connections"
    return counts


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("--retain-hidden", action="store_true")
    args = parser.parse_args()
    print(json.dumps(check(args.log.read_text(), release_hidden=not args.retain_hidden), indent=2))
