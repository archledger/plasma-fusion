#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Print this boot's crash count, or fail if the collector cannot provide it."""
import json
import os
from pathlib import Path
import shutil
import subprocess


def count_crashes():
    collector = shutil.which("coredumpctl")
    if collector is None:
        raise RuntimeError("coredumpctl unavailable")
    boot = next(line.split()[1] for line in Path("/proc/stat").read_text().splitlines() if line.startswith("btime "))
    result = subprocess.run([collector, "list", "--no-pager", "--json=short", "--since=@" + boot],
                            env={**os.environ, "LC_ALL": "C"}, capture_output=True, text=True)
    # coredumpctl returns 1 for the explicit no-matches case as well as for collector errors.
    if result.returncode == 1 and not result.stdout.strip() and result.stderr.strip().endswith("No coredumps found."):
        return 0
    if result.returncode != 0:
        raise RuntimeError(f"coredumpctl failed (exit {result.returncode}): {result.stderr.strip()}")
    try:
        rows = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError("invalid coredumpctl JSON") from error
    if not isinstance(rows, list):
        raise RuntimeError("coredumpctl JSON is not a list")
    return len(rows)


if __name__ == "__main__":
    try:
        print(count_crashes())
    except (OSError, RuntimeError, StopIteration) as error:
        raise SystemExit("crash-count: " + str(error))
