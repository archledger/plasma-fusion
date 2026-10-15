// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

// The model of Quick Look (quicklook.h) on sample files written here: which viewer each kind of
// file gets, the text read from text files (encodings, the 512 KB limit, binary files that look
// like text), a folder's count and size, and the session's files (a second Space, the arrow keys).

#include "quicklook.h"

#include <QDir>
#include <QFile>
#include <QImage>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

class QuickLookTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void kinds_data();
    void kinds();
    void imageDetails();
    void text();
    void latin1();
    void truncated();
    void folder();
    void missing();
    void session();
    void relativeAndRemote();

private:
    QString write(const QString &name, const QByteArray &data);
    QTemporaryDir m_dir;
};

QString QuickLookTest::write(const QString &name, const QByteArray &data)
{
    const QString path = m_dir.filePath(name);
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size()) {
        qFatal("cannot write %s", qPrintable(path));
    }
    return path;
}

void QuickLookTest::initTestCase()
{
    QStandardPaths::setTestModeEnabled(true);
    QVERIFY(m_dir.isValid());
    QImage picture(40, 30, QImage::Format_RGB32);
    picture.fill(Qt::darkCyan);
    QVERIFY(picture.save(m_dir.filePath(QStringLiteral("picture.png"))));
    write(QStringLiteral("drawing.svg"),
          "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\"><rect width=\"16\" height=\"16\" fill=\"#3daee9\"/></svg>\n");
    write(QStringLiteral("notes.txt"), "Hello Plasma Fusion\nsecond line \xe2\x82\xac\n");
    write(QStringLiteral("script.py"), "print('hello')\n");
    write(QStringLiteral("data.json"), "{\"a\": 1}\n");
    write(QStringLiteral("binary.txt"), QByteArray("abc\0def", 7));
    write(QStringLiteral("document.pdf"), "%PDF-1.4\n%\xe2\xe3\xcf\xd3\n1 0 obj << >> endobj\ntrailer << >>\n%%EOF\n");
    write(QStringLiteral("sound.wav"), QByteArray("RIFF\x24\x00\x00\x00WAVEfmt ", 16) + QByteArray(28, '\0'));
    // An MP4 file's first box ("ftyp", brand mp42).
    write(QStringLiteral("clip.mp4"), QByteArray::fromHex("00000018667479706d703432000000006d70343269736f6d") + QByteArray(64, '\0'));
    write(QStringLiteral("archive.zip"), QByteArray("PK\x03\x04", 4) + QByteArray(60, '\0'));
    write(QStringLiteral("folder/a.txt"), "a\n");
    write(QStringLiteral("folder/b.txt"), "bb\n");
    write(QStringLiteral("folder/sub/c.txt"), "ccc\n");
}

void QuickLookTest::kinds_data()
{
    QTest::addColumn<QString>("name");
    QTest::addColumn<QString>("kind");
    QTest::newRow("PNG") << "picture.png" << "image";
    QTest::newRow("SVG") << "drawing.svg" << "image";
    QTest::newRow("text") << "notes.txt" << "text";
    QTest::newRow("Python") << "script.py" << "text";
    QTest::newRow("JSON") << "data.json" << "text";
    QTest::newRow("NUL in a .txt") << "binary.txt" << "file";
    QTest::newRow("PDF") << "document.pdf" << "pdf";
    QTest::newRow("WAV") << "sound.wav" << "audio";
    QTest::newRow("MP4") << "clip.mp4" << "video";
    QTest::newRow("ZIP") << "archive.zip" << "file";
    QTest::newRow("folder") << "folder" << "folder";
}

void QuickLookTest::kinds()
{
    QFETCH(QString, name);
    QFETCH(QString, kind);
    QuickLookItem item(m_dir.filePath(name));
    QCOMPARE(item.kind(), kind);
    QCOMPARE(item.name(), name);
    QVERIFY2(!item.typeName().isEmpty(), qPrintable(item.mimeType()));
}

void QuickLookTest::imageDetails()
{
    QuickLookItem item(m_dir.filePath(QStringLiteral("picture.png")));
    QCOMPARE(item.imageSize(), QSize(40, 30));
    QVERIFY2(item.details().contains(QStringLiteral("40 × 30")), qPrintable(item.details()));
    QVERIFY2(item.details().contains(QStringLiteral("Modified")), qPrintable(item.details()));
}

void QuickLookTest::text()
{
    QuickLookItem item(m_dir.filePath(QStringLiteral("notes.txt")));
    QCOMPARE(item.text(), QString());
    item.load();
    QCOMPARE(item.text(), QStringLiteral("Hello Plasma Fusion\nsecond line €\n"));
    QVERIFY(!item.textTruncated());
}

void QuickLookTest::latin1()
{
    const QString path = write(QStringLiteral("latin1.txt"), "caf\xe9 cr\xe8me\n");
    QuickLookItem item(path);
    QCOMPARE(item.kind(), QStringLiteral("text"));
    item.load();
    QCOMPARE(item.text(), QStringLiteral("café crème\n"));
}

void QuickLookTest::truncated()
{
    QByteArray data;
    const QByteArray line = QByteArray(99, 'x') + '\n';
    while (data.size() <= QuickLookItem::TextLimit + 1000) {
        data += line;
    }
    QuickLookItem item(write(QStringLiteral("big.log"), data));
    QCOMPARE(item.kind(), QStringLiteral("text"));
    item.load();
    QVERIFY(item.textTruncated());
    QVERIFY(item.text().size() <= QuickLookItem::TextLimit);
    QVERIFY(item.text().size() > QuickLookItem::TextLimit - line.size());
    QVERIFY(item.text().endsWith(QLatin1Char('\n')));
}

void QuickLookTest::folder()
{
    QuickLookItem item(m_dir.filePath(QStringLiteral("folder")));
    QSignalSpy changed(&item, &QuickLookItem::detailsChanged);
    item.load();
    QVERIFY2(item.details().contains(QStringLiteral("3 items")), qPrintable(item.details()));
    // KIO adds the size of everything below: 2 + 3 + 4 bytes.
    QTRY_VERIFY_WITH_TIMEOUT(item.details().contains(QStringLiteral("in all")), 10000);
    QVERIFY2(item.details().contains(QStringLiteral("9 B in all")), qPrintable(item.details()));
}

void QuickLookTest::missing()
{
    QuickLookItem item(m_dir.filePath(QStringLiteral("gone.txt")));
    QCOMPARE(item.kind(), QStringLiteral("missing"));
    QVERIFY2(item.details().contains(QStringLiteral("no longer there")), qPrintable(item.details()));
}

void QuickLookTest::session()
{
    QuickLookSession session;
    QSignalSpy current(&session, &QuickLookSession::currentChanged);
    const QStringList two{m_dir.filePath(QStringLiteral("picture.png")), m_dir.filePath(QStringLiteral("notes.txt"))};
    QVERIFY(session.setFiles(two, m_dir.path()));
    QCOMPARE(session.count(), 2);
    QCOMPARE(session.index(), 0);
    QCOMPARE(session.current()->name(), QStringLiteral("picture.png"));
    // Space again on the same selection: the caller closes the preview.
    QVERIFY(!session.setFiles(two, m_dir.path()));
    session.next();
    QCOMPARE(session.index(), 1);
    // The text is read when the file is shown.
    QCOMPARE(session.current()->text(), QStringLiteral("Hello Plasma Fusion\nsecond line €\n"));
    session.next();
    QCOMPARE(session.index(), 0);
    session.previous();
    QCOMPARE(session.index(), 1);
    // Another selection: shown from its first file.
    QVERIFY(session.setFiles({m_dir.filePath(QStringLiteral("script.py"))}, m_dir.path()));
    QCOMPARE(session.count(), 1);
    QCOMPARE(session.index(), 0);
    session.next();
    QCOMPARE(session.index(), 0);
    QVERIFY(current.count() >= 5);
}

void QuickLookTest::relativeAndRemote()
{
    QuickLookSession session;
    QVERIFY(session.setFiles({QStringLiteral("notes.txt"),
                              QUrl::fromLocalFile(m_dir.filePath(QStringLiteral("script.py"))).toString(),
                              QStringLiteral("https://example.org/remote.txt")},
                             m_dir.path()));
    QCOMPARE(session.paths(), (QStringList{m_dir.filePath(QStringLiteral("notes.txt")), m_dir.filePath(QStringLiteral("script.py"))}));
    // Remote files only: nothing changes.
    QVERIFY(session.setFiles({QStringLiteral("sftp://host/file.txt")}, m_dir.path()));
    QCOMPARE(session.count(), 2);
}

QTEST_MAIN(QuickLookTest)
#include "quicklooktest.moc"
