// SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
// SPDX-FileCopyrightText: 2024 Devin Lin <devin@kde.org>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "taskmodel.h"

#include <window.h>

#include <QAbstractListModel>
#include <QHash>
#include <QQmlEngine>
#include <QSet>
#include <QSortFilterProxyModel>
#include <QVariant>

namespace KWin
{

class FusionTaskFilterModel : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(KWin::FusionTaskModel *windowModel READ windowModel WRITE setWindowModel NOTIFY windowModelChanged)
    Q_PROPERTY(QString screenName READ screenName WRITE setScreenName NOTIFY screenNameChanged)
    QML_ELEMENT

public:
    explicit FusionTaskFilterModel(QObject *parent = nullptr);

    FusionTaskModel *windowModel() const;
    void setWindowModel(KWin::FusionTaskModel *taskModel);

    QString screenName() const;
    void setScreenName(const QString &screenName);

    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;

    // Plasma Fusion: the row of the card that shows this window (a split pair's card shows two), or -1.
    Q_INVOKABLE int rowOf(KWin::Window *window) const;
    // Plasma Fusion: closes the card's app, both apps of a split pair.
    Q_INVOKABLE void closeTask(KWin::Window *window);

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;

Q_SIGNALS:
    void screenNameChanged();
    void windowModelChanged();

private:
    bool isTask(Window *window) const;
    void updatePairs();
    void addPair(Window *window, Window *partner);
    qint64 lastActivated(Window *window) const;
    void handleWindowRemoved(Window *window);

    FusionTaskModel *m_taskModel = nullptr;
    QPointer<LogicalOutput> m_output;

    // Plasma Fusion (SPLIT.md item 4): a split pair is one card, found when the switcher opens.
    QHash<Window *, Window *> m_partners; // both ways
    QSet<Window *> m_hidden; // the pair's other app, left out of the list
    QSet<Window *> m_closing; // closed from a card: its pair's card goes with it
};

} // namespace KWin
