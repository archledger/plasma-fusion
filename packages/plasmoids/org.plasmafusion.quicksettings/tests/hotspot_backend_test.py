#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Read-only native hotspot capability check on an owned VM with hwsim radios."""

import os
from pathlib import Path
import sys

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

if os.environ.get("PF_HOTSPOT_TEST") != "1":
    raise SystemExit("Use PF_HOTSPOT_TEST=1 on the owned virtual-radio test VM")
app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
component = QQmlComponent(engine, QUrl.fromLocalFile(str(Path(__file__).resolve().parent.parent / "contents/ui/services/Network.qml")))
network = component.create()
assert network is not None
QTest.qWait(500)
assert network.property("wifiDevice") and network.property("wifiEnabled"), "prepare managed hwsim Wi-Fi first"
assert network.property("hotspotSupported"), "native hotspot capability missing"
assert not network.property("hotspotActive"), "a fresh virtual-radio fixture should not have an active hotspot"
print("Hotspot capabilities: 2 checks, 0 failures")
