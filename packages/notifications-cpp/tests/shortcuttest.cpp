/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QAction>
#include <QCoreApplication>
#include <QObject>
#include <QString>
#include <QTest>

#include <algorithm>

#include "../src/globalshortcuts.h"

// The "Focus notification banner" shortcut through GlobalShortcuts itself. tests/versiontest.cpp
// covers the version rule alone; this covers the code that applies it: the action exists only while
// the running Plasma is the one this copy was built from.
class FocusShortcutTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void existsAtTheVersionTheCopyWasBuiltFrom()
    {
        QCoreApplication::setApplicationVersion(QStringLiteral(PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION));
        GlobalShortcuts shortcuts;
        QVERIFY(focusAction(shortcuts));
        QVERIFY(shortcuts.bannerTriageAvailable());
    }

    void doesNotExistAtAnyOtherVersion()
    {
        QCoreApplication::setApplicationVersion(QStringLiteral("0.0.1"));
        GlobalShortcuts shortcuts;
        QVERIFY(!focusAction(shortcuts));
        QVERIFY(!shortcuts.bannerTriageAvailable());
    }

private:
    // The stock two shortcuts are QAction children of GlobalShortcuts; the focus action would be the third.
    static QAction *focusAction(GlobalShortcuts &shortcuts)
    {
        const auto actions = shortcuts.findChildren<QAction *>();
        const auto found = std::find_if(actions.cbegin(), actions.cend(), [](QAction *action) {
            return action->objectName() == QStringLiteral("focus notification banner");
        });
        return found == actions.cend() ? nullptr : *found;
    }
};

QTEST_MAIN(FocusShortcutTest)

#include "shortcuttest.moc"
