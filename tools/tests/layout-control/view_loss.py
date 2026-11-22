#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Capture and qualify P0 output-loss and activity-switch evidence. Never operate a desktop.

Each step reads only the complete log lines between an exclusive mark, written before its
native action, and the point where the step was confirmed. The final check recomputes every
step from those windows, then audits the whole run.
"""

import json
import re
import sys
from pathlib import Path

if __package__:
    from .mixed_lifetime import complete_lines, events, require
else:
    from mixed_lifetime import complete_lines, events, require

APP = "pf.focus.alpha"
STALE = "stale-context"
VIEW_KEYS = frozenset({"reason", "source", "from", "generation", "prepared", "screens",
                       "activityId", "activities", "desktopId", "activeClass", "activeOutput",
                       "subjectClass", "subjectOutput", "subjectFrame", "subjectInView"})
SCREEN_KEYS = frozenset({"name", "known", "x", "y", "width", "height"})
# Every native event that may advance the provider's context generation.
SOURCES = frozenset({
    "activation", "window-removed", "current-desktop", "current-activity", "screens", "desktops",
    "activities", "window-desktops", "window-activities", "window-output", "window-minimized",
    "window-fullscreen", "window-maximized", "window-tile", "window-skip-taskbar",
    "window-skip-switcher", "window-transient", "window-modal", "shell-pid", "shell-owner",
    "shell-lookup",
})
CHECKS = ["roundtrip-native", "guarded-target", "output-loss", "same-name-output",
          "activity-switch", "wrong-view-refusal", "explicit-recovery"]
LABEL = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")


def load(directory: Path, name: str):
    return json.loads((directory / name).read_text())


def line_counts(directory: Path) -> dict:
    return {"shellLines": len(complete_lines(directory / "plasmashell.log")),
            "kwinLines": len(complete_lines(directory / "kwin.log"))}


def mark(directory: Path, label: str) -> dict:
    require(isinstance(label, str) and LABEL.fullmatch(label) is not None,
            "invalid view mark label")
    value = {"schema": 1} | line_counts(directory)
    with (directory / f"view-mark-{label}.json").open("x") as output:
        json.dump(value, output)
    return value


def valid_view(row) -> dict:
    require(isinstance(row, dict) and set(row) == VIEW_KEYS and isinstance(row["screens"], list)
            and all(isinstance(screen, dict) and set(screen) == SCREEN_KEYS
                    for screen in row["screens"])
            and type(row["from"]) is int and type(row["generation"]) is int
            and type(row["prepared"]) is bool and type(row["subjectInView"]) is bool
            and (row["subjectFrame"] is None or isinstance(row["subjectFrame"], dict)),
            "malformed native view report")
    return row


class Evidence:
    """Complete shell/backend lines from one mark to a fixed (or the current) end."""

    def __init__(self, directory: Path, label: str, end: dict | None):
        start = load(directory, f"view-mark-{label}.json")
        require(isinstance(start, dict) and set(start) == {"schema", "shellLines", "kwinLines"}
                and start["schema"] == 1, "invalid view mark")
        shell = complete_lines(directory / "plasmashell.log")
        backend = complete_lines(directory / "kwin.log")
        stop = {"shellLines": len(shell), "kwinLines": len(backend)} if end is None else end
        require(isinstance(stop, dict) and set(stop) == {"shellLines", "kwinLines"},
                "invalid view evidence end")
        for field, total in (("shellLines", len(shell)), ("kwinLines", len(backend))):
            require(type(start[field]) is int and type(stop[field]) is int
                    and 0 <= start[field] <= stop[field] <= total, "invalid view evidence window")
        self.start, self.stop = start, dict(stop)
        self.shell_lines = shell[:stop["shellLines"]]
        self.backend_lines = backend[:stop["kwinLines"]]

    def shell(self, kind: str) -> list:
        return [(index, row) for index, row in events(self.shell_lines, kind)
                if index >= self.start["shellLines"]]

    def backend(self, kind: str) -> list:
        return [(index, row) for index, row in events(self.backend_lines, kind)
                if index >= self.start["kwinLines"]]

    def shell_before(self, kind: str) -> list:
        return [(index, row) for index, row in events(self.shell_lines, kind)
                if index < self.start["shellLines"]]

    def backend_before(self, kind: str) -> list:
        return [(index, row) for index, row in events(self.backend_lines, kind)
                if index < self.start["kwinLines"]]

    def views(self) -> list:
        return [valid_view(row) for _, row in self.backend("view")]

    def views_until(self) -> list:
        return [valid_view(row) for _, row in events(self.backend_lines, "view")]


def latest(rows: list) -> dict:
    return {row["boot"]: row for _, row in rows}


def requests(ev: Evidence, boot: str) -> list:
    return [(index, row) for index, row in ev.shell("query") if row["boot"] == boot]


def keyboard(ev: Evidence, boot: str) -> list:
    return [(index, row) for index, row in ev.shell("keyboard-query") if row["boot"] == boot]


def no_readiness(ev: Evidence) -> None:
    require(not [row for _, row in ev.backend("target") if row["ready"] is not False],
            "a target became ready during a view change")


def refusals(ev: Evidence, boot: str, request: int, intent: str, reason: str = STALE) -> list:
    """Accepted observations of one exact native refusal, each after its actual receipt."""
    verdicts = [row for _, row in ev.backend("target")
                if row["consumer"] == boot and row["request"] == request]
    require(verdicts and all(row["intent"] == intent and row["ready"] is False
                             and row["targetAlive"] is False and row["targetClass"] == ""
                             for row in verdicts), "missing exact native refusal")
    revisions = {row["revision"] for row in verdicts if row["reason"] == reason}
    require(revisions, f"missing exact native {reason} refusal")
    expected = {"intent": intent, "ready": False, "reason": reason, "token": ""}
    received = ev.shell("received")
    matches = []
    for index, row in ev.shell("observation"):
        packet = row["packet"]
        if (row["boot"] == boot and packet and packet.get("consumer") == boot
                and row["request"] == packet.get("request") == request
                and packet.get("revision") in revisions and packet.get("preparation") == expected
                and any(position < index and value == packet | {"receiverBoot": boot}
                        for position, value in received)):
            matches.append(row)
    require(matches, f"{reason} refusal did not reach its live receiver")
    return matches


def ready_reply(ev: Evidence, boot: str, request: int, intent: str) -> dict:
    verdicts = [row for _, row in ev.backend("target") if row["consumer"] == boot
                and row["request"] == request and row["intent"] == intent and row["ready"] is True]
    require(verdicts and all(row["reason"] == "" and row["targetAlive"] is True
                             and row["targetClass"] == APP for row in verdicts),
            "native verdict does not confirm the intended application")
    revisions = {row["revision"] for row in verdicts}
    received = ev.shell("received")
    for index, row in ev.shell("observation"):
        packet = row["packet"]
        preparation = packet.get("preparation") if packet else None
        # Only a preparation issues a handle; a confirmed validation never echoes it.
        token = preparation.get("token") if isinstance(preparation, dict) else None
        if (row["boot"] == boot and isinstance(preparation, dict) and packet.get("consumer") == boot
                and row["request"] == packet.get("request") == request
                and packet.get("revision") in revisions and preparation.get("intent") == intent
                and preparation.get("ready") is True and preparation.get("reason") == ""
                and isinstance(token, str) and bool(token) == (intent == "prepare")
                and any(position < index and value == packet | {"receiverBoot": boot}
                        for position, value in received)):
            return row
    raise ValueError("explicit recovery did not reach its live receiver")


def in_context(row: dict, base: dict, boot: str, activity: str, after: int) -> bool:
    """A reply carrying a newer context of the captured output in the given activity."""
    context = row["packet"].get("targetContext")
    return (isinstance(context, dict) and context.get("epoch") == base["epoch"]
            and context.get("outputName") == base["output"]
            and context.get("activityId") == activity
            and context.get("desktopId") == base["desktop"]
            and context.get("consumerLease") == base["leases"][boot]
            and type(context.get("generation")) is int and context["generation"] > after)


def reattached(ev: Evidence, base: dict, output: str, previous: int) -> int:
    """The read-only competing consumer survives the move with a fresh query and its lease."""
    other = base["otherBoot"]
    rows = [row for _, row in ev.shell("observation") if row["boot"] == other and row["packet"]
            and isinstance(row["packet"].get("targetContext"), dict)
            and row["packet"]["targetContext"].get("outputName") == output]
    require(rows and rows[-1]["request"] > previous
            and rows[-1]["packet"]["targetContext"].get("consumerLease") == base["leases"][other]
            and rows[-1]["packet"].get("epoch") == base["epoch"]
            and rows[-1]["packet"].get("preparation") is None,
            "competing consumer did not re-attach with its unchanged lease")
    require(not [row for _, row in ev.backend("target") if row["consumer"] == other],
            "the read-only consumer dispatched a target intent")
    return rows[-1]["request"]


def explicit_requests(ev: Evidence, boot: str, expected: list) -> None:
    keys, sent = keyboard(ev, boot), requests(ev, boot)
    require([(row["intent"], row["request"]) for _, row in keys] == expected
            and all(row["activeFocus"] is True and row["key"] == 32 for _, row in keys)
            and [row["request"] for _, row in sent] == [request for _, request in expected]
            and all(query[0] > key[0] for key, query in zip(keys, sent)),
            "explicit intents lack their focused keyboard input or include hidden requests")


def reestablished(ev: Evidence, base: dict) -> None:
    rows = [row for _, row in ev.backend("focus")
            if row["event"] == "activation" and row["activeClass"] == APP]
    require(rows and rows[-1]["rememberedClass"] == APP and rows[-1]["rememberedAlive"] is True
            and rows[-1]["rememberedOutput"] == base["output"]
            and rows[-1]["activityId"] == base["activity"],
            "the application was not re-established on the returned output")


def ready_only(ev: Evidence, allowed: set) -> None:
    ready = {(row["consumer"], row["request"], row["intent"]) for _, row in ev.backend("target")
             if row["ready"] is not False}
    require(ready == allowed, "unexpected native readiness during recovery")


def inventory_request(directory: Path, name: str, boot: str) -> dict:
    widgets = load(directory, f"view-{name}-inventory.json")
    require(isinstance(widgets, list), "invalid native inventory")
    rows = [row["request"] for row in widgets if isinstance(row, dict)
            and isinstance(row.get("request"), dict) and row["request"].get("consumer") == boot]
    require(len(rows) == 1, "the guarded consumer is not unique in the native inventory")
    return rows[0]


def step_baseline(directory: Path, saved: dict, ev: Evidence) -> dict:
    inventory = load(directory, "view-baseline-inventory.json")
    require(isinstance(inventory, list) and len(inventory) == 2
            and all(isinstance(row, dict) and type(row.get("id")) is int and row["id"] > 0
                    and isinstance(row.get("request"), dict) for row in inventory)
            and inventory[0]["id"] != inventory[1]["id"], "expected the two owned native widgets")
    by_intent = {row["request"].get("intent"): row["request"] for row in inventory}
    require(set(by_intent) == {"validate", "query"},
            "expected one retained validation and one read-only query")
    envelope, peer_query = by_intent["validate"], by_intent["query"]
    focus, other = envelope.get("consumer"), peer_query.get("consumer")
    require(isinstance(focus, str) and bool(focus) and isinstance(other, str) and bool(other)
            and focus != other, "native consumers must have distinct lifetimes")
    output = envelope.get("outputName")
    require(envelope.get("version") == 1 and type(envelope.get("request")) is int
            and envelope["request"] > 0 and isinstance(envelope.get("token"), str)
            and bool(envelope["token"]) and isinstance(output, str) and bool(output)
            and envelope.get("viewOutputName") == output
            and type(envelope.get("viewGeneration")) is int and envelope["viewGeneration"] >= 0
            and isinstance(envelope.get("consumerLease"), str) and bool(envelope["consumerLease"]),
            "retained validation envelope is incomplete")
    accepted = [row for _, row in ev.shell_before("observation") if row["packet"]]
    mine = [row for row in accepted if row["boot"] == focus]
    theirs = [row for row in accepted if row["boot"] == other]
    require(mine and theirs, "missing accepted state before the view changes")
    current, peer = mine[-1], theirs[-1]
    packet, peer_packet = current["packet"], peer["packet"]
    context, peer_context = packet.get("targetContext"), peer_packet.get("targetContext")
    require(current["request"] == packet.get("request") == envelope["request"]
            and packet.get("preparation") == {"intent": "validate", "ready": True, "reason": "",
                                              "token": ""}
            and isinstance(context, dict) and context.get("outputName") == output
            and context.get("consumerLease") == envelope["consumerLease"]
            and context.get("epoch") == packet.get("epoch") == envelope.get("viewEpoch"),
            "the retained validation was not confirmed ready before the view changes")
    verdicts = [row for _, row in ev.backend_before("target") if row["consumer"] == focus
                and row["request"] == envelope["request"] and row["revision"] == packet["revision"]]
    require(len(verdicts) == 1 and verdicts[0]["intent"] == "validate"
            and verdicts[0]["ready"] is True and verdicts[0]["targetAlive"] is True
            and verdicts[0]["targetClass"] == APP,
            "native verdict does not confirm the intended application")
    require(peer["request"] == peer_packet.get("request") == peer_query.get("request")
            and peer_packet.get("preparation") is None
            and peer_packet.get("epoch") == packet["epoch"]
            and isinstance(peer_context, dict) and peer_context.get("outputName") == output
            and isinstance(peer_context.get("consumerLease"), str)
            and peer_context["consumerLease"] not in ("", envelope["consumerLease"]),
            "competing consumer lacks its own current read-only context")
    wakes = [row for row in ev.views() if row["reason"] == "wake"]
    require(bool(wakes), "missing current native view report")
    view = wakes[-1]
    # A verdict for the guarded consumer must follow the last wake record, not the record alone:
    # a ready one logged after the disable mark would fail the loss step although the provider
    # then refuses the handle. Bound by log position, it may also come from a read already under
    # way at the wake; the scenario starts none. The audit checks which readiness it may carry.
    wake = max(index for index, row in ev.backend("view") if row["reason"] == "wake")
    require(any(index > wake and row["consumer"] == focus for index, row in ev.backend("target")),
            "no verdict for the guarded consumer follows the baseline wake yet")
    names = [screen["name"] for screen in view["screens"]]
    require(len(names) == 2 == len(set(names)) and output in names
            and all(screen["known"] is True for screen in view["screens"]),
            "this case requires the two original native outputs")
    require(view["subjectClass"] == APP and view["subjectOutput"] == output
            and view["subjectInView"] is True and view["prepared"] is True
            and view["activityId"] == context.get("activityId") and view["activities"] == 1
            and view["desktopId"] == context.get("desktopId"),
            "the guarded application is not live in the captured view")
    controls = latest(events(ev.shell_lines, "focus-control"))
    require(all(controls.get(boot, {}).get("screen") == output for boot in (focus, other)),
            "consumers are not on the captured output")
    pid = int((directory / "focus-shell-pid.txt").read_text().strip())
    require(pid > 0, "missing the verified shell PID")
    return {"focusBoot": focus, "otherBoot": other, "epoch": packet["epoch"],
            "leases": {focus: envelope["consumerLease"], other: peer_context["consumerLease"]},
            "output": output, "otherOutput": next(name for name in names if name != output),
            "activity": context["activityId"], "desktop": context["desktopId"],
            "envelope": envelope, "otherRequest": peer["request"],
            "generation": view["generation"], "shellPid": pid}


def step_lost(directory: Path, saved: dict, ev: Evidence) -> dict:
    base = saved["baseline"]
    focus, remaining = base["focusBoot"], base["otherOutput"]
    views = ev.views()
    require(any(row["source"] == "screens"
                and [(screen["name"], screen["known"]) for screen in row["screens"]]
                == [(remaining, True)] for row in views),
            "output removal lacks its own native screens event")
    require(any(row["prepared"] for row in views),
            "output removal did not clear a live preparation")
    no_readiness(ev)
    matches = refusals(ev, focus, base["envelope"]["request"], "validate")
    # The retained envelope names the removed output, so no current context can exist for it.
    selected = [row for row in matches if row["packet"].get("targetContext") is None
                and row["packet"].get("epoch") == base["epoch"]]
    require(bool(selected), "removed output still produced a target context")
    require(not requests(ev, focus), "view loss triggered an automatic resend")
    controls = latest(ev.shell("focus-control"))
    require(all(controls.get(boot, {}).get("screen") == remaining
                for boot in (focus, base["otherBoot"])),
            "consumers did not survive on the remaining output")
    other_request = reattached(ev, base, remaining, base["otherRequest"])
    return {"refusalRevision": selected[0]["packet"]["revision"], "otherRequest": other_request}


def step_evacuated(directory: Path, saved: dict, ev: Evidence) -> dict:
    base = saved["baseline"]
    wakes = [row for row in ev.views() if row["reason"] == "wake"]
    require(bool(wakes), "missing current native view report")
    view = wakes[-1]
    require([screen["name"] for screen in view["screens"]] == [base["otherOutput"]]
            and view["subjectClass"] == APP and view["subjectOutput"] == base["otherOutput"]
            and view["subjectInView"] is True,
            "the application was not evacuated live to the remaining output")
    no_readiness(ev)
    return {"generation": view["generation"]}


def step_returned(directory: Path, saved: dict, ev: Evidence) -> dict:
    base = saved["baseline"]
    focus, output, remaining = base["focusBoot"], base["output"], base["otherOutput"]
    views = ev.views()
    # Whichever event reports the returned name first must see a native object never seen before.
    listing = [row for row in views if output in [screen["name"] for screen in row["screens"]]]
    require(bool(listing) and {screen["name"]: screen["known"] for screen in listing[0]["screens"]}
            == {output: False, remaining: True},
            "returned output was not reported as a new native output")
    both = sorted((output, remaining))
    require(any(row["source"] == "screens"
                and sorted(screen["name"] for screen in row["screens"]) == both
                for row in views), "output return lacks its own native screens event")
    no_readiness(ev)
    envelope = base["envelope"]
    matches = refusals(ev, focus, envelope["request"], "validate")
    selected = [row for row in matches
                if in_context(row, base, focus, base["activity"], envelope["viewGeneration"])]
    require(bool(selected),
            "same-name output did not refuse the original envelope in a newer context")
    require(not requests(ev, focus), "view return triggered an automatic resend")
    controls = latest(ev.shell("focus-control"))
    require(all(controls.get(boot, {}).get("screen") == output
                for boot in (focus, base["otherBoot"])),
            "consumers did not return to the replacement output")
    other_request = reattached(ev, base, output, saved["lost"]["otherRequest"])
    return {"refusalRevision": selected[0]["packet"]["revision"],
            "generation": selected[0]["packet"]["targetContext"]["generation"],
            "otherRequest": other_request}


def fresh_validation(directory: Path, saved: dict, ev: Evidence, name: str, envelope: dict) -> dict:
    """One explicit re-send of an old handle from the current bar: refused, never refreshed."""
    base = saved["baseline"]
    focus = base["focusBoot"]
    expected = envelope | {"request": envelope["request"] + 1}
    require(inventory_request(directory, name, focus) == expected,
            "fresh validation changed the captured view or handle")
    require([row["request"] for _, row in requests(ev, focus)] == [expected["request"]]
            and not keyboard(ev, focus), "fresh validation was not one explicit request")
    no_readiness(ev)
    matches = refusals(ev, focus, expected["request"], "validate")
    selected = [row for row in matches
                if in_context(row, base, focus, base["activity"], envelope["viewGeneration"])]
    require(bool(selected), "fresh validation lacks the current view context")
    return {"request": expected["request"], "refusalRevision": selected[0]["packet"]["revision"]}


def step_revalidated(directory: Path, saved: dict, ev: Evidence) -> dict:
    return fresh_validation(directory, saved, ev, "revalidated", saved["baseline"]["envelope"])


def step_revalidated_a(directory: Path, saved: dict, ev: Evidence) -> dict:
    return fresh_validation(directory, saved, ev, "revalidated-a", saved["recovered"]["envelope"])


def step_activity_added(directory: Path, saved: dict, ev: Evidence) -> dict:
    base = saved["baseline"]
    require(any(row["source"] == "activities" and row["activities"] == 2
                and row["activityId"] == base["activity"] for row in ev.views()),
            "activity creation lacks its own native activities event")
    no_readiness(ev)
    return {}


def subject(directory: Path, saved: dict, ev: Evidence) -> dict:
    base = saved["baseline"]
    wakes = [row for row in ev.views() if row["reason"] == "wake"]
    require(bool(wakes), "missing current native view report")
    view = wakes[-1]
    screens = [screen for screen in view["screens"] if screen["name"] == base["output"]]
    frame = view["subjectFrame"]
    require(view["subjectClass"] == APP and view["subjectOutput"] == base["output"]
            and view["subjectInView"] is True and view["activityId"] == base["activity"]
            and len(screens) == 1 and isinstance(frame, dict),
            "the application is not visible on the returned output")
    screen = screens[0]
    x, y = frame["x"] + frame["width"] / 2, frame["y"] + frame["height"] / 2
    # Empty desktop beside the app makes the next app click a real activation, not a no-op.
    desktop_x, desktop_y = screen["x"] + screen["width"] - 60, screen["y"] + screen["height"] / 2
    require(screen["x"] <= x < screen["x"] + screen["width"]
            and screen["y"] <= y < screen["y"] + screen["height"]
            and frame["x"] + frame["width"] < desktop_x,
            "no clear desktop point beside the application")
    no_readiness(ev)
    return {"x": x, "y": y, "desktopX": desktop_x, "desktopY": desktop_y}


def step_recovered(directory: Path, saved: dict, ev: Evidence) -> dict:
    base = saved["baseline"]
    focus = base["focusBoot"]
    first = saved["revalidated"]["request"] + 1
    explicit_requests(ev, focus, [("prepare", first), ("validate", first + 1)])
    reestablished(ev, base)
    prepared = ready_reply(ev, focus, first, "prepare")
    validated = ready_reply(ev, focus, first + 1, "validate")
    token = prepared["packet"]["preparation"]["token"]
    require(token.startswith(base["epoch"] + ":") and token != base["envelope"]["token"],
            "recovery reused an invalidated handle")
    require(all(in_context(row, base, focus, base["activity"], -1)
                for row in (prepared, validated)), "recovery left the returned view")
    ready_only(ev, {(focus, first, "prepare"), (focus, first + 1, "validate")})
    envelope = inventory_request(directory, "recovered", focus)
    require(envelope.get("intent") == "validate" and envelope.get("request") == first + 1
            and envelope.get("token") == token and envelope.get("outputName") == base["output"]
            and envelope.get("viewOutputName") == base["output"]
            and envelope.get("activityId") == base["activity"]
            and envelope.get("consumerLease") == base["leases"][focus]
            and type(envelope.get("viewGeneration")) is int,
            "recovered validation envelope does not match its handle")
    return {"prepareRequest": first, "validateRequest": first + 1, "token": token,
            "envelope": envelope}


def step_activity_left(directory: Path, saved: dict, ev: Evidence) -> dict:
    base = saved["baseline"]
    focus = base["focusBoot"]
    envelope = saved["recovered"]["envelope"]
    views = ev.views()
    switched = [row for row in views
                if row["source"] == "current-activity" and row["activityId"] != base["activity"]]
    require(bool(switched) and len({row["activityId"] for row in switched}) == 1,
            "activity switch lacks its own native event")
    other = switched[0]["activityId"]
    require(any(row["prepared"] for row in views),
            "activity switch did not clear a live preparation")
    no_readiness(ev)
    matches = refusals(ev, focus, envelope["request"], "validate")
    selected = [row for row in matches
                if in_context(row, base, focus, other, envelope["viewGeneration"])]
    require(bool(selected), "the old preparation was not refused in the other activity's context")
    require(not requests(ev, focus), "activity switch triggered an automatic resend")
    last = views[-1]
    require(last["subjectClass"] == APP and last["subjectInView"] is False
            and last["activityId"] == other,
            "the original activity's application remained in the new view")
    return {"activity": other, "refusalRevision": selected[0]["packet"]["revision"]}


def step_activity_returned(directory: Path, saved: dict, ev: Evidence) -> dict:
    base = saved["baseline"]
    focus = base["focusBoot"]
    envelope = saved["recovered"]["envelope"]
    views = ev.views()
    require(any(row["source"] == "current-activity" and row["activityId"] == base["activity"]
                for row in views), "activity return lacks its own native event")
    no_readiness(ev)
    matches = refusals(ev, focus, envelope["request"], "validate")
    selected = [row for row in matches
                if in_context(row, base, focus, base["activity"], envelope["viewGeneration"])]
    require(bool(selected),
            "returning to the original activity did not keep the old handle refused")
    require(not requests(ev, focus), "activity return triggered an automatic resend")
    last = views[-1]
    require(last["subjectClass"] == APP and last["subjectInView"] is True
            and last["activityId"] == base["activity"],
            "the application did not return with its activity")
    return {"refusalRevision": selected[0]["packet"]["revision"]}


def followed(ev: Evidence, base: dict, activity: str) -> None:
    """Both bars accepted the switched view before the driver clicks there again.

    A click that raced the shell's own handling of the switch did not open the popup once
    (native run v05); every passing run had both acceptances first.
    """
    for boot in (base["focusBoot"], base["otherBoot"]):
        require(any(row["boot"] == boot and row["packet"]
                    and isinstance(row["packet"].get("targetContext"), dict)
                    and row["packet"]["targetContext"].get("activityId") == activity
                    and row["packet"]["targetContext"].get("consumerLease") == base["leases"][boot]
                    and row["packet"].get("epoch") == base["epoch"]
                    for _, row in ev.shell("observation")),
                "consumers did not follow the activity switch")


def step_activity_left_again(directory: Path, saved: dict, ev: Evidence) -> dict:
    base = saved["baseline"]
    other = saved["activity-left"]["activity"]
    before = [row for _, row in ev.backend_before("focus")]
    last = before[-1] if before else {}
    require(last.get("activeClass") == APP and last.get("rememberedClass") == APP
            and last.get("rememberedAlive") is True and last.get("activityId") == base["activity"],
            "the application was not remembered on its own activity before the switch")
    require(any(row["source"] == "current-activity" and row["activityId"] == other
                for row in ev.views()), "activity switch lacks its own native event")
    after = [row for _, row in ev.backend("focus")]
    current = after[-1] if after else {}
    require(current.get("rememberedClass") == "" and current.get("rememberedAlive") is False
            and current.get("activityId") == other,
            "the switch kept the other activity's application as a candidate")
    followed(ev, base, other)
    no_readiness(ev)
    return {}


def step_popup_b(directory: Path, saved: dict, ev: Evidence) -> dict:
    base = saved["baseline"]
    rows = [row for _, row in ev.backend("focus")]
    last = rows[-1] if rows else {}
    require(last.get("activeAppletPopup") is True and last.get("activeNormal") is False
            and last.get("activePid") == base["shellPid"] and last.get("rememberedClass") == ""
            and last.get("rememberedAlive") is False
            and last.get("activityId") == saved["activity-left"]["activity"],
            "the control's popup is not focused in the other activity")
    no_readiness(ev)
    return {}


def step_wrong_view(directory: Path, saved: dict, ev: Evidence) -> dict:
    base = saved["baseline"]
    focus, other = base["focusBoot"], saved["activity-left"]["activity"]
    request = saved["revalidated-a"]["request"] + 1
    explicit_requests(ev, focus, [("prepare", request)])
    no_readiness(ev)
    matches = refusals(ev, focus, request, "prepare")
    selected = [row for row in matches if in_context(row, base, focus, other, -1)]
    require(bool(selected), "the other activity's preparation lacked its own view context")
    views = ev.views_until()
    require(bool(views) and views[-1]["subjectClass"] == APP and views[-1]["subjectInView"] is False
            and views[-1]["activityId"] == other,
            "the original activity's application was in the prepared view")
    return {"request": request, "refusalRevision": selected[0]["packet"]["revision"]}


def step_activity_returned_again(directory: Path, saved: dict, ev: Evidence) -> dict:
    home = saved["baseline"]["activity"]
    require(any(row["source"] == "current-activity" and row["activityId"] == home
                for row in ev.views()), "activity return lacks its own native event")
    followed(ev, saved["baseline"], home)
    no_readiness(ev)
    return {}


def step_final(directory: Path, saved: dict, ev: Evidence) -> dict:
    base = saved["baseline"]
    focus = base["focusBoot"]
    request = saved["wrong-view"]["request"] + 1
    explicit_requests(ev, focus, [("prepare", request)])
    reestablished(ev, base)
    prepared = ready_reply(ev, focus, request, "prepare")
    token = prepared["packet"]["preparation"]["token"]
    require(token.startswith(base["epoch"] + ":")
            and token not in (base["envelope"]["token"], saved["recovered"]["token"]),
            "recovery reused an invalidated handle")
    require(in_context(prepared, base, focus, base["activity"], -1),
            "recovery left the original view")
    ready_only(ev, {(focus, request, "prepare")})
    return {"request": request, "token": token}


# Step name -> (mark written before its native action, evidence function), in run order.
STEPS = {
    "baseline": ("start", step_baseline),
    "lost": ("disable", step_lost),
    "evacuated": ("evacuated", step_evacuated),
    "returned": ("enable", step_returned),
    "revalidated": ("revalidate", step_revalidated),
    "activity-added": ("activity-add", step_activity_added),
    "subject-a": ("subject-a", subject),
    "recovered": ("recover-a", step_recovered),
    "activity-left": ("switch-b", step_activity_left),
    "activity-returned": ("switch-a", step_activity_returned),
    "revalidated-a": ("revalidate-a", step_revalidated_a),
    "activity-left-again": ("switch-b2", step_activity_left_again),
    "popup-b": ("popup-b", step_popup_b),
    "wrong-view": ("wrong-view", step_wrong_view),
    "activity-returned-again": ("switch-a2", step_activity_returned_again),
    "subject-final": ("subject-final", subject),
    "final": ("recover-final", step_final),
}
ORDER = list(STEPS)


def evaluate(directory: Path, name: str, saved: dict, end: dict | None) -> dict:
    label, function = STEPS[name]
    ev = Evidence(directory, label, end)
    return function(directory, saved, ev) | {"end": ev.stop}


def record_step(directory: Path, name: str) -> dict:
    require(name in STEPS, "unknown view-loss step")
    saved = {previous: load(directory, f"view-{previous}.json")
             for previous in ORDER[:ORDER.index(name)]}
    record = evaluate(directory, name, saved, None)
    with (directory / f"view-{name}.json").open("x") as output:
        json.dump(record, output)
    return record


def chain(rows: list) -> None:
    """Every generation advance in the run is reported once, in order, with a known source."""
    require(bool(rows) and rows[0]["from"] == 0,
            "the native view report does not start at generation 0")
    previous = None
    for row in rows:
        if row["reason"] == "wake":
            require(row["source"] == "wake" and row["from"] == row["generation"],
                    "a wake report changed the context generation")
        else:
            require(row["source"] in SOURCES, "unattributed context advance")
            expected = row["from"] + 1 if 0 <= row["from"] < 2147483646 else -1
            require(row["generation"] == expected, "a context advance skipped a generation")
        if previous is not None:
            require(row["from"] == previous["generation"], "an unreported context advance occurred")
        previous = row


def audit(directory: Path, saved: dict) -> None:
    base = saved["baseline"]
    focus, other = base["focusBoot"], base["otherBoot"]
    start = load(directory, "view-mark-start.json")
    # The provider logs each verdict before it publishes the packet, so reading the shell log
    # first cannot see an acceptance whose verdict is not yet in the backend log.
    shell = complete_lines(directory / "plasmashell.log")
    backend = complete_lines(directory / "kwin.log")
    chain([valid_view(row) for _, row in events(backend, "view")])
    loss = load(directory, "view-mark-disable.json")
    verdicts = [(index, row) for index, row in events(backend, "target")
                if index >= start["kwinLines"]]
    live = lambda row: row["targetAlive"] is True and row["targetClass"] == APP
    exchange = lambda row: (row["revision"], row["consumer"], row["request"], row["intent"])
    # Until the first output change, the original validation may be re-confirmed, nothing else.
    early = [row for index, row in verdicts
             if index < loss["kwinLines"] and row["ready"] is not False]
    require({(row["consumer"], row["request"], row["intent"]) for row in early}
            <= {(focus, base["envelope"]["request"], "validate")} and all(map(live, early)),
            "unexpected native readiness before the view changes")
    # Afterwards, readiness belongs only to the explicit recoveries and only within their own
    # spans: a later re-confirmation of a recovered handle (after an activity switch, say) fails.
    recover_mark, away_mark, final_mark = (
        load(directory, f"view-mark-{label}.json")["kwinLines"]
        for label in ("recover-a", "switch-b", "recover-final"))
    spans = {(focus, saved["recovered"]["prepareRequest"], "prepare"): (recover_mark, away_mark),
             (focus, saved["recovered"]["validateRequest"], "validate"): (recover_mark, away_mark),
             (focus, saved["final"]["request"], "prepare"): (final_mark, len(backend))}
    ready = [(index, row) for index, row in verdicts
             if index >= loss["kwinLines"] and row["ready"] is not False]
    keys = [(row["consumer"], row["request"], row["intent"]) for _, row in ready]
    require(set(keys) == set(spans)
            and all(spans[key][0] <= index < spans[key][1] and live(row)
                    for key, (index, row) in zip(keys, ready)),
            "unexpected native readiness during the view-loss case")
    # Accepted readiness must come from the exact exchange of one of those verdicts, or of an
    # original pre-change re-confirmation, which may be accepted shortly after a mark.
    original = {exchange(row) for index, row in events(backend, "target")
                if index < loss["kwinLines"] and row["ready"] is True and row["consumer"] == focus
                and row["request"] == base["envelope"]["request"] and live(row)}
    bounded = {exchange(row) for _, row in ready} | original
    for index, row in events(shell, "observation"):
        packet = row["packet"]
        preparation = packet.get("preparation") if packet else None
        if (index >= start["shellLines"] and isinstance(preparation, dict)
                and preparation.get("ready") is not False):
            require((packet.get("revision"), row["boot"], packet.get("request"),
                     preparation.get("intent")) in bounded,
                    "accepted readiness lacks its bounded native verdict")
    first = base["envelope"]["request"]
    sent = [row["request"] for index, row in events(shell, "query")
            if index >= start["shellLines"] and row["boot"] == focus]
    require(sent == list(range(first + 1, first + 7)),
            "hidden, repeated or missing guarded-consumer requests")
    require(not [row for _, row in verdicts if row["consumer"] == other],
            "the read-only consumer dispatched a target intent")
    for index, row in events(shell, "observation"):
        packet = row["packet"]
        if index < start["shellLines"] or not packet or row["boot"] not in base["leases"]:
            continue
        require(packet.get("epoch") == base["epoch"],
                "accepted state from another provider lifetime")
        context = packet.get("targetContext")
        lease = base["leases"][row["boot"]]
        require(context is None
                or (isinstance(context, dict) and context.get("consumerLease") == lease),
                "accepted context changed a consumer lease")


def check_view_loss(directory: Path) -> None:
    saved, previous = {}, None
    for name in ORDER:
        record = load(directory, f"view-{name}.json")
        start = load(directory, f"view-mark-{STEPS[name][0]}.json")
        require(isinstance(record, dict) and isinstance(record.get("end"), dict)
                and isinstance(start, dict), f"invalid {name} evidence record")
        if previous is not None:
            require(all(type(start.get(field)) is int and start[field] >= previous[field]
                        for field in ("shellLines", "kwinLines")),
                    "view evidence windows overlap or are out of order")
        require(evaluate(directory, name, saved, record["end"]) == record,
                f"{name} record does not match its raw evidence")
        saved[name] = record
        previous = record["end"]
    audit(directory, saved)


def write_receipt(directory: Path) -> None:
    """The receipt's check list has one source: it is written only after the full check."""
    check_view_loss(directory)
    with (directory / "view-loss-result.json").open("x") as output:
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
            print("PASS: view-loss evidence")
        elif len(arguments) >= 4 and arguments[0] == "value":
            require(arguments[2] in STEPS, "unknown view-loss step")
            value = load(Path(arguments[1]), f"view-{arguments[2]}.json")
            for key in arguments[3:]:
                require(isinstance(value, dict) and key in value, "missing recorded value")
                value = value[key]
            scalar = isinstance(value, (str, int, float)) and not isinstance(value, bool)
            print(value if scalar else json.dumps(value))
        else:
            raise SystemExit("usage: view_loss.py {mark OUT LABEL|step OUT NAME|receipt OUT"
                             "|value OUT NAME KEY...}")
    except (ValueError, OSError) as error:
        raise SystemExit(f"view-loss: {error}") from None


if __name__ == "__main__":
    main()
