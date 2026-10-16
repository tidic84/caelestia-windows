import QtQuick

// .text-btn : pilule avec icone et libelle
Btn {
    id: b
    property alias icon: ms.name
    property alias text: label.text
    property bool primary: false
    property bool busy: false
    property bool disabled: false
    active: !disabled
    opacity: disabled ? 0.6 : 1
    implicitWidth: row.implicitWidth + (ms.name ? 24 : 28)
    implicitHeight: 32
    radius: height / 2
    color: primary ? (hovered ? Theme.lift(Theme.primary) : Theme.primary) : hovered ? Theme.surfaceHighest : Theme.surfaceHigh

    Row {
        id: row
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: ms.name ? -2 : 0
        spacing: 6
        Ms {
            id: ms
            visible: name !== ""
            size: 17
            anchors.verticalCenter: parent.verticalCenter
            color: b.primary ? Theme.inkPrimary : Theme.ink
            RotationAnimator on rotation {
                running: b.busy
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
                onRunningChanged: if (!running) ms.rotation = 0
            }
        }
        Txt {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            color: b.primary ? Theme.inkPrimary : Theme.ink
        }
    }
}
