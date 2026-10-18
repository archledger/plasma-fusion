// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "area.h"
#include "capture.h"

#include <QTest>
#include <QVariantMap>

#include <csignal>
#include <thread>
#include <unistd.h>

using namespace Qt::StringLiterals;

// KWin's raw picture through a real pipe (small pictures written at once, and a large one written
// slowly in small pieces, as a pipe may hand it over) and the box's arithmetic.
class CoreTest : public QObject
{
    Q_OBJECT

    static QVariantMap meta(int width, int height, qsizetype stride, QImage::Format format, qreal scale)
    {
        return {{u"type"_s, u"raw"_s}, {u"width"_s, width}, {u"height"_s, height}, {u"stride"_s, stride}, {u"format"_s, uint(format)}, {u"scale"_s, scale}};
    }
    // The bytes written to a pipe, then read back as KWin's answer META describes them.
    static QImage through(const QByteArray &bytes, const QVariantMap &meta)
    {
        int fds[2];
        if (pipe(fds) != 0) {
            return {};
        }
        const auto written = write(fds[1], bytes.constData(), bytes.size());
        ::close(fds[1]);
        if (written != bytes.size()) {
            ::close(fds[0]);
            return {};
        }
        return readRawImage(fds[0], meta);
    }

private Q_SLOTS:
    void readsRows()
    {
        // 3 x 2 ARGB32 with 4 bytes of padding per row, as a stride above the row gives it.
        QByteArray bytes;
        const QList<QRgb> pixels{0xff112233, 0xff445566, 0xff778899, 0xffaabbcc, 0xffddeeff, 0xff000000};
        for (int y = 0; y < 2; ++y) {
            for (int x = 0; x < 3; ++x) {
                const QRgb p = pixels[y * 3 + x];
                bytes.append(reinterpret_cast<const char *>(&p), 4);
            }
            bytes.append(4, '\0');
        }
        const QImage image = through(bytes, meta(3, 2, 16, QImage::Format_ARGB32, 1.75));
        QVERIFY(!image.isNull());
        QCOMPARE(image.size(), QSize(3, 2));
        QCOMPARE(image.devicePixelRatio(), 1.75);
        QCOMPARE(image.pixel(0, 0), pixels[0]);
        QCOMPARE(image.pixel(2, 1), pixels[5]);
    }
    void readsASlowWriter()
    {
        // Rows of 20 KiB (above QIODevice's 16 KiB read chunk) with padding, written by another
        // thread in pieces of 1000 bytes with pauses: each read() of the pipe returns a piece, and
        // every row must still arrive whole.
        const int width = 5120;
        const int height = 3;
        const qsizetype stride = width * 4 + 16;
        QByteArray bytes(stride * height, '\0');
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                const QRgb p = qRgb(x & 0xff, x >> 8, y);
                memcpy(bytes.data() + y * stride + x * 4, &p, 4);
            }
        }
        // A reader that stops early must fail the case, not end the test with SIGPIPE.
        std::signal(SIGPIPE, SIG_IGN);
        int fds[2];
        QCOMPARE(pipe(fds), 0);
        std::thread writer([fd = fds[1], &bytes] {
            for (qsizetype at = 0; at < bytes.size(); at += 1000) {
                const auto written = write(fd, bytes.constData() + at, qMin<qsizetype>(1000, bytes.size() - at));
                Q_UNUSED(written)
                usleep(200);
            }
            ::close(fd);
        });
        const QImage image = readRawImage(fds[0], meta(width, height, stride, QImage::Format_ARGB32, 1.0));
        writer.join();
        QVERIFY(!image.isNull());
        QCOMPARE(image.size(), QSize(width, height));
        QCOMPARE(image.pixel(0, 0), qRgb(0, 0, 0));
        QCOMPARE(image.pixel(4097, 1), qRgb(1, 16, 1));
        QCOMPARE(image.pixel(width - 1, height - 1), qRgb(0xff, 19, 2));
    }
    void refusesDoubt()
    {
        const QByteArray full(3 * 2 * 4, '\x7f');
        QVERIFY(through(full.left(10), meta(3, 2, 12, QImage::Format_ARGB32, 1)).isNull()); // short read
        QVERIFY(through(full, meta(3, 2, 8, QImage::Format_ARGB32, 1)).isNull()); // stride under a row
        QVERIFY(through(full, meta(3, 2, 12, QImage::Format_Invalid, 1)).isNull());
        QVERIFY(through(full, meta(3, 2, 12, QImage::Format(QImage::NImageFormats), 1)).isNull());
        QVERIFY(through(full, meta(0, 2, 12, QImage::Format_ARGB32, 1)).isNull());
        QVariantMap png = meta(3, 2, 12, QImage::Format_ARGB32, 1);
        png[u"type"_s] = u"png"_s;
        QVERIFY(through(full, png).isNull());
        // No scale (KWin before version 4): a ratio of 1.
        QVariantMap old = meta(3, 2, 12, QImage::Format_ARGB32, 1);
        old.remove(u"scale"_s);
        QCOMPARE(through(full, old).devicePixelRatio(), 1.0);
    }
    void nativeArea_data()
    {
        QTest::addColumn<QRectF>("box");
        QTest::addColumn<qreal>("dpr");
        QTest::addColumn<QRect>("expected");
        QTest::newRow("scale 1") << QRectF(100, 50, 200, 30) << 1.0 << QRect(100, 50, 200, 30);
        QTest::newRow("scale 2") << QRectF(100, 50, 200, 30) << 2.0 << QRect(200, 100, 400, 60);
        // 1.75: every pixel the box touches (outward), as the board's 1.75 test ran.
        QTest::newRow("scale 1.75") << QRectF(10.3, 20.6, 100.1, 30.2) << 1.75 << QRect(18, 36, 176, 53);
        QTest::newRow("past the edge") << QRectF(1600, 1000, 200, 100) << 1.75 << QRect(2800, 1750, 80, 50);
    }
    void nativeArea()
    {
        QFETCH(QRectF, box);
        QFETCH(qreal, dpr);
        QFETCH(QRect, expected);
        QCOMPARE(::nativeArea(box, dpr, QRect(0, 0, 2880, 1800)), expected);
    }
};

QTEST_GUILESS_MAIN(CoreTest)
#include "coretest.moc"
