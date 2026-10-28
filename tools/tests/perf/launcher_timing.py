#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Card-aware output timing, not surface-specific presentation feedback."""
import json
import math

CONTRACT = "applet-popup/output-composition-after-map/v1"


def window_events(text):
    """Decode winmon's JSON independently of caption delimiters and legacy tags."""
    events = []
    seen = set()
    prefix = 'string "PFPERF window '
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith(prefix):
            continue
        if not line.endswith('"'):
            raise ValueError("unterminated window record")
        event = json.loads(line[len(prefix):-1])
        if not isinstance(event, dict) or type(event.get("schema")) is not int or event["schema"] != 1:
            raise ValueError("unsupported window-record schema")
        if (event.get("event") not in ("added", "removed")
                or not isinstance(event.get("id"), str) or not event["id"]
                or not isinstance(event.get("resourceClass"), str)
                or type(event.get("windowType")) is not int
                or type(event.get("appletPopup")) is not bool):
            raise ValueError("invalid window identity")
        for key in ("time_ms", "width", "height"):
            if type(event.get(key)) not in (int, float) or not math.isfinite(event[key]):
                raise ValueError("invalid window timestamp or size")
        signature = json.dumps(event, sort_keys=True)
        if signature not in seen:
            seen.add(signature)
            events.append(event)
    return events


def launcher_timings(marks, frames, text):
    """Require one AppletPopup per opening; never fall back to the normal dimmer."""
    try:
        events = window_events(text)
        record_error = None
    except (ValueError, TypeError) as error:
        events, record_error = [], str(error)
    results = []
    for i in range(1, 4):
        result = {"opening": i, "window_id": None, "mapped_ms": None,
                  "first_frame_ms": None, "settled_ms": None, "error": record_error}
        results.append(result)
        mark = marks.get(f"launcher{i}")
        if record_error or not mark:
            result["error"] = record_error or "missing input marker"
            continue
        start = mark["epoch"]
        end = min(start + 2, marks.get(f"launcher{i}-close", {}).get("epoch", start + 2))
        candidates = [event for event in events if event["event"] == "added"
                      and start <= event["time_ms"] / 1000 < end
                      and event["resourceClass"] in ("plasmashell", "org.kde.plasmashell")
                      and event["appletPopup"] and event["windowType"] == 18
                      and event["width"] > 0 and event["height"] > 0]
        if len(candidates) != 1:
            result["error"] = f"expected one launcher card, found {len(candidates)}"
            continue
        event = candidates[0]
        result["window_id"] = event["id"]
        result["mapped_ms"] = event["time_ms"] - start * 1000
        mapped = mark["mono"] + result["mapped_ms"] / 1000
        # A frame already rendering when the card mapped cannot establish its visibility.
        # KWin's output timestamps remain a proxy, especially on a virtual output.
        stamps = [frame[1] / 1e9 for frame in frames
                  if mapped <= frame[2] / 1e9 and mapped <= frame[1] / 1e9 <= mark["mono"] + 1.4]
        if not stamps:
            result["error"] = "no output composition after launcher mapping"
            continue
        result["first_frame_ms"] = (stamps[0] - mark["mono"]) * 1000
        for stamp, following in zip(stamps, stamps[1:] + [float("inf")]):
            if following - stamp > 0.1:
                result["settled_ms"] = (stamp - mark["mono"]) * 1000
                break
    return results
