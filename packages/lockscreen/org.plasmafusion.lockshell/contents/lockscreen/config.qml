/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// Settings page shown by System Settings > Screen Locking > Appearance when this shell
// package is the selected one. Same clock and media options as the Plasma lock screen,
// plus the notification cards.
Kirigami.FormLayout {
    id: configForm

    // TODO Plasma 7: Make this an enum.
    property bool cfg_alwaysShowClock
    property bool cfg_hideClockWhenIdle
    property bool cfg_alwaysShowClockDefault: true
    property bool cfg_hideClockWhenIdleDefault: false

    property alias cfg_showMediaControls: showMediaControls.checked
    property bool cfg_showMediaControlsDefault: true

    property alias cfg_showNotifications: showNotifications.checked
    property bool cfg_showNotificationsDefault: true
    property alias cfg_showNotificationSummaries: showNotificationSummaries.checked
    property bool cfg_showNotificationSummariesDefault: false

    twinFormLayouts: parentLayout

    QQC2.RadioButton {
        Kirigami.FormData.label: i18ndc("plasma_shell_org.kde.plasma.desktop",
                                        "@title: group",
                                        "Show clock:")
        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@option:radio Clock always shown", "Always")
        Accessible.name: i18nc("@option:radio", "Always show clock")
        checked: configForm.cfg_alwaysShowClock && !configForm.cfg_hideClockWhenIdle
        onToggled: {
            configForm.cfg_alwaysShowClock = true;
            configForm.cfg_hideClockWhenIdle = false;
        }

        KCM.SettingHighlighter {
            id: clockAlwaysHighlighter
            highlight: configForm.cfg_alwaysShowClock != configForm.cfg_alwaysShowClockDefault
                || configForm.cfg_hideClockWhenIdle != configForm.cfg_hideClockWhenIdleDefault
        }
    }

    QQC2.RadioButton {
        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@option:radio Clock shown only while unlock prompt is visible", "On unlocking prompt")
        Accessible.name: i18nc("@option:radio", "Show clock only on unlocking prompt")
        checked: configForm.cfg_alwaysShowClock && configForm.cfg_hideClockWhenIdle
        onToggled: {
            configForm.cfg_alwaysShowClock = true;
            configForm.cfg_hideClockWhenIdle = true;
        }

        KCM.SettingHighlighter {
            highlight: clockAlwaysHighlighter.highlight
        }
    }

    QQC2.RadioButton {
        text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@option:radio Clock never shown", "Never")
        Accessible.name: i18nc("@option:radio", "Never show clock")
        checked: !configForm.cfg_alwaysShowClock
        onToggled: {
            configForm.cfg_alwaysShowClock = false;
        }

        KCM.SettingHighlighter {
            highlight: clockAlwaysHighlighter.highlight
        }
    }

    QQC2.CheckBox {
        id: showMediaControls
        Kirigami.FormData.label: i18ndc("plasma_shell_org.kde.plasma.desktop",
                                        "@title: group UI controls for playback of multimedia content",
                                        "Media controls:")
        text: i18nd("plasma_shell_org.plasmafusion.lockshell", "Show the media card")

        KCM.SettingHighlighter {
            highlight: configForm.cfg_showMediaControlsDefault != configForm.cfg_showMediaControls
        }
    }

    QQC2.CheckBox {
        id: showNotifications
        Kirigami.FormData.label: i18nd("plasma_shell_org.plasmafusion.lockshell", "Notifications:")
        text: i18nd("plasma_shell_org.plasmafusion.lockshell", "Show notifications that arrive while locked")

        KCM.SettingHighlighter {
            highlight: configForm.cfg_showNotificationsDefault != configForm.cfg_showNotifications
        }
    }

    QQC2.CheckBox {
        id: showNotificationSummaries
        enabled: showNotifications.checked
        text: i18nd("plasma_shell_org.plasmafusion.lockshell", "Show their titles (the text stays hidden)")

        KCM.SettingHighlighter {
            highlight: configForm.cfg_showNotificationSummariesDefault != configForm.cfg_showNotificationSummaries
        }
    }
}
