/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QFileInfo>
#include <QJsonArray>
#include <QJsonObject>
#include <QPluginLoader>
#include <QString>
#include <QTest>

#include <algorithm>

// The copy must be the stock applet under another path: it loads, and it says what the stock
// metadata says. PLUGIN_PATH is the plugin as this build produced it.
class NotificationPluginTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void loadsAsTheStockApplet()
    {
        QPluginLoader loader(QStringLiteral(PLUGIN_PATH));
        QVERIFY2(loader.load(), qPrintable(loader.errorString()));

        // The loader wraps the plugin's own JSON as "MetaData" beside the interface it was built for.
        QCOMPARE(loader.metaData().value(QStringLiteral("IID")).toString(),
                 QStringLiteral("org.kde.KPluginFactory"));
        const QJsonObject metadata = loader.metaData().value(QStringLiteral("MetaData")).toObject();
        QCOMPARE(metadata.value(QStringLiteral("X-Plasma-API-Minimum-Version")).toString(),
                 QStringLiteral("6.0"));
        QCOMPARE(metadata.value(QStringLiteral("KPlugin")).toObject().value(QStringLiteral("Name")).toString(),
                 QStringLiteral("Notifications"));

        const QJsonArray provides = metadata.value(QStringLiteral("X-Plasma-Provides")).toArray();
        const auto isStockApplet = [](const QJsonValue &value) {
            return value.toString() == QLatin1String("org.kde.plasma.notifications");
        };
        QVERIFY(std::any_of(provides.begin(), provides.end(), isStockApplet));
    }

    // Plasma takes an applet's id from its file name when the metadata does not state one, which
    // is the case for the stock metadata: only this name lets the copy stand in for the stock applet.
    void isNamedAfterTheStockPlugin()
    {
        QCOMPARE(QFileInfo(QStringLiteral(PLUGIN_PATH)).completeBaseName(),
                 QStringLiteral("org.kde.plasma.notifications"));
    }
};

QTEST_GUILESS_MAIN(NotificationPluginTest)

#include "plugintest.moc"
