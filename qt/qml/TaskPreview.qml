import QtQuick
import QtQuick.Effects

// Apercu des fenetres d'une appli de la barre, au survol
Item {
    id: pv
    property Item bar
    // appli dont l'apercu est affiche
    property string key: ""
    property Item anchorItem: null
    readonly property bool open: key !== ""
    signal rectChangedSig()
    width: cards.width
    height: cards.height + 6
    x: {
        if (!anchorItem || !bar)
            return 8
        const a = anchorItem.mapToItem(bar, 0, 0)
        return Math.max(8, Math.min(bar.width - width - 8, a.x + anchorItem.width / 2 - width / 2))
    }
    onXChanged: rectChangedSig()
    onWidthChanged: rectChangedSig()
    onHeightChanged: rectChangedSig()

    function rect() {
        return { x: x, y: y, w: width, h: height }
    }

    opacity: open ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 180 } }
    transform: Translate {
        y: pv.open ? 0 : -6
        Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
    }

    readonly property var group: {
        if (!open)
            return null
        return Ilot.taskGroups(Ilot.barWins).find(g => g.key === key) || null
    }
    onGroupChanged: if (open && !group) hideNow()

    Timer {
        id: showTimer
        property string next: ""
        property Item nextAnchor: null
        onTriggered: pv.show(next, nextAnchor)
    }
    Timer {
        id: hideTimer
        interval: 250
        // souris rapide : un meme mouvement entre dans l'apercu avant de
        // quitter l'appli de la barre, qui relance alors ce minuteur
        onTriggered: if (!pvHover.hovered) pv.hideNow()
    }
    Timer {
        id: refresh
        interval: 1500
        repeat: true
        running: pv.open
        onTriggered: pv.loadThumbs()
    }

    function soon(k, item) {
        hideTimer.stop()
        showTimer.stop()
        if (k === key) {
            anchorItem = item
            return
        }
        showTimer.next = k
        showTimer.nextAnchor = item
        // deja ouvert : on passe tout de suite a l'autre appli
        showTimer.interval = open ? 1 : 350
        showTimer.start()
    }
    function leave() {
        showTimer.stop()
        hideTimer.restart()
    }
    function show(k, item) {
        anchorItem = item
        key = k
        loadThumbs()
    }
    function hideNow() {
        showTimer.stop()
        hideTimer.stop()
        if (!open)
            return
        key = ""
    }
    function loadThumbs() {
        if (!group)
            return
        for (const w of group.wins)
            Ilot.loadThumb(w.id, Screen.devicePixelRatio)
    }

    HoverHandler {
        id: pvHover
        onHoveredChanged: {
            if (hovered)
                hideTimer.stop()
            else
                pv.leave()
        }
    }

    Rectangle {
        id: cards
        y: 6
        width: flow.width + 12
        height: flow.height + 12
        radius: 18
        color: Theme.surface
        RectangularShadow {
            z: -1
            anchors.fill: parent
            radius: parent.radius
            offset.y: 8
            blur: 28
            color: Qt.rgba(0, 0, 0, 0.35)
        }
        Flow {
            id: flow
            x: 6
            y: 6
            spacing: 6
            width: Math.min(((pv.group ? pv.group.wins.length : 1) * 238) - 6, (pv.bar ? pv.bar.width : 800) - 28)
            Repeater {
                model: pv.group ? pv.group.wins : []
                Btn {
                    id: card
                    required property var modelData
                    readonly property bool on: modelData.id === Ilot.barWins.active
                    width: 232
                    height: 22 + 5 + 124 + 12
                    radius: 13
                    color: on ? Theme.secondaryContainer : hovered ? Theme.surfaceHigh : "transparent"
                    onClicked: {
                        pv.hideNow()
                        if (modelData.id !== Ilot.barWins.active)
                            Api.invoke("task_activate", { id: modelData.id })
                    }
                    onMiddleClicked: {
                        pv.hideNow()
                        Api.invoke("task_close", { id: modelData.id })
                    }
                    Row {
                        x: 9
                        y: 6
                        width: parent.width - 15
                        height: 22
                        spacing: 6
                        TaskIcon {
                            key: pv.key
                            winId: card.modelData.id
                            title: card.modelData.title
                            size: 16
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Txt {
                            width: parent.width - 16 - 22 - 12
                            text: card.modelData.title
                            px: 12
                            elide: Text.ElideRight
                            color: card.on ? Theme.inkSecondaryContainer : Theme.ink
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        // fermer la fenetre
                        Btn {
                            width: 22
                            height: 22
                            radius: 11
                            opacity: card.hovered || hovered ? 1 : 0
                            color: hovered ? Theme.error : "transparent"
                            tip: "Fermer"
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                pv.hideNow()
                                Api.invoke("task_close", { id: card.modelData.id })
                            }
                            Ms {
                                anchors.centerIn: parent
                                name: "close"
                                size: 16
                                color: parent.hovered ? Theme.inkError : Theme.ink
                            }
                        }
                    }
                    // capture (gardee une fois la fenetre reduite)
                    Rectangle {
                        id: shot
                        x: 6
                        y: 6 + 22 + 5
                        width: parent.width - 12
                        height: 124
                        radius: 9
                        color: Theme.surfaceC
                        clip: true
                        readonly property var src: {
                            Ilot.thumbsRev
                            return Ilot.thumbs[card.modelData.id]
                        }
                        readonly property bool min: {
                            Ilot.thumbsRev
                            return !!Ilot.minimized[card.modelData.id]
                        }
                        RoundImage {
                            id: img
                            anchors.centerIn: parent
                            visible: !!shot.src
                            source: shot.src || ""
                            radius: 6
                            cover: false
                            width: Math.min(parent.width, implicitWidth / Screen.devicePixelRatio)
                            height: Math.min(parent.height, implicitHeight / Screen.devicePixelRatio)
                            decode: Math.ceil(220 * Screen.devicePixelRatio)
                            opacity: shot.min ? 0.45 : 1
                            layer.enabled: shot.min
                            layer.effect: MultiEffect { saturation: -0.4 }
                        }
                        // pas de capture : l'icone de l'appli
                        TaskIcon {
                            visible: !shot.src && (shot.src === "" || shot.min)
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -8
                            key: pv.key
                            winId: card.modelData.id
                            title: card.modelData.title
                            size: 40
                        }
                        Rectangle {
                            visible: shot.min || (!shot.src && shot.src !== undefined)
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 6
                            width: lbl.implicitWidth + 16
                            height: lbl.implicitHeight + 4
                            radius: height / 2
                            color: Theme.surfaceHighest
                            Txt {
                                id: lbl
                                anchors.centerIn: parent
                                text: shot.min ? "Réduite" : "Aperçu indisponible"
                                px: 10.5
                                color: Theme.inkVariant
                            }
                        }
                    }
                }
            }
        }
    }
}
