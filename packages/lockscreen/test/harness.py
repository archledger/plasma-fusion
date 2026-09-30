#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offscreen render check for the Plasma Fusion lock screen (no greeter, no PAM).

Loads contents/lockscreen/LockScreen.qml the way kscreenlocker_greet does (same context
properties, wallpaper item re-parented under the root) with a mock authenticator, drives the
states and saves one PNG per scenario. Run it on a private bus with fonts from the repository:

  QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 harness.py OUTDIR [scenario...]

Scenarios: idle, prompt, messages, fperror, focus, nopassword. Environment: PF_LOCALE (default en_GB),
PF_SIZE (default 1440x900), PF_WALLPAPER (PNG; default: the Lock board wallpaper).
"""
import atexit
import os
import shutil
import subprocess
import sys
import tempfile

from PySide6.QtCore import QObject, QTimer, QUrl, Slot, QLocale, QSize, Qt, QByteArray
from PySide6.QtGui import QGuiApplication, QFontDatabase, QImage, QPainter, QIcon
from PySide6.QtQml import QQmlComponent, QQmlPropertyMap, QQmlProperty
from PySide6.QtQuick import QQuickView, QQuickItem
from PySide6.QtSvg import QSvgRenderer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC_PKG = os.path.join(HERE, "..", "org.plasmafusion.lockshell", "contents", "lockscreen")


def staged_package():
    """The package as tools/build.d/90-lockscreen.sh installs it: the source files plus a copy of
    packages/common/FusionMetrics.qml, in a temporary folder removed at exit."""
    tmp = tempfile.mkdtemp(prefix="pf-lockshell-")
    atexit.register(shutil.rmtree, tmp, True)
    pkg = os.path.join(tmp, "lockscreen")
    shutil.copytree(SRC_PKG, pkg)
    shutil.copy(os.path.join(ROOT, "packages", "common", "FusionMetrics.qml"), pkg)
    return pkg


PKG = staged_package()

# The Lock board's wallpaper (design/boards/Lock.dc.html), used when PF_WALLPAPER is unset.
BOARD_WALLPAPER = """<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="900" viewBox="0 0 1440 900">
<rect width="1440" height="900" fill="#141a2e"/>
<rect y="180" width="1440" height="160" fill="#181f3a"/>
<rect y="340" width="1440" height="220" fill="#1c2446"/>
<circle cx="1010" cy="360" r="212" fill="none" stroke="#f2a65a" stroke-opacity="0.18" stroke-width="2"/>
<circle cx="1010" cy="360" r="150" fill="#f2a65a"/>
<path d="M0 560 L180 430 L330 505 L520 350 L700 485 L860 405 L1060 520 L1240 385 L1440 470 L1440 900 L0 900 Z" fill="#253058"/>
<path d="M0 650 L220 545 L420 620 L640 505 L880 612 L1100 540 L1300 622 L1440 580 L1440 900 L0 900 Z" fill="#2e3d73"/>
<path d="M0 760 L260 662 L520 732 L780 642 L1040 722 L1280 662 L1440 702 L1440 900 L0 900 Z" fill="#3b56a0"/>
<path d="M0 846 L300 786 L600 834 L900 774 L1200 824 L1440 792 L1440 900 L0 900 Z" fill="#5a7fd6"/>
</svg>"""


def fmt(text, args):
    for i, a in enumerate(args):
        text = text.replace("%" + str(i + 1), str(a))
    return text


class I18n(QObject):
    """The KLocalizedContext functions the lock screen calls (English only)."""

    @Slot(str, result=str)
    @Slot(str, "QVariant", result=str)
    @Slot(str, "QVariant", "QVariant", result=str)
    def i18n(self, text, *args):
        return fmt(text, args)

    @Slot(str, str, result=str)
    @Slot(str, str, "QVariant", result=str)
    @Slot(str, str, "QVariant", "QVariant", result=str)
    def i18nc(self, ctx, text, *args):
        return fmt(text, args)

    @Slot(str, str, result=str)
    @Slot(str, str, "QVariant", result=str)
    @Slot(str, str, "QVariant", "QVariant", result=str)
    def i18nd(self, domain, text, *args):
        return fmt(text, args)

    @Slot(str, str, str, result=str)
    @Slot(str, str, str, "QVariant", result=str)
    def i18ndc(self, domain, ctx, text, *args):
        return fmt(text, args)

    @Slot(str, str, str, "QVariant", result=str)
    @Slot(str, str, str, "QVariant", "QVariant", result=str)
    def i18ndp(self, domain, singular, plural, n, *args):
        return fmt(singular if int(n) == 1 else plural, (n,) + args)


def wallpaper_image(size):
    path = os.environ.get("PF_WALLPAPER")
    if path:
        return QImage(path).scaled(size, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
    img = QImage(size, QImage.Format_ARGB32_Premultiplied)
    painter = QPainter(img)
    QSvgRenderer(QByteArray(BOARD_WALLPAPER.encode())).render(painter)
    painter.end()
    return img


def main():
    out = os.path.abspath(sys.argv[1])
    scenarios = sys.argv[2:] or ["idle", "prompt", "messages", "nopassword"]
    os.makedirs(out, exist_ok=True)
    if len(scenarios) > 1:
        # One process per scenario: every view gets a fresh engine and settings.
        for scenario in scenarios:
            subprocess.run([sys.executable, os.path.abspath(__file__), out, scenario], check=False)
        return
    w, h = (int(v) for v in os.environ.get("PF_SIZE", "1440x900").split("x"))

    # The repository fonts through fontconfig, as they are installed for the session
    # (variable fonts resolve their weights through fontconfig's named instances).
    conf = os.path.join(out, "fonts.conf")
    with open(conf, "w") as f:
        f.write('<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n<fontconfig>\n'
                '  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>\n'
                '  <dir>%s</dir>\n  <cachedir>%s</cachedir>\n</fontconfig>\n'
                % (os.path.join(ROOT, "fonts"), os.path.join(out, "fontcache")))
    os.environ["FONTCONFIG_FILE"] = conf

    QLocale.setDefault(QLocale(os.environ.get("PF_LOCALE", "en_GB")))
    app = QGuiApplication(sys.argv[:1])
    families = QFontDatabase.families()
    for family in ("Manrope", "Space Grotesk"):
        if family not in families:
            print("font family missing:", family)
    if os.environ.get("PF_ICON_DIR"):
        QIcon.setThemeSearchPaths([os.environ["PF_ICON_DIR"]] + QIcon.themeSearchPaths())
    QIcon.setThemeName(os.environ.get("PF_ICON_THEME", "breeze-dark"))

    wp_path = os.path.join(out, "wallpaper.png")
    wallpaper_image(QSize(w, h)).save(wp_path)

    for scenario in scenarios:
        render(app, out, scenario, w, h, wp_path)


def render(app, out, scenario, w, h, wp_path):
    view = QQuickView()
    view.setResizeMode(QQuickView.SizeRootObjectToView)
    engine = view.engine()
    engine.addImportPath(os.path.join(HERE, "imports"))
    ctx = engine.rootContext()
    i18n = I18n()
    ctx.setContextObject(i18n)

    auth_comp = QQmlComponent(engine, QUrl.fromLocalFile(os.path.join(HERE, "MockAuthenticator.qml")))
    auth = auth_comp.create()
    if scenario == "nopassword":
        auth.setProperty("hadPrompt", False)
    config = QQmlPropertyMap()
    config.insert("alwaysShowClock", True)
    config.insert("hideClockWhenIdle", False)
    config.insert("showMediaControls", True)
    config.insert("showNotifications", os.environ.get("PF_NOTIFICATIONS", "1") != "0")
    config.insert("showNotificationSummaries", False)

    wp_comp = QQmlComponent(engine)
    wp_comp.setData(("import QtQuick\nImage { source: '%s'; fillMode: Image.PreserveAspectCrop }"
                     % QUrl.fromLocalFile(wp_path).toString()).encode(), QUrl())
    wallpaper = wp_comp.create()

    ctx.setContextProperty("authenticator", auth)
    ctx.setContextProperty("kscreenlocker_userName", os.environ.get("PF_USER", "test"))
    ctx.setContextProperty("kscreenlocker_userImage", os.environ.get("PF_USER_IMAGE", ""))
    ctx.setContextProperty("config", config)
    ctx.setContextProperty("org_kde_plasma_screenlocker_greeter_interfaceVersion", 2)
    ctx.setContextProperty("org_kde_plasma_screenlocker_greeter_view", view)
    ctx.setContextProperty("wallpaper", wallpaper)

    view.resize(w, h)
    view.setSource(QUrl.fromLocalFile(os.path.join(PKG, "LockScreen.qml")))
    for e in view.errors():
        print("QML ERROR:", e.toString())
    root = view.rootObject()
    if root is None:
        print("no root object for", scenario)
        return
    wallpaper.setParentItem(root)
    wallpaper.setZ(-1000)
    wallpaper.setWidth(w)
    wallpaper.setHeight(h)
    view.show()
    root.setProperty("viewVisible", True)

    lock_root = root.findChild(QQuickItem, "lockScreenRoot")
    main_block = root.findChild(QQuickItem, "mainBlock")

    def step_prompt():
        lock_root.setProperty("uiVisible", True)
        if scenario == "messages":
            main_block.setProperty("capsLockOn", True)
            # pam_irlume reports progress with pam_info("irlume: <action>"); errors arrive the same way.
            auth.setProperty("infoMessage", "irlume: look directly at the camera")
            QTimer.singleShot(50, lambda: auth.setProperty("errorMessage", "irlume: face not recognised, type your password"))
            # pam_fprintd's instruction arrives as a noninteractive info message.
            QTimer.singleShot(100, lambda: auth.setProperty("fingerprintInfo", "Place your finger on Synaptics Sensors"))
        if scenario == "fperror":
            # pam_fprintd's instruction, then a failed match (shown in place of the hint for a moment).
            auth.setProperty("fingerprintInfo", "Place your finger on Synaptics Sensors")
            QTimer.singleShot(2500, lambda: auth.setProperty("fingerprintError", "Failed to match fingerprint"))
        if scenario == "nopassword":
            auth.succeeded.emit()
        pw = root.findChild(QQuickItem, "passwordBox")
        if scenario == "focus":
            # Keyboard focus on the unlock button (as after Tab): the focus ring.
            btn = root.findChild(QQuickItem, "unlockButton")
            if btn is not None:
                QTimer.singleShot(600, lambda: btn.forceActiveFocus(Qt.TabFocusReason))
        if scenario in ("prompt", "messages") and pw is not None:
            pw.setProperty("text", "secretpw")
            pw.forceActiveFocus()

    def grab():
        img = view.grabWindow()
        path = os.path.join(out, scenario + ".png")
        img.save(path)
        bd = root.findChild(QQuickItem, "backdrop")
        print("saved", path, img.width(), "x", img.height(),
              "startAuthenticating calls:", auth.property("startCount"),
              "wallpaper brightness: %.2f" % (bd.property("brightness") if bd else -1))
        view.close()
        app.quit()

    if scenario != "idle":
        QTimer.singleShot(1200, step_prompt)
    QTimer.singleShot(4200, grab)
    app.exec()


if __name__ == "__main__":
    main()
