#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Capture and qualify P0 keyboard-entry evidence. Never operate a desktop.

The probe panel gets keyboard focus from plasmashell's own shortcut for moving keyboard focus
between panels. A key on its focused control opens the probe popup, and a key in the popup
prepares: first with the controlled app remembered, then after that app has closed. Each step's
window of the raw logs starts at its mark, set before the step's shortcut, and must show:

- the shell's probe panel activated as a dock with the app remembered (or, for the refusal, none),
  and then the probe popup, with no other window activated in between;
- after the popup took keyboard focus, the focus consumer's keyboard preparation, and the provider's
  first native verdict for that request: given before anything else is activated, deciding the
  request's completion, and ready with the app or refused with no target;
- a frame the consumer accepted that carries that completion.

Across the whole run every verdict names the controlled app, alive, or no target: never a shell
surface. The receipt is written only after both steps are recomputed from the raw logs.
"""

import json
import sys
from pathlib import Path

if __package__:
    from .mixed_lifetime import complete_lines, events, require
else:
    from mixed_lifetime import complete_lines, events, require

CHECKS = ["roundtrip-native", "panel-keyboard-entry", "safe-refusal"]
APP = "pf.focus.alpha"
# The app each step expects the provider to remember; the refusal step expects none.
STEPS = {"entry": APP, "refusal": ""}
SPACE = 32


def line_counts(directory: Path) -> dict:
    return {"shellLines": len(complete_lines(directory / "plasmashell.log")),
            "kwinLines": len(complete_lines(directory / "kwin.log"))}


def mark(directory: Path, label: str) -> dict:
    require(label in STEPS, "unknown keyboard-entry mark")
    value = {"schema": 1} | line_counts(directory)
    with (directory / f"keyboard-entry-mark-{label}.json").open("x") as output:
        json.dump(value, output)
    return value


def window(directory: Path, label: str, end: dict) -> dict:
    value = json.loads((directory / f"keyboard-entry-mark-{label}.json").read_text())
    require(isinstance(value, dict) and set(value) == {"schema", "shellLines", "kwinLines"}
            and value["schema"] == 1, "invalid keyboard-entry mark")
    for field in ("shellLines", "kwinLines"):
        require(type(value[field]) is int and 0 <= value[field] <= end[field],
                "invalid keyboard-entry evidence window")
    return value


def remembers(row: dict, app: str) -> bool:
    if app:
        return row["rememberedClass"] == app and row["rememberedAlive"] is True
    return row["rememberedClass"] == "" and row["rememberedAlive"] is False


def decides(row: dict, request: int) -> bool:
    """The verdict at a preparation's first handling decides its completion, which later re-checks
    of the same request keep; an early refusal carries none."""
    completion = row["completion"]
    return (isinstance(completion, dict) and completion["request"] == request
            and completion["intent"] == "prepare" and completion["accepted"] is row["ready"])


def evaluate(directory: Path, label: str, start: dict, end: dict, shell_pid: int,
             boot: str) -> None:
    app = STEPS[label]
    kwin = complete_lines(directory / "kwin.log")[start["kwinLines"]:end["kwinLines"]]
    shell = complete_lines(directory / "plasmashell.log")[start["shellLines"]:end["shellLines"]]
    activations = [(index, row) for index, row in events(kwin, "focus")
                   if row["event"] == "activation"]

    def surface(row: dict) -> bool:
        return row["activePid"] == shell_pid and row["activeNormal"] is False

    docks = [position for position, (_, row) in enumerate(activations)
             if surface(row) and row["activeDock"] is True and row["activeAppletPopup"] is False]
    require(bool(docks), f"{label}: the probe panel never had keyboard focus")
    dock = docks[0]
    require(remembers(activations[dock][1], app),
            f"{label}: the panel's activation did not keep the expected app")
    require(dock + 1 < len(activations) and surface(activations[dock + 1][1])
            and activations[dock + 1][1]["activeAppletPopup"] is True,
            f"{label}: the popup did not open right after the panel")
    opened, popup = activations[dock + 1]
    require(remembers(popup, app), f"{label}: the popup's activation did not keep the expected app")
    # That popup is the active window until the next activation.
    closed = activations[dock + 2][0] if dock + 2 < len(activations) else len(kwin)
    focused = [index for index, row in events(shell, "popup-focus") if row["boot"] == boot]
    require(bool(focused), f"{label}: the popup never took keyboard focus")
    keys = [row for index, row in events(shell, "keyboard-query")
            if index > focused[0] and row["boot"] == boot and row["key"] == SPACE
            and row["activeFocus"] is True and row["intent"] == "prepare"]
    require(len(keys) == 1, f"{label}: expected one keyboard preparation after the popup's focus")
    request = keys[0]["request"]
    verdicts = [(index, row) for index, row in events(kwin, "target")
                if row["consumer"] == boot and row["request"] == request]
    require(bool(verdicts) and verdicts[0][1]["intent"] == "prepare",
            f"{label}: no native verdict for the keyboard preparation")
    index, first = verdicts[0]
    require(opened < index < closed,
            f"{label}: the keyboard preparation was not answered in the popup the panel opened")
    require(decides(first, request),
            f"{label}: the first verdict did not decide the preparation's completion")
    if app:
        require(first["ready"] is True and first["targetAlive"] is True
                and first["targetClass"] == app,
                f"{label}: the keyboard preparation did not prepare the remembered app")
    else:
        require(first["ready"] is False and first["targetAlive"] is False
                and first["targetClass"] == "" and bool(first["reason"]),
                f"{label}: the keyboard preparation was not refused with no target")
    # Every frame for the request carries the decided completion, unlike its re-checked preparation.
    accepted = [row for _, row in events(shell, "observation")
                if row["boot"] == boot and row["phase"] == "online"
                and row["packet"]["request"] == request
                and isinstance(row["packet"].get("completion"), dict)]
    require(bool(accepted) and accepted[0]["packet"]["completion"] == first["completion"],
            f"{label}: the consumer did not accept the provider's answer")


def never_a_shell_target(directory: Path) -> None:
    for _, row in events(complete_lines(directory / "kwin.log"), "target"):
        alive = row["targetAlive"] is True and row["targetClass"] == APP
        none = row["targetAlive"] is False and row["targetClass"] == ""
        require(alive or none, "a verdict named a target other than the controlled app")


def check_keyboard_entry(directory: Path) -> None:
    end = line_counts(directory)
    shell_pid = int((directory / "focus-shell-pid.txt").read_text())
    boot = (directory / "focus-control.txt").read_text().split()[2]
    entry, refusal = (window(directory, label, end) for label in STEPS)
    require(all(entry[field] <= refusal[field] for field in entry if field != "schema"),
            "keyboard-entry steps out of order")
    evaluate(directory, "entry", entry, refusal, shell_pid, boot)
    evaluate(directory, "refusal", refusal, end, shell_pid, boot)
    never_a_shell_target(directory)


def write_receipt(directory: Path) -> None:
    check_keyboard_entry(directory)
    with (directory / "keyboard-entry-result.json").open("x") as output:
        json.dump({"schema": 1, "passed": True, "checks": CHECKS}, output)


def main() -> None:
    arguments = sys.argv[1:]
    try:
        if len(arguments) == 3 and arguments[0] == "mark":
            mark(Path(arguments[1]), arguments[2])
        elif len(arguments) == 2 and arguments[0] == "receipt":
            write_receipt(Path(arguments[1]))
        else:
            raise SystemExit("usage: keyboard_entry.py mark DIR LABEL | receipt DIR")
    except (ValueError, OSError, KeyError, TypeError) as error:
        raise SystemExit(f"FAIL: {error}") from None


if __name__ == "__main__":
    main()
