#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Native stream-volume/mute/routing checks on a caller-prepared disposable Pulse server."""

import os
from pathlib import Path
import sys

from PySide6.QtCore import Q_ARG, QMetaObject, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

if not os.environ.get("PULSE_SERVER") or os.environ.get("PF_AUDIO_TEST") != "1":
    raise SystemExit("Use an explicit disposable Pulse server and PF_AUDIO_TEST=1")
app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
path = Path(__file__).resolve().parent.parent / "contents/ui/services/Audio.qml"
component = QQmlComponent(engine, QUrl.fromLocalFile(str(path)))
audio = component.create()
assert audio is not None
QTest.qWait(500)


def model(name):
    value = audio.property(name)
    return value.toQObject() if hasattr(value, "toQObject") else value


def rows(value):
    roles = {bytes(v).decode(): k for k, v in value.roleNames().items()}
    return [{name: value.data(value.index(row, 0), role) for name, role in roles.items()
             if name in {"PulseObject", "Index", "Name", "Description", "DeviceIndex"}}
            for row in range(value.rowCount())]


playbacks = rows(model("playbackModel"))
assert playbacks, "prepare a disposable playback stream first"
stream = playbacks[0]["PulseObject"]
QMetaObject.invokeMethod(audio, "setStreamVolume", Q_ARG("QVariant", stream), Q_ARG(float, 0.42))
QTest.qWait(150)
assert abs(stream.property("volume") / audio.property("normal") - .42) < .01
QMetaObject.invokeMethod(audio, "toggleStreamMute", Q_ARG("QVariant", stream))
QTest.qWait(100)
assert stream.property("muted")
QMetaObject.invokeMethod(audio, "toggleStreamMute", Q_ARG("QVariant", stream))
QTest.qWait(100)
assert not stream.property("muted")
devices = rows(model("sinkModel"))
assert len(devices) > 1, "prepare two disposable output devices"
target = next(d for d in devices if d["Index"] != stream.property("deviceIndex"))
QMetaObject.invokeMethod(audio, "routeStream", Q_ARG("QVariant", stream), Q_ARG(int, target["Index"]))
QTest.qWait(150)
assert stream.property("deviceIndex") == target["Index"]
assert rows(model("recordingModel")), "prepare a disposable capture stream first"
print("Application audio: 5 checks, 0 failures")
