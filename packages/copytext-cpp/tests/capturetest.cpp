// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "capture.h"

#include "fakekwin.h"

#include <QDBusConnection>
#include <QSignalSpy>
#include <QTest>

using namespace Qt::StringLiterals;

class CaptureTest : public QObject
{
    Q_OBJECT
    FakeKWin m_kwin;

private Q_SLOTS:
    void initTestCase()
    {
        QDBusConnection bus = QDBusConnection::sessionBus();
        QVERIFY2(bus.isConnected(), "no session bus (run under dbus-run-session)");
        QVERIFY(bus.registerService(u"org.kde.KWin.ScreenShot2"_s));
        QVERIFY(bus.registerObject(u"/org/kde/KWin/ScreenShot2"_s, &m_kwin, QDBusConnection::ExportAllSlots));
    }
    void captures()
    {
        ScreenCapture capture;
        QSignalSpy captured(&capture, &ScreenCapture::captured);
        QSignalSpy failed(&capture, &ScreenCapture::failed);
        capture.capture(u"DP-1"_s);
        QVERIFY(captured.wait(5000));
        QCOMPARE(failed.size(), 0);
        QCOMPARE(captured.at(0).at(0).toString(), u"DP-1"_s);
        const QImage image = captured.at(0).at(1).value<QImage>();
        QCOMPARE(image.size(), QSize(40, 30));
        QCOMPARE(image.devicePixelRatio(), 1.75);
        QCOMPARE(image.pixelColor(0, 0), QColor(0x5b, 0x9d, 0xff));
        QCOMPARE(image.pixelColor(39, 29), QColor(Qt::red));
        // The screen by its name, at native resolution, without the pointer.
        QCOMPARE(m_kwin.asked, QStringList{u"DP-1"_s});
        QCOMPARE(m_kwin.lastOptions.value(u"native-resolution"_s).toBool(), true);
        QCOMPARE(m_kwin.lastOptions.value(u"include-cursor"_s).toBool(), false);
    }
    void refused()
    {
        ScreenCapture capture;
        QSignalSpy captured(&capture, &ScreenCapture::captured);
        QSignalSpy failed(&capture, &ScreenCapture::failed);
        capture.capture(u"refused"_s);
        QVERIFY(failed.wait(5000));
        QCOMPARE(captured.size(), 0);
        QCOMPARE(failed.at(0).at(0).toString(), u"refused"_s);
        QVERIFY(failed.at(0).at(1).toString().contains(u"not authorized"_s));
    }
};

QTEST_GUILESS_MAIN(CaptureTest)
#include "capturetest.moc"
