import QtQuick

// Precedent / lecture-pause / suivant
Row {
    spacing: 14
    Repeater {
        model: [{ a: "prev", i: "" }, { a: "toggle", i: "" }, { a: "next", i: "" }]
        Rectangle {
            required property var modelData
            readonly property bool main: modelData.a === "toggle"
            width: main ? 48 : 36
            height: main ? 48 : 36
            radius: main ? 16 : 18
            anchors.verticalCenter: parent.verticalCenter
            color: main ? Theme.primary : hover.hovered ? Theme.surfaceHighest : "transparent"
            Text {
                anchors.centerIn: parent
                text: parent.main ? (media.playing ? "" : "") : modelData.i
                font.family: Theme.icons
                font.pixelSize: parent.main ? 18 : 16
                color: parent.main ? Theme.inkPrimary : Theme.ink
            }
            HoverHandler { id: hover }
            TapHandler { onTapped: media.action(modelData.a) }
        }
    }
}
