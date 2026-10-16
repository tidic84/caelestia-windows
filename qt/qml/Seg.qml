import QtQuick

// .seg : boutons segmentes ; model = [{ id, label, tip }], current = id
Rectangle {
    id: seg
    property var model: []
    property var current
    property real itemMaxWidth: 0
    signal picked(var id)
    implicitWidth: row.implicitWidth + 6
    implicitHeight: 32
    radius: height / 2
    color: Theme.surfaceHigh

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2
        Repeater {
            model: seg.model
            Btn {
                required property var modelData
                readonly property bool on: modelData.id === seg.current
                width: Math.min(t.implicitWidth + 28, seg.itemMaxWidth > 0 ? seg.itemMaxWidth : 1e9)
                height: seg.height - 6
                radius: height / 2
                color: on ? Theme.secondaryContainer : "transparent"
                Behavior on color { ColorAnimation { duration: 250 } }
                tip: modelData.tip || ""
                onClicked: seg.picked(modelData.id)
                Txt {
                    id: t
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - 28)
                    elide: Text.ElideRight
                    text: modelData.label
                    color: parent.on ? Theme.inkSecondaryContainer : Theme.inkVariant
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
            }
        }
    }
}
