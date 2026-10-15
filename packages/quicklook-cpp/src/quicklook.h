// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QDateTime>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QSize>
#include <QStringList>
#include <QUrl>

class KJob;

// One file of a preview: what it is (which viewer shows it) and the facts under it. The text of a
// text file, the size of a folder and the thumbnail of any other file are fetched only when the
// item is shown (load()).
class QuickLookItem : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl url READ url CONSTANT)
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(QString name READ name CONSTANT)
    // image, animation, pdf, text, audio, video, folder or file (no viewer of its own: its thumbnail
    // or icon), missing (gone since it was selected).
    Q_PROPERTY(QString kind READ kind CONSTANT)
    Q_PROPERTY(QString mimeType READ mimeType CONSTANT)
    Q_PROPERTY(QString typeName READ typeName CONSTANT)
    Q_PROPERTY(QString iconName READ iconName CONSTANT)
    Q_PROPERTY(QSize imageSize READ imageSize CONSTANT)
    // The line under the preview: type, size, modified, image size; a folder's item count and size.
    Q_PROPERTY(QString details READ details NOTIFY detailsChanged)
    Q_PROPERTY(QString text READ text NOTIFY textChanged)
    Q_PROPERTY(bool textTruncated READ textTruncated NOTIFY textChanged)
    // image://quicklook-thumbnail/... once KIO made one (kind "file"), else empty.
    Q_PROPERTY(QUrl thumbnail READ thumbnail NOTIFY thumbnailChanged)
    Q_PROPERTY(bool thumbnailDone READ thumbnailDone NOTIFY thumbnailChanged)
    // The application "Open" starts (the preferred one for the type), empty when there is none.
    Q_PROPERTY(QString openWithName READ openWithName CONSTANT)

public:
    // Text files: at most this much is read (a preview, not an editor).
    static constexpr qint64 TextLimit = 512 * 1024;

    explicit QuickLookItem(const QString &path, QObject *parent = nullptr);

    QUrl url() const;
    QString path() const;
    QString name() const;
    QString kind() const;
    QString mimeType() const;
    QString typeName() const;
    QString iconName() const;
    QSize imageSize() const;
    QString details() const;
    QString text() const;
    bool textTruncated() const;
    QUrl thumbnail() const;
    bool thumbnailDone() const;
    QString openWithName() const;

    // Fetches what showing the item needs (once).
    void load();

Q_SIGNALS:
    void detailsChanged();
    void textChanged();
    void thumbnailChanged();

private:
    void loadText();
    void loadFolder();
    void loadThumbnail();

    QString m_path;
    QString m_kind;
    QString m_mimeType;
    QString m_typeName;
    QString m_iconName;
    QString m_openWithName;
    QSize m_imageSize;
    qint64 m_size = -1;
    QDateTime m_modified;
    QString m_text;
    bool m_textTruncated = false;
    QString m_folderSummary;
    QUrl m_thumbnail;
    bool m_thumbnailDone = false;
    bool m_loaded = false;
    QPointer<KJob> m_job;
};

// The files of one preview, in the order they were given, and the one shown.
class QuickLookSession : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY filesChanged)
    Q_PROPERTY(int index READ index NOTIFY currentChanged)
    Q_PROPERTY(QuickLookItem *current READ current NOTIFY currentChanged)

public:
    explicit QuickLookSession(QObject *parent = nullptr);

    // Paths or file: URLs, relative ones to workingDirectory. Returns false when they are the files
    // shown already: a second Space on the same selection closes the preview.
    bool setFiles(const QStringList &files, const QString &workingDirectory);

    int count() const;
    int index() const;
    QuickLookItem *current() const;
    QStringList paths() const;

    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    // Opens the shown file in its application, then the preview closes.
    Q_INVOKABLE void openCurrent();
    // Test mode (--test-report): the JSON of the shown viewers, written at the end.
    Q_INVOKABLE void writeReport(const QString &file, const QVariantList &entries);

Q_SIGNALS:
    void filesChanged();
    void currentChanged();
    void closeRequested();

private:
    void setIndex(int index);

    QList<QuickLookItem *> m_items;
    int m_index = -1;
};
