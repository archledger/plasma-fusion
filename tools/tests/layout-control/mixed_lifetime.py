#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Capture and qualify combined P0 evidence. Never operate a desktop."""

import json
import sys
from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def complete_lines(path: Path) -> list[str]:
    lines = path.read_text().splitlines(keepends=True)
    if lines and not lines[-1].endswith("\n"):
        lines.pop()
    return lines


def events(lines: list[str], kind: str) -> list[tuple[int, dict]]:
    marker = f"layout-probe-{kind} "
    return [(index, json.loads(line.split(marker, 1)[1]))
            for index, line in enumerate(lines) if marker in line]


def snapshot(directory: Path, inventory: Path, phase: str, count: int,
             *, boundary: dict | None = None) -> dict:
    native = json.loads(inventory.read_text())
    require(count in (1, 2) and isinstance(native, list) and len(native) == count,
            "unexpected native widget count")
    ids = [row.get("id") for row in native]
    require(all(type(identifier) is int and identifier > 0 for identifier in ids)
            and len(set(ids)) == count, "native widget IDs must be unique positive integers")
    lines = complete_lines(directory / "plasmashell.log")
    backend = complete_lines(directory / "kwin.log")
    if boundary is not None:
        for field, total in (("shellLines", len(lines)), ("kwinLines", len(backend))):
            require(type(boundary[field]) is int and 0 <= boundary[field] <= total,
                    "invalid complete-line evidence boundary")
        lines = lines[:boundary["shellLines"]]
        backend = backend[:boundary["kwinLines"]]
    observations = events(lines, "observation")
    queries = events(lines, "query")
    controls = events(lines, "focus-control")
    widgets = []
    for row in native:
        query = row["request"]
        boot = query["consumer"]
        require(isinstance(boot, str) and bool(boot), "missing native consumer lifetime")
        accepted = [(index, value) for index, value in observations if value["boot"] == boot]
        require(bool(accepted), "missing receiver memory")
        index, current = accepted[-1]
        require(current["phase"] == phase, f"missing {phase} memory")
        require(type(query["request"]) is int and current["request"] == query["request"],
                "memory does not belong to the current query")
        outgoing = [(number, value) for number, value in queries
                    if value["boot"] == boot and value["request"] == current["request"]]
        # Loss is observed before freshQuery's deferred send; only accepted state follows it.
        require(len(outgoing) == 1 and (phase != "online" or outgoing[0][0] < index),
                "missing ordered current query")
        packet = current["packet"]
        if phase == "online":
            require(packet and packet["consumer"] == boot and packet["request"] == current["request"],
                    "accepted memory belongs to another exchange")
            require(packet["status"] == "online" and packet["capable"] is True,
                    "missing native online capability")
            context = packet.get("targetContext")
            require(isinstance(context, dict) and context.get("epoch") == packet["epoch"]
                    and isinstance(context.get("consumerLease"), str) and bool(context["consumerLease"])
                    and bool(context.get("outputName")) and context["outputName"] == query["outputName"],
                    "missing current target context after native output attachment")
        else:
            require(phase == "unknown" and packet is None and current["epoch"] == "",
                    "retired provider left authoritative memory")
        matches = [value for _, value in controls if value["boot"] == boot]
        widgets.append({"id": row["id"], "query": query, "observation": current,
                        "control": matches[-1] if matches else None})
    require(len({row["query"]["consumer"] for row in widgets}) == count,
            "native consumers must have distinct lifetimes")
    return {"shellLines": len(lines), "kwinLines": len(backend),
            "widgets": widgets}


def saved_snapshot(directory: Path, label: str, phase: str = "online") -> dict:
    saved = json.loads((directory / f"mixed-{label}.json").read_text())
    actual = snapshot(directory, directory / f"mixed-{label}-inventory.json", phase,
                      len(saved["widgets"]), boundary=saved)
    require(actual == saved, f"{label} snapshot does not match its native inventory and log prefix")
    return saved


def widgets(saved: dict) -> dict:
    return {row["id"]: row for row in saved["widgets"]}


def epoch(saved: dict) -> str:
    values = {row["observation"]["packet"]["epoch"] for row in saved["widgets"]}
    require(len(values) == 1, "consumers did not confirm the same provider lifetime")
    value = values.pop()
    require(isinstance(value, str) and len(value) == 32
            and all(character in "0123456789abcdef" for character in value),
            "invalid provider lifetime")
    for row in saved["widgets"]:
        packet = row["observation"]["packet"]
        require(packet["identityName"] == "org.plasmafusion.LayoutProbe.p" + value,
                "provider alias does not match its lifetime")
    return value


def native_preparation(directory: Path, observation: dict, start: int, stop: int) -> None:
    shell = events(complete_lines(directory / "plasmashell.log"), "observation")
    require(any(row == observation for _, row in shell), "missing accepted preparation memory")
    packet = observation["packet"]
    preparation = packet["preparation"]
    require(preparation["intent"] == "prepare" and preparation["ready"] is True
            and preparation["reason"] == "" and preparation["token"].startswith(packet["epoch"] + ":"),
            "missing explicit current preparation")
    rows = events(complete_lines(directory / "kwin.log")[start:stop], "target")
    matches = [row for _, row in rows if row["consumer"] == observation["boot"]
               and row["request"] == observation["request"] and row["revision"] == packet["revision"]]
    require(len(matches) == 1 and matches[0]["intent"] == "prepare"
            and matches[0]["ready"] is True and matches[0]["reason"] == ""
            and matches[0]["targetAlive"] is True and matches[0]["targetClass"] == "pf.focus.alpha",
            "native verdict does not confirm the intended application")


def late_frames(directory: Path) -> list[dict]:
    current = widgets(saved_snapshot(directory, "reloaded"))
    created = json.loads((directory / "mixed-created.json").read_text())
    retired = json.loads((directory / "mixed-retired-preparation.json").read_text())["packet"]
    survivor = json.loads((directory / "consumer-explicit-recovery.json").read_text())["packet"]
    replacement = current[created["id"]]
    retained = current[created["survivorId"]]
    c_packet, b_packet = replacement["observation"]["packet"], retained["observation"]["packet"]
    require(c_packet["revision"] + 1000 <= 2147483646
            and b_packet["revision"] + 2000 <= 2147483646, "late-frame revision would overflow")
    # Keep an unmodified old frame, then isolate the consumer and provider fences separately.
    return [
        {"kind": "retained-consumer", "id": replacement["id"],
         "receiver": replacement["query"]["consumer"], "packet": retired},
        {"kind": "retired-consumer-fence", "id": replacement["id"],
         "receiver": replacement["query"]["consumer"], "packet": retired | {
             "request": c_packet["request"], "epoch": c_packet["epoch"],
             "backendOwner": c_packet["backendOwner"], "identityName": c_packet["identityName"],
             "revision": c_packet["revision"] + 1000}},
        {"kind": "retired-provider-fence", "id": retained["id"],
         "receiver": retained["query"]["consumer"], "packet": survivor | {
             "request": b_packet["request"], "revision": b_packet["revision"] + 2000}},
    ]


def check_late(directory: Path) -> None:
    before, after = (saved_snapshot(directory, label) for label in ("reloaded", "after-late"))
    frames = json.loads((directory / "mixed-frames.json").read_text())
    require(frames == late_frames(directory), "late frames do not match the captured exchanges")
    lines = complete_lines(directory / "plasmashell.log")
    received = events(lines, "received")
    memory = events(lines, "observation")
    published = events(complete_lines(directory / "kwin.log")[:after["kwinLines"]], "published")
    owner = json.loads((directory / "cleanup-identity.json").read_text())["session"]["shell"]
    for identifier, current in widgets(after).items():
        previous = widgets(before)[identifier]
        boot = current["query"]["consumer"]
        require(current["query"] == previous["query"]
                and current["observation"]["epoch"] == previous["observation"]["epoch"],
                "late frame replaced the current exchange")
        delivered = []
        for frame in (row for row in frames if row["id"] == identifier):
            matches = [index for index, packet in received
                       if before["shellLines"] <= index < after["shellLines"]
                       and packet == frame["packet"] | {"receiverBoot": boot}]
            require(len(matches) == 1, "late frame did not reach its exact live receiver")
            delivered.extend(matches)
        acknowledgements = [index for index, row in memory if row == current["observation"]
                            and index < after["shellLines"]]
        packet = current["observation"]["packet"]
        # Receipt precedes verification, and a consumer holds one packet pending: only a response
        # received after the last late frame shows, once accepted, that none is still queued.
        receipts = [index for index, value in received if index < after["shellLines"]
                    and value == packet | {"receiverBoot": boot}]
        require(acknowledgements and len(receipts) == 1
                and max(delivered) < receipts[0] < min(acknowledgements)
                and current["observation"]["revision"] > previous["observation"]["revision"],
                "missing genuine response after the late-frame drain")
        expected = {key: packet[key] for key in
                    ("consumer", "request", "epoch", "revision", "status")} | {
                        "widget": identifier, "destination": owner,
                    }
        native = [index for index, value in published if value == expected]
        require(len(native) == 1 and native[0] >= before["kwinLines"],
                "late-frame drain lacks its exact native publication")
    require(not [row for index, row in events(lines, "query")
                 if before["shellLines"] <= index < after["shellLines"]],
            "late frame triggered an automatic query retry")
    receivers = {frame["receiver"] for frame in frames}
    current_epoch = epoch(before)
    for index, row in memory:
        if row["boot"] not in receivers:
            continue
        # Check the whole retained history after recovery, not just the final stable snapshot.
        if index >= before["shellLines"] and row["packet"]:
            require(row["packet"]["consumer"] == row["boot"]
                    and row["packet"]["epoch"] == current_epoch,
                    "accepted stale consumer/provider state after recovery")


def check_replay(directory: Path, boundary: dict | None = None) -> None:
    before = saved_snapshot(directory, "after-late")
    request = json.loads((directory / "mixed-replayed-request.json").read_text())
    backend = complete_lines(directory / "kwin.log")
    shell = complete_lines(directory / "plasmashell.log")
    stop = boundary or {"kwinLines": len(backend), "shellLines": len(shell)}
    verdicts = [row for index, row in events(backend, "target")
                if before["kwinLines"] <= index < stop["kwinLines"]
                and row["consumer"] == request["consumer"] and row["request"] == request["request"]
                and row["intent"] == "prepare"]
    require(verdicts and all(row["ready"] is False and row["reason"] == "consumer-not-current"
                            and row["targetAlive"] is False and row["targetClass"] == ""
                            for row in verdicts), "old preparation lacks its exact native refusal")
    received = events(shell, "received")
    require(any(before["shellLines"] <= index < stop["shellLines"]
                and row["receiverBoot"] == row["consumer"] == request["consumer"]
                and row["request"] == request["request"] and row["epoch"] == epoch(before)
                and row["preparation"] == {
                    "intent": "prepare", "ready": False, "reason": "consumer-not-current", "token": ""}
                and any(verdict["revision"] == row["revision"] for verdict in verdicts)
                for index, row in received), "native replay refusal did not reach its receiver")


def check_progress(directory: Path, label: str, previous_label: str) -> None:
    captured = saved_snapshot(directory, label)
    current, previous = widgets(captured), widgets(saved_snapshot(directory, previous_label))
    require(current.keys() == previous.keys(), "recovery changed the live widget inventory")
    boundary = None
    if label == "after-replay":
        boundary = json.loads((directory / "mixed-restored-boundary.json").read_text())
        require(type(boundary.get("schema")) is int and boundary["schema"] == 1,
                "invalid restoration boundary schema")
        before = saved_snapshot(directory, previous_label)
        require(all(type(boundary.get(field)) is int
                    and before[field] <= boundary[field] <= captured[field]
                    for field in ("shellLines", "kwinLines")), "invalid post-restoration boundary")
        check_replay(directory, boundary)
    for identifier, row in current.items():
        before = previous[identifier]
        require(row["query"] == before["query"]
                and row["observation"]["revision"] > before["observation"]["revision"]
                and row["observation"]["packet"]["targetContext"]["consumerLease"]
                == before["observation"]["packet"]["targetContext"]["consumerLease"],
                "replay changed an exchange/lease or lacked a genuine recovery response")
        if boundary is not None:
            lines = complete_lines(directory / "plasmashell.log")[:captured["shellLines"]]
            matches = [index for index, value in events(lines, "observation")
                       if value == row["observation"]]
            require(matches and min(matches) >= boundary["shellLines"],
                    "recovery acknowledgement preceded restoration")
            packet = row["observation"]["packet"]
            received = [index for index, value in events(lines, "received")
                        if value == packet | {"receiverBoot": row["query"]["consumer"]}]
            require(len(received) == 1 and boundary["shellLines"] <= received[0] < min(matches),
                    "recovery borrowed a receipt from before restoration")
            owner = json.loads((directory / "cleanup-identity.json").read_text())["session"]["shell"]
            expected = {key: packet[key] for key in
                        ("consumer", "request", "epoch", "revision", "status")} | {
                            "widget": identifier, "destination": owner,
                        }
            published = [index for index, value in events(
                complete_lines(directory / "kwin.log")[:captured["kwinLines"]], "published"
            ) if value == expected]
            require(len(published) == 1 and published[0] >= boundary["kwinLines"],
                    "recovery lacks its exact post-restoration native publication")


def check_exchanges(directory: Path, stages: dict, replacement_id: int) -> None:
    initial = {row["query"]["consumer"]: row["query"]["request"]
               for row in stages["consumers"]["widgets"]}
    replacement = widgets(stages["final"])[replacement_id]["observation"]
    boot, final_request = replacement["boot"], replacement["request"]
    require(final_request == initial[boot] + 2, "recovery skipped or replayed a request generation")
    expected = {(actor, request + 1) for actor, request in initial.items()} | {(boot, final_request)}
    lines = complete_lines(directory / "plasmashell.log")
    start = stages["consumers"]["shellLines"]
    keys = [(index, row) for index, row in events(lines, "keyboard-query") if index >= start]
    require(len(keys) == 1 and keys[0][0] >= stages["after-replay"]["shellLines"]
            and keys[0][1]["boot"] == boot and keys[0][1]["request"] == final_request
            and keys[0][1]["intent"] == "prepare" and keys[0][1]["activeFocus"] is True
            and keys[0][1]["key"] == 32, "replacement interval has unsolicited or missing explicit input")
    key_index = keys[0][0]
    active = dict(initial)
    confirmed = {actor: True for actor in initial}
    sent = {(actor, request) for actor, request in initial.items()}
    outgoing = []
    history = sorted((index, kind, row) for kind in ("observation", "query")
                     for index, row in events(lines, kind) if index >= start)
    old_epoch, new_epoch = epoch(stages["consumers"]), epoch(stages["reloaded"])
    def leases(label):
        return {row["observation"]["boot"]:
                row["observation"]["packet"]["targetContext"]["consumerLease"]
                for row in stages[label]["widgets"]}

    old_leases, new_leases = leases("consumers"), leases("reloaded")
    for index, kind, row in history:
        actor, request = row["boot"], row["request"]
        require(actor in active and type(request) is int, "unknown receiver or invalid request timeline")
        identity = (actor, request)
        if kind == "query":
            require(identity in expected and request == active[actor] and identity not in sent,
                    "automatic or unordered exchange during provider replacement")
            sent.add(identity)
            outgoing.append(identity)
        elif row["packet"] is None:
            if row["phase"] == "unknown":
                require(request == active[actor] + 1 and identity in expected,
                        "unexpected unknown request generation")
                require(identity != (boot, final_request) or index > key_index,
                        "recovery query preceded its input")
                active[actor] = request
                confirmed[actor] = False
            else:
                require(row["phase"] == "unconfirmed" and request == active[actor]
                        and not confirmed[actor], "uncertainty changed a confirmed exchange")
        else:
            packet = row["packet"]
            require(type(packet["request"]) is int
                    and packet["consumer"] == actor and packet["request"] == request == active[actor]
                    and identity in sent, "accepted packet does not match the active request timeline")
            if index < stages["unknown"]["shellLines"]:
                require(request == initial[actor] and packet["epoch"] == old_epoch,
                        "accepted state before the provider withdrawal boundary")
                expected_lease = old_leases[actor]
            else:
                require(packet["epoch"] == new_epoch, "accepted state from a retired provider")
                expected_lease = new_leases[actor] if index >= stages["reloaded"]["shellLines"] else None
            if packet["status"] == "online" and expected_lease is not None:
                context = packet.get("targetContext")
                require(isinstance(context, dict) and context.get("consumerLease") == expected_lease,
                        "accepted frame changed its lease")
            confirmed[actor] = packet["status"] == "online"
    require(len(outgoing) == len(expected) and set(outgoing) == expected,
            "missing or repeated exchanges during replacement/recovery")
    native = events(complete_lines(directory / "kwin.log"), "target")
    require(not [row for index, row in native
                 if stages["consumers"]["kwinLines"] <= index < stages["reloaded"]["kwinLines"]],
            "unsolicited native preparation during provider replacement")


def check_mixed(directory: Path) -> None:
    stages = {label: saved_snapshot(directory, label, "unknown" if label == "unknown" else "online")
              for label in ("before", "consumers", "unknown", "reloaded",
                            "after-late", "after-replay", "final")}
    before = widgets(stages["before"])
    require(len(before) == 1, "missing surviving competing consumer")
    survivor_id, survivor = next(iter(before.items()))
    created = json.loads((directory / "mixed-created.json").read_text())
    removed = json.loads((directory / "consumer-removed.json").read_text())
    consumer = widgets(stages["consumers"])
    replacement_id = created["id"]
    require(created["survivorId"] == survivor_id and set(consumer) == {survivor_id, replacement_id}
            and type(replacement_id) is int and replacement_id not in (survivor_id, removed["removedId"]),
            "native replacement did not preserve exactly one survivor")
    boots = {identifier: row["query"]["consumer"] for identifier, row in consumer.items()}
    require(boots[survivor_id] == survivor["query"]["consumer"]
            and boots[replacement_id] not in (boots[survivor_id], removed["consumer"]),
            "replacement reused a retired consumer lifetime")
    old_epoch = epoch(stages["before"])
    require(epoch(stages["consumers"]) == old_epoch, "consumer replacement changed the provider")
    retired = json.loads((directory / "mixed-retired-preparation.json").read_text())
    prepared = json.loads((directory / "consumer-explicit-recovery.json").read_text())
    require(retired["boot"] == removed["consumer"] and prepared["boot"] == boots[survivor_id],
            "prepared responses belong to different consumers")
    native_preparation(directory, retired, 0, stages["before"]["kwinLines"])
    native_preparation(directory, prepared, 0, stages["before"]["kwinLines"])
    old_leases = {row["packet"]["targetContext"]["consumerLease"] for row in (retired, prepared)}
    survivor_lease = prepared["packet"]["targetContext"]["consumerLease"]
    require(len(old_leases) == 2
            and consumer[replacement_id]["observation"]["packet"]["targetContext"]["consumerLease"]
            not in old_leases, "replacement reused a retired consumer lease")
    require(survivor["observation"]["packet"]["targetContext"]["consumerLease"] == survivor_lease
            == consumer[survivor_id]["observation"]["packet"]["targetContext"]["consumerLease"],
            "unrelated consumer replacement reissued the surviving lease")
    old_leases.update(row["observation"]["packet"]["targetContext"]["consumerLease"]
                      for row in consumer.values())
    unknown = widgets(stages["unknown"])
    reloaded = widgets(stages["reloaded"])
    new_epoch = epoch(stages["reloaded"])
    require(new_epoch != old_epoch, "provider reload reused its lifetime")
    new_leases = {row["observation"]["packet"]["targetContext"]["consumerLease"]
                  for row in reloaded.values()}
    require(len(new_leases) == 2 and not new_leases & old_leases,
            "provider reload reused an old consumer lease")
    for identifier, boot in boots.items():
        require(unknown[identifier]["query"]["consumer"] == reloaded[identifier]["query"]["consumer"] == boot
                and unknown[identifier]["query"]["request"] == consumer[identifier]["query"]["request"] + 1
                and unknown[identifier]["query"]["intent"] == "query"
                and reloaded[identifier]["query"]["request"] == unknown[identifier]["query"]["request"]
                and reloaded[identifier]["query"]["intent"] == "query"
                and reloaded[identifier]["observation"]["packet"]["preparation"] is None,
                "provider replacement replayed intent or reused stale receiver memory")
    owner = json.loads((directory / "mixed-owners.json").read_text())
    identity = json.loads((directory / "cleanup-identity.json").read_text())["session"]
    require(all(owner[key + "Before"] == owner[key + "After"] == identity[field]
                for key, field in (("bus", "bus"), ("backend", "backend"), ("shell", "shell"))),
            "bus/backend/shell changed during the provider-only replacement")
    require(owner["retiredIdentity"] == "org.plasmafusion.LayoutProbe.p" + old_epoch
            and owner["retiredHeld"] is False
            and owner["newIdentity"] == "org.plasmafusion.LayoutProbe.p" + new_epoch
            and owner["newOwner"] == identity["backend"], "provider alias ownership did not change safely")
    require(json.loads((directory / "mixed-replayed-request.json").read_text()) == survivor["query"],
            "replay did not use the original preparation envelope")
    check_late(directory)
    check_replay(directory, stages["after-replay"])
    for label, previous_label in (("after-late", "reloaded"), ("after-replay", "after-late")):
        check_progress(directory, label, previous_label)
    replayed = widgets(stages["after-replay"])
    final_widgets = widgets(stages["final"])
    require(set(final_widgets) == set(replayed) and all(
        row["query"]["consumer"] == replayed[identifier]["query"]["consumer"]
        and row["observation"]["packet"]["targetContext"]["consumerLease"]
        == replayed[identifier]["observation"]["packet"]["targetContext"]["consumerLease"]
        for identifier, row in final_widgets.items()),
        "final inventory lost or replaced a live consumer")
    final = final_widgets[replacement_id]["observation"]
    require(final["request"] > reloaded[replacement_id]["query"]["request"],
            "replacement did not receive a new explicit intent")
    native_preparation(directory, final, stages["after-replay"]["kwinLines"],
                       stages["final"]["kwinLines"])
    check_exchanges(directory, stages, replacement_id)


def write_frames(directory: Path) -> None:
    frames = late_frames(directory)
    with (directory / "mixed-frames.json").open("x") as output:
        json.dump(frames, output)
    # Only serialize captured data; execution remains in the guarded private scenario.
    script = "var frames=" + json.dumps(frames) + ";var written=0;"
    script += """
frames.forEach(function(m){
    var found=0;
    panels().forEach(function(p){p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){
        if(w.id===m.id){
            w.currentConfigGroup=['General'];
            var q=JSON.parse(w.readConfig('layoutRequest','{}'));
            if(q.consumer!==m.receiver)throw new Error('mixed receiver lifetime changed');
            w.writeConfig('layoutResponse',JSON.stringify(m.packet));
            ++written;++found;
        }
    });});
    if(found!==1)throw new Error('mixed receiver is not unique');
});
print(written);
"""
    with (directory / "mixed-inject.js").open("x") as output:
        output.write(script)


def record_restored(directory: Path) -> None:
    check_replay(directory)
    value = {"schema": 1, "shellLines": len(complete_lines(directory / "plasmashell.log")),
             "kwinLines": len(complete_lines(directory / "kwin.log"))}
    with (directory / "mixed-restored-boundary.json").open("x") as output:
        json.dump(value, output)


def main() -> None:
    if len(sys.argv) == 6 and sys.argv[1] == "snapshot":
        print(json.dumps(snapshot(Path(sys.argv[2]), Path(sys.argv[3]),
                                  sys.argv[4], int(sys.argv[5]))))
    elif len(sys.argv) == 3 and sys.argv[1] in ("frames", "late", "refusal", "restored", "progress", "check"):
        actions = {"frames": write_frames, "late": check_late,
                   "refusal": check_replay, "check": check_mixed,
                   "restored": record_restored,
                   "progress": lambda path: check_progress(path, "after-replay", "after-late")}
        actions[sys.argv[1]](Path(sys.argv[2]))
        print(f"PASS: mixed {sys.argv[1]} evidence")
    else:
        raise SystemExit("usage: mixed_lifetime.py {snapshot OUT INVENTORY PHASE COUNT"
                         "|frames OUT|late OUT|refusal OUT|restored OUT|progress OUT|check OUT}")


if __name__ == "__main__":
    main()
