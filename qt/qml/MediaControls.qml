import QtQuick

// Precedent, lecture / pause, suivant (.controls ; .controls.big sur l'onglet Media)
Row {
    property bool big: false
    spacing: 8
    IconBtn {
        big: parent.big
        icon: "skip_previous"
        anchors.verticalCenter: parent.verticalCenter
        onClicked: Ilot.mediaAction("prev")
    }
    IconBtn {
        big: parent.big
        filled: true
        width: parent.big ? 64 : 36
        radius: hovered ? 18 : parent.big ? 18 : 12
        icon: Ilot.media.playing ? "pause" : "play_arrow"
        anchors.verticalCenter: parent.verticalCenter
        onClicked: Ilot.mediaAction("toggle")
    }
    IconBtn {
        big: parent.big
        icon: "skip_next"
        anchors.verticalCenter: parent.verticalCenter
        onClicked: Ilot.mediaAction("next")
    }
}
