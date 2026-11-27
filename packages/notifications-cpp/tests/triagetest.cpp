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
        QTest::addColumn<bool>("replyStarted");
        QTest::addColumn<QString>("expectedState");
        QTest::addColumn<bool>("expectedRestore");

        const QString idle = QStringLiteral("idle");
        const QString requested = QStringLiteral("requested");
        const QString active = QStringLiteral("active");

        QTest::newRow("a request starts the interaction") << idle << QStringLiteral("request") << false << requested << false;
        QTest::newRow("focus granted") << requested << QStringLiteral("granted") << false << active << false;
        QTest::newRow("the shortcut again while focused changes nothing") << active << QStringLiteral("request") << false << active << false;
        QTest::newRow("the shortcut again while pending changes nothing") << requested << QStringLiteral("request") << false << requested << false;
        QTest::newRow("focus without a request changes nothing") << idle << QStringLiteral("granted") << false << idle << false;

        QTest::newRow("focus lost while pending") << requested << QStringLiteral("lost") << false << idle << false;
        QTest::newRow("banner gone while pending") << requested << QStringLiteral("hidden") << false << idle << false;
        QTest::newRow("focus never granted") << requested << QStringLiteral("not-granted") << false << idle << false;
        QTest::newRow("focus lost while focused") << active << QStringLiteral("lost") << false << idle << false;
        QTest::newRow("banner gone while focused") << active << QStringLiteral("hidden") << false << idle << false;
        QTest::newRow("focus lost while a reply is being typed") << active << QStringLiteral("lost") << true << idle << false;

        QTest::newRow("replaced while focused gives focus back") << active << QStringLiteral("replaced") << false << idle << true;
        QTest::newRow("replaced while a reply is being typed leaves the keyboard with the banner")
            << active << QStringLiteral("replaced") << true << idle << false;
        QTest::newRow("replaced while pending") << requested << QStringLiteral("replaced") << false << idle << false;
        QTest::newRow("replaced after the interaction ended") << idle << QStringLiteral("replaced") << false << idle << false;
        QTest::newRow("an unknown event changes nothing") << active << QStringLiteral("unknown") << false << active << false;
    }

    void transition()
    {
        QFETCH(QString, state);
        QFETCH(QString, event);
        QFETCH(bool, replyStarted);
        QFETCH(QString, expectedState);
        QFETCH(bool, expectedRestore);

        QVariant newState;
        QVERIFY(call(&newState, "transitionState", {state, event, replyStarted}));
        QCOMPARE(newState.toString(), expectedState);

        QVariant restores;
        QVERIFY(call(&restores, "transitionRestores", {state, event, replyStarted}));
        QCOMPARE(restores.toBool(), expectedRestore);
    }

    // The window recorded when the shortcut is pressed. An invalid QVariant is no record at all.
    void recordedWindow_data()
    {
        QTest::addColumn<bool>("takenBannerActive");
        QTest::addColumn<QVariant>("activeTask");
        QTest::addColumn<QVariant>("earlierRecord");
        QTest::addColumn<QVariant>("expected");

        const QVariant windowA = QStringLiteral("window A");
        const QVariant windowB = QStringLiteral("window B");
        QTest::newRow("the window that has the keyboard focus") << false << windowA << QVariant() << windowA;
        QTest::newRow("nothing active, nothing recorded before") << false << QVariant() << QVariant() << QVariant();
        QTest::newRow("a record of earlier gives way to the window that has the keyboard focus now") << false << windowB << windowA << windowB;
        QTest::newRow("nothing active: a record of earlier gives way to nothing") << false << QVariant() << windowA << QVariant();
        QTest::newRow("a banner taken before is the active window: the record stands") << true << QVariant() << windowA << windowA;
        QTest::newRow("  whatever task the model marks active beside it") << true << windowB << windowA << windowA;
        QTest::newRow("  and there was nothing to stand") << true << QVariant() << QVariant() << QVariant();
    }

    void recordedWindow()
    {
        QFETCH(bool, takenBannerActive);
        QFETCH(QVariant, activeTask);
        QFETCH(QVariant, earlierRecord);
        QFETCH(QVariant, expected);

        QVariant result;
        QVERIFY(call(&result, "recordedWindow", {takenBannerActive, activeTask, earlierRecord}));
        if (!expected.isValid()) {
            QVERIFY2(result.isNull() || !result.isValid(), "nothing should be recorded");
        } else {
            QCOMPARE(result.toString(), expected.toString());
        }
    }

    void escapeAction_data()
    {
        QTest::addColumn<bool>("interactionActive");
        QTest::addColumn<bool>("replyFieldFocused");
        QTest::addColumn<bool>("dismissed");
        QTest::addColumn<bool>("autoRepeat");
        QTest::addColumn<QString>("expected");

        QTest::newRow("Escape on the focused banner dismisses it") << true << false << false << false << QStringLiteral("dismiss");
        QTest::newRow("Escape with the keyboard focus in the reply field is not ours") << true << true << false << false << QString();
        QTest::newRow("Escape outside the interaction is not ours") << false << false << false << false << QString();
        QTest::newRow("a second Escape does not expire the banner again") << true << false << true << false << QStringLiteral("consume");
        QTest::newRow("a held Escape does not repeat") << true << false << false << true << QStringLiteral("consume");
    }

    void escapeAction()
    {
        QFETCH(bool, interactionActive);
        QFETCH(bool, replyFieldFocused);
        QFETCH(bool, dismissed);
        QFETCH(bool, autoRepeat);
        QFETCH(QString, expected);
        QVariant result;
        QVERIFY(call(&result, "escapeAction", {interactionActive, replyFieldFocused, dismissed, autoRepeat}));
        QCOMPARE(result.toString(), expected);
    }

    void enterAction_data()
    {
        QTest::addColumn<bool>("interactionActive");
        QTest::addColumn<bool>("focusOnContent");
        QTest::addColumn<bool>("hasDefaultAction");
        QTest::addColumn<bool>("autoRepeat");
        QTest::addColumn<QString>("expected");

        QTest::newRow("Enter with a default action activates it") << true << true << true << false << QStringLiteral("activate");
        QTest::newRow("Enter without a default action does nothing") << true << true << false << false << QStringLiteral("consume");
        QTest::newRow("a held Enter does not repeat the action") << true << true << true << true << QStringLiteral("consume");
        QTest::newRow("Enter outside the interaction is not ours") << false << true << true << false << QString();
        QTest::newRow("Enter on a control inside the banner is that control's own") << true << false << true << false << QString();
        QTest::newRow("  also when there is no default action") << true << false << false << false << QString();
    }

    void enterAction()
    {
        QFETCH(bool, interactionActive);
        QFETCH(bool, focusOnContent);
        QFETCH(bool, hasDefaultAction);
        QFETCH(bool, autoRepeat);
        QFETCH(QString, expected);
        QVariant result;
        QVERIFY(call(&result, "enterAction", {interactionActive, focusOnContent, hasDefaultAction, autoRepeat}));
        QCOMPARE(result.toString(), expected);
    }

    void activeTaskPath_data()
    {
        QTest::addColumn<QVariantList>("tasks");
        QTest::addColumn<QVariantList>("expected");

        const QVariantList noWindows;
        QTest::newRow("no task at all") << QVariantList() << QVariantList();
        QTest::newRow("no task is active") << QVariantList{task(false, noWindows)} << QVariantList();
        QTest::newRow("a window of its own") << QVariantList{task(true, noWindows)} << QVariantList{0.0};
        QTest::newRow("after an idle one") << QVariantList{task(false, noWindows), task(true, noWindows)} << QVariantList{1.0};
        QTest::newRow("a window in a group, not the group") << QVariantList{task(true, {window(false, 0), window(true, 2)})} << QVariantList{0.0, 1.0};
        QTest::newRow("a group's only window") << QVariantList{task(true, {window(true, 1)})} << QVariantList{0.0, 0.0};
        QTest::newRow("of two windows marked active, the one higher in the stacking order")
            << QVariantList{task(true, {window(true, 3), window(true, 5)})} << QVariantList{0.0, 1.0};
        QTest::newRow("  the other way round") << QVariantList{task(true, {window(true, 5), window(true, 3)})} << QVariantList{0.0, 0.0};
        QTest::newRow("a group marked active with no window of its own marked active restores nothing")
            << QVariantList{task(true, {window(false, 1)})} << QVariantList();
    }

    void activeTaskPath()
    {
        QFETCH(QVariantList, tasks);
        QFETCH(QVariantList, expected);
        QVariant result;
        QVERIFY(call(&result, "activeTaskPath", {tasks}));
        if (expected.isEmpty()) {
            QVERIFY2(result.isNull() || !result.isValid(), "nothing should be restored");
        } else {
            QCOMPARE(result.toList(), expected);
        }
    }

    // The walk on real items: the editor in the reply field and the field itself are in it; the
    // button next to it, the content and no item at all are not.
    void inReplyFieldOnItems()
    {
        QObject *holder = m_holder.get();
        QObject *content = holder->property("walkContentItem").value<QObject *>();
        QVERIFY(content);
        for (const char *name : {"walkEditorItem", "walkFieldItem"}) {
            QObject *item = holder->property(name).value<QObject *>();
            QVERIFY(item);
            QVariant result;
            QVERIFY(call(&result, "inReplyField", {QVariant::fromValue(item), QVariant::fromValue(content)}));
            QVERIFY2(result.toBool(), name);
        }
        for (const char *name : {"walkButtonItem", "walkContentItem"}) {
            QObject *item = holder->property(name).value<QObject *>();
            QVERIFY(item);
            QVariant result;
            QVERIFY(call(&result, "inReplyField", {QVariant::fromValue(item), QVariant::fromValue(content)}));
            QVERIFY2(!result.toBool(), name);
        }
        QVariant result;
        QVERIFY(call(&result, "inReplyField", {QVariant(), QVariant::fromValue(content)}));
        QVERIFY(!result.toBool());
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

    // A window of a group, as the applet reads it: whether it is active, and its place in the
    // stacking order.
    static QVariantMap window(bool active, int stacking)
    {
        return QVariantMap{{QStringLiteral("active"), active}, {QStringLiteral("stacking"), stacking}};
    }

    // A task of the applet's task model: whether it is active, and the windows of its group.
    static QVariantMap task(bool active, const QVariantList &windows)
    {
        return QVariantMap{{QStringLiteral("active"), active}, {QStringLiteral("children"), windows}};
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
        case 3:
            return QMetaObject::invokeMethod(holder,
                                             method,
                                             Q_RETURN_ARG(QVariant, *result),
                                             Q_ARG(QVariant, args.at(0)),
                                             Q_ARG(QVariant, args.at(1)),
                                             Q_ARG(QVariant, args.at(2)));
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
