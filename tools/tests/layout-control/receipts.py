#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Correlate private target/consumer receipts; never act on a desktop."""

import json
import re
import sys
from pathlib import Path

# A provider publication starts with its status line and ends when its shell script call
# reports back, as written or failed.
PUBLICATION = re.compile(r"layout-probe: publication (\S+)")


def accepted_exchange(path: str, consumer: str) -> tuple:
    with open(path) as log:
        trace = log.readlines()
    events = []
    for index, line in enumerate(trace):
        if line.endswith("\n"):
            for kind in ("query", "observation"):
                marker = f"layout-probe-{kind} "
                if marker in line:
                    events.append((index, kind, json.loads(line.split(marker, 1)[1])))
    index, _, observation = [event for event in events
                             if event[1] == "observation" and event[2]["boot"] == consumer][-1]
    return index, observation, events


def native_verdicts(path: str) -> list:
    return [json.loads(line.split("layout-probe-target ", 1)[1])
            for line in open(path)
            if line.endswith("\n") and "layout-probe-target " in line]


def target_reply(arguments: list[str]) -> None:
    index, observation, events = accepted_exchange(arguments[1], arguments[3])
    request = observation["request"]
    assert type(request) is int and request > int(arguments[6])
    assert observation["phase"] == "online"
    packet = observation["packet"]
    assert packet["consumer"] == arguments[3] and packet["request"] == request
    preparation = packet["preparation"]
    assert set(preparation) == {"intent", "ready", "reason", "token"}
    assert preparation["intent"] == arguments[4] and preparation["ready"] is (arguments[5] == "true")
    queries = [event for event in events if event[1] == "query"
               and event[2]["boot"] == arguments[3] and event[2]["request"] == request]
    assert len(queries) == 1 and queries[0][0] < index
    native = native_verdicts(arguments[2])
    # The verdict of the accepted frame itself: later frames may re-validate the same request.
    native = [row for row in native if row["consumer"] == arguments[3]
              and row["request"] == request and row["intent"] == arguments[4]
              and row["revision"] == packet["revision"]][-1]
    assert native["ready"] is preparation["ready"]
    if preparation["ready"]:
        assert native["targetAlive"] and native["targetClass"] == arguments[7], native
    else:
        assert not native["targetAlive"] and native["targetClass"] == "", native
        assert preparation["reason"] and preparation["reason"] == native["reason"]
        assert preparation["token"] == ""
    with (Path(arguments[8]) / f"target-observations-{request}.json").open("w") as output:
        json.dump(observation, output)
    print(request)


def consumer_state(arguments: list[str]) -> None:
    index, observation, events = accepted_exchange(arguments[1], arguments[3])
    packet = observation["packet"]
    assert observation["phase"] == "online" and packet["consumer"] == arguments[3]
    assert packet["request"] == observation["request"]
    assert type(packet["revision"]) is int and packet["revision"] > int(arguments[4])
    context = packet["targetContext"]
    assert context and isinstance(context["consumerLease"], str) and context["consumerLease"]
    preparation = packet["preparation"]
    assert preparation["intent"] == arguments[5] and preparation["ready"] is (arguments[6] == "true")
    assert preparation["reason"] == ("" if arguments[7] == "-" else arguments[7])
    queries = [event for event in events if event[1] == "query" and event[2]["boot"] == arguments[3]
               and event[2]["request"] == observation["request"]]
    assert len(queries) == 1 and queries[0][0] < index
    native = native_verdicts(arguments[2])
    native = [row for row in native if row["consumer"] == arguments[3]
              and row["request"] == observation["request"] and row["revision"] == packet["revision"]][-1]
    assert all(native[key] == preparation[key] for key in ("intent", "ready", "reason"))
    if preparation["ready"]:
        assert native["targetAlive"] and native["targetClass"] == arguments[8]
    else:
        assert preparation["token"] == ""
    with open(arguments[9], "w") as output:
        json.dump(observation, output)
    print(observation["request"], packet["revision"])


def provider_context(lines: list[str]) -> dict:
    """The provider's newest focus observation, which carries its current context generation."""
    return [json.loads(line.split("layout-probe-focus ", 1)[1])
            for line in lines
            if line.endswith("\n") and "layout-probe-focus " in line][-1]


def provider_busy(lines: list[str]) -> bool:
    """Whether a provider read or publication has started and not finished. A publication is a
    shell script call, which the shell serves on its main thread."""
    reads = publications = 0
    for line in lines:
        if not line.endswith("\n"):
            continue
        if "layout-probe: read started" in line:
            reads += 1
        elif "layout-probe: read finished" in line:
            reads -= 1
        match = PUBLICATION.search(line)
        if match:
            publications += -1 if match.group(1) in ("writes", "failed") else 1
    return reads != 0 or publications != 0


def provider_generation(arguments: list[str]) -> None:
    with open(arguments[1]) as log:
        generation = provider_context(log.readlines())["contextGeneration"]
    assert type(generation) is int
    print(generation)


def target_settled(arguments: list[str]) -> None:
    """The shell has applied a context change: the provider observed it (its generation reached
    the minimum), the receiver holds that newest context, and no read or publication is
    outstanding."""
    _, observation, _ = accepted_exchange(arguments[1], arguments[3])
    # One snapshot after reading the receiver: a wake can start work without advancing the
    # generation, so reading it separately from the outstanding-work markers is insufficient.
    with open(arguments[2]) as log:
        lines = log.readlines()
    assert not provider_busy(lines)
    generation = provider_context(lines)["contextGeneration"]
    assert type(generation) is int and generation >= int(arguments[4])
    assert observation["phase"] == "online"
    context = observation["packet"]["targetContext"]
    assert context and context["generation"] == generation
    print(generation)


def main() -> None:
    modes = {"target-reply": (target_reply, 9), "consumer-state": (consumer_state, 10),
             "target-settled": (target_settled, 5), "provider-generation": (provider_generation, 2)}
    if len(sys.argv) < 2 or sys.argv[1] not in modes:
        raise SystemExit("usage: receipts.py {target-reply|consumer-state|target-settled|"
                         "provider-generation} RECEIPT_ARGUMENTS...")
    checker, count = modes[sys.argv[1]]
    arguments = [sys.argv[0], *sys.argv[2:]]
    if len(arguments) != count:
        raise SystemExit("wrong number of receipt arguments")
    checker(arguments)


if __name__ == "__main__":
    main()
