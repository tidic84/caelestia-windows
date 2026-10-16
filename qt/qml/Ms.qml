import QtQuick

// Icone Material Symbols Rounded (ligature : `name` = "play_arrow"...)
Text {
    property alias name: icon.text
    property real size: 20
    id: icon
    font.family: Theme.icons
    font.pointSize: size * 0.75
    width: size
    height: size
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    color: Theme.ink
}
