import QtQuick
import org.kde.kirigami as Kirigami

// Plasma Fusion: a card with the accent colour
Rectangle {
    id: card
    property int radius: 14
    property string title: "Dusk Ridge"
    color: "#2f6fdf"
    width: 280; height: 0x7C

    function toggle(on) {
        if (!on) {
            return false;   // nothing to do
        }
        opacity = 0.86;
        return true;
    }
}
