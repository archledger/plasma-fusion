/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QCoreApplication>
#include <QString>
#include <QTest>

#include "../src/bannertriageversion.h"

// The version rule of the banner keyboard triage: it is offered only while the running Plasma is
// the one this copy of the applet was built from.
class BannerTriageVersionTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void available_data()
    {
        QTest::addColumn<QString>("running");
        QTest::addColumn<bool>("available");

        QTest::newRow("the version it was built from") << QStringLiteral("6.8.3") << true;
        QTest::newRow("a newer patch version") << QStringLiteral("6.8.4") << false;
        QTest::newRow("an older patch version") << QStringLiteral("6.8.2") << false;
        QTest::newRow("the next series") << QStringLiteral("6.9.0") << false;
        QTest::newRow("a beta of the next series") << QStringLiteral("6.8.80") << false;
        QTest::newRow("nothing was reported") << QString() << false;
    }

    void available()
    {
        QFETCH(QString, running);
        QFETCH(bool, available);
        QCOMPARE(PlasmaFusion::bannerTriageAvailable(running, QStringLiteral("6.8.3")), available);
    }

    // Outside plasmashell the application version is whatever the process says.
    void theRunningVersionIsReadAtRunTime()
    {
        QCoreApplication::setApplicationVersion(QStringLiteral("6.8.3"));
        QVERIFY(PlasmaFusion::bannerTriageAvailable());
        QCoreApplication::setApplicationVersion(QStringLiteral("6.8.4"));
        QVERIFY(!PlasmaFusion::bannerTriageAvailable());
    }
};

QTEST_GUILESS_MAIN(BannerTriageVersionTest)

#include "versiontest.moc"
