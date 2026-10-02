#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check which fonts draw non-Latin text set in Manrope and Space Grotesk (GAPS G28).

    check_fallback.py [--render OUT.png]

Runs with the fontconfig of the current environment (point XDG_CONFIG_HOME, XDG_DATA_HOME and
XDG_CACHE_HOME at a sandbox that holds the Fusion fonts and 60-plasma-fusion-fallback.conf).
For each sample it lists `fc-match -s FAMILY:lang=L` up to the first font that covers the language,
and the fonts Qt actually draws the sample with (QTextLayout glyph runs, offscreen). A sample passes
when every glyph run is the Fusion family itself or a Noto family. --render also writes a picture of
the samples drawn by QML Text items (Manrope), for the evidence.
"""
import os
import subprocess
import sys

os.environ["QT_QPA_PLATFORM"] = "offscreen"
from PySide6.QtCore import QRectF, Qt  # noqa: E402
from PySide6.QtGui import QColor, QFont, QGuiApplication, QImage, QPainter, QTextLayout  # noqa: E402

SAMPLES = [
    ("ru", "Доброе утро, Сергей"),
    ("el", "Καλημέρα κόσμε"),
    ("vi", "Chào buổi sáng, Việt Nam"),
    ("ar", "صباح الخير يا عالم"),
    ("he", "בוקר טוב עולם"),
    ("hi", "सुप्रभात दुनिया"),
    ("zh-cn", "早上好，世界"),
    ("ja", "おはようございます世界"),
    ("ko", "좋은 아침입니다"),
]


def fc_first_covering(family, lang):
    out = subprocess.run(["fc-match", "-s", f"{family}:lang={lang}", "family", "lang"],
                         capture_output=True, text=True, check=True).stdout.splitlines()
    chain = []
    for line in out:
        fam, _, langs = line.partition(":")
        fam = fam.split(",")[0]
        chain.append(fam)
        if lang in langs.replace("lang=", "").split("|"):
            return fam, chain
    return None, chain


def qt_runs(family, text):
    layout = QTextLayout(text, QFont(family, 12))
    layout.beginLayout()
    line = layout.createLine()
    line.setLineWidth(10000)
    layout.endLayout()
    fams = []
    for run in layout.glyphRuns():
        f = run.rawFont().familyName()
        if f not in fams:
            fams.append(f)
    return fams


def main():
    app = QGuiApplication(sys.argv[:1])  # noqa: F841
    failures = 0
    rows = []
    for family in ("Manrope", "Space Grotesk"):
        for lang, text in SAMPLES:
            first, chain = fc_first_covering(family, lang)
            runs = qt_runs(family, text)
            ok = all(r == family or r.startswith("Noto ") or (family == "Space Grotesk" and r == "Manrope")
                     for r in runs)
            ok = ok and first is not None and (first == family or first.startswith("Noto ")
                                               or (family == "Space Grotesk" and first == "Manrope"))
            failures += 0 if ok else 1
            rows.append((family, lang, first, " > ".join(chain[:3]), ", ".join(runs), "pass" if ok else "FAIL"))
    print("| Family | lang | First font covering it (fc-match -s) | Chain start | Qt draws it with | Result |")
    print("|---|---|---|---|---|---|")
    for r in rows:
        print("| %s | %s | %s | %s | %s | %s |" % r)
    if "--render" in sys.argv:
        out = sys.argv[sys.argv.index("--render") + 1]
        img = QImage(900, 40 + 44 * len(SAMPLES), QImage.Format_ARGB32)
        img.fill(QColor("#1b2031"))
        p = QPainter(img)
        p.setRenderHint(QPainter.TextAntialiasing)
        p.setPen(QColor("#e8ebf4"))
        for i, (lang, text) in enumerate(SAMPLES):
            p.setFont(QFont("Manrope", 11))
            p.drawText(QRectF(16, 16 + 44 * i, 120, 40), Qt.AlignVCenter, lang)
            p.setFont(QFont("Manrope", 16))
            p.drawText(QRectF(100, 16 + 44 * i, 380, 40), Qt.AlignVCenter, text)
            p.setFont(QFont("Space Grotesk", 16))
            p.drawText(QRectF(500, 16 + 44 * i, 380, 40), Qt.AlignVCenter, text)
        p.end()
        img.save(out)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
