# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Read the actual probe QML handlers for the isolated Node.js tests."""

import re
from pathlib import Path


def qml_handler(name: str, filename: str = "consumer.qml") -> str:
    source = Path(__file__).with_name(filename).read_text()
    start = source.index(f"function {name}(")
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    # QML's signature annotations are not JavaScript; keep the actual decision body.
    header = re.sub(r":\s*(?:int|bool|var|string|real|void)\b", "", source[start:opening])
    return header + source[opening:end]
