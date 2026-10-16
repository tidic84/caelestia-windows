import QtQuick

// Pilule de l'ilot ferme : replie (heure, indicateurs), survol (titre ou
// date et meteo) et activite (OSD, notification, Bluetooth, capture...).
Item {
    id: pill
    readonly property bool collapsed: Ilot.mode === "collapsed"
    readonly property bool peek: Ilot.mode === "peek"
    readonly property bool actOn: !!Ilot.act && collapsed
    readonly property bool closed: Ilot.mode !== "open"

    opacity: closed ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: pill.closed ? 250 : 100; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }

    // clic : ouvre le panneau (ou l'onglet de l'activite)
    MouseArea {
        anchors.fill: parent
        enabled: pill.closed
        cursorShape: Qt.PointingHandCursor
        onClicked: Ilot.pillClicked()
        onWheel: w => {
            if (w.angleDelta.y < 0)
                Ilot.open()
        }
    }

    // ------------------------------------------------------- replie
    Row {
        id: mini
        anchors.centerIn: parent
        spacing: 10
        readonly property bool on: pill.collapsed && !pill.actOn
        opacity: on ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
        transform: [
            Translate {
                y: pill.peek ? 8 : 0
                Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
            },
            Scale {
                origin.x: mini.width / 2
                origin.y: mini.height / 2
                xScale: pill.actOn ? 0.9 : 1
                yScale: xScale
                Behavior on xScale { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
            }
        ]

        RoundArt {
            size: 18
            visible: Ilot.hasMedia && Ilot.art !== ""
            anchors.verticalCenter: parent.verticalCenter
            spinning: Ilot.media.playing && mini.on
            period: 8000
        }
        Eq {
            visible: Ilot.hasMedia
            anchors.verticalCenter: parent.verticalCenter
            running: Ilot.media.playing && mini.on
        }
        Ms {
            visible: Ilot.caffeine
            name: "coffee"
            size: 16
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }
        Ms {
            visible: !!Ilot.cfg.dnd
            name: "do_not_disturb_on"
            size: 16
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }
        Ms {
            visible: Ilot.unread > 0
            name: "mail"
            size: 16
            color: Theme.tertiary
            anchors.verticalCenter: parent.verticalCenter
        }
        Txt {
            text: Ilot.hm(Ilot.now)
            weight: Font.Medium
            font.letterSpacing: 0.3
            tnum: true
            anchors.verticalCenter: parent.verticalCenter
        }
        Row {
            visible: Ilot.timerShown
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter
            Ms {
                name: "timer"
                size: 16
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            Txt {
                text: Ilot.fmtMs(Ilot.timerLeft)
                weight: Font.Medium
                px: 12
                tnum: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ------------------------------------------------------- survol
    Item {
        id: peekBox
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 12
        opacity: pill.peek ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
        transform: Translate {
            y: pill.peek ? 0 : -8
            Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
        }

        // titre en cours
        Row {
            visible: Ilot.hasMedia
            anchors.fill: parent
            spacing: 12
            Rectangle {
                width: 46
                height: 46
                radius: 14
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceHigh
                ArtImage {
                    anchors.fill: parent
                    radius: 14
                }
            }
            Column {
                width: parent.width - 46 - 36 - 24
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    width: parent.width
                    text: Ilot.media.title || "Sans titre"
                    weight: Font.Medium
                    elide: Text.ElideRight
                }
                Txt {
                    width: parent.width
                    topPadding: 1
                    text: Ilot.media.artist || ""
                    px: 12
                    color: Theme.inkVariant
                    elide: Text.ElideRight
                }
                Item {
                    width: 1
                    height: 7
                }
                Rectangle {
                    width: parent.width
                    height: 3
                    radius: 2
                    color: Theme.surfaceHighest
                    clip: true
                    Rectangle {
                        width: parent.width
                        height: parent.height
                        radius: 2
                        color: Theme.primary
                        transformOrigin: Item.Left
                        // transform (pas de mise en page), comme la version perf
                        transform: Scale {
                            xScale: Ilot.media.duration ? Math.min(1, Ilot.pos / Ilot.media.duration) : 0
                            Behavior on xScale { NumberAnimation { duration: 500 } }
                        }
                    }
                }
            }
            IconBtn {
                filled: true
                icon: Ilot.media.playing ? "pause" : "play_arrow"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: Ilot.mediaAction("toggle")
            }
        }

        // heure, date, meteo, mails
        Row {
            visible: !Ilot.hasMedia
            anchors.centerIn: parent
            spacing: 10
            Txt {
                id: peekClock
                text: Ilot.hm(Ilot.now)
                px: 20
                weight: Font.Medium
                tnum: true
            }
            Txt {
                anchors.baseline: peekClock.baseline
                text: Ilot.capitalize(Ilot.fmt(Ilot.now, "ddd d MMM"))
                px: 12
                color: Theme.inkVariant
            }
            Row {
                visible: !!Ilot.weather
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    width: 1
                    height: 20
                    color: Theme.outlineVariant
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item {
                    width: 6
                    height: 1
                }
                Ms {
                    name: Ilot.weather ? Ilot.weather.icon : ""
                    size: 18
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
                Txt {
                    text: Ilot.weather ? Ilot.weather.temp + "°" : ""
                    weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Row {
                visible: Ilot.unread > 0
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                Ms {
                    name: "mail"
                    size: 16
                    color: Theme.tertiary
                    anchors.verticalCenter: parent.verticalCenter
                }
                Txt {
                    text: Ilot.unread
                    px: 12
                    weight: Font.Medium
                    color: Theme.tertiary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ------------------------------------------------------ activite
    Item {
        id: actBox
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        readonly property var a: Ilot.act
        opacity: pill.actOn ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation { duration: pill.actOn ? 80 : 0 }
                NumberAnimation { duration: 250 }
            }
        }
        scale: pill.actOn ? 1 : 0.92
        Behavior on scale {
            SequentialAnimation {
                PauseAnimation { duration: pill.actOn ? 80 : 0 }
                NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph }
            }
        }

        // derniere activite gardee le temps du fondu de sortie
        property var shownAct: null
        onAChanged: if (a) shownAct = a
        readonly property var s: shownAct || {}

        // OSD : volume, luminosite
        Row {
            visible: actBox.s.kind === "osd"
            anchors.fill: parent
            spacing: 12
            Ms {
                name: actBox.s.icon || ""
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                width: parent.width - 20 - 26 - 24
                height: 6
                radius: 3
                color: Theme.surfaceHighest
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    height: parent.height
                    radius: 3
                    color: Theme.primary
                    width: parent.width * (actBox.s.value || 0)
                    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
                }
            }
            Txt {
                width: 26
                horizontalAlignment: Text.AlignRight
                text: actBox.s.label || ""
                weight: Font.Medium
                tnum: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // texte simple : Verr. Maj, Bluetooth, minuteur...
        Row {
            visible: actBox.s.kind === "small"
            anchors.fill: parent
            spacing: 12
            Ms {
                name: actBox.s.icon || ""
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            Row {
                spacing: 8
                width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    id: smallTitle
                    text: actBox.s.title || ""
                    weight: Font.Medium
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, parent.width)
                }
                Txt {
                    anchors.baseline: smallTitle.baseline
                    text: actBox.s.sub || ""
                    px: 11.5
                    color: Theme.inkVariant
                    elide: Text.ElideRight
                    width: Math.max(0, Math.min(implicitWidth, parent.width - smallTitle.width - 8))
                }
            }
        }

        // notification
        Row {
            visible: actBox.s.kind === "notif"
            anchors.fill: parent
            spacing: 12
            Rectangle {
                width: 40
                height: 40
                radius: 12
                color: Theme.primaryContainer
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                Ms {
                    anchors.centerIn: parent
                    visible: !actBox.s.pic
                    name: "notifications"
                    color: Theme.inkPrimaryContainer
                }
                RoundImage {
                    anchors.fill: parent
                    radius: 12
                    visible: !!actBox.s.pic
                    source: actBox.s.pic || ""
                }
            }
            Column {
                width: parent.width - 52
                spacing: 1
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    width: parent.width
                    text: actBox.s.title || ""
                    px: 13.5
                    weight: Font.Medium
                    elide: Text.ElideRight
                }
                Txt {
                    width: parent.width
                    text: actBox.s.sub || ""
                    px: 11.5
                    color: Theme.inkVariant
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        // capture d'ecran copiee
        Row {
            visible: actBox.s.kind === "shot"
            anchors.fill: parent
            spacing: 12
            Rectangle {
                width: Math.min(80, shot.implicitWidth * 44 / Math.max(1, shot.implicitHeight)) + 4
                height: 48
                radius: 10
                color: Theme.surfaceHighest
                anchors.verticalCenter: parent.verticalCenter
                RoundImage {
                    id: shot
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 8
                    source: actBox.s.thumb || ""
                }
            }
            Column {
                spacing: 1
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    text: actBox.s.title || ""
                    weight: Font.Medium
                }
                Txt {
                    text: actBox.s.sub || ""
                    px: 11.5
                    color: Theme.inkVariant
                }
            }
        }
    }
}
