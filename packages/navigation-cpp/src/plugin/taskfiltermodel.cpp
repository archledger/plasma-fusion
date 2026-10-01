// SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
// SPDX-FileCopyrightText: 2024 Devin Lin <devin@kde.org>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "taskfiltermodel.h"

// KWin
#include <activities.h>
#include <config-kwin.h>
#include <core/output.h>
#include <core/outputbackend.h>
#include <virtualdesktops.h>
#include <workspace.h>

namespace KWin
{

FusionTaskFilterModel::FusionTaskFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setSortRole(FusionTaskModel::LastActivatedRole);

    // Don't auto-sort, because this model is loaded at runtime during the task switcher
    // -> We don't want to re-sort while the task switcher is open
    setDynamicSortFilter(false);
}

FusionTaskModel *FusionTaskFilterModel::windowModel() const
{
    return m_taskModel;
}

void FusionTaskFilterModel::setWindowModel(FusionTaskModel *taskModel)
{
    if (taskModel == m_taskModel) {
        return;
    }
    m_taskModel = taskModel;
    setSourceModel(m_taskModel);
    Q_EMIT windowModelChanged();

    // Sort after source model is set
    sort(0);
}

QString FusionTaskFilterModel::screenName() const
{
    return m_output ? m_output->name() : QString();
}

void FusionTaskFilterModel::setScreenName(const QString &screen)
{
    LogicalOutput *output = workspace()->findOutput(screen);
    if (m_output != output) {
        // Plasma Fusion: Qt 6.11 deprecates invalidateFilter()
        beginFilterChange();
        m_output = output;
        endFilterChange(QSortFilterProxyModel::Direction::Rows);
        Q_EMIT screenNameChanged();
    }
}

bool FusionTaskFilterModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    if (!m_taskModel) {
        return false;
    }
    const QModelIndex index = m_taskModel->index(sourceRow, 0, sourceParent);
    if (!index.isValid()) {
        return false;
    }
    const QVariant data = index.data();
    if (!data.isValid()) {
        // an invalid QVariant is valid data
        return true;
    }

    Window *window = qvariant_cast<Window *>(data);
    if (!window || !window->isClient()) {
        return false;
    }

#if KWIN_BUILD_ACTIVITIES 
    // Filter by same activity
    auto activity = Workspace::self()->activities()->current();
    if (!window->isOnActivity(activity)) {
        return false;
    }
#endif

    // Filter by same desktop
    auto desktop = VirtualDesktopManager::self()->currentDesktop();
    if (!window->isOnDesktop(desktop)) {
        return false;
    }

    // Filter by same screen
    if (window->output() != m_output) {
        return false;
    }

    if (window->isDock()) {
        return false;
    }
    if (window->isDesktop()) {
        return false;
    }
    if (window->isNotification()) {
        return false;
    }
    if (window->isCriticalNotification()) {
        return false;
    }
    if (window->skipSwitcher()) {
        return false;
    }

    // Plasma Fusion: never the on-screen keyboard's panel (a 0x0 utility window once it was shown;
    // KWin's Overview drew it as a zero-size texture), pop-ups, OSDs, other zero-size windows or the
    // shell's own surfaces (the launcher sheet and the other Fusion sheets are plasmashell windows).
    if (window->isInputMethod() || window->isPopupWindow() || window->isOnScreenDisplay() || window->isAppletPopup()) {
        return false;
    }
    if (window->frameGeometry().isEmpty()) {
        return false;
    }
    const QString resourceClass = window->resourceClass();
    if (resourceClass == QLatin1String("plasmashell") || resourceClass == QLatin1String("org.kde.plasmashell")) {
        return false;
    }

    return true;
}

bool FusionTaskFilterModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    qint64 leftLastActivated = qvariant_cast<qint64>(left.data(FusionTaskModel::LastActivatedRole));
    qint64 rightLastActivated = qvariant_cast<qint64>(right.data(FusionTaskModel::LastActivatedRole));

    // Sort order: oldest -> newest
    // - For ties: alphabetically

    if (leftLastActivated != rightLastActivated) {
        return leftLastActivated > rightLastActivated;
    } else {
        // If leftLastActivated == rightLastActivated, sort alphabetically by window title
        Window *leftWindow = qvariant_cast<Window *>(left.data(FusionTaskModel::WindowRole));
        Window *rightWindow = qvariant_cast<Window *>(right.data(FusionTaskModel::WindowRole));

        if (!leftWindow || !rightWindow) {
            return true;
        }

        return leftWindow->caption() < rightWindow->caption();
    }
}

} // namespace KWin
