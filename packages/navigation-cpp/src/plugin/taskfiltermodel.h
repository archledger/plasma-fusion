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

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;

Q_SIGNALS:
    void screenNameChanged();
    void windowModelChanged();

private:
    FusionTaskModel *m_taskModel = nullptr;
    QPointer<LogicalOutput> m_output;
};

} // namespace KWin
