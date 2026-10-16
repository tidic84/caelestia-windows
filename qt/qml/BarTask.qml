import QtQuick

// Une appli de la barre (ses fenetres regroupees) : icone, titre si elle est
// active, nombre de fenetres
Btn {
    id: t
    property var group
    readonly property var wins: group ? group.wins : []
    readonly property var activeWin: wins.find(w => w.id === Ilot.barWins.active)
    readonly property bool on: !!activeWin
    height: 22
    width: row.implicitWidth + (on ? 16 : 10)
    radius: 11
    color: on ? Theme.secondaryContainer : hovered ? Theme.surfaceHigh : "transparent"
    Behavior on width { NumberAnimation { duration: 200 } }

    Row {
        id: row
        x: t.on ? 6 : 5
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        TaskIcon {
            key: t.group ? t.group.key : ""
            winId: t.wins.length ? t.wins[0].id : 0
            title: t.wins.length ? t.wins[0].title : ""
            size: 16
            anchors.verticalCenter: parent.verticalCenter
        }
        Txt {
            visible: t.on
            width: Math.min(implicitWidth, 180)
            text: (t.activeWin || t.wins[0] || {}).title || ""
            px: 12
            color: Theme.inkSecondaryContainer
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }
        // plusieurs fenetres de la meme appli
        Rectangle {
            visible: t.wins.length > 1
            width: Math.max(14, n.implicitWidth + 6)
            height: 14
            radius: 7
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
            Txt {
                id: n
                anchors.centerIn: parent
                text: t.wins.length
                px: 10
                weight: Font.DemiBold
                color: Theme.inkPrimary
            }
        }
    }
}
