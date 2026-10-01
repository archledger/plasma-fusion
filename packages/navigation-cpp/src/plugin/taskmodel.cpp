// SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
// SPDX-FileCopyrightText: 2024 Devin Lin <devin@kde.org>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "taskmodel.h"

// KWin
#include <core/output.h>
#include <virtualdesktops.h>
#include <workspace.h>

namespace KWin
{

FusionTaskModel::FusionTaskModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(workspace(), &Workspace::windowAdded, this, &FusionTaskModel::handleWindowAdded);
    connect(workspace(), &Workspace::windowRemoved, this, &FusionTaskModel::handleWindowRemoved);
    connect(workspace(), &Workspace::windowActivated, this, &FusionTaskModel::handleActiveWindowChanged);

    auto windows = workspace()->windows();
    const qint64 currentTime = QDateTime::currentMSecsSinceEpoch();

    for (Window *window : std::as_const(windows)) {
        m_windows.push_back({window, currentTime});
        setupWindowConnections(window);
    }
}

void FusionTaskModel::markRoleChanged(Window *window, int role)
{
    int windowIndex = -1;
    for (int i = 0; i < m_windows.size(); ++i) {
        if (m_windows[i].first == window) {
            windowIndex = i;
            break;
        }
    }
    const QModelIndex row = index(windowIndex, 0);
    Q_EMIT dataChanged(row, row, {role});
}

void FusionTaskModel::setupWindowConnections(Window *window)
{
    connect(window, &Window::desktopsChanged, this, [this, window]() {
        markRoleChanged(window, DesktopRole);
    });
    connect(window, &Window::outputChanged, this, [this, window]() {
        markRoleChanged(window, OutputRole);
    });
    connect(window, &Window::activitiesChanged, this, [this, window]() {
        markRoleChanged(window, ActivityRole);
    });
}

void FusionTaskModel::handleWindowAdded(Window *window)
{
    beginInsertRows(QModelIndex(), m_windows.count(), m_windows.count());
    const qint64 currentTime = QDateTime::currentMSecsSinceEpoch();
    m_windows.append({window, currentTime});
    endInsertRows();

    setupWindowConnections(window);
}

void FusionTaskModel::handleWindowRemoved(Window *window)
{
    int index = -1;
    for (int i = 0; i < m_windows.size(); ++i) {
        if (m_windows[i].first == window) {
            index = i;
            break;
        }
    }
    Q_ASSERT(index != -1);

    beginRemoveRows(QModelIndex(), index, index);
    m_windows.removeAt(index);
    endRemoveRows();
}

QHash<int, QByteArray> FusionTaskModel::roleNames() const
{
    return {
        {Qt::DisplayRole, QByteArrayLiteral("display")},
        {WindowRole, QByteArrayLiteral("window")},
        {OutputRole, QByteArrayLiteral("output")},
        {DesktopRole, QByteArrayLiteral("desktop")},
        {ActivityRole, QByteArrayLiteral("activity")},
    };
}

QVariant FusionTaskModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_windows.count()) {
        return QVariant();
    }

    Window *window = m_windows[index.row()].first;
    qint64 lastActivated = m_windows[index.row()].second;
    switch (role) {
    case Qt::DisplayRole:
    case WindowRole:
        return QVariant::fromValue(window);
    case OutputRole:
        return QVariant::fromValue(window->output());
    case DesktopRole:
        return QVariant::fromValue(window->desktops());
    case ActivityRole:
        return window->activities();
    case LastActivatedRole:
        return lastActivated;
    default:
        return QVariant();
    }
}

int FusionTaskModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_windows.count();
}

void FusionTaskModel::handleActiveWindowChanged()
{
    Window *window = workspace()->activeWindow();
    if (!window) {
        return;
    }

    const qint64 currentTime = QDateTime::currentMSecsSinceEpoch();
    for (int i = 0; i < m_windows.size(); ++i) {
        if (m_windows[i].first == window) {
            m_windows[i] = {window, currentTime};
            Q_EMIT dataChanged(index(i, 0), index(i, 0), {FusionTaskModel::LastActivatedRole});
        }
    }
}

} // namespace KWin
