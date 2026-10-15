// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "quicklook.h"
#include "thumbnails.h"

#include <KApplicationTrader>
#include <KFileItem>
#include <KFormat>
#include <KIO/DirectorySizeJob>
#include <KIO/JobUiDelegateFactory>
#include <KIO/OpenUrlJob>
#include <KIO/PreviewJob>
#include <KLocalizedString>

#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocale>
#include <QMimeDatabase>
#include <QPixmap>
#include <QStringDecoder>

namespace
{
// A text file is a binary one when its start holds a NUL byte (what file(1) and editors go by).
bool looksBinary(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return false;
    }
    return file.read(8192).contains('\0');
}

bool isImage(const QMimeType &mime)
{
    if (mime.name().startsWith(QLatin1String("image/"))) {
        return true;
    }
    // Image formats with another MIME type (Krita's, for one) that a Qt image plugin reads.
    const QList<QByteArray> readable = QImageReader::supportedMimeTypes();
    return readable.contains(mime.name().toLatin1());
}
}

QuickLookItem::QuickLookItem(const QString &path, QObject *parent)
    : QObject(parent)
    , m_path(QFileInfo(path).absoluteFilePath())
{
    const QFileInfo info(m_path);
    if (!info.exists()) {
        m_kind = QStringLiteral("missing");
        m_iconName = QStringLiteral("dialog-question");
        m_typeName = i18nc("@info a file that was selected is gone", "Not found");
        return;
    }
    const QMimeDatabase db;
    // By name and content, as Dolphin shows the type.
    const QMimeType mime = db.mimeTypeForFile(info);
    m_mimeType = mime.name();
    m_typeName = mime.comment();
    m_iconName = mime.iconName();
    m_modified = info.lastModified();
    if (info.isDir()) {
        m_kind = QStringLiteral("folder");
        m_iconName = QStringLiteral("folder");
    } else {
        m_size = info.size();
        if (m_mimeType == QLatin1String("application/pdf")) {
            m_kind = QStringLiteral("pdf");
        } else if (isImage(mime)) {
            QImageReader reader(m_path);
            if (reader.canRead()) {
                m_imageSize = reader.size();
                m_kind = reader.imageCount() > 1 ? QStringLiteral("animation") : QStringLiteral("image");
            } else {
                m_kind = QStringLiteral("file");
            }
        } else if (m_mimeType.startsWith(QLatin1String("audio/"))) {
            m_kind = QStringLiteral("audio");
        } else if (m_mimeType.startsWith(QLatin1String("video/"))) {
            m_kind = QStringLiteral("video");
        } else if (mime.inherits(QStringLiteral("text/plain")) && !looksBinary(m_path)) {
            m_kind = QStringLiteral("text");
        } else {
            m_kind = QStringLiteral("file");
        }
    }
    if (const KService::Ptr service = KApplicationTrader::preferredService(m_mimeType)) {
        m_openWithName = service->name();
    }
}

QuickLookItem::~QuickLookItem()
{
    if (!m_thumbnailId.isEmpty()) {
        Thumbnails::remove(m_thumbnailId);
    }
}

QUrl QuickLookItem::url() const
{
    return QUrl::fromLocalFile(m_path);
}

QString QuickLookItem::path() const
{
    return m_path;
}

QString QuickLookItem::name() const
{
    return QFileInfo(m_path).fileName();
}

QString QuickLookItem::kind() const
{
    return m_kind;
}

QString QuickLookItem::mimeType() const
{
    return m_mimeType;
}

QString QuickLookItem::typeName() const
{
    return m_typeName;
}

QString QuickLookItem::iconName() const
{
    return m_iconName;
}

QSize QuickLookItem::imageSize() const
{
    return m_imageSize;
}

QString QuickLookItem::details() const
{
    if (m_kind == QLatin1String("missing")) {
        return i18nc("@info", "%1 is no longer there", m_path);
    }
    QStringList parts{m_typeName};
    if (!m_folderSummary.isEmpty()) {
        parts << m_folderSummary;
    }
    if (m_imageSize.isValid()) {
        parts << i18nc("@info image width × height in pixels", "%1 × %2", m_imageSize.width(), m_imageSize.height());
    }
    if (m_size >= 0) {
        parts << KFormat().formatByteSize(m_size);
    }
    if (m_modified.isValid()) {
        parts << i18nc("@info %1 date and time", "Modified %1", QLocale().toString(m_modified, QLocale::ShortFormat));
    }
    parts.removeAll(QString());
    return parts.join(QStringLiteral(" · "));
}

QString QuickLookItem::text() const
{
    return m_text;
}

bool QuickLookItem::textTruncated() const
{
    return m_textTruncated;
}

QUrl QuickLookItem::thumbnail() const
{
    return m_thumbnail;
}

bool QuickLookItem::thumbnailDone() const
{
    return m_thumbnailDone;
}

QString QuickLookItem::openWithName() const
{
    return m_openWithName;
}

void QuickLookItem::load()
{
    if (m_loaded) {
        return;
    }
    m_loaded = true;
    if (m_kind == QLatin1String("text")) {
        loadText();
        m_thumbnailDone = true;
    } else if (m_kind == QLatin1String("folder")) {
        loadFolder();
        m_thumbnailDone = true;
    } else if (m_kind == QLatin1String("file") || m_kind == QLatin1String("audio")) {
        // Any other file: what Dolphin shows for it (a page of a document, an archive's icon...);
        // a song: its cover.
        loadThumbnail();
    } else {
        m_thumbnailDone = true;
    }
}

void QuickLookItem::requestThumbnail()
{
    if (m_kind == QLatin1String("missing") || m_thumbnailRequested) {
        return;
    }
    m_thumbnailDone = false;
    Q_EMIT thumbnailChanged();
    loadThumbnail();
}

void QuickLookItem::loadText()
{
    QFile file(m_path);
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    QByteArray data = file.read(TextLimit);
    m_textTruncated = file.size() > TextLimit;
    if (m_textTruncated) {
        // End at a line break, not inside a character or a line.
        const qsizetype lineEnd = data.lastIndexOf('\n');
        if (lineEnd > 0) {
            data.truncate(lineEnd + 1);
        }
    }
    // Stateful: a character the limit cut (one long line) stays in the decoder's state and is left
    // out, without an error.
    QStringDecoder utf8(QStringDecoder::Utf8);
    QString text = utf8.decode(data);
    if (utf8.hasError()) {
        // Not UTF-8: the old 8-bit files are Latin-1 most of the time.
        text = QString::fromLatin1(data);
    }
    m_text = text;
    Q_EMIT textChanged();
}

void QuickLookItem::loadFolder()
{
    const QDir dir(m_path);
    const auto entries = dir.entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System).count();
    m_folderSummary = i18ncp("@info items directly in a folder", "%1 item", "%1 items", entries);
    Q_EMIT detailsChanged();
    // The size of everything below it, which can take a while.
    auto *job = KIO::directorySize(url());
    m_job = job;
    connect(job, &KJob::result, this, [this, job, entries] {
        if (!job->error()) {
            m_folderSummary = i18ncp("@info items directly in a folder", "%1 item", "%1 items", entries) + QStringLiteral(" · ")
                + i18nc("@info total size of a folder", "%1 in all", KFormat().formatByteSize(job->totalSize()));
            Q_EMIT detailsChanged();
        }
    });
}

void QuickLookItem::loadThumbnail()
{
    m_thumbnailRequested = true;
    const KFileItemList items{KFileItem(url(), m_mimeType)};
    const QStringList plugins = KIO::PreviewJob::availablePlugins();
    auto *job = new KIO::PreviewJob(items, QSize(512, 512), &plugins);
    job->setScaleType(KIO::PreviewJob::ScaledAndCached);
    m_job = job;
    connect(job, &KIO::PreviewJob::gotPreview, this, [this](const KFileItem &, const QPixmap &preview) {
        if (!m_thumbnailId.isEmpty()) {
            Thumbnails::remove(m_thumbnailId);
        }
        m_thumbnailId = Thumbnails::add(preview.toImage());
        m_thumbnail = QUrl(QStringLiteral("image://quicklook-thumbnail/") + m_thumbnailId);
    });
    connect(job, &KJob::result, this, [this] {
        m_thumbnailDone = true;
        Q_EMIT thumbnailChanged();
    });
    job->start();
}

QuickLookSession::QuickLookSession(QObject *parent)
    : QObject(parent)
{
}

bool QuickLookSession::setFiles(const QStringList &files, const QString &workingDirectory)
{
    QStringList paths;
    for (const QString &file : files) {
        const QUrl url = QUrl::fromUserInput(file, workingDirectory, QUrl::AssumeLocalFile);
        // Local files only: a remote one would have to be fetched first.
        if (url.isLocalFile()) {
            paths << QFileInfo(url.toLocalFile()).absoluteFilePath();
        }
    }
    // Nothing to show (remote files only): the preview stays as it is.
    if (paths.isEmpty()) {
        return true;
    }
    if (!m_items.isEmpty() && paths == this->paths()) {
        return false;
    }
    qDeleteAll(m_items);
    m_items.clear();
    for (const QString &path : std::as_const(paths)) {
        m_items << new QuickLookItem(path, this);
    }
    m_index = -1;
    Q_EMIT filesChanged();
    setIndex(m_items.isEmpty() ? -1 : 0);
    return true;
}

int QuickLookSession::count() const
{
    return m_items.count();
}

int QuickLookSession::index() const
{
    return m_index;
}

QuickLookItem *QuickLookSession::current() const
{
    return m_index >= 0 ? m_items.at(m_index) : nullptr;
}

QStringList QuickLookSession::paths() const
{
    QStringList result;
    for (const QuickLookItem *item : m_items) {
        result << item->path();
    }
    return result;
}

void QuickLookSession::next()
{
    if (m_items.count() > 1) {
        setIndex((m_index + 1) % m_items.count());
    }
}

void QuickLookSession::previous()
{
    if (m_items.count() > 1) {
        setIndex((m_index + m_items.count() - 1) % m_items.count());
    }
}

void QuickLookSession::openCurrent()
{
    QuickLookItem *item = current();
    if (!item || item->kind() == QLatin1String("missing")) {
        return;
    }
    auto *job = new KIO::OpenUrlJob(item->url(), item->mimeType());
    job->setUiDelegate(KIO::createDefaultJobUiDelegate(KJobUiDelegate::AutoHandlingEnabled, nullptr));
    // The preview ends once the application is started (ending it before would end the job).
    connect(job, &KJob::result, this, &QuickLookSession::closeRequested);
    job->start();
}

void QuickLookSession::writeReport(const QString &file, const QVariantList &entries)
{
    QFile out(file);
    if (out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        out.write(QJsonDocument(QJsonArray::fromVariantList(entries)).toJson());
    }
}

QString QuickLookSession::clipboardText() const
{
    return QGuiApplication::clipboard()->text();
}

void QuickLookSession::setIndex(int index)
{
    m_index = index;
    if (QuickLookItem *item = current()) {
        item->load();
    }
    Q_EMIT currentChanged();
}
