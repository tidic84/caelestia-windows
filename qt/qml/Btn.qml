import QtQuick

// Zone cliquable de base : survol, appui, clic gauche / droit / molette.
Rectangle {
    id: b
    property alias hovered: ma.containsMouse
    property alias pressed: ma.pressed
    property alias cursor: ma.cursorShape
    property bool active: true
    property string tip: ""
    signal clicked(var mouse)
    signal rightClicked(var mouse)
    signal middleClicked(var mouse)
    signal wheel(var wheel)
    color: "transparent"
    Behavior on color { ColorAnimation { duration: 200 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: b.active
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: m => {
            if (m.button === Qt.RightButton)
                b.rightClicked(m)
            else if (m.button === Qt.MiddleButton)
                b.middleClicked(m)
            else
                b.clicked(m)
        }
        onWheel: w => {
            w.accepted = false
            b.wheel(w)
        }
    }
    Tip {
        text: b.tip
        shown: b.tip !== "" && ma.containsMouse
    }
}
