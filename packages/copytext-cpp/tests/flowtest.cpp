// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "overlay.h"

#include "fakekwin.h"

#include <QDBusConnection>
#include <QDBusPendingCall>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QScreen>
#include <QTemporaryDir>
#include <QTest>

#include <csignal>

using namespace Qt::StringLiterals;

// Two screens of known names and sizes (Qt's offscreen platform reads them from a file): DP-1 at
// scale 2, HDMI-1 at scale 1 beside it.
static const char s_screens[] = R"({"synchronousWindowSystemEvents": false, "windowFrameMargins": false, "screens": [
    {"name": "DP-1", "x": 0, "y": 0, "width": 120, "height": 100, "logicalDpi": 96, "logicalBaseDpi": 96, "dpr": 1},
    {"name": "HDMI-1", "x": 120, "y": 0, "width": 100, "height": 80, "logicalDpi": 96, "logicalBaseDpi": 96, "dpr": 1}]})";

// A screen's native picture: every pixel says where it is (red x, green y; under 256 on both
// screens) and on which screen (blue).
static QImage nativePicture(QSize size, qreal scale, int screen)
{
    QImage image(size * scale, QImage::Format_ARGB32);
    for (int y = 0; y < image.height(); ++y) {
        for (int x = 0; x < image.width(); ++x) {
            image.setPixel(x, y, qRgb(x, y, screen));
        }
    }
    image.setDevicePixelRatio(scale);
    return image;
}

// The overlay on a private bus (dbus-run-session) with a stand-in for KWin's ScreenShot2, its QML
// offscreen on two screens, and a stand-in for plasma-fusion-copytext next to this test, where the
// overlay looks for it (flow/plasma-fusion-copytext: what it was given, in $FLOW_OUT): Start() on
// the bus shows one window per screen; a box drawn on one goes to the helper as that screen's native
// pixels, in a private directory in the runtime directory that is gone once the helper is done; a
// second Start() while the box is chosen, or while the helper reads it, does nothing; Esc and a
// click end it with no helper; KWin's refusal runs the helper's own way
// (PLASMA_FUSION_COPYTEXT_NO_OVERLAY), and a picture that comes after a refusal is dropped; so does
// a capture that makes no window (the QML giving no window), which is not said shown, and the next
// Start() asks KWin again.
class FlowTest : public QObject
{
    Q_OBJECT

    FakeKWin m_kwin;
    Overlay m_overlay;
    QString m_out = qEnvironmentVariable("FLOW_OUT");

    static QList<QQuickWindow *> overlays()
    {
        QList<QQuickWindow *> shown;
        const auto windows = QGuiApplication::topLevelWindows();
        for (QWindow *window : windows) {
            auto *quick = qobject_cast<QQuickWindow *>(window);
            if (quick && quick->isVisible()) {
                shown.append(quick);
            }
        }
        return shown;
    }
    static QQuickWindow *overlayOn(const QString &screenName)
    {
        const auto shown = overlays();
        for (QQuickWindow *window : shown) {
            if (window->property("screenName").toString() == screenName) {
                return window;
            }
        }
        return nullptr;
    }
    QStringList runs() const
    {
        QFile file(m_out + u"/runs"_s);
        if (!file.open(QIODevice::ReadOnly)) {
            return {};
        }
        return QString::fromUtf8(file.readAll()).split(u'\n', Qt::SkipEmptyParts);
    }
    // What the overlay says (its qInfo and qWarning lines), passed on to QTest's own handler.
    static inline QStringList s_said;
    static inline QtMessageHandler s_previous = nullptr;
    static void listen(QtMsgType type, const QMessageLogContext &context, const QString &message)
    {
        s_said.append(message);
        s_previous(type, context, message);
    }
    static QStringList privateDirs()
    {
        return QDir(qEnvironmentVariable("XDG_RUNTIME_DIR")).entryList({u"plasma-fusion-copytext-overlay.*"_s}, QDir::Dirs);
    }
    static void drag(QQuickWindow *window, QPoint from, QPoint to)
    {
        QTest::mousePress(window, Qt::LeftButton, {}, from);
        QTest::mouseMove(window, (from + to) / 2);
        QTest::mouseMove(window, to);
        QTest::mouseRelease(window, Qt::LeftButton, {}, to);
    }
    // The picture the helper was given (--image, a file in a private directory in the runtime
    // directory; not the helper's own way), once it has run.
    void handedOver(QImage &area)
    {
        QTRY_COMPARE_WITH_TIMEOUT(runs().size(), 1, 5000);
        const QString run = runs().constFirst();
        const QRegularExpression expected(
            u"^--image %1/plasma-fusion-copytext-overlay\\.[^/]+/region\\.png\\|$"_s.arg(QRegularExpression::escape(qEnvironmentVariable("XDG_RUNTIME_DIR"))));
        QVERIFY2(expected.match(run).hasMatch(), qPrintable(run));
        // The directory is the user's alone.
        QFile mode(m_out + u"/mode"_s);
        QVERIFY(mode.open(QIODevice::ReadOnly));
        QCOMPARE(mode.readAll().trimmed(), QByteArray("700"));
        area = QImage(m_out + u"/region.png"_s);
    }

private Q_SLOTS:
    void initTestCase()
    {
        // A stand-in that reads too little must not end the test.
        std::signal(SIGPIPE, SIG_IGN);
        s_previous = qInstallMessageHandler(listen);
        QVERIFY(!m_out.isEmpty());
        QCOMPARE(QGuiApplication::screens().size(), 2);
        m_kwin.pictures.insert(u"DP-1"_s, nativePicture({120, 100}, 2, 0x10));
        m_kwin.pictures.insert(u"HDMI-1"_s, nativePicture({100, 80}, 1, 0x20));
        QDBusConnection bus = QDBusConnection::sessionBus();
        QVERIFY2(bus.isConnected(), "no session bus (run under dbus-run-session)");
        QVERIFY(bus.registerService(u"org.kde.KWin.ScreenShot2"_s));
        QVERIFY(bus.registerObject(u"/org/kde/KWin/ScreenShot2"_s, &m_kwin, QDBusConnection::ExportAllSlots));
        // As the program does (main.cpp), for the helper's call.
        QVERIFY(bus.registerService(u"org.plasmafusion.CopyTextOverlay"_s));
        QVERIFY(bus.registerObject(u"/"_s, &m_overlay, QDBusConnection::ExportScriptableSlots));
    }
    void init()
    {
        QFile::remove(m_out + u"/runs"_s);
        QFile::remove(m_out + u"/region.png"_s);
        QFile::remove(m_out + u"/mode"_s);
        QFile::remove(m_out + u"/hold"_s);
        m_kwin.asked.clear();
        m_kwin.refuseAll = false;
        m_kwin.refused = QStringList{u"refused"_s};
    }
    void cleanup()
    {
        // A failed case may leave its selection open or its helper reading: end both, so that the
        // next case starts as the program would.
        const auto left = overlays();
        for (QQuickWindow *window : left) {
            QMetaObject::invokeMethod(window, "cancelled");
        }
        QFile::remove(m_out + u"/hold"_s);
        QTRY_VERIFY_WITH_TIMEOUT(overlays().isEmpty(), 5000);
        QTRY_VERIFY_WITH_TIMEOUT(privateDirs().isEmpty(), 15000);
    }

    void handsOverTheBox()
    {
        // The helper's call: busctl --user call org.plasmafusion.CopyTextOverlay / org.plasmafusion.CopyTextOverlay Start
        const QDBusMessage start =
            QDBusMessage::createMethodCall(u"org.plasmafusion.CopyTextOverlay"_s, u"/"_s, u"org.plasmafusion.CopyTextOverlay"_s, u"Start"_s);
        QDBusConnection::sessionBus().asyncCall(start);
        QTRY_COMPARE_WITH_TIMEOUT(overlays().size(), 2, 5000);
        QCOMPARE(m_kwin.asked, (QStringList{u"DP-1"_s, u"HDMI-1"_s}));
        for (QScreen *screen : QGuiApplication::screens()) {
            QQuickWindow *window = overlayOn(screen->name());
            QVERIFY2(window, qPrintable(screen->name()));
            QCOMPARE(window->screen(), screen);
            QCOMPARE(window->geometry(), screen->geometry());
        }
        QQuickWindow *window = overlayOn(u"DP-1"_s);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        drag(window, {10, 20}, {60, 45});
        // Every window closes; the box (10, 20) 50 x 25 at scale 2 is 100 x 50 native pixels at (20, 40).
        QTRY_VERIFY_WITH_TIMEOUT(overlays().isEmpty(), 5000);
        QImage area;
        handedOver(area);
        if (QTest::currentTestFailed()) {
            return;
        }
        QCOMPARE(area.size(), QSize(100, 50));
        QCOMPARE(QColor(area.pixel(0, 0)), QColor(20, 40, 0x10));
        QCOMPARE(QColor(area.pixel(99, 49)), QColor(119, 89, 0x10));
        // The private directory goes once the helper is done with it.
        QTRY_VERIFY_WITH_TIMEOUT(privateDirs().isEmpty(), 5000);
    }
    void otherScreen()
    {
        m_overlay.Start();
        QTRY_COMPARE_WITH_TIMEOUT(overlays().size(), 2, 5000);
        QQuickWindow *window = overlayOn(u"HDMI-1"_s);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        drag(window, {55, 35}, {5, 5});
        QImage area;
        handedOver(area);
        if (QTest::currentTestFailed()) {
            return;
        }
        QCOMPARE(area.size(), QSize(50, 30));
        QCOMPARE(QColor(area.pixel(0, 0)), QColor(5, 5, 0x20));
        QCOMPARE(QColor(area.pixel(49, 29)), QColor(54, 34, 0x20));
        QTRY_VERIFY_WITH_TIMEOUT(privateDirs().isEmpty(), 5000);
    }
    void cancels_data()
    {
        QTest::addColumn<bool>("esc");
        QTest::newRow("Esc") << true;
        QTest::newRow("a click") << false;
    }
    void cancels()
    {
        QFETCH(bool, esc);
        m_overlay.Start();
        // A second press while the box is chosen: nothing more asked of KWin, no more windows.
        m_overlay.Start();
        QTRY_COMPARE_WITH_TIMEOUT(overlays().size(), 2, 5000);
        QCOMPARE(m_kwin.asked.size(), 2);
        QQuickWindow *window = overlayOn(u"DP-1"_s);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        if (esc) {
            QTest::keyClick(window, Qt::Key_Escape);
        } else {
            QTest::mouseClick(window, Qt::LeftButton, {}, {30, 30});
        }
        QTRY_VERIFY_WITH_TIMEOUT(overlays().isEmpty(), 5000);
        QTest::qWait(500);
        QCOMPARE(runs(), QStringList());
        QCOMPARE(privateDirs(), QStringList());
    }
    void waitsForTheHelper()
    {
        // The helper still reads the first area (Tesseract): a press meanwhile shows nothing, as
        // the helper would drop a second area (its lock).
        QFile hold(m_out + u"/hold"_s);
        QVERIFY(hold.open(QIODevice::WriteOnly));
        hold.close();
        m_overlay.Start();
        QTRY_COMPARE_WITH_TIMEOUT(overlays().size(), 2, 5000);
        QQuickWindow *window = overlayOn(u"DP-1"_s);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        drag(window, {10, 20}, {60, 45});
        QTRY_VERIFY_WITH_TIMEOUT(QFile::exists(m_out + u"/region.png"_s), 5000);
        m_overlay.Start();
        QTest::qWait(500);
        QVERIFY(overlays().isEmpty());
        QCOMPARE(m_kwin.asked.size(), 2);
        QCOMPARE(runs(), QStringList());
        // Done: the next press shows the selection again.
        QFile::remove(hold.fileName());
        QTRY_COMPARE_WITH_TIMEOUT(runs().size(), 1, 15000);
        QTRY_VERIFY_WITH_TIMEOUT(privateDirs().isEmpty(), 5000);
        m_overlay.Start();
        QTRY_COMPARE_WITH_TIMEOUT(overlays().size(), 2, 5000);
        QCOMPARE(m_kwin.asked.size(), 4);
        window = overlayOn(u"DP-1"_s);
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        QTest::keyClick(window, Qt::Key_Escape);
    }
    void partlyRefused()
    {
        // KWin refuses one screen and gives the other: the helper's own way once, no window, and
        // the picture that comes after the refusal is not kept until the next press.
        m_kwin.refused = QStringList{u"DP-1"_s};
        QTest::ignoreMessage(QtInfoMsg, "copytext-overlay: a picture of HDMI-1 after the end, dropped");
        m_overlay.Start();
        QTRY_COMPARE_WITH_TIMEOUT(runs(), QStringList{u"|1"_s}, 5000);
        QTest::qWait(500);
        QCOMPARE(runs(), QStringList{u"|1"_s});
        QVERIFY(overlays().isEmpty());
    }
    void refusedFallsBack()
    {
        m_kwin.refuseAll = true;
        m_overlay.Start();
        // Once, with no picture and no window: the helper's own way, Spectacle's selection.
        QTRY_COMPARE_WITH_TIMEOUT(runs(), QStringList{u"|1"_s}, 5000);
        QTest::qWait(500);
        QCOMPARE(runs(), QStringList{u"|1"_s});
        QVERIFY(overlays().isEmpty());
    }
    void noWindowFallsBack_data()
    {
        QTest::addColumn<QByteArray>("qml");
        // An object that is not a window, and a window that cannot be made (a property it needs
        // that the overlay does not give).
        QTest::newRow("not a window") << QByteArray("import QtQuick\nItem {}\n");
        QTest::newRow("no object") << QByteArray("import QtQuick\nWindow { required property int missing }\n");
    }
    void noWindowFallsBack()
    {
        QFETCH(QByteArray, qml);
        // An overlay of its own with that QML (the bus's keeps its own for the other cases).
        Overlay overlay;
        auto *component = overlay.findChild<QQmlComponent *>();
        QVERIFY(component);
        component->setData(qml, QUrl());
        QVERIFY2(component->isReady(), qPrintable(component->errorString()));
        s_said.clear();
        overlay.Start();
        // The helper's own way once, no window, and the overlay not said shown.
        QTRY_COMPARE_WITH_TIMEOUT(runs(), QStringList{u"|1"_s}, 5000);
        QVERIFY(overlays().isEmpty());
        // Not stuck: the next press asks KWin again, and goes the helper's way again.
        overlay.Start();
        QTRY_COMPARE_WITH_TIMEOUT(runs(), (QStringList{u"|1"_s, u"|1"_s}), 5000);
        QTest::qWait(500);
        QCOMPARE(runs(), (QStringList{u"|1"_s, u"|1"_s}));
        QCOMPARE(m_kwin.asked.size(), 4);
        QVERIFY(overlays().isEmpty());
        QVERIFY2(s_said.contains(u"copytext-overlay: no overlay window, Spectacle's selection instead"_s), qPrintable(s_said.join(u'\n')));
        QVERIFY2(s_said.filter(u"copytext-overlay: shown in"_s).isEmpty(), qPrintable(s_said.join(u'\n')));
    }
};

int main(int argc, char **argv)
{
    QTemporaryDir config;
    QTemporaryDir runtime; // the runtime directory (0700, as Qt wants it)
    QTemporaryDir out;
    if (!config.isValid() || !runtime.isValid() || !out.isValid()) {
        return 1;
    }
    QFile screens(config.filePath(u"screens.json"_s));
    if (!screens.open(QIODevice::WriteOnly) || screens.write(s_screens) < 0) {
        return 1;
    }
    screens.close();
    const QByteArray platform = "offscreen:configfile=" + screens.fileName().toLocal8Bit();
    qputenv("QT_QPA_PLATFORM", platform);
    qputenv("XDG_RUNTIME_DIR", runtime.path().toLocal8Bit());
    qputenv("FLOW_OUT", out.path().toLocal8Bit());
    QGuiApplication app(argc, argv);
    FlowTest test;
    return QTest::qExec(&test, argc, argv);
}

#include "flowtest.moc"
