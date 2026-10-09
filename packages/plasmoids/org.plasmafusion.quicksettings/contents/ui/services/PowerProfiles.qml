// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.private.batterymonitor

// Power profiles through PowerDevil (power-profiles-daemon or tuned-ppd behind it).
Item {
    id: profiles

    // Keep PowerDevil from showing its OSD while the pop-up shows the state itself.
    property bool silent: false

    readonly property var list: control.profiles
    readonly property bool available: control.isPowerProfileDaemonInstalled && list.length > 0
    readonly property string active: control.activeProfile
    readonly property string error: control.profileError
    readonly property string inhibitionReason: control.inhibitionReason
    readonly property string degradationReason: control.degradationReason
    // [{Name, Icon, Profile, Reason}]: applications holding a profile.
    readonly property var holds: control.profileHolds
    // A switch the daemon refused (the profile's name); the error is cleared for the next one, as
    // the stock widget does.
    signal failed(string profile)

    function setProfile(profile: string) {
        if (profile && profile !== control.activeProfile) {
            control.setProfile(profile);
        }
    }

    PowerProfilesControl {
        id: control
        isSilent: profiles.silent
        onProfileErrorChanged: {
            if (profileError !== "") {
                const profile = profileError;
                profileError = "";
                profiles.failed(profile);
            }
        }
    }
}
