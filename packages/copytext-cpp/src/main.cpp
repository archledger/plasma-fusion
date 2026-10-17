// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "overlay.h"

#include <KLocalizedString>

#include <QDBusConnection>
#include <QGuiApplication>
#include <QQuickWindow>
#include <QTimer>

using namespace Qt::StringLiterals;

int main(int argc, char **argv)
{
    // It draws one still picture, a veil and a box: Qt Quick's software renderer does that as fast
    // as the GPU here (71-89 ms to the overlay against 90-100 ms, 2880 x 1800, 2026-10-17) and
    // keeps no GPU driver memory while it waits (74-95 MB after a use against 120-140 MB).
    // QT_QUICK_BACKEND still chooses another for a test.
    if (qEnvironmentVariableIsEmpty("QT_QUICK_BACKEND")) {
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
    }
    QGuiApplication app(argc, argv);
    app.setApplicationName(u"plasma-fusion-copytext-overlay"_s);
    KLocalizedString::setApplicationDomain("plasma-fusion-copytext-overlay");
    QGuiApplication::setDesktopFileName(u"org.plasmafusion.copytextoverlay"_s);
    // It waits for the next capture with no window open.
    app.setQuitOnLastWindowClosed(false);

    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerService(u"org.plasmafusion.CopyTextOverlay"_s)) {
        qInfo("copytext-overlay: already running");
        return 0;
    }
    Overlay overlay;
    bus.registerObject(u"/"_s, &overlay, QDBusConnection::ExportScriptableSlots);
    // --now: a capture right away (tests; the helper calls Start() on the bus).
    if (app.arguments().contains(u"--now"_s)) {
        QTimer::singleShot(0, &overlay, &Overlay::Start);
    }
    return app.exec();
}
