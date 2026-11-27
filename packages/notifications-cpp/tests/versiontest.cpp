/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QCoreApplication>
#include <QString>
#include <QStringList>
#include <QTest>

#include "../src/bannertriageversion.h"

// The version rule of the banner keyboard triage: it is offered only while the running Plasma is
// the one this copy of the applet was built from. The rows are built from the version of the
// build, so that they stay right when the copy is built from another one.
class BannerTriageVersionTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void available_data()
    {
        QTest::addColumn<QString>("running");
        QTest::addColumn<bool>("available");

        const QString built = QStringLiteral(PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION);
        QTest::newRow("the version it was built from") << built << true;
        QTest::newRow("a newer patch version") << withPatch(built, 1) << false;
        QTest::newRow("an older patch version") << withPatch(built, -1) << false;
        QTest::newRow("the next series") << withSeries(built, 1) << false;
        QTest::newRow("the previous series") << withSeries(built, -1) << false;
        QTest::newRow("a beta of the next series") << withSeries(built, 1, 80) << false;
        QTest::newRow("a longer number that begins with it") << built + QStringLiteral("0") << false;
        QTest::newRow("a fourth part") << built + QStringLiteral(".1") << false;
        QTest::newRow("a distribution's release of it") << built + QStringLiteral("-1.fc44") << false;
        QTest::newRow("a leading v") << QStringLiteral("v") + built << false;
        QTest::newRow("a leading space") << QStringLiteral(" ") + built << false;
        QTest::newRow("a trailing space") << built + QStringLiteral(" ") << false;
        QTest::newRow("nothing was reported") << QString() << false;
    }

    void available()
    {
        QFETCH(QString, running);
        QFETCH(bool, available);
        QCOMPARE(PlasmaFusion::bannerTriageAvailable(running, QStringLiteral(PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION)), available);
    }

    // Outside plasmashell the application version is whatever the process says.
    void theRunningVersionIsReadAtRunTime()
    {
        QCoreApplication::setApplicationVersion(QStringLiteral(PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION));
        QVERIFY(PlasmaFusion::bannerTriageAvailable());
        QCoreApplication::setApplicationVersion(withPatch(QStringLiteral(PF_NOTIFICATIONS_PLASMA_SOURCE_VERSION), 1));
        QVERIFY(!PlasmaFusion::bannerTriageAvailable());
    }

private:
    // VERSION with its last part moved by DELTA: "6.8.3" and 1 give "6.8.4".
    static QString withPatch(const QString &version, int delta)
    {
        QStringList parts = version.split(QLatin1Char('.'));
        parts.last() = QString::number(parts.last().toInt() + delta);
        return parts.join(QLatin1Char('.'));
    }

    // VERSION with its second part moved by DELTA, and its last part set to PATCH (0 unless given):
    // "6.8.3" and 1 give "6.9.0".
    static QString withSeries(const QString &version, int delta, int patch = 0)
    {
        QStringList parts = version.split(QLatin1Char('.'));
        parts[1] = QString::number(parts.at(1).toInt() + delta);
        parts.last() = QString::number(patch);
        return parts.join(QLatin1Char('.'));
    }
};

QTEST_GUILESS_MAIN(BannerTriageVersionTest)

#include "versiontest.moc"
