#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Capture and qualify P0 refused-native-backend evidence. Never operate a desktop.

The occupier fixture holds the fork's single native provider slot from session start, so the
probe's own registration is refused. Each step reads only the complete log lines between an
exclusive mark, written before its native action, and the point where the step was confirmed.
The final check recomputes every step from those windows, then audits the run up to the end of
its last step.
"""

import json
import re
import sys
from pathlib import Path

if __package__:
    from .mixed_lifetime import complete_lines, events, require
else:
    from mixed_lifetime import complete_lines, events, require

CHECKS = ["roundtrip-native", "refused-registration", "refused-lifetime-labels",
          "occupier-release", "accepted-recovery"]
ALIAS = "org.plasmafusion.LayoutProbe.p"
LABEL = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
EPOCH = re.compile(r"[0-9a-f]{32}")
INITIALIZED = re.compile(r"qml: layout-probe: initialized (true|false) (-?[0-9]+)")
OCCUPIER = re.compile(r"qml: layout-occupier: (registered|released) (true|false)")
# The fork refuses createTile with a null output before any provider check, in every lifetime.
NULL_OUTPUT_REFUSAL = -1
# States a consumer may pass through between two provider lifetimes.
TRANSIENT = frozenset({"unknown", "unconfirmed", "offline"})


def load(directory: Path, name: str):
    return json.loads((directory / name).read_text())


def line_counts(directory: Path) -> dict:
    return {"shellLines": len(complete_lines(directory / "plasmashell.log")),
            "kwinLines": len(complete_lines(directory / "kwin.log"))}


def mark(directory: Path, label: str) -> dict:
    require(isinstance(label, str) and LABEL.fullmatch(label) is not None,
            "invalid refused-backend mark label")
    value = {"schema": 1} | line_counts(directory)
    with (directory / f"refused-mark-{label}.json").open("x") as output:
        json.dump(value, output)
    return value


class Evidence:
    """Complete shell/backend lines from one mark to a fixed (or the current) end."""

    def __init__(self, directory: Path, label: str, end: dict | None):
        start = load(directory, f"refused-mark-{label}.json")
        require(isinstance(start, dict) and set(start) == {"schema", "shellLines", "kwinLines"}
                and start["schema"] == 1, "invalid refused-backend mark")
        shell = complete_lines(directory / "plasmashell.log")
        backend = complete_lines(directory / "kwin.log")
        stop = {"shellLines": len(shell), "kwinLines": len(backend)} if end is None else end
        require(isinstance(stop, dict) and set(stop) == {"shellLines", "kwinLines"},
                "invalid refused-backend evidence end")
        for field, total in (("shellLines", len(shell)), ("kwinLines", len(backend))):
            require(type(start[field]) is int and type(stop[field]) is int
                    and 0 <= start[field] <= stop[field] <= total,
                    "invalid refused-backend evidence window")
        self.start, self.stop = start, dict(stop)
        self.shell_lines = shell[:stop["shellLines"]]
        self.backend_lines = backend[:stop["kwinLines"]]

    def shell(self, kind: str, *, everything: bool = False) -> list:
        first = 0 if everything else self.start["shellLines"]
        rows = [(index, row) for index, row in events(self.shell_lines, kind) if index >= first]
        require(all(isinstance(row, dict) for _, row in rows), f"malformed {kind} event")
        return rows

    def backend(self, pattern: re.Pattern, *, everything: bool = False) -> list:
        first = 0 if everything else self.start["kwinLines"]
        found = []
        for index, line in enumerate(self.backend_lines):
            match = pattern.fullmatch(line.rstrip("\n"))
            if index >= first and match:
                found.append((index, match.groups()))
        return found


def initialisations(ev: Evidence, *, everything: bool = False) -> list:
    return [(index, verdict == "true", int(code))
            for index, (verdict, code) in ev.backend(INITIALIZED, everything=everything)]


def occupier_lines(ev: Evidence, *, everything: bool = False) -> list:
    return [(index, action, verdict == "true")
            for index, (action, verdict) in ev.backend(OCCUPIER, everything=everything)]


def frames(ev: Evidence, boots: list, *, everything: bool = False) -> list:
    rows = ev.shell("received", everything=everything)
    for _, row in rows:
        require(isinstance(row, dict) and row.get("receiverBoot") in boots
                and row.get("consumer") == row.get("receiverBoot"),
                "a frame reached an unexpected or swapped consumer")
        epoch = row.get("epoch")
        require(isinstance(epoch, str) and EPOCH.fullmatch(epoch) is not None
                and row.get("identityName") == ALIAS + epoch,
                "a frame's identity is not derived from its provider label")
    return rows


def step_occupied(directory: Path, saved: dict, ev: Evidence) -> dict:
    held = occupier_lines(ev, everything=True)
    require([entry[1:] for entry in held] == [("registered", True)],
            "the occupier did not hold the native provider slot before the probe loaded")
    require(not initialisations(ev, everything=True),
            "the probe initialized before the occupier case")
    return {"occupierLine": held[0][0]}


def still_previous(row: dict, previous: dict, boot: str) -> bool:
    """A newer frame of the previous lifetime, accepted before the consumer dropped it.

    That provider published once per wake and the consumer verifies one frame at a time, so
    the previous step can be confirmed between two of its acceptances.
    """
    packet = row.get("packet")
    return (row.get("phase") == ("online" if previous["capable"] else "unsupported")
            and row.get("epoch") == previous["epoch"] and isinstance(packet, dict)
            and packet.get("epoch") == previous["epoch"]
            and packet.get("request") == previous["requests"][boot]
            and packet.get("capable") is previous["capable"]
            and packet.get("identityName") == previous["identity"])


def lifetime(ev: Evidence, name: str, *, capable: bool, boots: list | None,
             earlier: list, previous: dict | None) -> dict:
    inits = initialisations(ev)
    require(len(inits) == 1, f"{name}: expected exactly one provider initialization")
    require(inits[0][1] is capable,
            f"{name}: {'accepted' if capable else 'refused'} registration not reported")
    require(inits[0][2] == NULL_OUTPUT_REFUSAL, f"{name}: unexpected native null-output result")
    require(not occupier_lines(ev), f"{name}: the occupier changed during a provider lifetime")
    observations = ev.shell("observation")
    if boots is None:
        found = {row.get("boot") for _, row in observations}
        require(all(isinstance(boot, str) for boot in found),
                f"{name}: a consumer reported state without a boot label")
        boots = sorted(found)
    require(len(boots) == 2 and all(isinstance(boot, str) for boot in boots),
            f"{name}: expected exactly two probe consumers")
    require(all(row.get("boot") in boots for _, row in observations),
            f"{name}: an unexpected consumer reported state")
    received = frames(ev, boots)
    # Report the specific violation first: no capable state or frame in a refused lifetime.
    for _, row in observations:
        packet = row.get("packet")
        require(capable or (row.get("phase") != "online"
                            and not (isinstance(packet, dict) and packet.get("capable") is True)),
                f"{name}: a consumer accepted capable state during a refused lifetime")
    require(capable or not any(row.get("capable") is True for _, row in received),
            f"{name}: a capable frame was published during a refused lifetime")
    settled = "online" if capable else "unsupported"
    labels, owners, requests = set(), set(), {}
    for boot in boots:
        rows = [(index, row) for index, row in observations if row["boot"] == boot]
        require(bool(rows), f"{name}: consumer {boot} reported no state")
        final_index, final = rows[-1]
        packet = final.get("packet")
        require(final.get("phase") == settled and isinstance(packet, dict),
                f"{name}: consumer {boot} did not settle {settled}")
        epoch = final.get("epoch")
        require(isinstance(epoch, str) and EPOCH.fullmatch(epoch) is not None
                and packet.get("epoch") == epoch, f"{name}: invalid provider label")
        # Checked first: a reused label also looks like a return to the previous provider.
        require(epoch not in earlier, f"{name}: a provider lifetime reused a provider label")
        require(packet.get("status") == "online" and packet.get("capable") is capable,
                f"{name}: accepted capable flag does not match the native verdict")
        require(packet.get("identityName") == ALIAS + epoch,
                f"{name}: the identity is not derived from the provider label")
        labels.add(epoch)
        owners.add(packet.get("backendOwner"))
        requests[boot] = packet.get("request")
        if previous is not None:
            # Alias invalidation, the accepted retirement frame and the next provider's first
            # frame race in the consumer, and any of them may end the binding. Whichever won,
            # the consumer must drop its state, settle through a fresh query and never return.
            dropped = [index for index, row in rows
                       if row.get("phase") == "unknown" and row.get("packet") is None]
            require(bool(dropped) and dropped[0] < final_index,
                    f"{name}: consumer {boot} kept the previous provider's state")
            require(all(row.get("epoch") != previous["epoch"]
                        for index, row in rows if index > dropped[0]),
                    f"{name}: consumer {boot} returned to the previous provider")
            require(type(packet.get("request")) is int
                    and packet["request"] > previous["requests"][boot],
                    f"{name}: consumer {boot} settled without a fresh query")
        for index, row in rows[:-1]:
            phase = row.get("phase")
            late = previous is not None and index < dropped[0] and still_previous(
                row, previous, boot)
            require(phase in TRANSIENT or late or (phase == settled and row.get("epoch") == epoch),
                    f"{name}: consumer {boot} passed through an unexpected state")
    require(len(labels) == 1, f"{name}: the consumers settled on different provider labels")
    label = labels.pop()
    require(len(owners) == 1 and isinstance(next(iter(owners)), str),
            f"{name}: inconsistent backend connection")
    return {"epoch": label, "identity": ALIAS + label, "boots": boots, "requests": requests,
            "backendOwner": next(iter(owners)), "initLine": inits[0][0], "capable": capable}


def step_refused_first(directory: Path, saved: dict, ev: Evidence) -> dict:
    return lifetime(ev, "refused-1", capable=False, boots=None, earlier=[], previous=None)


def step_refused_second(directory: Path, saved: dict, ev: Evidence) -> dict:
    first = saved["refused-1"]
    return lifetime(ev, "refused-2", capable=False, boots=first["boots"],
                    earlier=[first["epoch"]], previous=first)


def step_released(directory: Path, saved: dict, ev: Evidence) -> dict:
    released = occupier_lines(ev)
    require([entry[1:] for entry in released] == [("released", True)],
            "the occupier did not release the native provider slot")
    require(not initialisations(ev), "a provider initialized while the occupier released")
    for _, row in ev.shell("observation"):
        packet = row.get("packet")
        require(row.get("phase") != "online"
                and not (isinstance(packet, dict) and packet.get("capable") is True),
                "a consumer accepted capable state before the probe re-registered")
    return {"releaseLine": released[0][0]}


def step_accepted(directory: Path, saved: dict, ev: Evidence) -> dict:
    first, second = saved["refused-1"], saved["refused-2"]
    return lifetime(ev, "accepted", capable=True, boots=first["boots"],
                    earlier=[first["epoch"], second["epoch"]], previous=second)


STEPS = {
    "occupied": ("start", step_occupied),
    "refused-1": ("load-1", step_refused_first),
    "refused-2": ("reload-1", step_refused_second),
    "released": ("release", step_released),
    "accepted": ("reload-2", step_accepted),
}
ORDER = list(STEPS)


def evaluate(directory: Path, name: str, saved: dict, end: dict | None) -> dict:
    label, function = STEPS[name]
    ev = Evidence(directory, label, end)
    return function(directory, saved, ev) | {"end": ev.stop}


def record_step(directory: Path, name: str) -> dict:
    require(name in STEPS, "unknown refused-backend step")
    saved = {previous: load(directory, f"refused-{previous}.json")
             for previous in ORDER[:ORDER.index(name)]}
    record = evaluate(directory, name, saved, None)
    with (directory / f"refused-{name}.json").open("x") as output:
        json.dump(record, output)
    return record


def audit(directory: Path, saved: dict) -> None:
    """The whole run up to the last step: native verdicts, release order and every state."""
    ev = Evidence(directory, "start", saved["accepted"]["end"])
    inits = initialisations(ev, everything=True)
    lifetimes = ("refused-1", "refused-2", "accepted")
    require([entry[1:] for entry in inits] == [(False, NULL_OUTPUT_REFUSAL),
                                               (False, NULL_OUTPUT_REFUSAL),
                                               (True, NULL_OUTPUT_REFUSAL)]
            and [entry[0] for entry in inits] == [saved[name]["initLine"] for name in lifetimes],
            "the run's provider initializations are not refused, refused, accepted")
    held = occupier_lines(ev, everything=True)
    require([entry[1:] for entry in held] == [("registered", True), ("released", True)]
            and held[0][0] == saved["occupied"]["occupierLine"]
            and held[1][0] == saved["released"]["releaseLine"]
            and held[0][0] < inits[0][0] and inits[1][0] < held[1][0] < inits[2][0],
            "the occupier did not hold the slot across both refusals, then release it")
    labels = [saved[name]["epoch"] for name in lifetimes]
    require(len(set(labels)) == 3, "a provider lifetime reused a provider label")
    boots = saved["refused-1"]["boots"]
    accepted_from = load(directory, "refused-mark-reload-2.json")["shellLines"]
    for index, row in ev.shell("observation", everything=True):
        require(row.get("boot") in boots, "an unexpected consumer reported state")
        packet = row.get("packet")
        capable_state = row.get("phase") == "online" or (
            isinstance(packet, dict) and packet.get("capable") is True)
        require(not capable_state or (index >= accepted_from and row.get("epoch") == labels[2]),
                "a consumer accepted capable state outside the accepted lifetime")
        require(row.get("phase") != "unsupported" or row.get("epoch") in labels[:2],
                "a consumer reported unsupported state for a capable provider")
    owners = set()
    for _, row in frames(ev, boots, everything=True):
        require(row.get("epoch") in labels, "a frame carried an unknown provider label")
        require((row.get("capable") is True) == (row.get("epoch") == labels[2]),
                "a frame's capable flag does not match its provider lifetime")
        owners.add(row.get("backendOwner"))
    require(owners == {saved["accepted"]["backendOwner"]},
            "frames named more than one backend connection")


def check_refused(directory: Path) -> None:
    saved, previous = {}, None
    for name in ORDER:
        record = load(directory, f"refused-{name}.json")
        start = load(directory, f"refused-mark-{STEPS[name][0]}.json")
        require(isinstance(record, dict) and isinstance(record.get("end"), dict)
                and isinstance(start, dict), f"invalid {name} evidence record")
        if previous is not None:
            require(all(type(start.get(field)) is int and start[field] >= previous[field]
                        for field in ("shellLines", "kwinLines")),
                    "refused-backend evidence windows overlap or are out of order")
        require(evaluate(directory, name, saved, record["end"]) == record,
                f"{name} record does not match its raw evidence")
        saved[name] = record
        previous = record["end"]
    audit(directory, saved)


def write_receipt(directory: Path) -> None:
    """The receipt's check list has one source: it is written only after the full check."""
    check_refused(directory)
    with (directory / "refused-backend-result.json").open("x") as output:
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
            print("PASS: refused-backend evidence")
        else:
            raise SystemExit("usage: refused_backend.py {mark OUT LABEL|step OUT NAME|receipt OUT}")
    except (ValueError, OSError) as error:
        raise SystemExit(f"refused-backend: {error}") from None


if __name__ == "__main__":
    main()
