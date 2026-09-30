#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offscreen render check for the Plasma Fusion lock screen (no greeter, no PAM).

Loads contents/lockscreen/LockScreen.qml the way kscreenlocker_greet does (same context
properties, wallpaper item re-parented under the root) with a mock authenticator, drives the
states and saves one PNG per scenario. Run it on a private bus with fonts from the repository:

  test/run.sh OUTDIR [scenario...]   (a private bus without activation, mock services, no display)

Scenarios: idle, prompt, messages, fperror, focus, nopassword. Environment: PF_LOCALE (default en_GB),
PF_SIZE (default 1440x900), PF_WALLPAPER (PNG; default: the Lock board wallpaper).
"""
import atexit
import os
import shutil
import subprocess
import sys
import tempfile
import time
import json

from PySide6.QtCore import QObject, QTimer, QUrl, Slot, QLocale, QSize, Qt, QByteArray
from PySide6.QtGui import QGuiApplication, QFontDatabase, QImage, QPainter, QIcon
from PySide6.QtQml import QQmlComponent, QQmlPropertyMap, QQmlProperty
from PySide6.QtQuick import QQuickView, QQuickItem
from PySide6.QtSvg import QSvgRenderer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
# PF_PKG_SRC: another copy of the package (org.plasmafusion.lockshell) to render, for A/B runs.
PKG_ROOT = os.environ.get("PF_PKG_SRC", os.path.join(HERE, "..", "org.plasmafusion.lockshell"))
SRC_PKG = os.path.join(PKG_ROOT, "contents", "lockscreen")


def staged_package():
    """The package as tools/build.d/90-lockscreen.sh installs it: the source files plus copies of
    the shared blocks it uses (packages/common, tools/build-lib/shared-qml.sh), in a temporary
    folder removed at exit."""
    tmp = tempfile.mkdtemp(prefix="pf-lockshell-")
    atexit.register(shutil.rmtree, tmp, True)
    pkg = os.path.join(tmp, "lockscreen")
    shutil.copytree(SRC_PKG, pkg)
    subprocess.run(["bash", os.path.join(ROOT, "tools", "build-lib", "shared-qml.sh"), "install",
                    PKG_ROOT, pkg], check=True)
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

    # The colour scheme, as the greeter reads it from kdeglobals (Kirigami's colours through the
    # org.kde.desktop style): Plasma Fusion Dark, or PF_SCHEME=Light. PF_ACCENT=#rrggbb applies a
    # user accent the way System Settings does (DecorationFocus, DecorationHover and the
    # selection fill of every colour set).
    cfg = os.path.join(out, "config")
    os.makedirs(cfg, exist_ok=True)
    scheme = os.path.join(ROOT, "packages", "color-schemes",
                          "PlasmaFusion%s.colors" % os.environ.get("PF_SCHEME", "Dark"))
    text = open(scheme).read()
    accent = os.environ.get("PF_ACCENT", "")
    if accent:
        rgb = ",".join(str(int(accent.lstrip("#")[i:i + 2], 16)) for i in (0, 2, 4))
        lines, group = [], ""
        for line in text.splitlines():
            if line.startswith("["):
                group = line
            key = line.split("=", 1)[0]
            if group.startswith("[Colors:") and key in ("DecorationFocus", "DecorationHover"):
                line = key + "=" + rgb
            if group == "[Colors:Selection]" and key == "BackgroundNormal":
                line = key + "=" + rgb
            lines.append(line)
        text = "\n".join(lines) + "\n[General]\nAccentColor=" + rgb + "\n"
    with open(os.path.join(cfg, "kdeglobals"), "w") as f:
        f.write(text)
    os.environ["XDG_CONFIG_HOME"] = cfg
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "org.kde.desktop")

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
    if os.environ.get("PF_FULLSCREEN") == "1":
        view.showFullScreen()
    else:
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

    if scenario == "timing":
        timing(app, out, view, root, lock_root)
        return
    if scenario == "tablet":
        tablet(app, out, view, root, lock_root, w, h)
        return
    if scenario != "idle":
        QTimer.singleShot(1200, step_prompt)
    QTimer.singleShot(4200, grab)
    app.exec()


def gpu_ns():
    """GPU time of this process so far (ns): the drm-engine-render lines of its DRM file
    descriptors (one per DRM client)."""
    total, seen = 0, set()
    fdinfo = "/proc/self/fdinfo"
    for fd in os.listdir(fdinfo):
        try:
            text = open(os.path.join(fdinfo, fd)).read()
        except OSError:
            continue
        fields = dict(line.split(":", 1) for line in text.splitlines() if ":" in line)
        client = fields.get("drm-client-id", "").strip()
        if not client or client in seen:
            continue
        seen.add(client)
        for key, value in fields.items():
            if key.startswith("drm-engine-"):
                total += int(value.split()[0])
    return total


def timing(app, out, view, root, lock_root):
    """BACKLOG S1 and EFFECTS X7 on a real GPU (a private Wayland session): frames while idle,
    the reveal and hide times, the first key's echo, and this process's GPU time for each phase.
    Writes timing.json."""
    from PySide6.QtTest import QTest
    pw = root.findChild(QQuickItem, "passwordBox")
    bd = root.findChild(QQuickItem, "backdrop")
    res = {"renderer": "", "phases": {}}
    frames = []
    view.frameSwapped.connect(lambda: frames.append(time.perf_counter()))
    marks = {}

    def phase(name, start):
        res["phases"][name] = {"frames": len([f for f in frames if f >= start["t"]]),
                               "gpu_ms": round((gpu_ns() - start["gpu"]) / 1e6, 2),
                               "seconds": round(time.perf_counter() - start["t"], 2)}

    def mark():
        return {"t": time.perf_counter(), "gpu": gpu_ns()}

    def step_idle():
        marks["idle"] = mark()
        QTimer.singleShot(5000, step_key)

    def step_key():
        phase("idle_5s", marks["idle"])
        view.requestActivate()
        marks["key"] = mark()
        t0 = marks["key"]["t"]
        QTest.keyClick(view, Qt.Key_A)

        def watch():
            now = time.perf_counter()
            if "echo" not in marks and pw is not None and pw.property("text") == "a":
                marks["echo"] = now
            if "echo" in marks and "echo_frame" not in marks:
                after = [f for f in frames if f >= marks["echo"]]
                if after:
                    marks["echo_frame"] = after[0]
                    res["echo_ms"] = round((after[0] - t0) * 1000, 1)
            if "revealed" not in marks and lock_root.property("promptFactor") >= 1:
                marks["revealed"] = now
                res["reveal_ms"] = round((now - marks.get("forced", t0)) * 1000, 1)
            # A package whose first key does not show the prompt (HEAD before LOCK-1, with no
            # pointer over the window): open it the way a click would, to compare the reveal.
            if "forced" not in marks and now - t0 > 0.5 and not lock_root.property("uiVisible"):
                marks["forced"] = now
                res["key_reveals"] = False
                marks["key"] = mark()
                lock_root.setProperty("uiVisible", True)
            if "revealed" in marks and "echo_frame" in marks:
                phase("reveal", marks["key"])
                marks["prompt"] = mark()
                QTimer.singleShot(3000, step_hide)
                return
            if now - t0 > 3:
                res["error"] = "no echo or reveal within 3 s"
                res["state"] = {"uiVisible": lock_root.property("uiVisible"),
                                "promptFactor": lock_root.property("promptFactor"),
                                "fieldActiveFocus": pw.property("activeFocus") if pw is not None else None,
                                "fieldVisible": pw.property("visible") if pw is not None else None,
                                "rootActiveFocus": lock_root.property("activeFocus"),
                                "activeFocusItem": str(view.activeFocusItem().objectName() if view.activeFocusItem() else None),
                                "windowActive": view.isActive()}
                finish()
                return
            QTimer.singleShot(2, watch)
        # The state when the key is sent (the prompt hidden).
        res["before_key"] = {"fieldActiveFocus": pw.property("activeFocus") if pw is not None else None,
                             "fieldVisible": pw.property("visible") if pw is not None else None,
                             "activeFocusItem": str(view.activeFocusItem().metaObject().className() if view.activeFocusItem() else None),
                             "windowActive": view.isActive()}
        watch()

    def step_hide():
        phase("prompt_3s", marks["prompt"])
        view.grabWindow().save(os.path.join(out, "timing-prompt.png"))
        marks["hide"] = mark()
        t0 = marks["hide"]["t"]
        lock_root.setProperty("uiVisible", False)

        def watch():
            now = time.perf_counter()
            if lock_root.property("promptFactor") <= 0:
                res["hide_ms"] = round((now - t0) * 1000, 1)
                phase("hide", marks["hide"])
                marks["after"] = mark()
                QTimer.singleShot(5000, step_after)
                return
            if now - t0 > 3:
                res["error"] = "not hidden within 3 s"
                finish()
                return
            QTimer.singleShot(2, watch)
        watch()

    def step_after():
        phase("idle_after_5s", marks["after"])
        finish()

    def finish():
        res["renderer"] = str(view.rendererInterface().graphicsApi())
        res["backdrop"] = {k: bd.property(k) for k in ("effectsAvailable", "blurPx", "dpr", "brightness")} if bd else {}
        res["typed"] = pw.property("text") if pw is not None else None
        img = view.grabWindow()
        img.save(os.path.join(out, "timing-end.png"))
        with open(os.path.join(out, "timing.json"), "w") as f:
            json.dump(res, f, indent=1)
        print("timing:", json.dumps(res))
        view.close()
        app.quit()

    # Settle (the wallpaper copy is taken 400 ms after start), then measure.
    QTimer.singleShot(2500, step_idle)
    app.exec()


def tablet(app, out, view, root, lock_root, w, h):
    """TABLET T13: run with KDE_KIRIGAMI_TABLET_MODE=1 (no KWin on the harness bus, so FusionTablet
    follows Kirigami). The prompt block (avatar, name, pill) centred at 38 % of the height (a third
    in portrait), 48 px pill, 44 px buttons inside it, 48 px power and keyboard buttons; with the
    on-screen keyboard shown, the whole prompt 24 px or more above it. Writes tablet.json."""
    from PySide6.QtCore import QPointF
    res = {"size": [w, h], "checks": []}

    def item(name):
        return root.findChild(QQuickItem, name)

    def rect(it):
        p = it.mapToScene(QPointF(0, 0))
        return [round(p.x(), 1), round(p.y(), 1), round(it.width(), 1), round(it.height(), 1)]

    def check(name, ok, detail):
        res["checks"].append({"check": name, "pass": bool(ok), "detail": detail})

    def step_prompt():
        lock_root.setProperty("uiVisible", True)
        QTimer.singleShot(1500, step_measure)

    def step_measure():
        card, pill = item("promptCard"), item("passwordPill")
        header_bottom = pill.mapToScene(QPointF(0, pill.height())).y()
        top = card.mapToScene(QPointF(0, 0)).y()
        centre = (top + header_bottom) / 2
        target = h / 3 if h > w else 0.38 * h
        check("prompt block centred at %s of the height" % ("1/3" if h > w else "38 %"),
              abs(centre - target) <= 2, "centre %.1f, target %.1f" % (centre, target))
        check("password pill at least 48 px tall", pill.height() >= 48, rect(pill))
        check("pill width min(400 x ts, W - 64)", pill.width() <= min(400 * 1.34, w - 64) and pill.width() >= min(400, w - 64) - 1, rect(pill))
        for name in ("unlockButton", "revealButton"):
            b = item(name)
            check(name + " 44 px", b is not None and b.width() >= 44 and b.height() >= 44, rect(b) if b else None)
        circles = [c for c in root.findChildren(QQuickItem, "powerCircle") if c.isVisible()]
        check("power buttons 48 px", circles and all(c.width() >= 48 and c.height() >= 48 for c in circles), [rect(c) for c in circles])
        kb = item("keyboardButton")
        check("keyboard button 48 px (when shown)", kb is None or not kb.isVisible() or (kb.width() >= 48 and kb.height() >= 48),
              rect(kb) if kb and kb.isVisible() else "not shown")
        res["prompt_before_keyboard"] = rect(card)
        view.grabWindow().save(os.path.join(out, "tablet-prompt.png"))
        panel = item("inputPanel")
        if panel is None:
            check("on-screen keyboard loader", False, "inputPanel not found")
            finish()
            return
        panel.setProperty("state", "visible")
        QTimer.singleShot(1200, step_keyboard)

    def step_keyboard():
        panel, card = item("inputPanel"), item("promptCard")
        kb_top = panel.mapToScene(QPointF(0, 0)).y()
        kb_h = panel.height()
        bottom = card.mapToScene(QPointF(0, card.height())).y()
        res["keyboard"] = rect(panel)
        res["prompt_with_keyboard"] = rect(card)
        check("keyboard has a height", kb_h > 50, kb_h)
        check("whole prompt 24 px above the keyboard", bottom + 24 <= kb_top + 0.5 or kb_h <= 50,
              "prompt bottom %.1f, keyboard top %.1f" % (bottom, kb_top))
        view.grabWindow().save(os.path.join(out, "tablet-keyboard.png"))
        finish()

    def finish():
        res["pass"] = all(c["pass"] for c in res["checks"])
        with open(os.path.join(out, "tablet.json"), "w") as f:
            json.dump(res, f, indent=1)
        print("tablet:", json.dumps(res))
        view.close()
        app.quit()

    QTimer.singleShot(1200, step_prompt)
    app.exec()


if __name__ == "__main__":
    main()
