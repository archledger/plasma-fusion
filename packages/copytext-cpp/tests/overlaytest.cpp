// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include <KLocalizedQmlContext>

#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QTest>

using namespace Qt::StringLiterals;

// The picture under the veil: one known colour.
static const QColor s_picture(0xf4, 0xf5, 0xf7);

class Picture : public QQuickImageProvider
{
public:
    Picture()
        : QQuickImageProvider(QQuickImageProvider::Image)
    {
    }
    QImage requestImage(const QString &, QSize *size, const QSize &) override
    {
        QImage image(1440, 900, QImage::Format_RGB32);
        image.fill(s_picture);
        if (size) {
            *size = image.size();
        }
        return image;
    }
};

// The overlay's QML offscreen against the CopyText board: the hint 46 px from the top, centred,
// 32 px high, gone once the drag starts; the veil (rgba 8 11 22 0.45) outside the box, the picture
// inside, the accent edge (#5b9dff) 2 px around it; a drag chooses its box, Esc, a click and a box
// under 4 px cancel.
class OverlayTest : public QObject
{
    Q_OBJECT

    QQmlEngine m_engine;
    std::unique_ptr<QQuickWindow> m_window;

    QQuickItem *item(const char *name) const
    {
        return m_window->findChild<QQuickItem *>(QString::fromLatin1(name));
    }
    QColor at(int x, int y) const
    {
        return m_window->grabWindow().pixelColor(x, y);
    }
    static bool near(const QColor &a, const QColor &b)
    {
        return qAbs(a.red() - b.red()) <= 3 && qAbs(a.green() - b.green()) <= 3 && qAbs(a.blue() - b.blue()) <= 3;
    }

private Q_SLOTS:
    void initTestCase()
    {
        KLocalization::setupLocalizedContext(&m_engine);
        m_engine.addImageProvider(u"capture"_s, new Picture);
    }
    void init()
    {
        QQmlComponent component(&m_engine, QUrl::fromLocalFile(QStringLiteral(OVERLAY_QML)));
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        QObject *object = component.createWithInitialProperties({{u"screenName"_s, u"DP-1"_s}, {u"picture"_s, QUrl(u"image://capture/DP-1/1"_s)}});
        m_window.reset(qobject_cast<QQuickWindow *>(object));
        QVERIFY(m_window);
        m_window->resize(1440, 900);
        m_window->show();
        m_window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(m_window.get()));
    }
    void cleanup()
    {
        m_window.reset();
    }

    void hint()
    {
        QQuickItem *hint = item("hint");
        QVERIFY(hint);
        QVERIFY(hint->isVisible());
        QCOMPARE(hint->y(), 46.0);
        QCOMPARE(hint->height(), 32.0);
        QVERIFY2(qAbs(hint->x() + hint->width() / 2 - 720.0) <= 0.5,
                 qPrintable(u"hint x %1 width %2 window %3"_s.arg(hint->x()).arg(hint->width()).arg(m_window->width())));
        QVERIFY(!item("edge")->isVisible());
    }
    void veil()
    {
        // The veil over the picture everywhere while no box is drawn.
        const QColor veiled = at(700, 600);
        const QColor expected(qRound(0.55 * s_picture.red() + 0.45 * 8),
                              qRound(0.55 * s_picture.green() + 0.45 * 11),
                              qRound(0.55 * s_picture.blue() + 0.45 * 22));
        QVERIFY2(near(veiled, expected), qPrintable(veiled.name() + u" not "_s + expected.name()));
    }
    void dragChooses()
    {
        QSignalSpy chosen(m_window.get(), SIGNAL(chosen(QString, QRectF)));
        QTest::mousePress(m_window.get(), Qt::LeftButton, {}, QPoint(100, 120));
        QTest::mouseMove(m_window.get(), QPoint(250, 160));
        QTest::mouseMove(m_window.get(), QPoint(400, 220));
        // Drawing: the hint goes, the box is clear, its edge accent.
        QVERIFY(!item("hint")->isVisible());
        QVERIFY(item("edge")->isVisible());
        QVERIFY2(near(at(250, 170), s_picture), qPrintable(at(250, 170).name()));
        QVERIFY2(near(at(99, 170), QColor(0x5b, 0x9d, 0xff)), qPrintable(at(99, 170).name()));
        QTest::mouseRelease(m_window.get(), Qt::LeftButton, {}, QPoint(400, 220));
        QCOMPARE(chosen.size(), 1);
        QCOMPARE(chosen.at(0).at(0).toString(), u"DP-1"_s);
        QCOMPARE(chosen.at(0).at(1).toRectF(), QRectF(100, 120, 300, 100));
    }
    void dragUpwardsChooses()
    {
        QSignalSpy chosen(m_window.get(), SIGNAL(chosen(QString, QRectF)));
        QTest::mousePress(m_window.get(), Qt::LeftButton, {}, QPoint(400, 220));
        QTest::mouseMove(m_window.get(), QPoint(100, 120));
        QTest::mouseRelease(m_window.get(), Qt::LeftButton, {}, QPoint(100, 120));
        QCOMPARE(chosen.size(), 1);
        QCOMPARE(chosen.at(0).at(1).toRectF(), QRectF(100, 120, 300, 100));
    }
    void cancels_data()
    {
        QTest::addColumn<QString>("how");
        QTest::newRow("Esc") << u"esc"_s;
        QTest::newRow("a click") << u"click"_s;
        QTest::newRow("a box under 4 px") << u"tiny"_s;
    }
    void cancels()
    {
        QFETCH(QString, how);
        QSignalSpy chosen(m_window.get(), SIGNAL(chosen(QString, QRectF)));
        QSignalSpy cancelled(m_window.get(), SIGNAL(cancelled()));
        if (how == u"esc"_s) {
            QTest::keyClick(m_window.get(), Qt::Key_Escape);
        } else {
            QTest::mousePress(m_window.get(), Qt::LeftButton, {}, QPoint(300, 300));
            if (how == u"tiny"_s) {
                QTest::mouseMove(m_window.get(), QPoint(302, 340));
            }
            QTest::mouseRelease(m_window.get(), Qt::LeftButton, {}, how == u"tiny"_s ? QPoint(302, 340) : QPoint(300, 300));
        }
        QCOMPARE(cancelled.size(), 1);
        QCOMPARE(chosen.size(), 0);
    }
};

QTEST_MAIN(OverlayTest)
#include "overlaytest.moc"
