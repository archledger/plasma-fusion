// SPDX-FileCopyrightText: 2021 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
// SPDX-FileCopyrightText: 2024 Devin Lin <devin@kde.org>
// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "taskfiltermodel.h"
#include "splitside.h"

// KWin
#include <activities.h>
#include <config-kwin.h>
#include <core/output.h>
#include <core/outputbackend.h>
#include <virtualdesktops.h>
#include <workspace.h>

#include <QTimer>

namespace KWin
{

FusionTaskFilterModel::FusionTaskFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setSortRole(FusionTaskModel::LastActivatedRole);

    // Don't auto-sort, because this model is loaded at runtime during the task switcher
    // -> We don't want to re-sort while the task switcher is open
    setDynamicSortFilter(false);

    connect(workspace(), &Workspace::windowRemoved, this, &FusionTaskFilterModel::handleWindowRemoved);
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
    updatePairs();
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
        updatePairs();
        endFilterChange(QSortFilterProxyModel::Direction::Rows);
        Q_EMIT screenNameChanged();
    }
}

QHash<int, QByteArray> FusionTaskFilterModel::roleNames() const
{
    QHash<int, QByteArray> names = QSortFilterProxyModel::roleNames();
    names.insert(FusionTaskModel::PartnerRole, QByteArrayLiteral("partner"));
    return names;
}

QVariant FusionTaskFilterModel::data(const QModelIndex &index, int role) const
{
    if (role == FusionTaskModel::PartnerRole) {
        Window *window = qvariant_cast<Window *>(QSortFilterProxyModel::data(index, FusionTaskModel::WindowRole));
        return QVariant::fromValue(m_partners.value(window));
    }
    return QSortFilterProxyModel::data(index, role);
}

int FusionTaskFilterModel::rowOf(Window *window) const
{
    if (!window) {
        return -1;
    }
    for (int row = 0; row < rowCount(); ++row) {
        Window *task = qvariant_cast<Window *>(data(index(row, 0), FusionTaskModel::WindowRole));
        if (task && (task == window || m_partners.value(task) == window)) {
            return row;
        }
    }
    return -1;
}

void FusionTaskFilterModel::closeTask(Window *window)
{
    if (!window) {
        return;
    }
    Window *partner = m_partners.value(window);
    for (Window *app : {window, partner}) {
        if (app && !app->isDeleted()) {
            m_closing.insert(app);
            app->closeWindow();
        }
    }
}

// Plasma Fusion: the window filter of Plasma Mobile's model, for the list and for the split pairs.
bool FusionTaskFilterModel::isTask(Window *window) const
{
    if (!window || window->isDeleted() || !window->isClient()) {
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
    return isTask(window) && !m_hidden.contains(window);
}

// Plasma Fusion (SPLIT.md item 4): two apps side by side are one card, as Android's Overview shows
// a split pair. Found once, when the switcher opens (before it minimizes the apps):
// - the apps shown, layer by layer: the topmost app and the app seen in the other half of its
//   split, then the same again under them (an older split under a newer one, or under an app);
// - then the pairs the task model remembers (seen side by side, or minimized by the switcher as
//   one card), both shown or both minimized: a split with an app between its two halves, and
//   minimized apps (they keep their tiles, so tiles alone would pair apps that were never side
//   by side).
// The more recently used app of a pair stands for it in the list (the higher one when both came
// up at once), the other is left out. An app on a card of its own is no longer part of a pair.
void FusionTaskFilterModel::updatePairs()
{
    m_partners.clear();
    m_hidden.clear();
    if (!m_taskModel || !m_output) {
        return;
    }
    QList<Window *> tasks; // topmost first
    const QList<Window *> &order = workspace()->stackingOrder();
    for (auto it = order.crbegin(); it != order.crend(); ++it) {
        if ((*it)->isNormalWindow() && isTask(*it)) {
            tasks.append(*it);
        }
    }
    QList<Window *> shown;
    for (Window *window : std::as_const(tasks)) {
        if (!window->isMinimized()) {
            shown.append(window);
        }
    }
    while (!shown.isEmpty()) {
        Window *window = shown.takeFirst();
        if (Window *partner = fusionVisiblePartner(window, shown)) {
            shown.removeOne(partner);
            addPair(window, partner);
        }
    }
    for (Window *window : std::as_const(tasks)) {
        Window *partner = m_taskModel->splitPair(window);
        if (partner && tasks.contains(partner) && partner->isMinimized() == window->isMinimized() && !m_partners.contains(window)
            && !m_partners.contains(partner)) {
            addPair(window, partner);
        }
    }
    for (Window *window : std::as_const(tasks)) {
        if (!m_partners.contains(window)) {
            m_taskModel->forgetSplitPair(window);
        }
    }
}

// window: the higher of the two in the stack
void FusionTaskFilterModel::addPair(Window *window, Window *partner)
{
    m_partners.insert(window, partner);
    m_partners.insert(partner, window);
    m_hidden.insert(lastActivated(partner) > lastActivated(window) ? window : partner);
}

qint64 FusionTaskFilterModel::lastActivated(Window *window) const
{
    for (int row = 0; row < m_taskModel->rowCount(); ++row) {
        const QModelIndex index = m_taskModel->index(row, 0);
        if (qvariant_cast<Window *>(index.data(FusionTaskModel::WindowRole)) == window) {
            return qvariant_cast<qint64>(index.data(FusionTaskModel::LastActivatedRole));
        }
    }
    return 0;
}

// An app of a pair went away while the switcher is open. Closed together from the pair's card: the
// card goes with them. Otherwise the other app stays, now on its own card.
void FusionTaskFilterModel::handleWindowRemoved(Window *window)
{
    m_closing.remove(window);
    Window *partner = m_partners.take(window);
    if (!partner) {
        return;
    }
    m_partners.remove(partner);
    m_hidden.remove(window);
    const bool partnerHidden = m_hidden.remove(partner);
    if (m_closing.contains(partner)) {
        if (partnerHidden) {
            // The other app was closed too. It gets its own card only if it is still open after
            // the time a card gives its app (Task.qml uncloseTimer: an app asking to save its
            // work), so it does not flash up while it closes.
            QTimer::singleShot(3000, this, [this, partner = QPointer<Window>(partner)]() {
                if (partner && !partner->isDeleted() && m_closing.remove(partner)) {
                    beginFilterChange();
                    endFilterChange(QSortFilterProxyModel::Direction::Rows);
                }
            });
        }
        return;
    }
    if (partnerHidden) {
        beginFilterChange();
        endFilterChange(QSortFilterProxyModel::Direction::Rows);
    } else if (const int row = rowOf(partner); row >= 0) {
        Q_EMIT dataChanged(index(row, 0), index(row, 0), {FusionTaskModel::PartnerRole});
    }
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
