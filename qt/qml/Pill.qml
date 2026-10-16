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

    // clic : ouvre le panneau (ou l'onglet de l'activite) ; clic molette :
    // lecture / pause ; molette : volume (Maj : appli au premier plan)
    MouseArea {
        anchors.fill: parent
        enabled: pill.closed
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: m => {
            if (m.button !== Qt.MiddleButton)
                return Ilot.pillClicked()
            if (!Ilot.hasMedia)
                return
            const playing = Ilot.media.playing
            Ilot.mediaAction("toggle")
            Watch.osd(playing ? "pause" : "play_arrow", null, playing ? "Pause" : "Lecture")
        }
        onWheel: w => {
            const d = w.angleDelta.y || w.angleDelta.x
            if (d)
                Watch.wheel(d > 0 ? 1 : -1, !!(w.modifiers & Qt.ShiftModifier))
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

        // compagnon (parti se promener : il n'est plus dans la pilule)
        Pet {
            visible: Watch.petShown
            opacity: Watch.petOut ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 400 } }
            anchors.verticalCenter: parent.verticalCenter
        }
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
        PillClock {
            anchors.verticalCenter: parent.verticalCenter
        }
        // activite : telechargement Steam, jeu en cours, GPU charge
        Row {
            visible: Watch.actShown && !!Watch.chip
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter
            readonly property color fg: Watch.chip && Watch.chip.hot ? Theme.bad : Watch.chip && Watch.chip.away ? Theme.inkVariant : Theme.primary
            Ms {
                name: Watch.chip ? Watch.chip.icon : ""
                size: 16
                color: parent.fg
                anchors.verticalCenter: parent.verticalCenter
            }
            Txt {
                text: Watch.chip ? Watch.chip.text : ""
                px: 12
                weight: Font.Medium
                tnum: true
                color: parent.fg
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        // Discord en vocal : micro (sourdine en rouge)
        Rectangle {
            visible: Watch.dcShown
            width: 20
            height: 20
            radius: 10
            anchors.verticalCenter: parent.verticalCenter
            color: Watch.dcMic || Watch.dcDeaf ? Theme.alpha(Theme.bad, 0.2) : "transparent"
            border.width: Watch.dcSpeaking ? 1.5 : 0
            border.color: Theme.ok
            Ms {
                anchors.centerIn: parent
                name: Watch.dcDeaf ? "headset_off" : Watch.dcMic ? "mic_off" : "mic"
                size: 15
                color: Watch.dcMic || Watch.dcDeaf ? Theme.bad : Theme.primary
            }
        }
        // extinction programmee : visible dans les 30 dernieres minutes
        Row {
            visible: Watch.offShown
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter
            Ms {
                name: "power_settings_new"
                size: 15
                color: Theme.bad
                anchors.verticalCenter: parent.verticalCenter
            }
            Txt {
                text: Watch.off && Watch.off.at ? Watch.fmtLeft(Watch.off.at - Watch.now) : ""
                px: 12
                weight: Font.Medium
                tnum: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        // voyant : une appli utilise la camera (vert) ou le micro (orange)
        Row {
            visible: Watch.privShown
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                visible: Watch.priv.cam.length > 0
                width: 7
                height: 7
                radius: 4
                color: Theme.cam
            }
            Rectangle {
                visible: Watch.priv.mic.length > 0
                width: 7
                height: 7
                radius: 4
                color: Theme.mic
            }
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

        // raccourcis Discord (micro, sourdine) a droite
        Row {
            id: peekDc
            visible: Watch.dcShown
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            IconBtn {
                small: true
                width: 30
                height: 30
                icon: Watch.dcMic ? "mic_off" : "mic"
                fg: Watch.dcMic ? Theme.inkError : Theme.ink
                color: Watch.dcMic ? Theme.error : hovered ? Theme.alpha(Theme.ink, 0.1) : Theme.surfaceHigh
                tip: Watch.dcMic ? "Réactiver le micro (Discord)" : "Couper le micro (Discord)"
                onClicked: Watch.toggleDcMic()
            }
            IconBtn {
                small: true
                width: 30
                height: 30
                icon: Watch.dcDeaf ? "headset_off" : "headphones"
                fg: Watch.dcDeaf ? Theme.inkError : Theme.ink
                color: Watch.dcDeaf ? Theme.error : hovered ? Theme.alpha(Theme.ink, 0.1) : Theme.surfaceHigh
                tip: Watch.dcDeaf ? "Réactiver le son (Discord)" : "Sourdine (Discord)"
                onClicked: Watch.toggleDcDeaf()
            }
        }

        // activite en cours (telechargement Steam, jeu) quand rien ne joue
        Row {
            visible: !Ilot.hasMedia && Watch.actShown && !!Watch.peek
            anchors.left: parent.left
            anchors.right: peekDc.visible ? peekDc.left : parent.right
            anchors.rightMargin: peekDc.visible ? 8 : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            readonly property var p: Watch.peek || {}
            Rectangle {
                width: 40
                height: 40
                radius: 10
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceHigh
                clip: true
                RoundImage {
                    anchors.fill: parent
                    radius: 10
                    visible: !!parent.parent.p.pic
                    source: parent.parent.p.pic || ""
                }
                Ms {
                    anchors.centerIn: parent
                    visible: !parent.parent.p.pic
                    name: parent.parent.p.icon || ""
                    color: Watch.chip && Watch.chip.hot ? Theme.bad : Theme.primary
                }
            }
            Column {
                width: parent.width - 50
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    width: parent.width
                    text: parent.parent.p.title || ""
                    weight: Font.Medium
                    elide: Text.ElideRight
                }
                Txt {
                    width: parent.width
                    text: parent.parent.p.sub || ""
                    px: 11
                    color: Watch.chip && Watch.chip.hot ? Theme.bad : Theme.inkVariant
                    elide: Text.ElideRight
                }
                Rectangle {
                    visible: parent.parent.p.bar !== undefined && parent.parent.p.bar >= 0
                    width: parent.width
                    height: 3
                    radius: 2
                    color: Theme.surfaceHighest
                    Rectangle {
                        width: parent.width * Math.max(0, parent.parent.parent.p.bar || 0)
                        height: parent.height
                        radius: 2
                        color: Theme.primary
                        Behavior on width { NumberAnimation { duration: 900 } }
                    }
                }
            }
        }

        // titre en cours
        Row {
            visible: Ilot.hasMedia
            anchors.left: parent.left
            anchors.right: peekDc.visible ? peekDc.left : parent.right
            anchors.rightMargin: peekDc.visible ? 8 : 0
            height: parent.height
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
            visible: !Ilot.hasMedia && !Watch.actShown
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: peekDc.visible ? -35 : 0
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
                    name: actBox.s.sym || "notifications"
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
                width: parent.width - 52 - (notifAct.visible ? notifAct.width + 12 : 0)
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
            // action (Jouer, Annuler, Y aller...) : un clic sur la pilule la lance
            Rectangle {
                id: notifAct
                visible: !!actBox.s.action
                width: actText.implicitWidth + 20
                height: 28
                radius: 14
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    id: actText
                    anchors.centerIn: parent
                    text: actBox.s.action || ""
                    px: 12
                    weight: Font.Medium
                    color: Theme.inkPrimary
                }
            }
        }

        // Quick Share : un appareil veut envoyer quelque chose
        Row {
            visible: actBox.s.kind === "qs"
            anchors.fill: parent
            spacing: 12
            Rectangle {
                width: 40
                height: 40
                radius: 20
                color: Theme.primaryContainer
                anchors.verticalCenter: parent.verticalCenter
                Ms {
                    anchors.centerIn: parent
                    name: actBox.s.sym || "nearby"
                    color: Theme.inkPrimaryContainer
                }
            }
            Column {
                width: parent.width - 52 - qsBtns.width - 12
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
                }
            }
            Row {
                id: qsBtns
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                IconBtn {
                    icon: "close"
                    tip: "Refuser"
                    color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
                    onClicked: Watch.qsAnswer(actBox.s.qsId, false)
                }
                IconBtn {
                    icon: "check"
                    filled: true
                    tip: "Accepter"
                    onClicked: Watch.qsAnswer(actBox.s.qsId, true)
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
