#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Capture and qualify P0 two-bar evidence. Never operate a desktop.

Two probe bars sit on two outputs, one consumer each. The holder, on the first output, prepared
and was accepted before the case began; the other bar then prepares on its own output while the
holder holds the provider's one slot, the holder's bar is removed, and the other bar prepares
again with a new explicit request. Every step replays the provider's native verdicts and the
consumers' received frames up to its confirmation, in a window with exactly one provider start,
and applies the completion rules (completion.py) to both bars.

Each bar's output is the screen its control last reported, and the two must differ. Once a bar's
control has reported that output, every frame the bar accepts with a view must carry that
output's view, so a frame for the other bar's view, or one view shared by both, fails. Frames
accepted before then answer a request sent before the bar settled on its output.

The steps then require what the scenario's actions produce: both bars bound to their own views
with the holder's preparation accepted; the other bar's preparation refused as busy, published
together with a frame that keeps the holder's completion; after the holder's bar is removed, no
answer for the holder from any read started after the removal, while a read already under way
may still give one, every publication after the removal following a read of its own, the first
publication after the first such read answering the other bar's refused request before any
context change since the refusal, and a frame from that publication or a later one accepted by
the other bar; and the other bar's new explicit preparation accepted with the app on its own
output. The refused request is never answered ready again: freeing the slot while its view is
still current does not promote it. The receipt is written only after every step's record is
recomputed from the raw logs.
"""

import json
import re
import sys
from pathlib import Path

if __package__:
    from .completion import (PUBLICATION, STARTED, accepted_with, check_frames, decisions,
                             first_decision, line_counts, load, received, summary, verdicts)
    from .mixed_lifetime import complete_lines, events, require
else:
    from completion import (PUBLICATION, STARTED, accepted_with, check_frames, decisions,
                            first_decision, line_counts, load, received, summary, verdicts)
    from mixed_lifetime import complete_lines, events, require

CHECKS = ["own-output-views", "decided-once", "busy-across-bars", "holder-retired",
          "refusal-not-promoted", "explicit-recovery"]
STEPS = ("bars", "competitor", "retired", "explicit")
MARKS = STEPS[1:]
ROLES = ("holder", "other")
READ = re.compile(r"(?:\S+: )?layout-probe: read started")
FINISHED = re.compile(r"(?:\S+: )?layout-probe: read finished")


def mark(directory: Path, label: str) -> dict:
    require(label in MARKS, "unknown two-bar mark")
    value = {"schema": 1} | line_counts(directory)
    with (directory / f"two-bar-mark-{label}.json").open("x") as output:
        json.dump(value, output)
    return value


def subjects(directory: Path) -> dict:
    boots = {}
    for role in ROLES:
        value = load(directory, f"two-bar-subject-{role}.json")
        require(isinstance(value, dict) and set(value) == {"schema", "boot"}
                and value["schema"] == 1 and isinstance(value["boot"], str)
                and 0 < len(value["boot"]) <= 128, f"invalid two-bar {role} record")
        boots[role] = value["boot"]
    return boots


def window(directory: Path, label: str, end: dict) -> dict:
    value = load(directory, f"two-bar-mark-{label}.json")
    require(isinstance(value, dict) and set(value) == {"schema", "shellLines", "kwinLines"}
            and value["schema"] == 1, "invalid two-bar mark")
    for field in ("shellLines", "kwinLines"):
        require(type(value[field]) is int and 0 <= value[field] <= end[field],
                "invalid two-bar evidence window")
    return value


def controls(shell: list) -> list:
    """The consumers' control reports with an output name, in log order."""
    rows = []
    for index, row in events(shell, "focus-control"):
        require(isinstance(row, dict) and isinstance(row.get("boot"), str)
                and isinstance(row.get("screen"), str), "malformed focus control")
        if row["screen"]:
            rows.append((index, row))
    return rows


def bar_outputs(reports: list, boots: dict) -> dict:
    """Each bar's output: the screen its control last reported."""
    latest = {row["boot"]: row["screen"] for _, row in reports}
    require(all(boot in latest for boot in boots.values()), "a bar never reported its output")
    outputs = {role: latest[boot] for role, boot in boots.items()}
    require(outputs["holder"] != outputs["other"], "the two bars are on one output")
    return outputs


def check_views(reports: list, observed: list, boots: dict, outputs: dict) -> None:
    """Once a bar's control reported its output, every frame the bar accepts with a view carries
    that output's view. A consumer accepts only answers to its current request and, while that
    request is a query, as at both bars' start, refreshes synchronously in the report that first
    names a new output, so no answer to a request sent for the old output is accepted after."""
    for role, boot in boots.items():
        settled = min(index for index, row in reports
                      if row["boot"] == boot and row["screen"] == outputs[role])
        bound = 0
        for index, row in observed:
            context = row["packet"].get("targetContext")
            if index < settled or row.get("boot") != boot or not isinstance(context, dict):
                continue
            require(context.get("outputName") == outputs[role],
                    f"the {role} bar accepted a frame for another bar's view")
            bound += 1
        require(bound, f"the {role} bar never accepted a frame for its own view")


def publication_rows(native: list, publications: list, line: int) -> list:
    """The verdicts of the publication logged at `line`: those after the previous one."""
    previous = max([index for index in publications if index < line], default=-1)
    return [row for index, row in native if previous < index < line]


def retirement(native: list, publications: list, reads: list, finished: list, contexts: list,
               start: dict, boots: dict, busy: dict) -> dict:
    """The answer to the other bar's refused request from the first publication after the first
    read started after the mark. The scenario writes the mark once the provider reader's own walk
    no longer lists the holder's panel, so no read started after the mark may answer the holder,
    while a read already under way may. Reads and publications are serialized: without a reply
    delay, which two-bar seeds refuse, a read publishes before it logs its end, and the next read
    starts only after that. Every publication after the
    mark must therefore come from the latest read started before it, one that has not ended yet,
    so every verdict after that read's start is from it or a later read; a read that ends without
    publishing answers nobody, so the first publication after its start counts. The refused
    request's view must still be current then: a provider that evaluated the refusal again and
    prepared it afresh could then grant it, which this provider's stored outcome and
    validate-only re-reads both prevent."""
    holder, other = boots["holder"], boots["other"]
    for line in publications:
        begun = max([index for index in reads if index < line], default=-1)
        require(line < start["kwinLines"]
                or (begun >= 0 and not any(begun < index < line for index in finished)),
                "a publication after the holder's removal followed no read of its own")
    started = [index for index in reads if index >= start["kwinLines"]]
    require(started, "no read after the holder's bar was removed")
    require(not any(row["consumer"] == holder for index, row in native if index > started[0]),
            "the holder's bar was not retired: a read started after its removal answered it")
    published = [line for line in publications if line > started[0]]
    require(published, "the read after the holder's bar was removed has not been published yet")
    answers = [row for row in publication_rows(native, publications, published[0])
               if row["consumer"] == other and row["request"] == busy["request"]]
    require(answers,
            "the read after the holder's retirement did not answer the other bar's refusal")
    require(not any(busy["index"] < index < published[0] for index in contexts),
            "the holder's bar was retired after the refused request's view changed")
    return answers[0]


def evaluate(directory: Path, name: str, end: dict | None) -> dict:
    require(name in STEPS, "unknown two-bar step")
    shell = complete_lines(directory / "plasmashell.log")
    backend = complete_lines(directory / "kwin.log")
    stop = {"shellLines": len(shell), "kwinLines": len(backend)} if end is None else end
    require(isinstance(stop, dict) and set(stop) == {"shellLines", "kwinLines"},
            "invalid two-bar evidence end")
    for field, total in (("shellLines", len(shell)), ("kwinLines", len(backend))):
        require(type(stop[field]) is int and 0 <= stop[field] <= total,
                "invalid two-bar evidence end")
    shell, backend = shell[:stop["shellLines"]], backend[:stop["kwinLines"]]
    # Verdicts do not name their provider lifetime, so the case allows exactly one.
    starts = sum(STARTED.fullmatch(line.rstrip("\n")) is not None for line in backend)
    require(starts == 1, f"the two-bar case expects one provider lifetime: {starts} starts")
    frames = received(shell)
    require(len({packet["epoch"] for _, packet in frames}) <= 1,
            "the two-bar case expects one provider lifetime: frames from more than one")
    native = verdicts(backend)
    decided = decisions(native)
    check_frames(frames, native, decided)
    observed = [(index, row) for index, row in events(shell, "observation")
                if isinstance(row, dict) and isinstance(row.get("packet"), dict)]
    boots = subjects(directory)
    reports = controls(shell)
    outputs = bar_outputs(reports, boots)
    check_views(reports, observed, boots, outputs)
    holder, other = boots["holder"], boots["other"]
    held = first_decision(decided, holder, 0, "the holder's preparation was not decided")
    require(held["completion"]["accepted"], "the holder's first preparation was not accepted")
    require(accepted_with(observed, holder, held, 0),
            "the holder never accepted a frame carrying its completion")
    if name == "bars":
        return {"outputs": outputs, "holder": summary(held), "end": stop}
    publications = [index for index, line in enumerate(backend)
                    if PUBLICATION.fullmatch(line.rstrip("\n"))]
    start = window(directory, "competitor", stop)
    busy = first_decision(decided, other, start["kwinLines"],
                          "the other bar's preparation was not decided after its mark")
    completion = busy["completion"]
    require(not completion["accepted"] and completion["reason"] == "busy",
            "expected the other bar's preparation to be refused as busy")
    # A refusal stays one: no later answer to that request may turn it into an acceptance.
    require(not any(row["consumer"] == other and row["request"] == busy["request"]
                    and row["ready"] for index, row in native if index > busy["index"]),
            "the other bar's refused request was promoted to an acceptance")
    if name == "competitor":
        later = [index for index in publications if index > busy["index"]]
        require(later, "the other bar's decision has not been published yet")
        holders = [row for row in publication_rows(native, publications, later[0])
                   if row["consumer"] == holder and row["request"] == held["request"]
                   and row["completion"] == held["completion"]]
        require(holders, "the other bar's decision was not published with a frame keeping the"
                " holder's completion")
        require(accepted_with(observed, other, busy, start["shellLines"]),
                "the other bar never accepted a frame carrying its refusal")
        return {"other": summary(busy), "holderRevision": holders[0]["revision"], "end": stop}
    reads = [index for index, line in enumerate(backend) if READ.fullmatch(line.rstrip("\n"))]
    finished = [index for index, line in enumerate(backend)
                if FINISHED.fullmatch(line.rstrip("\n"))]
    contexts = [index for index, row in events(backend, "focus")
                if isinstance(row, dict) and row.get("event") == "context-changed"]
    start = window(directory, "retired", stop)
    answer = retirement(native, publications, reads, finished, contexts, start, boots, busy)
    if name == "retired":
        frames = [packet for packet in accepted_with(observed, other, busy, start["shellLines"])
                  if packet["revision"] >= answer["revision"]]
        require(frames, "the other bar accepted no frame after the holder's bar was retired")
        return {"revision": answer["revision"], "reason": answer["reason"], "end": stop}
    start = window(directory, "explicit", stop)
    recovery = first_decision(decided, other, start["kwinLines"],
                              "the other bar's new preparation was not decided after its mark")
    verdict = dict(native)[recovery["index"]]
    # A decision after the mark is for a newer request: each is decided once, and an older
    # request gets only an answer that cannot decide it.
    require(recovery["completion"]["accepted"] and verdict["targetClass"] == "pf.focus.beta",
            "expected the other bar's new preparation to be accepted with pf.focus.beta")
    frames = accepted_with(observed, other, recovery, start["shellLines"])
    require(frames, "the other bar never accepted a frame carrying its new completion")
    # check_views skips frames without a view, and earlier frames meet its count: the recovery
    # itself must carry the other bar's view.
    require(any(isinstance(packet.get("targetContext"), dict)
                and packet["targetContext"].get("outputName") == outputs["other"]
                for packet in frames),
            "the other bar's new completion was not accepted with its own view")
    return {"other": summary(recovery), "end": stop}


def record_step(directory: Path, name: str) -> dict:
    record = evaluate(directory, name, None)
    with (directory / f"two-bar-{name}.json").open("x") as output:
        json.dump(record, output)
    return record


def check_two_bar(directory: Path) -> None:
    for name in STEPS:
        record = load(directory, f"two-bar-{name}.json")
        require(isinstance(record, dict) and isinstance(record.get("end"), dict),
                "invalid two-bar evidence record")
        require(evaluate(directory, name, record["end"]) == record,
                f"{name} record does not match its raw evidence")


def write_receipt(directory: Path) -> None:
    """The receipt's check list has one source: it is written only after the full check."""
    check_two_bar(directory)
    with (directory / "two-bar-result.json").open("x") as output:
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
            print("PASS: two-bar evidence")
        else:
            raise SystemExit("usage: two_bar.py {mark OUT LABEL|step OUT NAME|receipt OUT}")
    except (ValueError, OSError) as error:
        raise SystemExit(f"two-bar: {error}") from None


if __name__ == "__main__":
    main()
