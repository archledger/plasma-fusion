#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""FusionBackdrop follows the desktop's wallpaper, also when that is the Global Theme's default.

  QT_QPA_PLATFORM=offscreen dbus-run-session \\
      --config-file=packages/kwin/tests/offscreen/session-bus.conf -- \\
      python3 packages/common/tests/backdrop_wallpaper_test.py

A desktop whose wallpaper was never chosen has an empty Image key: Plasma's image wallpaper then
shows the Global Theme's default (libkworkspace DefaultWallpaper: kdeglobals [KDE]
LookAndFeelPackage, that package's defaults [Wallpaper] Image, a folder under wallpapers/). The
backdrop (the tablet launcher sheet, the Notification Centre) asked plasmashell for the
wallpaper, got the empty key and drew only the tint, so Full glass looked like Solid on such a
desktop (the ThinkPad, 2026-10-11). In a throw-away HOME, with a stand-in plasmashell on the
private bus, this checks that the backdrop takes:
  1. the desktop's own Image when it is set;
  2. the Global Theme's default wallpaper package when Image is empty, with the file closest to
     the backdrop's size (the light images, and contents/images_dark/ in the dark variant);
  3. nothing (the tint) when neither the key nor the theme names a wallpaper that exists.
Needs PySide6 (Qt Quick, offscreen), python3-dbus, python3-gobject and plasma-workspace's QML
D-Bus module.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HOME = Path(tempfile.mkdtemp(prefix="pf-backdrop-"))
for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"):
    os.environ.pop(key, None)
os.environ["HOME"] = str(HOME)
os.environ["XDG_CONFIG_HOME"] = str(HOME / ".config")
os.environ["XDG_DATA_HOME"] = str(HOME / ".local/share")
# Only this HOME's data: no Global Theme or wallpaper of the machine that runs the test.
os.environ["XDG_DATA_DIRS"] = str(HOME / "system")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

import dbus  # noqa: E402
from PySide6.QtCore import QObject, QUrl  # noqa: E402
from PySide6.QtGui import QColor, QGuiApplication, QImage  # noqa: E402
from PySide6.QtQuick import QQuickView  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
COMMON = ROOT / "packages" / "common"
checks = 0
failures = []


def check(ok, message):
    global checks
    checks += 1
    print(("PASS " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)


def picture(path, w, h):
    path.parent.mkdir(parents=True, exist_ok=True)
    img = QImage(max(1, w // 16), max(1, h // 16), QImage.Format.Format_RGB32)
    img.fill(QColor("#3b56a0"))
    img.save(str(path))


bus = dbus.SessionBus()
if bus.name_has_owner("org.kde.plasmashell"):
    raise SystemExit("Run on a fresh private bus; refusing a live desktop bus")

# The Global Theme (named in kdeglobals) and its default wallpaper package; a file for case 1.
(HOME / ".config").mkdir(parents=True)
kdeglobals_text = "[General]\nColorScheme=Test\n\n[KDE]\nLookAndFeelPackage=org.example.lnf\n"
(HOME / ".config/kdeglobals").write_text(kdeglobals_text)
lnf = HOME / ".local/share/plasma/look-and-feel/org.example.lnf/contents"
lnf.mkdir(parents=True)
(lnf / "defaults").write_text("[kdeglobals][KDE]\nwidgetStyle=Breeze\n\n[Wallpaper]\nImage=ExampleWall\n")
# The wallpaper package is installed system-wide (the RPM's /usr/share/wallpapers).
wall = HOME / "system/wallpapers/ExampleWall/contents"
picture(wall / "images/1280x800.png", 1280, 800)
picture(wall / "images/3840x2400.png", 3840, 2400)
picture(wall / "images_dark/1280x800.png", 1280, 800)
chosen = HOME / "Pictures/chosen.png"
picture(chosen, 640, 400)

# The stand-in plasmashell: org.kde.PlasmaShell.wallpaper(uint) answers the image plugin's
# settings with Image from a file, so each case can change it.
answer = HOME / "image.txt"
shell = subprocess.Popen([sys.executable, "-c", f'''
import dbus, dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName("org.kde.plasmashell", bus)
class Shell(dbus.service.Object):
    @dbus.service.method("org.kde.PlasmaShell", in_signature="u", out_signature="a{{sv}}")
    def wallpaper(self, screen):
        image = open({str(answer)!r}).read()
        return {{"wallpaperPlugin": dbus.String("org.kde.image"), "Image": dbus.String(image),
                 "ImageDefault": dbus.String("")}}
    @dbus.service.signal("org.kde.PlasmaShell", signature="u")
    def wallpaperChanged(self, screen):
        pass
Shell(bus, "/PlasmaShell")
GLib.MainLoop().run()
'''])

ui = HOME / "ui"
ui.mkdir()
shutil.copy(COMMON / "FusionBackdrop.qml", ui / "FusionBackdrop.qml")
(ui / "Harness.qml").write_text("""import QtQuick
Item {
    width: 1280
    height: 800
    FusionBackdrop { objectName: "light"; anchors.fill: parent; followWallpaper: true; dark: false }
    FusionBackdrop { objectName: "dark"; width: 640; height: 400; followWallpaper: true; dark: true }
}
""")


def show_with(image):
    """A new harness asking the stand-in, which answers Image = `image`."""
    answer.write_text(image)
    view = QQuickView()
    view.setSource(QUrl.fromLocalFile(str(ui / "Harness.qml")))
    if view.status() == QQuickView.Status.Error:
        raise SystemExit("the harness did not load: " + "; ".join(e.toString() for e in view.errors()))
    view.resize(1280, 800)
    view.show()
    return view


def files_of(view, seconds=4):
    root = view.rootObject()
    light, dark = root.findChild(QObject, "light"), root.findChild(QObject, "dark")
    waited = 0
    while waited < seconds * 1000:
        QTest.qWait(100)
        waited += 100
        if light.property("file").toString() and dark.property("file").toString():
            break
    return light.property("file").toString(), dark.property("file").toString()


app = QGuiApplication(sys.argv[:1])
try:
    waited = 0
    while not bus.name_has_owner("org.kde.plasmashell") and waited < 5000:
        QTest.qWait(50)
        waited += 50
    check(bus.name_has_owner("org.kde.plasmashell"), "the stand-in plasmashell is on the bus")

    view = show_with(chosen.as_uri())
    light, dark = files_of(view)
    check(light == chosen.as_uri() and dark == chosen.as_uri(), "1. the desktop's own Image (%r, %r)" % (light, dark))
    view.close()
    view.deleteLater()

    view = show_with("")
    light, dark = files_of(view)
    check(light.endswith("/system/wallpapers/ExampleWall/contents/images/1280x800.png"),
          "2. an empty Image: the Global Theme's default wallpaper, the light file closest to the size (%r)" % light)
    check(dark.endswith("/system/wallpapers/ExampleWall/contents/images_dark/1280x800.png"),
          "   and its dark images in the dark variant (%r)" % dark)
    view.close()
    view.deleteLater()

    (lnf / "defaults").write_text("[Wallpaper]\nImage=NoSuchWall\n")
    view = show_with("")
    light, dark = files_of(view, seconds=2)
    check(light == "" and dark == "", "3. a default that does not exist: no picture, the tint only (%r, %r)" % (light, dark))
    view.close()
    check((HOME / ".config/kdeglobals").read_text() == kdeglobals_text and not (HOME / ".config/ui.conf").exists(),
          "reading the configuration wrote nothing")
finally:
    shell.terminate()
    shell.wait(timeout=5)

print(f"Backdrop wallpaper: {checks} checks, {len(failures)} failures")
sys.exit(1 if failures else 0)
