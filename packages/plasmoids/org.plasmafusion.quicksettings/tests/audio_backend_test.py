#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise native input controls on an isolated Pulse server or owned test VM.

The caller must provide PULSE_SERVER and a disposable source named pf_test_input.
"""

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
if audio is None:
    raise SystemExit("Audio service did not load")
QTest.qWait(500)
assert audio.property("inputAvailable"), "native microphone/input control missing"
assert audio.property("inputName") == "pf_test_input", "refusing a non-test source"
QMetaObject.invokeMethod(audio, "setInputVolume", Q_ARG(float, 0.37))
QTest.qWait(100)
assert abs(audio.property("inputVolume") - 0.37) < 0.01, "input volume did not reach native source"
QMetaObject.invokeMethod(audio, "setInputVolume", Q_ARG(float, -1.0))
QTest.qWait(100)
assert audio.property("inputVolume") == 0 and audio.property("inputMuted"), "zero volume did not mute input"
QMetaObject.invokeMethod(audio, "setInputVolume", Q_ARG(float, 3.0))
QTest.qWait(100)
assert abs(audio.property("inputVolume") - 1) < 0.01 and not audio.property("inputMuted"), "input volume not clamped/unmuted"
QMetaObject.invokeMethod(audio, "toggleInputMute")
QTest.qWait(100)
assert audio.property("inputMuted"), "microphone mute did not reach native source"
QMetaObject.invokeMethod(audio, "toggleInputMute")
QTest.qWait(100)
assert not audio.property("inputMuted"), "microphone unmute did not reach native source"
print("Audio input: 6 checks, 0 failures")
