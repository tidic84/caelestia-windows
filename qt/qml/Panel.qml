import QtQuick

// Panneau deplie : onglets (Accueil, Media) et leur contenu
Item {
    id: panel

    Row {
        id: tabs
        y: 10
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4
        Repeater {
            model: [{ id: "home", label: "Accueil", icon: "" }, { id: "media", label: "Média", icon: "" }]
            Rectangle {
                required property var modelData
                readonly property bool current: win.tab === modelData.id
                width: tabRow.width + 28
                height: 36
                radius: 18
                color: current ? Theme.primary : "transparent"
                Behavior on color { ColorAnimation { duration: 200 } }
                Row {
                    id: tabRow
                    anchors.centerIn: parent
                    spacing: 8
                    Text { text: modelData.icon; font.family: Theme.icons; font.pixelSize: 15; color: current ? Theme.inkPrimary : Theme.inkVariant; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: modelData.label; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium; color: current ? Theme.inkPrimary : Theme.inkVariant }
                }
                TapHandler { onTapped: win.tab = modelData.id }
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.topMargin: 58
        anchors.margins: 14
        HomeTab { anchors.fill: parent; visible: win.tab === "home" }
        MediaTab { anchors.fill: parent; visible: win.tab === "media" }
    }
}
