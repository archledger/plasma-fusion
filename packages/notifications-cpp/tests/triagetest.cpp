/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QMetaObject>
#include <QObject>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QString>
#include <QTest>
#include <QUrl>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

#include <initializer_list>
#include <memory>

// The rules of the banner keyboard triage, src/global/BannerTriage.js, through the test holder
// triagetest loads (tests/triage-holder.qml). Each rule is a pure function of its arguments, so
// the cases are the specification's rules stated as data.
class BannerTriageTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        QQmlComponent component(&m_engine, QUrl::fromLocalFile(QStringLiteral(TRIAGE_HOLDER_QML)));
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        m_holder.reset(component.create());
        QVERIFY(m_holder);

        // The three states a banner's interaction moves through.
        QCOMPARE(m_holder->property("idle").toString(), QStringLiteral("idle"));
        QCOMPARE(m_holder->property("requested").toString(), QStringLiteral("requested"));
        QCOMPARE(m_holder->property("active").toString(), QStringLiteral("active"));
    }

    void newestBanner_data()
    {
        QTest::addColumn<QVariantList>("banners");
        QTest::addColumn<int>("expected");

        QTest::newRow("no banner") << QVariantList() << -1;
        QTest::newRow("one banner") << banners({{1000, true, true}}) << 0;
        QTest::newRow("the newest wins, whatever the order") << banners({{3000, true, true}, {1000, true, true}, {2000, true, true}}) << 0;
        QTest::newRow("a newer banner that is not visible is skipped") << banners({{1000, true, true}, {4000, false, true}}) << 0;
        QTest::newRow("a newer banner that is not eligible is skipped") << banners({{1000, true, true}, {4000, true, false}}) << 0;
        QTest::newRow("equal times take the later one") << banners({{7000, true, true}, {7000, true, true}}) << 1;
        QTest::newRow("only banners that cannot be taken") << banners({{5000, false, true}, {4000, true, false}}) << -1;
    }

    void newestBanner()
    {
        QFETCH(QVariantList, banners);
        QFETCH(int, expected);
        QVariant result;
        QVERIFY(call(&result, "newestBannerIndex", {banners}));
        QCOMPARE(result.toInt(), expected);
    }

    void transition_data()
    {
        QTest::addColumn<QString>("state");
        QTest::addColumn<QString>("event");
        QTest::addColumn<QString>("expectedState");
        QTest::addColumn<bool>("expectedRestore");

        const QString idle = QStringLiteral("idle");
        const QString requested = QStringLiteral("requested");
        const QString active = QStringLiteral("active");

        QTest::newRow("a request starts the interaction") << idle << QStringLiteral("request") << requested << false;
        QTest::newRow("focus granted") << requested << QStringLiteral("granted") << active << false;
        QTest::newRow("the shortcut again while focused changes nothing") << active << QStringLiteral("request") << active << false;
        QTest::newRow("the shortcut again while pending changes nothing") << requested << QStringLiteral("request") << requested << false;
        QTest::newRow("focus without a request changes nothing") << idle << QStringLiteral("granted") << idle << false;

        QTest::newRow("focus lost while pending") << requested << QStringLiteral("lost") << idle << false;
        QTest::newRow("banner gone while pending") << requested << QStringLiteral("hidden") << idle << false;
        QTest::newRow("focus never granted") << requested << QStringLiteral("not-granted") << idle << false;
        QTest::newRow("focus lost while focused") << active << QStringLiteral("lost") << idle << false;
        QTest::newRow("banner gone while focused") << active << QStringLiteral("hidden") << idle << false;

        QTest::newRow("replaced while focused gives focus back") << active << QStringLiteral("replaced") << idle << true;
        QTest::newRow("replaced while pending") << requested << QStringLiteral("replaced") << idle << false;
        QTest::newRow("replaced after the interaction ended") << idle << QStringLiteral("replaced") << idle << false;
        QTest::newRow("an unknown event changes nothing") << active << QStringLiteral("unknown") << active << false;
    }

    void transition()
    {
        QFETCH(QString, state);
        QFETCH(QString, event);
        QFETCH(QString, expectedState);
        QFETCH(bool, expectedRestore);

        QVariant newState;
        QVERIFY(call(&newState, "transitionState", {state, event}));
        QCOMPARE(newState.toString(), expectedState);

        QVariant restores;
        QVERIFY(call(&restores, "transitionRestores", {state, event}));
        QCOMPARE(restores.toBool(), expectedRestore);
    }

    void escapeAction_data()
    {
        QTest::addColumn<bool>("interactionActive");
        QTest::addColumn<bool>("replying");
        QTest::addColumn<bool>("spent");
        QTest::addColumn<bool>("autoRepeat");
        QTest::addColumn<QString>("expected");

        QTest::newRow("Escape on the focused banner dismisses it") << true << false << false << false << QStringLiteral("dismiss");
        QTest::newRow("Escape in the reply field is not ours") << true << true << false << false << QString();
        QTest::newRow("Escape outside the interaction is not ours") << false << false << false << false << QString();
        QTest::newRow("a second Escape does not expire the banner again") << true << false << true << false << QStringLiteral("consume");
        QTest::newRow("a held Escape does not repeat") << true << false << false << true << QStringLiteral("consume");
    }

    void escapeAction()
    {
        QFETCH(bool, interactionActive);
        QFETCH(bool, replying);
        QFETCH(bool, spent);
        QFETCH(bool, autoRepeat);
        QFETCH(QString, expected);
        QVariant result;
        QVERIFY(call(&result, "escapeAction", {interactionActive, replying, spent, autoRepeat}));
        QCOMPARE(result.toString(), expected);
    }

    void enterAction_data()
    {
        QTest::addColumn<bool>("interactionActive");
        QTest::addColumn<bool>("hasDefaultAction");
        QTest::addColumn<bool>("spent");
        QTest::addColumn<bool>("autoRepeat");
        QTest::addColumn<QString>("expected");

        QTest::newRow("Enter with a default action activates it") << true << true << false << false << QStringLiteral("activate");
        QTest::newRow("Enter without a default action does nothing") << true << false << false << false << QStringLiteral("consume");
        QTest::newRow("a second Enter does not activate again") << true << true << true << false << QStringLiteral("consume");
        QTest::newRow("a held Enter does not repeat") << true << true << false << true << QStringLiteral("consume");
        QTest::newRow("Enter outside the interaction is not ours") << false << true << false << false << QString();
    }

    void enterAction()
    {
        QFETCH(bool, interactionActive);
        QFETCH(bool, hasDefaultAction);
        QFETCH(bool, spent);
        QFETCH(bool, autoRepeat);
        QFETCH(QString, expected);
        QVariant result;
        QVERIFY(call(&result, "enterAction", {interactionActive, hasDefaultAction, spent, autoRepeat}));
        QCOMPARE(result.toString(), expected);
    }

private:
    // What the applet knows about each banner: when it was created, whether it shows, whether it
    // may be taken.
    static QVariantList banners(const std::initializer_list<std::initializer_list<QVariant>> &rows)
    {
        QVariantList list;
        for (const auto &row : rows) {
            const QVariantList values(row);
            list.append(
                QVariantMap{{QStringLiteral("created"), values.at(0)}, {QStringLiteral("visible"), values.at(1)}, {QStringLiteral("eligible"), values.at(2)}});
        }
        return list;
    }

    bool call(QVariant *result, const char *method, std::initializer_list<QVariant> arguments)
    {
        const QVariantList args(arguments);
        QObject *holder = m_holder.get();
        switch (args.size()) {
        case 0:
            return QMetaObject::invokeMethod(holder, method, Q_RETURN_ARG(QVariant, *result));
        case 1:
            return QMetaObject::invokeMethod(holder, method, Q_RETURN_ARG(QVariant, *result), Q_ARG(QVariant, args.at(0)));
        case 2:
            return QMetaObject::invokeMethod(holder, method, Q_RETURN_ARG(QVariant, *result), Q_ARG(QVariant, args.at(0)), Q_ARG(QVariant, args.at(1)));
        case 4:
            return QMetaObject::invokeMethod(holder,
                                             method,
                                             Q_RETURN_ARG(QVariant, *result),
                                             Q_ARG(QVariant, args.at(0)),
                                             Q_ARG(QVariant, args.at(1)),
                                             Q_ARG(QVariant, args.at(2)),
                                             Q_ARG(QVariant, args.at(3)));
        default:
            return false;
        }
    }

    QQmlEngine m_engine;
    std::unique_ptr<QObject> m_holder;
};

QTEST_GUILESS_MAIN(BannerTriageTest)

#include "triagetest.moc"
