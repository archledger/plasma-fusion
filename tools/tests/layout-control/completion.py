#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Capture and qualify P0 completion evidence. Never operate a desktop.

The provider logs one native verdict per target row of each publication, with the completion it
published, and each consumer logs every frame it receives. Every step replays both up to its
confirmation, in a window with exactly one provider start. A prepare's first answer that is not a
wait (an unavailable context, or a consumer, request or envelope the provider cannot handle yet)
must carry its completion, which restates that answer. No answer given before the provider touches
the consumer's record may introduce one: the checker enforces that for an unknown consumer or lease,
an older or conflicting request and a malformed envelope, but cannot for an unavailable context,
which looks like the unavailable refusal a decided prepare gets when the provider runs out of
handles. Every later native verdict for that consumer and request number, whatever its own intent or
answer, must carry the identical completion until the provider handles a newer request for that
consumer, and every received frame must carry exactly what its native verdict published. A re-leased
consumer at its decided request fails, which is stricter than the provider.

The steps then require what the scenario's actions produce: the holder's accepted preparation;
a newer frame, caused by a context change, that keeps it while the preparation reports the
target no longer valid; the competitor's busy refusal, published together with a frame that
keeps the holder's completion; a newer frame that keeps that refusal; the holder's new
preparation, refused for its stale context; and a newer frame that keeps that refusal. A newer
frame counts only if its consumer accepted it from a publication after the context change. The
receipt is written only after every step's record is recomputed from the raw logs.
"""

import json
import re
import sys
from pathlib import Path

if __package__:
    from .mixed_lifetime import complete_lines, events, require
else:
    from mixed_lifetime import complete_lines, events, require

CHECKS = ["roundtrip-native", "decided-once", "kept-by-newer-frames", "validity-separate",
          "refusal-kept"]
STEPS = ("accepted", "context", "competitor", "refusal", "stale", "stale-kept")
MARKS = STEPS[1:]
# Answers the provider gives before it touches the consumer's record: they never decide.
EARLY = {"consumer-not-current", "stale-or-conflicting-request", "malformed"}
# A request stays undecided while it gets one of these, or an unavailable context.
UNDECIDED = EARLY | {"unavailable"}
VERDICT_KEYS = {"consumer", "request", "intent", "revision", "ready", "reason", "targetClass",
                "targetAlive", "completion"}
COMPLETION_KEYS = {"request", "intent", "accepted", "token", "reason"}
PUBLICATION = re.compile(r"(?:\S+: )?layout-probe: publication online [0-9]+")
STARTED = re.compile(r"(?:\S+: )?layout-probe: initialized (?:true|false) -?[0-9]+")


def load(directory: Path, name: str):
    return json.loads((directory / name).read_text())


def line_counts(directory: Path) -> dict:
    return {"shellLines": len(complete_lines(directory / "plasmashell.log")),
            "kwinLines": len(complete_lines(directory / "kwin.log"))}


def mark(directory: Path, label: str) -> dict:
    require(label in MARKS, "unknown completion mark")
    value = {"schema": 1} | line_counts(directory)
    with (directory / f"completion-mark-{label}.json").open("x") as output:
        json.dump(value, output)
    return value


def subject(directory: Path, role: str) -> str:
    value = load(directory, f"completion-subject-{role}.json")
    require(isinstance(value, dict) and set(value) == {"schema", "boot"} and value["schema"] == 1
            and isinstance(value["boot"], str) and 0 < len(value["boot"]) <= 128,
            f"invalid completion {role} record")
    return value["boot"]


def window(directory: Path, label: str, end: dict) -> dict:
    value = load(directory, f"completion-mark-{label}.json")
    require(isinstance(value, dict) and set(value) == {"schema", "shellLines", "kwinLines"}
            and value["schema"] == 1, "invalid completion mark")
    for field in ("shellLines", "kwinLines"):
        require(type(value[field]) is int and 0 <= value[field] <= end[field],
                "invalid completion evidence window")
    return value


def verdicts(lines: list) -> list:
    """The provider's native verdicts, one per target row of each publication."""
    rows = []
    for index, row in events(lines, "target"):
        require(isinstance(row, dict) and set(row) == VERDICT_KEYS
                and isinstance(row["consumer"], str) and type(row["request"]) is int
                and isinstance(row["intent"], str) and type(row["revision"]) is int
                and type(row["ready"]) is bool and isinstance(row["reason"], str),
                "malformed native target verdict")
        rows.append((index, row))
    return rows


def decisions(native: list) -> dict:
    """Each prepare's decision, after checking every verdict against it, in log order.

    A prepare's own answer decides its completion. Every later verdict for that consumer and
    request number repeats it unchanged, whatever that verdict's own intent or answer, until
    the provider handles a newer request for that consumer; a verdict for the older request may
    then drop it. Before the decision no verdict carries one.
    """
    newest, decided = {}, {}
    for index, row in native:
        key, completion = (row["consumer"], row["request"]), row["completion"]
        advanced = newest.get(row["consumer"], 0) > row["request"]
        # Only a handled request supersedes an older one: a verdict shows that when it carries a
        # completion or gives an answer after the provider touched the consumer's record. An
        # early answer leaves the record, and its completion, at the older request.
        if completion is not None or row["reason"] not in UNDECIDED:
            newest[row["consumer"]] = max(newest.get(row["consumer"], 0), row["request"])
        decision = decided.get(key)
        if decision is not None:
            if completion is None:
                require(advanced, "a newer frame dropped a decided completion")
            else:
                require(completion == decision["completion"],
                        "a completion changed after its decision")
            continue
        if completion is None:
            require(row["intent"] != "prepare"
                    or (not row["ready"] and row["reason"] in UNDECIDED),
                    "a prepare was answered without its completion")
            continue
        require(row["intent"] == "prepare", f"a {row['intent']} frame carried a completion")
        require(not advanced and row["reason"] not in EARLY,
                "an answer that cannot decide a request carried a completion")
        require(isinstance(completion, dict) and set(completion) == COMPLETION_KEYS
                and isinstance(completion["token"], str),
                "malformed completion")
        # An acceptance carries its handle; a refusal carries none.
        token = completion["token"]
        handle = 0 < len(token) <= 128 if row["ready"] else token == ""
        require(handle and completion == {
            "request": row["request"], "intent": "prepare", "accepted": row["ready"],
            "token": completion["token"], "reason": row["reason"]},
            "a completion does not match the answer that decided it")
        decided[key] = {"index": index, "request": row["request"], "revision": row["revision"],
                        "completion": completion}
    return decided


def received(lines: list) -> list:
    rows = []
    for index, packet in events(lines, "received"):
        require(isinstance(packet, dict) and isinstance(packet.get("consumer"), str)
                and type(packet.get("revision")) is int and type(packet.get("request")) is int
                and isinstance(packet.get("epoch"), str), "malformed received frame")
        rows.append((index, packet))
    return rows


def check_frames(frames: list, native: list, decided: dict) -> None:
    """Every frame a consumer received carries exactly the preparation and completion that its
    native verdict published."""
    published = {(row["consumer"], row["revision"]): row for _, row in native}
    require(len({packet["epoch"] for _, packet in frames}) <= 1,
            "the completion case expects one provider lifetime")
    for _, packet in frames:
        completion = packet.get("completion")
        verdict = published.get((packet["consumer"], packet["revision"]))
        if packet.get("status") != "online" or verdict is None:
            require(completion is None, "a frame without a native target verdict carried a"
                    " completion")
            continue
        preparation = packet.get("preparation")
        require(packet["request"] == verdict["request"] and isinstance(preparation, dict)
                and [preparation.get(key) for key in ("intent", "ready", "reason")]
                == [verdict[key] for key in ("intent", "ready", "reason")],
                "a received frame does not match its native verdict")
        require(completion == verdict["completion"],
                "a received frame's completion differs from the provider's")
        decision = decided.get((packet["consumer"], packet["request"]))
        if decision and decision["revision"] == packet["revision"] and completion["accepted"]:
            require(preparation.get("token") == completion["token"],
                    "the deciding frame's handle differs from its completion")


def first_decision(decided: dict, boot: str, after: int, message: str) -> dict:
    choices = [value for (consumer, _), value in decided.items()
               if consumer == boot and value["index"] >= after]
    require(choices, message)
    return min(choices, key=lambda value: value["index"])


def summary(decision: dict) -> dict:
    return {key: decision[key] for key in ("request", "revision", "completion")}


def accepted_with(observed: list, boot: str, decision: dict, after: int) -> list:
    """Frames the consumer accepted after `after` for the decided request, carrying its
    completion, in the order it accepted them."""
    return [row["packet"] for index, row in observed
            if index >= after and row.get("boot") == boot
            and row["packet"].get("request") == decision["request"]
            and row["packet"].get("completion") == decision["completion"]]


def kept(evidence: dict, boot: str, decision: dict, start: dict, *, invalid=False) -> dict:
    """A context change after the mark, then a newer native verdict for the decided request and
    an accepted frame from that publication or a later one, both carrying its completion."""
    validity = ("validity was not reported separately: no newer frame reported the target no"
                " longer valid")
    changes = [index for index in evidence["contexts"] if index >= start["kwinLines"]]
    require(changes, "no context change after the step's mark")
    native = [row for index, row in evidence["native"]
              if index > changes[0] and row["consumer"] == boot
              and row["request"] == decision["request"] and row["revision"] > decision["revision"]]
    require(native, f"no newer frame kept the decided completion of {boot}")
    if invalid:
        native = [row for row in native if not row["ready"]]
        require(native, validity)
    # Delivery must be one of those frames, not one published before the change. A received
    # frame repeats its verdict's preparation (check_frames), so its readiness is the verdict's.
    published = {row["revision"] for row in native}
    frames = [packet for packet in accepted_with(evidence["observed"], boot, decision,
                                                 start["shellLines"])
              if packet.get("revision") in published]
    require(frames, f"no newer frame accepted by {boot} kept its completion")
    return {"revision": frames[0]["revision"], "reason": frames[0]["preparation"]["reason"]}


def evaluate(directory: Path, name: str, end: dict | None) -> dict:
    require(name in STEPS, "unknown completion step")
    shell = complete_lines(directory / "plasmashell.log")
    backend = complete_lines(directory / "kwin.log")
    stop = {"shellLines": len(shell), "kwinLines": len(backend)} if end is None else end
    require(isinstance(stop, dict) and set(stop) == {"shellLines", "kwinLines"},
            "invalid completion evidence end")
    for field, total in (("shellLines", len(shell)), ("kwinLines", len(backend))):
        require(type(stop[field]) is int and 0 <= stop[field] <= total,
                "invalid completion evidence end")
    shell, backend = shell[:stop["shellLines"]], backend[:stop["kwinLines"]]
    # Verdicts do not name their provider lifetime, so the case allows exactly one.
    starts = sum(STARTED.fullmatch(line.rstrip("\n")) is not None for line in backend)
    require(starts == 1, f"the completion case expects one provider lifetime: {starts} starts")
    native = verdicts(backend)
    decided = decisions(native)
    check_frames(received(shell), native, decided)
    evidence = {
        "native": native,
        "observed": [(index, row) for index, row in events(shell, "observation")
                     if isinstance(row, dict) and isinstance(row.get("packet"), dict)],
        "contexts": [index for index, row in events(backend, "focus")
                     if isinstance(row, dict) and row.get("event") == "context-changed"],
        "publications": [index for index, line in enumerate(backend)
                         if PUBLICATION.fullmatch(line.rstrip("\n"))],
    }
    holder = subject(directory, "holder")
    held = first_decision(decided, holder, 0, "the holder's preparation was not decided")
    require(held["completion"]["accepted"], "the holder's first preparation was not accepted")
    require(accepted_with(evidence["observed"], holder, held, 0),
            "the holder never accepted a frame carrying its completion")
    if name == "accepted":
        return {"holder": summary(held), "end": stop}
    if name == "context":
        start = window(directory, "context", stop)
        return kept(evidence, holder, held, start, invalid=True) | {"end": stop}
    if name in ("stale", "stale-kept"):
        stale = first_decision(decided, holder, window(directory, "stale", stop)["kwinLines"],
                               "the holder's new preparation was not decided after its mark")
        completion = stale["completion"]
        require(stale["request"] > held["request"] and not completion["accepted"]
                and completion["reason"] == "stale-context",
                "expected the holder's new preparation to be refused as stale-context")
        if name == "stale":
            require(accepted_with(evidence["observed"], holder, stale, 0),
                    "the holder never accepted a frame carrying its refusal")
            return {"holder": summary(stale), "end": stop}
        return kept(evidence, holder, stale, window(directory, "stale-kept", stop)) | {"end": stop}
    competitor = subject(directory, "competitor")
    start = window(directory, "competitor", stop)
    busy = first_decision(decided, competitor, start["kwinLines"],
                          "the competitor's preparation was not decided after its mark")
    completion = busy["completion"]
    require(not completion["accepted"] and completion["reason"] == "busy",
            "expected the competitor's preparation to be refused as busy")
    if name == "refusal":
        return kept(evidence, competitor, busy, window(directory, "refusal", stop)) | {"end": stop}
    # The decision's own publication: its verdicts lie between the previous publication line and
    # the next one. It must also carry a frame for the holder's decided request.
    later = [index for index in evidence["publications"] if index > busy["index"]]
    require(later, "the competitor's decision has not been published yet")
    previous = max([index for index in evidence["publications"] if index < busy["index"]],
                   default=-1)
    holders = [row for index, row in native if previous < index < later[0]
               and row["consumer"] == holder and row["request"] == held["request"]]
    require(holders, "the competitor's decision was not published with a frame keeping the"
            " holder's completion")
    require(accepted_with(evidence["observed"], competitor, busy, start["shellLines"]),
            "the competitor never accepted a frame carrying its refusal")
    return {"competitor": summary(busy), "holderRevision": holders[0]["revision"], "end": stop}


def record_step(directory: Path, name: str) -> dict:
    record = evaluate(directory, name, None)
    with (directory / f"completion-{name}.json").open("x") as output:
        json.dump(record, output)
    return record


def check_completion(directory: Path) -> None:
    for name in STEPS:
        record = load(directory, f"completion-{name}.json")
        require(isinstance(record, dict) and isinstance(record.get("end"), dict),
                "invalid completion evidence record")
        require(evaluate(directory, name, record["end"]) == record,
                f"{name} record does not match its raw evidence")


def write_receipt(directory: Path) -> None:
    """The receipt's check list has one source: it is written only after the full check."""
    check_completion(directory)
    with (directory / "completion-result.json").open("x") as output:
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
            print("PASS: completion evidence")
        else:
            raise SystemExit("usage: completion.py {mark OUT LABEL|step OUT NAME|receipt OUT}")
    except (ValueError, OSError) as error:
        raise SystemExit(f"completion: {error}") from None


if __name__ == "__main__":
    main()
