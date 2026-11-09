// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "capabilities.h"

#include <QTest>

#include <limits>

class NavigationCapabilityTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void missingEffect()
    {
        QVERIFY(!KWin::fusionSupportsOffscreenOpacity(nullptr));
    }

    void offscreenOpacity_data()
    {
        QTest::addColumn<QVariant>("version");
        QTest::addColumn<bool>("supported");

        QTest::newRow("missing") << QVariant() << false;
        QTest::newRow("zero") << QVariant(0) << false;
        QTest::newRow("negative") << QVariant(-1) << false;
        QTest::newRow("version-one") << QVariant(1) << true;
        QTest::newRow("future-version") << QVariant(2) << true;
        QTest::newRow("maximum-version") << QVariant(std::numeric_limits<int>::max()) << true;
        QTest::newRow("boolean") << QVariant(true) << false;
        QTest::newRow("string") << QVariant(QStringLiteral("1")) << false;
        QTest::newRow("floating-point") << QVariant(1.0) << false;
        QTest::newRow("wide-integer") << QVariant::fromValue<qlonglong>(1) << false;
    }

    void offscreenOpacity()
    {
        QFETCH(QVariant, version);
        QFETCH(bool, supported);

        QObject effect;
        if (version.isValid()) {
            effect.setProperty("plasmaFusionOffscreenOpacityVersion", version);
        }
        QCOMPARE(KWin::fusionSupportsOffscreenOpacity(&effect), supported);
    }
};

QTEST_GUILESS_MAIN(NavigationCapabilityTest)

#include "capabilities_test.moc"
