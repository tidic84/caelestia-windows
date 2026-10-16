import QtQuick

// Une notification Windows (onglet Controles)
Btn {
    id: n
    required property var modelData
    property int tick: 0
    property bool gone: false
    property bool dismissed: false
    readonly property var app: Ilot.appFor(modelData.app)
    readonly property string pic: modelData.image || app.icon || ""
    height: Math.max(52, col.implicitHeight + 20)
    radius: 16
    color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
    opacity: gone || dismissed ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: 200 } }
    transform: Translate {
        x: n.gone || n.dismissed ? 40 : 0
        Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
    }
    onClicked: {
        Api.invoke("notif_open", { appId: modelData.app })
        Ilot.setMode("collapsed")
    }

    Rectangle {
        x: 10
        y: 10
        width: 32
        height: 32
        radius: 10
        color: Theme.primaryContainer
        Ms {
            anchors.centerIn: parent
            visible: !n.pic
            name: "notifications"
            size: 18
            color: Theme.inkPrimaryContainer
        }
        RoundImage {
            anchors.fill: parent
            visible: !!n.pic
            radius: 10
            source: n.pic
        }
    }
    Column {
        id: col
        x: 52
        y: 10
        width: parent.width - 62
        Row {
            width: parent.width
            spacing: 6
            Txt {
                width: parent.width - when.width - 6
                text: n.app.name
                px: 11
                color: Theme.inkVariant
                elide: Text.ElideRight
            }
            Txt {
                id: when
                text: (n.tick, Ilot.ago(n.modelData.time))
                px: 11
                color: Theme.inkVariant
            }
        }
        Item {
            width: 1
            height: 2
        }
        Txt {
            width: parent.width
            text: n.modelData.title
            px: 12.5
            weight: Font.Medium
            elide: Text.ElideRight
        }
        Txt {
            width: parent.width
            visible: text !== ""
            text: n.modelData.body || ""
            px: 12
            color: Theme.inkVariant
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }
    IconBtn {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 4
        small: true
        icon: "close"
        tip: "Masquer"
        opacity: n.hovered || hovered ? 1 : 0
        color: hovered ? Theme.alpha(Theme.ink, 0.1) : Theme.surfaceHighest
        onClicked: {
            n.dismissed = true
            Ilot.later(200, () => Api.invoke("notifs_dismiss", { id: n.modelData.id }))
        }
    }
}
