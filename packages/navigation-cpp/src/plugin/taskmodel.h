// SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
// SPDX-FileCopyrightText: 2024 Devin Lin <devin@kde.org>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <window.h>

#include <QAbstractListModel>
#include <QHash>
#include <QSortFilterProxyModel>
#include <QVariant>
#include <qqmlregistration.h>

namespace KWin
{

class FusionTaskModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")

public:
    enum Roles {
        WindowRole = Qt::UserRole + 1,
        OutputRole,
        DesktopRole,
        ActivityRole,
        LastActivatedRole,
        // Plasma Fusion: the other app of a split pair (FusionTaskFilterModel serves it)
        PartnerRole
    };

    explicit FusionTaskModel(QObject *parent = nullptr);

    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;

    // Plasma Fusion (SPLIT.md item 4): split pairs, two apps seen side by side (the split on
    // screen when an app is activated or tiled) or minimized by the switcher as one card. Minimized
    // apps keep their tiles, so the tiles alone do not tell which apps were a pair. A pair ends
    // when one of the two closes or leaves its side (untiled, maximized, the other side), or when
    // the switcher shows them on cards of their own.
    void rememberSplitPair(Window *window, Window *partner);
    // the other app of the window's pair while the two are still side by side, or null
    Window *splitPair(Window *window) const;
    void forgetSplitPair(Window *window);

private:
    void markRoleChanged(Window *window, int role);
    void checkSplitPair(Window *window);
    void noteVisibleSplit();

    void handleWindowAdded(Window *window);
    void handleWindowRemoved(Window *window);
    void setupWindowConnections(Window *window);

    void handleActiveWindowChanged();

    // qint64 - Last activated timestamp
    QList<std::pair<Window *, qint64>> m_windows;

    QHash<Window *, Window *> m_splitPairs; // both ways
};

}; // namespace KWin
