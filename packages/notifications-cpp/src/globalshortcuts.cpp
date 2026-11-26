/*
    SPDX-FileCopyrightText: 2019 Kai Uwe Broulik <kde@broulik.de>
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

// Plasma Fusion changes in this file are marked "Plasma Fusion": the banner keyboard triage of
// SPEC-notification-triage.md.

#include "globalshortcuts.h"

// Plasma Fusion
#include "bannertriageversion.h"
#include "notifications_debug.h"

#include <QAction>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>

#include <KLocalizedString>

#include <KGlobalAccel>

GlobalShortcuts::GlobalShortcuts(QObject *parent)
    : QObject(parent)
    , m_toggleDoNotDisturbAction(new QAction(this))
    , m_clearHistoryAction(new QAction(this))
    , m_focusBannerAction(nullptr) // Plasma Fusion
{
    m_toggleDoNotDisturbAction->setObjectName(QStringLiteral("toggle do not disturb"));
    m_toggleDoNotDisturbAction->setProperty("componentName", QStringLiteral("plasmashell"));
    m_toggleDoNotDisturbAction->setText(i18n("Toggle do not disturb"));
    m_toggleDoNotDisturbAction->setIcon(QIcon::fromTheme(QStringLiteral("notifications-disabled")));
    m_toggleDoNotDisturbAction->setShortcutContext(Qt::ApplicationShortcut);
    connect(m_toggleDoNotDisturbAction, &QAction::triggered, this, &GlobalShortcuts::toggleDoNotDisturbTriggered);

    KGlobalAccel::self()->setGlobalShortcut(m_toggleDoNotDisturbAction, QKeySequence());

    m_clearHistoryAction->setObjectName(QStringLiteral("clear history"));
    m_clearHistoryAction->setProperty("componentName", QStringLiteral("plasmashell"));
    m_clearHistoryAction->setText(i18nc("@action", "Clear Notification History"));
    m_clearHistoryAction->setIcon(QIcon::fromTheme(QStringLiteral("edit-clear-history")));
    m_clearHistoryAction->setShortcutContext(Qt::ApplicationShortcut);
    connect(m_clearHistoryAction, &QAction::triggered, this, &GlobalShortcuts::clearHistoryTriggered);

    KGlobalAccel::self()->setGlobalShortcut(m_clearHistoryAction, QKeySequence());

    // Plasma Fusion: the focus action exists only while the running Plasma is the one this copy was
    // built from; at any other version the stock shortcuts are all there is. It ships unassigned.
    if (bannerTriageAvailable()) {
        m_focusBannerAction = new QAction(this);
        m_focusBannerAction->setObjectName(QStringLiteral("focus notification banner"));
        m_focusBannerAction->setProperty("componentName", QStringLiteral("plasmashell"));
        m_focusBannerAction->setText(i18nc("@action", "Focus Notification Banner"));
        m_focusBannerAction->setIcon(QIcon::fromTheme(QStringLiteral("notifications")));
        m_focusBannerAction->setShortcutContext(Qt::ApplicationShortcut);
        connect(m_focusBannerAction, &QAction::triggered, this, &GlobalShortcuts::focusBannerTriggered);

        KGlobalAccel::self()->setGlobalShortcut(m_focusBannerAction, QKeySequence());
    }
    qCDebug(PLASMA_APPLET_NOTIFICATIONS_DEBUG) << "banner triage available:" << (m_focusBannerAction != nullptr) << "running"
                                               << QCoreApplication::applicationVersion() << "built" << PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION;
}

GlobalShortcuts::~GlobalShortcuts() = default;

// Plasma Fusion
bool GlobalShortcuts::bannerTriageAvailable() const
{
    return m_focusBannerAction != nullptr;
}

// Plasma Fusion
void GlobalShortcuts::reportTriage(const QString &step)
{
    qCDebug(PLASMA_APPLET_NOTIFICATIONS_DEBUG) << "banner triage" << step;
}

void GlobalShortcuts::showDoNotDisturbOsd(bool doNotDisturb) const
{
    QDBusMessage msg = QDBusMessage::createMethodCall( //
        QStringLiteral("org.kde.plasmashell"),
        QStringLiteral("/org/kde/osdService"),
        QStringLiteral("org.kde.osdService"),
        QStringLiteral("showText"));

    const QString iconName = doNotDisturb ? QStringLiteral("notifications-disabled") : QStringLiteral("notifications");
    const QString text = doNotDisturb ? i18nc("OSD popup, keep short", "Notifications Off") //
                                      : i18nc("OSD popup, keep short", "Notifications On");

    msg.setArguments({iconName, text});

    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

void GlobalShortcuts::showNotificationsHistoryCleaned() const
{
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.plasmashell"),
                                                      QStringLiteral("/org/kde/osdService"),
                                                      QStringLiteral("org.kde.osdService"),
                                                      QStringLiteral("showText"));

    const QString iconName = QStringLiteral("edit-clear-history");
    const QString text = i18nc("@label OSD popup, keep short", "Notification history cleared");

    msg.setArguments({iconName, text});

    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

#include "moc_globalshortcuts.cpp"
