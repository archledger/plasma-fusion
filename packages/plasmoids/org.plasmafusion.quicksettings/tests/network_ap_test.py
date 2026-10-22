#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Native plasma-nm connection dispatch on private NetworkManager/session buses.

Needs PySide6 and python-dbusmock. No real radio, profile or password is used.
QT_QPA_PLATFORM=offscreen python3 network_ap_test.py STAGE_HOME
"""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest

# Backend.qml imports Plasma's clipboard plugin even with its loader disabled. On the offscreen
# platform its GLX probe must stay off, as in pages_test.py and clipboard_sheet_test.py.
os.environ["QT_QPA_OFFSCREEN_NO_GLX"] = "1"


SERVICES = Path(__file__).resolve().parent.parent / "contents/ui/services"
CASES = ("stable", "open", "wpa3", "replaced", "other-device", "gone", "security-changed",
         "unknown", "unknown-encrypted", "unknown-secret", "saved", "ambiguous", "facade", "facade-gone")


def run_case(case, stage):
    import dbus
    import dbusmock
    from PySide6.QtCore import QCoreApplication, QEvent, QObject, Q_ARG, QMetaObject, Q_RETURN_ARG, QUrl, Slot
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine
    from PySide6.QtTest import QTest

    class Buses(dbusmock.DBusTestCase):
        pass

    class Context(QObject):
        @Slot(str, str, result=str)
        def i18nc(self, context, text):
            return text

    with tempfile.TemporaryDirectory() as home:
        os.environ.update(HOME=home, XDG_CONFIG_HOME=home, QT_QUICK_BACKEND="software")
        Buses.setUpClass()
        Buses.start_system_bus()
        Buses.start_session_bus()
        process, obj = Buses.spawn_server_template("networkmanager", {"Version": "1.56.1"}, stdout=subprocess.DEVNULL)
        root = engine = app = None
        try:
            mock = dbus.Interface(obj, dbusmock.MOCK_IFACE)
            dev = mock.AddWiFiDevice("test0", "test0", 30)
            flags = 0 if case == "open" else 0x100 if case in ("unknown-encrypted", "unknown-secret") else 0x188
            old = mock.AddAccessPoint(dev, "old", "Fusion-test", "02:00:00:00:00:01", 2, 2412, 54000, 60,
                                     flags)
            if case == "wpa3":
                mock.SetProperty(old, "org.freedesktop.NetworkManager.AccessPoint", "WpaFlags", dbus.UInt32(0))
                mock.SetProperty(old, "org.freedesktop.NetworkManager.AccessPoint", "RsnFlags", dbus.UInt32(0x488))
            manager = dbus.Interface(Buses.get_dbus(True).get_object(
                "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager"), dbusmock.MOCK_IFACE)
            manager.AddMethod("org.freedesktop.NetworkManager", "AddAndActivateConnection", "a{sa{sv}}oo", "oo",
                              "ret = (dbus.ObjectPath('/test/connection'), dbus.ObjectPath('/test/active'))")
            app = QGuiApplication(sys.argv[:1])
            engine = QQmlEngine()
            context = Context()
            engine.rootContext().setContextObject(context)
            component = QQmlComponent(engine)
            ui = stage / ".local/share/plasma/plasmoids/org.plasmafusion.quicksettings/contents/ui"
            declaration = '''Ui.Backend { id: facade; leader: false; showClipboard: false;
                showKdeConnect: false; showNotifications: false }
                readonly property var network: facade.net''' if case.startswith("facade") else 'Services.Network { id: network }'
            component.setData(('''
import QtQuick
import org.kde.kitemmodels as KItemModels
import "%s" as Services
import "%s" as Ui
Item {
    %s
    function ready(): bool { return network && network.otherModel !== null; }
    function rows(): string {
        const m = network.otherModel;
        const role = name => m.KItemModels.KRoleNames.role(name);
        let result = [];
        for (let row = 0; row < m.rowCount(); ++row) {
            const i = m.index(row, 0);
            result.push({device: m.data(i, role("DevicePath")),
                         path: m.data(i, role("SpecificPath")),
                         security: m.data(i, role("SecurityType")),
                         ssid: m.data(i, role("Ssid"))});
        }
        return JSON.stringify(result);
    }
    function attempt(device: string, path: string, security: int, password: string): bool {
        return network.addAndActivate(device, path, password, "Fusion-test", security) === true;
    }
    function error(): string { return network.connectionError || ""; }
    function closeList() { network.listVisible = true; network.listVisible = false; }
    function savedActivation(path: string, device: string, ap: string) { network.activate(path, device, ap); }
}
''' % (SERVICES.as_uri(), ui.as_uri(), declaration)).encode(), QUrl("file:///network-ap-test.qml"))
            root = component.create()
            assert root is not None, "\n".join(e.toString() for e in component.errors())
            for _ in range(60):
                if QMetaObject.invokeMethod(root, "ready", Q_RETURN_ARG(bool)):
                    break
                QTest.qWait(50)
            QTest.qWait(200)

            def rows():
                return json.loads(QMetaObject.invokeMethod(root, "rows", Q_RETURN_ARG(str)))

            assert any(r["path"] == old for r in rows()), "initial native row missing"
            if case in ("open", "unknown-encrypted", "unknown-secret"):
                security = next(r["security"] for r in rows() if r["path"] == old)
            else:
                security = 8 if case == "wpa3" else 6
            assert next(r["security"] for r in rows() if r["path"] == old) == security, "security fixture not classified"
            expected = str(old)
            if case in ("replaced", "other-device"):
                new = mock.AddAccessPoint(dev, "new", "Fusion-test", "02:00:00:00:00:02", 2, 5180, 54000, 90, 0x188)
                mock.RemoveAccessPoint(dev, old)
                expected = str(new)
            if case == "other-device":
                other = mock.AddWiFiDevice("test1", "test1", 30)
                mock.AddAccessPoint(other, "wrong_device", "Fusion-test", "02:00:00:00:00:03", 2, 5180, 54000, 100, 0x188)
            if case in ("gone", "facade-gone"):
                mock.RemoveAccessPoint(dev, old)
            if case == "security-changed":
                for prop in ("Flags", "WpaFlags", "RsnFlags"):
                    mock.SetProperty(old, "org.freedesktop.NetworkManager.AccessPoint", prop, dbus.UInt32(0))
            if case in ("saved", "ambiguous"):
                settings = dbus.Interface(Buses.get_dbus(True).get_object(
                    "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager/Settings"),
                    "org.freedesktop.NetworkManager.Settings")
                profile = settings.AddConnection({
                    "connection": {"id": "Fusion-test", "type": "802-11-wireless", "autoconnect": False},
                    "802-11-wireless": {"ssid": dbus.ByteArray(b"Fusion-test"),
                                        "security": "802-11-wireless-security"},
                    "802-11-wireless-security": {"key-mgmt": "wpa-psk"},
                })
                profiles = [dbus.ObjectPath(profile)]
                if case == "ambiguous":
                    profiles.append(settings.AddConnection({
                        "connection": {"id": "second", "type": "802-11-wireless", "autoconnect": False},
                        "802-11-wireless": {"ssid": dbus.ByteArray(b"Fusion-test"),
                                            "security": "802-11-wireless-security"},
                        "802-11-wireless-security": {"key-mgmt": "wpa-psk"},
                    }))
                mock.SetProperty(dev, "org.freedesktop.NetworkManager.Device", "AvailableConnections",
                                 dbus.Array(profiles, signature="o"))
            QTest.qWait(250)
            # Use the row's current path: unfixed plasma-nm retains the old one, a later fixed
            # version may already expose the replacement. Both must dispatch the current AP.
            selected = next((r["path"] for r in rows() if r["device"] == dev), str(old))
            dispatched = QMetaObject.invokeMethod(root, "attempt", Q_RETURN_ARG(bool), Q_ARG(str, str(dev)),
                                                 Q_ARG(str, selected), Q_ARG(int, -1 if case == "unknown" else security),
                                                 Q_ARG(str, "" if case in ("open", "unknown-encrypted") else "fixture-password"))
            QTest.qWait(250)
            calls = manager.GetMethodCalls("AddAndActivateConnection")
            if case in ("gone", "facade-gone", "security-changed", "unknown", "unknown-secret", "saved", "ambiguous"):
                assert not dispatched and not calls, "unsafe or unavailable target was dispatched"
                assert QMetaObject.invokeMethod(root, "error", Q_RETURN_ARG(str)), "missing failure explanation"
                if case == "gone":
                    QMetaObject.invokeMethod(root, "closeList")
                    assert not QMetaObject.invokeMethod(root, "error", Q_RETURN_ARG(str)), "error survived page dismissal"
                if case == "saved":
                    QMetaObject.invokeMethod(root, "savedActivation", Q_ARG(str, str(profile)),
                                             Q_ARG(str, str(dev)), Q_ARG(str, str(old)))
                    assert not QMetaObject.invokeMethod(root, "error", Q_RETURN_ARG(str)), "error survived saved activation"
            else:
                assert dispatched, "connection dispatch refused"
                assert len(calls) == 1 and str(calls[0][1][2]) == expected, "wrong or stale access point dispatched"
                assert str(calls[0][1][1]) == str(dev), "wrong device dispatched"
                if case == "open":
                    assert "802-11-wireless-security" not in calls[0][1][0], "open network was forced to use encryption"
                if case == "unknown-encrypted":
                    assert "802-11-wireless-security" in calls[0][1][0], "unknown encrypted network was forced open"
        finally:
            if root is not None:
                root.deleteLater()
                QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)
            if app is not None:
                app.processEvents()
            del engine
            process.terminate()
            process.wait(timeout=10)
            Buses.tearDownClass()


class NetworkAccessPointTest(unittest.TestCase):
    def test_dispatch(self):
        for case in CASES:
            with self.subTest(case=case):
                with subprocess.Popen([sys.executable, __file__, "--case", case, str(STAGE)],
                                      env={**os.environ, "QT_QPA_PLATFORM": "offscreen"}, text=True,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                      start_new_session=True) as process:
                    try:
                        out, err = process.communicate(timeout=30)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        out, err = process.communicate()
                        self.fail("private-bus test timed out: " + out + err)
                    self.assertEqual(process.returncode, 0, out + err)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--case":
        run_case(sys.argv[2], Path(sys.argv[3]).resolve())
    else:
        if len(sys.argv) != 2:
            raise SystemExit("usage: network_ap_test.py STAGE_HOME")
        STAGE = Path(sys.argv[1]).resolve()
        unittest.main(argv=[sys.argv[0]])
