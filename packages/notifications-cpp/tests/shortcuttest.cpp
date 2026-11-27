/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QAction>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusReply>
#include <QObject>
#include <QString>
#include <QTest>

#include <algorithm>

#include <KGlobalAccel>

#include "../src/globalshortcuts.h"

// The "Focus notification banner" shortcut through GlobalShortcuts itself. tests/versiontest.cpp
// covers the version rule alone; this covers the code that applies it: the action exists only while
// the running Plasma is the one this copy was built from, and the stock shortcuts are as they were.
// It runs only on the private session bus its driver makes (run-shortcut-test.sh): the class
// registers its actions with the global shortcut daemon, and on the bus of a real desktop it would
// reach the desktop's own shortcut settings.
class FocusShortcutTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        // The driver's mark, and no global shortcut daemon on the bus: a test binary run by hand on
        // a desktop has neither assurance, and stops here before anything is registered.
        QVERIFY2(qEnvironmentVariableIsSet("PF_SHORTCUT_TEST_BUS"), "not on a bus made by tests/run-shortcut-test.sh: this test registers global shortcuts");
        QDBusConnectionInterface *bus = QDBusConnection::sessionBus().interface();
        QVERIFY2(bus, "no session bus");
        const QDBusReply<QStringList> names = bus->registeredServiceNames();
        QVERIFY2(names.isValid(), qPrintable(names.error().message()));
        QVERIFY2(!names.value().contains(QStringLiteral("org.kde.kglobalaccel")), "the session bus has a global shortcut daemon on it");
    }

    void existsAtTheVersionTheCopyWasBuiltFrom()
    {
        QCoreApplication::setApplicationVersion(QStringLiteral(PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION));
        GlobalShortcuts shortcuts;
        QAction *focus = focusAction(shortcuts);
        QVERIFY(focus);
        QVERIFY(shortcuts.bannerTriageAvailable());
        QVERIFY2(stockActionsAreThere(shortcuts), "a stock shortcut is gone at the built-from version");
        // It ships unassigned: no shortcut, and no default one that is set. (Without the daemon
        // KGlobalAccel keeps a default of one empty key sequence, as it does for the stock actions.)
        QVERIFY(focus->shortcut().isEmpty());
        QVERIFY(KGlobalAccel::self()->shortcut(focus).isEmpty());
        const QList<QKeySequence> defaults = KGlobalAccel::self()->defaultShortcut(focus);
        QVERIFY(std::all_of(defaults.cbegin(), defaults.cend(), [](const QKeySequence &key) {
            return key.isEmpty();
        }));
    }

    void doesNotExistAtAnyOtherVersion()
    {
        QCoreApplication::setApplicationVersion(QStringLiteral("0.0.1"));
        GlobalShortcuts shortcuts;
        QVERIFY(!focusAction(shortcuts));
        QVERIFY(!shortcuts.bannerTriageAvailable());
        QVERIFY2(stockActionsAreThere(shortcuts), "a stock shortcut is gone at another version");
    }

private:
    // The stock two shortcuts are QAction children of GlobalShortcuts; the focus action would be
    // the third.
    static QAction *focusAction(GlobalShortcuts &shortcuts)
    {
        return actionNamed(shortcuts, QStringLiteral("focus notification banner"));
    }

    static QAction *actionNamed(GlobalShortcuts &shortcuts, const QString &name)
    {
        const auto actions = shortcuts.findChildren<QAction *>();
        const auto found = std::find_if(actions.cbegin(), actions.cend(), [&name](QAction *action) {
            return action->objectName() == name;
        });
        return found == actions.cend() ? nullptr : *found;
    }

    static bool stockActionsAreThere(GlobalShortcuts &shortcuts)
    {
        // A plain value: a QVERIFY in a helper would only leave the helper, and the test would pass.
        return actionNamed(shortcuts, QStringLiteral("toggle do not disturb")) && actionNamed(shortcuts, QStringLiteral("clear history"));
    }
};

QTEST_MAIN(FocusShortcutTest)

#include "shortcuttest.moc"
