#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Correlate private target/consumer receipts; never act on a desktop."""

import json
import sys
from pathlib import Path


def accepted_exchange(path: str, consumer: str) -> tuple:
    trace = open(path).readlines()
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
    native = [row for row in native if row["consumer"] == arguments[3]
              and row["request"] == request and row["intent"] == arguments[4]][-1]
    assert native["ready"] is preparation["ready"]
    if preparation["ready"]:
        assert native["targetAlive"] and native["targetClass"] == arguments[7], native
    else:
        assert not native["targetAlive"] and native["targetClass"] == "", native
        assert preparation["reason"] and preparation["token"] == ""
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


def main() -> None:
    modes = {"target-reply": (target_reply, 9), "consumer-state": (consumer_state, 10)}
    if len(sys.argv) < 2 or sys.argv[1] not in modes:
        raise SystemExit("usage: receipts.py {target-reply|consumer-state} RECEIPT_ARGUMENTS...")
    checker, count = modes[sys.argv[1]]
    arguments = [sys.argv[0], *sys.argv[2:]]
    if len(arguments) != count:
        raise SystemExit("wrong number of receipt arguments")
    checker(arguments)


if __name__ == "__main__":
    main()
