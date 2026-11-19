#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Capture and qualify P0 read/publish pipeline evidence. Never operate a desktop.

The scenario writes an exclusive mark and the number of wake-ups it fires, then fires them
concurrently. The settled step replays every pipeline event of the run up to the point where it
is confirmed: no read starts while a read or a publication is outstanding, at most one
publication is outstanding, every wake-up is followed by a read, at least one wake-up of the
burst met a busy pipeline, the burst's wake-ups coalesced into fewer reads, and both consumers
end online on their current request with a frame published after the mark. The provider's
revision counter starts at zero and rises by one per message, so the publication lines' message
counts give the highest revision published before the mark. The receipt is written only after
the step's record is recomputed from the raw logs.
"""

import json
import re
import sys
from pathlib import Path

if __package__:
    from .mixed_lifetime import complete_lines, events, require
else:
    from mixed_lifetime import complete_lines, events, require

CHECKS = ["roundtrip-native", "serialized-pipeline", "coalesced-wakes", "settled-consumers"]
LABEL = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
# console.info and console.warn lines of the provider, with the log's category prefix.
EVENT = re.compile(r"(?:\S+: )?layout-probe: (wake received|read started|read finished|"
                   r"publication (?:online|offline) ([0-9]+)|publication writes ([0-9]+)|"
                   r"publication failed)")
# Any other read or publication line is a format this checker does not know: fail, never skip.
PIPELINE_LINE = re.compile(r"layout-probe: (?:read |publication )")


def load(directory: Path, name: str):
    return json.loads((directory / name).read_text())


def line_counts(directory: Path) -> dict:
    return {"shellLines": len(complete_lines(directory / "plasmashell.log")),
            "kwinLines": len(complete_lines(directory / "kwin.log"))}


def mark(directory: Path, label: str) -> dict:
    require(isinstance(label, str) and LABEL.fullmatch(label) is not None,
            "invalid pipeline mark label")
    value = {"schema": 1} | line_counts(directory)
    with (directory / f"pipeline-mark-{label}.json").open("x") as output:
        json.dump(value, output)
    return value


def replay(lines: list, burst_start: int) -> dict:
    """Every pipeline event of the run, in order; counts only those after the burst mark.

    A wake-up owes the pipeline a read until the next read starts: one that arrives while idle
    starts its read at once, and one that arrives while busy must be followed by a later read.
    """
    reading, outstanding, owed = False, 0, False
    published = {"before": 0, "total": 0}
    counts = {"wakes": 0, "busyWakes": 0, "reads": 0, "publications": 0, "saves": 0,
              "failedPublications": 0}
    for index, line in enumerate(lines):
        text = line.rstrip("\n")
        match = EVENT.fullmatch(text)
        if match is None:
            require(PIPELINE_LINE.search(text) is None, f"unrecognized pipeline line: {text[:80]}")
            continue
        kind, after = match.group(1), index >= burst_start
        if kind == "wake received":
            owed = True
            counts["wakes"] += after
            counts["busyWakes"] += after and (reading or outstanding > 0)
        elif kind == "read started":
            require(not reading, "a read started while another read was running")
            require(outstanding == 0, "a read started while a publication was outstanding")
            reading, owed = True, False
            counts["reads"] += after
        elif kind == "read finished":
            require(reading, "a read finished that was not running")
            reading = False
        elif kind.startswith("publication writes") or kind == "publication failed":
            require(outstanding == 1, "a publication finished that was not outstanding")
            outstanding = 0
            if after:
                counts["saves"] += int(match.group(3) or 0)
                counts["failedPublications"] += kind == "publication failed"
        else:
            require(outstanding == 0, "more than one publication outstanding")
            outstanding = 1
            counts["publications"] += after
            published["total"] += int(match.group(2))
            if not after:
                published["before"] = published["total"]
    return {"reading": reading, "outstanding": outstanding, "owed": owed,
            "published": published, "counts": counts}


def settled_consumers(shell: list, published: dict) -> list:
    """Each consumer's last state is online, on its current request, from a frame the provider
    published after the burst mark: above every revision published before it, and no higher than
    any revision published at all."""
    latest = {}
    for _, row in events(shell, "observation"):
        require(isinstance(row, dict) and isinstance(row.get("boot"), str),
                "malformed observation event")
        latest[row["boot"]] = row
    require(len(latest) == 2, "expected exactly two probe consumers")
    for boot, row in sorted(latest.items()):
        packet = row.get("packet")
        require(row.get("phase") == "online" and isinstance(packet, dict)
                and packet.get("request") == row.get("request")
                and packet.get("status") == "online" and type(packet.get("revision")) is int
                and published["before"] < packet["revision"] <= published["total"],
                f"consumer {boot} did not settle online on its current request with a frame"
                " published after the burst")
    return sorted(latest)


def evaluate(directory: Path, end: dict | None) -> dict:
    start = load(directory, "pipeline-mark-burst.json")
    require(isinstance(start, dict) and set(start) == {"schema", "shellLines", "kwinLines"}
            and start["schema"] == 1, "invalid pipeline mark")
    burst = load(directory, "pipeline-burst.json")
    require(isinstance(burst, dict) and set(burst) == {"schema", "wakes"} and burst["schema"] == 1
            and type(burst["wakes"]) is int and burst["wakes"] > 0, "invalid pipeline burst record")
    shell = complete_lines(directory / "plasmashell.log")
    backend = complete_lines(directory / "kwin.log")
    stop = {"shellLines": len(shell), "kwinLines": len(backend)} if end is None else end
    require(isinstance(stop, dict) and set(stop) == {"shellLines", "kwinLines"},
            "invalid pipeline evidence end")
    for field, total in (("shellLines", len(shell)), ("kwinLines", len(backend))):
        require(type(start[field]) is int and type(stop[field]) is int
                and 0 <= start[field] <= stop[field] <= total, "invalid pipeline evidence window")
    state = replay(backend[:stop["kwinLines"]], start["kwinLines"])
    counts = state["counts"]
    require(not state["reading"] and state["outstanding"] == 0,
            "the pipeline has not settled: a read or publication is still outstanding")
    require(not state["owed"], "a wake-up was never followed by a read")
    require(counts["wakes"] == burst["wakes"],
            f"expected {burst['wakes']} wakes after the burst mark, found {counts['wakes']}")
    require(counts["busyWakes"] >= 1, "no wake arrived while the pipeline was busy")
    require(counts["reads"] < counts["wakes"], "the burst's wake-ups did not coalesce")
    boots = settled_consumers(shell[:stop["shellLines"]], state["published"])
    return {"counts": counts, "published": state["published"], "boots": boots, "end": stop}


def record_step(directory: Path, name: str) -> dict:
    require(name == "settled", "unknown pipeline step")
    record = evaluate(directory, None)
    with (directory / "pipeline-settled.json").open("x") as output:
        json.dump(record, output)
    return record


def check_pipeline(directory: Path) -> None:
    record = load(directory, "pipeline-settled.json")
    require(isinstance(record, dict) and isinstance(record.get("end"), dict),
            "invalid pipeline evidence record")
    require(evaluate(directory, record["end"]) == record,
            "settled record does not match its raw evidence")


def write_receipt(directory: Path) -> None:
    """The receipt's check list has one source: it is written only after the full check."""
    check_pipeline(directory)
    with (directory / "pipeline-result.json").open("x") as output:
        json.dump({"schema": 1, "passed": True, "checks": CHECKS}, output)


def main() -> None:
    arguments = sys.argv[1:]
    try:
        if len(arguments) == 3 and arguments[0] == "mark":
            print(json.dumps(mark(Path(arguments[1]), arguments[2])))
        elif len(arguments) == 3 and arguments[0] == "step":
            print(json.dumps(record_step(Path(arguments[1]), arguments[2])))
        elif len(arguments) == 2 and arguments[0] == "receipt":
            write_receipt(Path(arguments[1]))
            print("PASS: pipeline evidence")
        else:
            raise SystemExit("usage: pipeline.py {mark OUT LABEL|step OUT NAME|receipt OUT}")
    except (ValueError, OSError) as error:
        raise SystemExit(f"pipeline: {error}") from None


if __name__ == "__main__":
    main()
