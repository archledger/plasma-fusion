/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#include "tabletmode.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QLoggingCategory>
#include <QPointer>
#include <QTimer>

Q_DECLARE_LOGGING_CATEGORY(PFDECO)

namespace PlasmaFusion
{

namespace
{
QPointer<TabletMode> s_self;
constexpr int s_maxRetries = 5;
constexpr int s_retryDelay = 1000; // ms; KWin registers the object during start-up

QString service()
{
    return QStringLiteral("org.kde.KWin");
}
QString path()
{
    return QStringLiteral("/org/kde/KWin");
}
QString interface()
{
    return QStringLiteral("org.kde.KWin.TabletModeManager");
}
} // namespace

TabletMode *TabletMode::self()
{
    if (!s_self) {
        s_self = new TabletMode(QCoreApplication::instance());
    }
    return s_self;
}

TabletMode::TabletMode(QObject *parent)
    : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        return;
    }
    // Any sender: only KWin's TabletModeManager emits this signal on this path and interface.
    // Naming the service would make QtDBus look up its owner with a blocking call.
    bus.connect(QString(), path(), interface(), QStringLiteral("tabletModeChanged"), this, SLOT(onTabletModeChanged(bool)));
    requestInitialValue();
}

void TabletMode::requestInitialValue()
{
    QDBusMessage message = QDBusMessage::createMethodCall(service(), path(), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    message << interface() << QStringLiteral("tabletMode");
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, &TabletMode::onInitialValue);
}

void TabletMode::onInitialValue(QDBusPendingCallWatcher *watcher)
{
    watcher->deleteLater();
    if (m_signalSeen) {
        return;
    }
    const QDBusPendingReply<QDBusVariant> reply = *watcher;
    if (reply.isError()) {
        qCDebug(PFDECO) << "tablet mode: no initial value yet:" << reply.error().message();
        if (m_retries++ < s_maxRetries) {
            QTimer::singleShot(s_retryDelay, this, &TabletMode::requestInitialValue);
        }
        return;
    }
    setTablet(reply.value().variant().toBool());
}

void TabletMode::onTabletModeChanged(bool tablet)
{
    m_signalSeen = true;
    setTablet(tablet);
}

void TabletMode::setTablet(bool tablet)
{
    if (tablet == m_tablet) {
        return;
    }
    m_tablet = tablet;
    qCDebug(PFDECO) << "tablet mode" << tablet;
    Q_EMIT tabletChanged(tablet);
}

} // namespace PlasmaFusion

#include "moc_tabletmode.cpp"
