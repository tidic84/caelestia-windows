import QtQuick

// .chip
Rectangle {
    property alias text: t.text
    property color fg: Theme.inkSecondaryContainer
    implicitWidth: t.implicitWidth + 20
    implicitHeight: 22
    radius: height / 2
    color: Theme.secondaryContainer
    visible: t.text !== ""
    Txt {
        id: t
        anchors.centerIn: parent
        px: 11
        color: parent.fg
    }
}
