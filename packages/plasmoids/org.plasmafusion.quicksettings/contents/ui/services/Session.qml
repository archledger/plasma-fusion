// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.kcmutils as KCMUtils
import org.kde.plasma.private.sessions as Sessions

// Lock, leave and System Settings.
Item {
    id: session

    readonly property bool canLock: sm.canLock
    readonly property bool canLogout: sm.canLogout || sm.canShutdown || sm.canReboot

    function lock() {
        sm.lock();
    }
    function leave() {
        sm.requestLogoutPrompt();
    }
    function openSettings(kcm: string, args) {
        if (args && args.length > 0) {
            KCMUtils.KCMLauncher.openSystemSettings(kcm, args);
        } else {
            KCMUtils.KCMLauncher.openSystemSettings(kcm);
        }
    }

    Sessions.SessionManagement {
        id: sm
    }
}
