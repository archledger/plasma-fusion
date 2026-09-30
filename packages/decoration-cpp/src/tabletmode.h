/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <QObject>

class QDBusPendingCallWatcher;

namespace PlasmaFusion
{

// KWin's tablet mode (org.kde.KWin.TabletModeManager on /org/kde/KWin), read over D-Bus without
// ever blocking: the decoration runs inside KWin, so a synchronous call to KWin would deadlock.
// The initial value comes from an asynchronous Properties.Get, changes from the tabletModeChanged
// signal (TABLET.md 4.9; not Kirigami's TabletModeWatcher, which reads its value once at start and
// can stay stale, TABLET.md F3).
//
// One instance serves every decoration of the process. It is created with the first decoration
// and lives as long as the application (a child of it), so windows decorated later, for example
// when tablet mode ends and title bars come back, start from the current value instead of waiting
// for a new reply. KWin never unloads a decoration plugin (DecorationBridge keeps the library).
class TabletMode : public QObject
{
    Q_OBJECT

public:
    static TabletMode *self();

    bool isTablet() const
    {
        return m_tablet;
    }

Q_SIGNALS:
    void tabletChanged(bool tablet);

private Q_SLOTS:
    void onTabletModeChanged(bool tablet);

private:
    explicit TabletMode(QObject *parent);
    void requestInitialValue();
    void onInitialValue(QDBusPendingCallWatcher *watcher);
    void setTablet(bool tablet);

    bool m_tablet = false;
    bool m_signalSeen = false; // a signal is newer than any Get reply still in flight
    int m_retries = 0;
};

} // namespace PlasmaFusion
