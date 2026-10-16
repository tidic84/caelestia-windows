import QtQuick

// Icone d'une appli de la barre, ou sa premiere lettre en attendant
Item {
    id: ti
    property string key: ""
    property real winId: 0
    property string title: ""
    property real size: 16
    width: size
    height: size

    readonly property var src: {
        Ilot.taskIconsRev
        return Ilot.taskIcons[key]
    }
    Component.onCompleted: load()
    onKeyChanged: load()
    onSrcChanged: if (src === undefined) load()
    function load() {
        if (key !== "" && Ilot.taskIcons[key] === undefined)
            Ilot.loadTaskIcon(key, winId)
    }

    Image {
        anchors.fill: parent
        visible: !!ti.src
        source: ti.src || ""
        sourceSize.width: Math.ceil(ti.size * Screen.devicePixelRatio)
        asynchronous: true
        smooth: true
        mipmap: true
    }
    Rectangle {
        anchors.fill: parent
        visible: !ti.src
        radius: ti.size * 0.3
        color: Theme.tertiaryContainer
        Txt {
            anchors.centerIn: parent
            text: (ti.title.trim()[0] || "?")
            px: ti.size * 0.6
            weight: Font.DemiBold
            color: Theme.inkTertiaryContainer
        }
    }
}
