#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Hotspot name and password handling in Fusion's network service, on plasma-nm's own settings.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 tests/hotspot_settings_test.py
Requires PySide6 and plasma-nm's QML module. The settings live in a throwaway XDG_CONFIG_HOME;
the test never starts or stops a hotspot. plasma-nm writes its settings file when the process
ends, so every step runs in a child process and the file is read after it exits.
"""

import configparser
import getpass
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent


def child(steps):
    from PySide6.QtCore import Q_ARG, Q_RETURN_ARG, QMetaObject, QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine
    from PySide6.QtTest import QTest

    app = QGuiApplication(sys.argv[:1])
    engine = QQmlEngine()
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(here.parent / "contents/ui/services/Network.qml")))
    network = component.create()
    if network is None:
        raise SystemExit("Network service did not load: " + "; ".join(e.toString() for e in component.errors()))
    QTest.qWait(300)
    results = {
        "name": network.property("hotspotName"),
        "starting": network.property("hotspotStarting"),
        "failed": network.property("hotspotFailedToStart"),
        "configure": [],
    }
    for step in steps:
        if step == "password":
            results["password"] = QMetaObject.invokeMethod(network, "hotspotPassword", Q_RETURN_ARG(str))
        else:
            ok = QMetaObject.invokeMethod(network, "configureHotspot", Q_RETURN_ARG(bool), Q_ARG(str, step[0]), Q_ARG(str, step[1]))
            results["configure"].append(ok)
    results["nameAfter"] = network.property("hotspotName")
    print(json.dumps(results))
    del network, component, engine, app


if len(sys.argv) == 3 and sys.argv[1] == "--child":
    child(json.loads(sys.argv[2]))
    sys.exit(0)

checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


def run(config, steps):
    env = dict(os.environ, XDG_CONFIG_HOME=config)
    out = subprocess.run([sys.executable, __file__, "--child", json.dumps(steps)], env=env, check=True,
                         capture_output=True, text=True, timeout=60).stdout
    return json.loads(out.strip().splitlines()[-1])


def saved(config):
    parser = configparser.RawConfigParser(strict=False)
    parser.optionxform = str
    parser.read(Path(config) / "plasma-nm")
    return dict(parser["General"]) if parser.has_section("General") else {}


with tempfile.TemporaryDirectory(prefix="pf-hotspot-settings-") as control, \
        tempfile.TemporaryDirectory(prefix="pf-hotspot-settings-") as config:
    # Control: reading the password makes plasma-nm generate and save one, so the file check
    # below would see a password generated at load.
    generated = run(control, ["password"])["password"]
    check(len(generated) == 26 and saved(control).get("HotspotPassword") == generated,
          "control: reading the password saves plasma-nm's generated one")

    loaded = run(config, [])
    check("HotspotPassword" not in saved(config), "loading the service saves no generated hotspot password")
    check(loaded["name"] == getpass.getuser() + "-hotspot", "the name is plasma-nm's default")
    check(not loaded["starting"] and not loaded["failed"], "idle until a start request")

    refused = run(config, [["   ", "abcdefgh"], ["Fusion", "short"], ["Fusion", "a" * 64]])
    check(refused["configure"] == [False, False, False], "blank names and passwords outside 8–63 characters are refused")
    check(saved(config) == {}, "refused settings are not written")

    kept = run(config, [["  Fusion test ", ""]])
    check(kept["configure"] == [True] and kept["nameAfter"] == "Fusion test", "an empty password keeps the saved one")
    check(saved(config) == {"HotspotName": "Fusion test"}, "the trimmed name is saved, and no password is generated")

    changed = run(config, [["Fusion test", "abcdefgh1"], "password"])
    check(changed["configure"] == [True] and changed["password"] == "abcdefgh1", "a valid password is accepted and read back")
    check(saved(config).get("HotspotPassword") == "abcdefgh1", "the password is saved where plasma-nm reads it")

print(f"Hotspot settings: {checks} checks, 0 failures")
