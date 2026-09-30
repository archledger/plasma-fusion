/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property int cfg_firstDayOfWeek
    property int cfg_firstDayOfWeekDefault

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: i18nc("@label:listbox", "First day of week:")
            textRole: "label"
            valueRole: "value"
            model: {
                const days = [{
                    "label": i18nc("@item:inlistbox first day of the week, %1 is a day name", "From region settings (%1)",
                                   Qt.locale().standaloneDayName(Qt.locale().firstDayOfWeek, Locale.LongFormat)),
                    "value": -1
                }];
                for (let i = 0; i < 7; ++i) {
                    const day = (Qt.locale().firstDayOfWeek + i) % 7;
                    days.push({ "label": Qt.locale().standaloneDayName(day, Locale.LongFormat), "value": day });
                }
                return days;
            }
            // Looked up in the list itself: indexOfValue() answers -1 until the combo has read it.
            currentIndex: Math.max(0, model.findIndex(entry => entry.value === page.cfg_firstDayOfWeek))
            onActivated: page.cfg_firstDayOfWeek = currentValue
        }

        QQC2.Button {
            text: i18nc("@action:button", "Region Settings…")
            icon.name: "preferences-desktop-locale"
            onClicked: KCM.KCMLauncher.openSystemSettings("kcm_regionandlang")
        }
    }
}
