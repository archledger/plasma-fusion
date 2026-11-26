/*
    SPDX-FileCopyrightText: 2019 Kai Uwe Broulik <kde@broulik.de>
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

// Plasma Fusion changes in this file are marked "Plasma Fusion": the banner keyboard triage of
// SPEC-notification-triage.md.

#pragma once

#include <QObject>
#include <qqmlregistration.h>

class QAction;

class GlobalShortcuts : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit GlobalShortcuts(QObject *parent = nullptr);
    ~GlobalShortcuts() override;

    Q_INVOKABLE void showDoNotDisturbOsd(bool doNotDisturb) const;
    Q_INVOKABLE void showNotificationsHistoryCleaned() const;

    // Plasma Fusion: banner keyboard triage. True while the running Plasma is the one this copy was
    // built from; the focus action exists only then.
    Q_PROPERTY(bool bannerTriageAvailable READ bannerTriageAvailable CONSTANT)
    bool bannerTriageAvailable() const;

    // Plasma Fusion: the applet's QML reports its triage steps through the applet's debug category.
    Q_INVOKABLE void reportTriage(const QString &step);

Q_SIGNALS:
    void toggleDoNotDisturbTriggered();
    void clearHistoryTriggered();
    // Plasma Fusion: the "Focus notification banner" shortcut was pressed.
    void focusBannerTriggered();

private:
    QAction *m_toggleDoNotDisturbAction;
    QAction *m_clearHistoryAction;
    // Plasma Fusion: null while the triage is not available.
    QAction *m_focusBannerAction;
};
