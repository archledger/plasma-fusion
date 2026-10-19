#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""A window rule's regular expression as the tablet policy matches it (RuleRegex.qml) against KWin.

  QT_QPA_PLATFORM=offscreen python3 packages/kwin/tests/tablet_regex_test.py

KWin matches a rule's window class with QRegularExpression(wmclass).match(class).hasMatch() (Rules::
matchWMClass, 6.7.5 and 6.8.0). RuleRegex.matches() must give the same answer, or undefined (taken
as applying) where it cannot read the pattern:
1. PCRE syntax JavaScript reads otherwise or not at all: \\A and \\z, POSIX classes, {,n}, \\p{..},
   \\x{..}, \\Q..\\E, ASCII-only \\w and \\s, $ before a final newline, leading (?i) and (?m);
2. patterns it cannot read: lookbehind, possessive quantifiers, (?s), parentheses that do not pair
   up on their own;
3. 6000 random patterns of PCRE and JavaScript syntax over 11 classes (a fixed seed): never an
   answer that differs from KWin's.
Needs PySide6 (Qt Quick, offscreen).
"""
import random
import sys
from pathlib import Path

from PySide6.QtCore import Q_ARG, Q_RETURN_ARG, QMetaObject, QRegularExpression, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine

ROOT = Path(__file__).resolve().parents[3]
QML = ROOT / "packages/kwin/scripts/plasmafusion-tablet/contents/ui/RuleRegex.qml"
checks = 0
failures = []


def check(ok, message):
    global checks
    checks += 1
    print(("PASS " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)


app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
unit = QQmlComponent(engine, QUrl.fromLocalFile(str(QML)))
regex = unit.create()
if regex is None:
    print("FAIL RuleRegex.qml: " + "; ".join(e.toString() for e in unit.errors()))
    sys.exit(1)


def ours(pattern, text):
    return QMetaObject.invokeMethod(regex, "matches", Q_RETURN_ARG("QVariant"), Q_ARG(str, pattern), Q_ARG(str, text))


def kwin(pattern, text):
    r = QRegularExpression(pattern)
    return r.isValid() and r.match(text).hasMatch()


CLASSES = ["org.kde.kcalc", "org.kde.kwrite", "kcalc", "org.kde.ark", "kcalc org.kde.kcalc", "Qml Runtime",
           "steam_app_123", "a.b", "", "ark\n", "ÉCALC"]

# 1. Read as KWin reads them.
for pattern in [r"(?:\A|\.)ark\z", r"\Aorg\.kde\.kcalc", r"[[:alpha:]]+\.kde", r"x{,3}kcalc", r"\p{Lu}", r"\x{6b}calc",
                r"\Qorg.kde\E", r"\Qa.b", r"^\w+$", r"^a\sb$", r"ark$", r"(?i)KCALC", r"(?m)^kcalc$", r"[]a]", r"org/kde",
                r"(k)\1", r"", r"[^]", r"^org\.kde\.k(calc|write)$", r"steam_app_\d+", r"kcalc org"]:
    got = [ours(pattern, c) for c in CLASSES]
    want = [kwin(pattern, c) for c in CLASSES]
    check(got == want, f"{pattern!r}: {''.join('t' if g else 'f' for g in got)} as KWin")

# 2. Not read: taken as applying by Rules.js.
for pattern in [r"(?<=\.)kcalc", r"(?<!x)kcalc", r"a++", r"(?>org)", r"(?s)a.b", r"(?x) k calc", r"a(?i)b",
                r"a+)|(?=\A", r"kcalc\\" + "\\"]:
    got = [ours(pattern, c) for c in CLASSES]
    check(all(g is None for g in got), f"{pattern!r}: not read ({set(map(repr, got))})")

# 3. Random patterns: the same answer as KWin's wherever there is one.
TOKENS = ["o", "r", "g", "k", "d", "e", "c", "a", "l", "w", "1", "-", "_", " ", ".", "^", "$", "|", "(", ")", "*", "+", "?",
          "{2}", "{,2}", "\\.", "\\d", "\\w", "\\s", "\\b", "\\A", "\\z", "\\Z", "[a-k]", "[^.o]", "[[:alpha:]]", "(?=",
          "(?!", "(?:", "\\Q", "\\E", "\\p{L}", "\\x{6b}", "(?i)"]
rng = random.Random(11)
answered = differ = 0
first = None
for _ in range(6000):
    pattern = "".join(rng.choice(TOKENS) for _ in range(rng.randint(1, 6)))
    for c in CLASSES:
        got = ours(pattern, c)
        if got is None:
            continue
        answered += 1
        if got != kwin(pattern, c):
            differ += 1
            first = first or (pattern, c, got)
check(answered > 20000 and differ == 0,
      f"random patterns: {answered} answers, {differ} differ from KWin's" + (f" (first {first!r})" if first else ""))

print(f"Tablet rule regex: {checks} checks, {len(failures)} failures")
sys.exit(1 if failures else 0)
