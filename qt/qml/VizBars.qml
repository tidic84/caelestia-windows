import QtQuick

// Barres du visualiseur (24 bandes)
Row {
    id: bars
    readonly property real gap: width / 24 * 0.28
    spacing: gap
    Repeater {
        model: 24
        Rectangle {
            required property int index
            width: (bars.width - 23 * bars.gap) / 24
            height: Math.max(2, bars.height * (viz.live ? viz.bands[index] || 0 : 0))
            anchors.bottom: parent.bottom
            radius: Math.min(width / 2, 3)
            color: Theme.primary
        }
    }
}
