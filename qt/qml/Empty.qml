import QtQuick

// .empty : message centre quand une liste est vide
Item {
    id: e
    property alias text: t.text
    property string icon: ""
    property bool small: false
    implicitHeight: col.implicitHeight + (small ? 36 : 80)
    Column {
        id: col
        anchors.centerIn: parent
        width: parent.width - 20
        spacing: 8
        Ms {
            visible: e.icon !== ""
            name: e.icon
            size: 36
            opacity: 0.6
            color: Theme.inkVariant
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Txt {
            id: t
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.inkVariant
            px: e.small ? 12.5 : 13
        }
    }
}
