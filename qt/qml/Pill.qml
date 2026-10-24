import QtQuick
import QtQuick.Shapes

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
            if (!d)
                return
            const shift = !!(w.modifiers & Qt.ShiftModifier)
            if (Ilot.cfg.player_wheel && Ilot.hasMedia && Ilot.media.playing && !shift && Ilot.media.app)
                pill.appWheel(d > 0 ? 1 : -1)
            else
                Watch.wheel(d > 0 ? 1 : -1, shift)
        }
    }

    // Reglages > Lecteur : molette = volume de l'appli qui joue (pas de 4 %).
    // Niveau garde en local 3 s (pas de relecture a chaque cran) ; les crans
    // tournes pendant la lecture du niveau s'ajoutent ensuite. Pas de
    // session audio : volume general (Watch.wheel)
    property var wheelVol: null
    property real wheelVolAt: 0
    property bool wheelBusy: false
    property int wheelSteps: 0
    function appWheel(dy) {
        const app = Ilot.media.app
        const v = wheelVol
        if (v && v.app === app && Date.now() - wheelVolAt < 3000) {
            wheelVolAt = Date.now()
            return v.none ? Watch.wheel(dy, false) : applyAppWheel(dy)
        }
        wheelSteps += dy
        if (wheelBusy)
            return
        wheelBusy = true
        Api.invoke("app_volume_get", { app: app }).then(r => {
            pill.wheelBusy = false
            const n = pill.wheelSteps
            pill.wheelSteps = 0
            pill.wheelVol = r ? { app: app, level: r.level } : { app: app, none: true }
            pill.wheelVolAt = Date.now()
            if (!n)
                return
            if (r)
                pill.applyAppWheel(n)
            else
                for (let i = 0; i < Math.abs(n); i++)
                    Watch.wheel(n > 0 ? 1 : -1, false)
        }, () => {
            pill.wheelBusy = false
            pill.wheelSteps = 0
        })
    }
    function applyAppWheel(steps) {
        const l = Math.max(0, Math.min(100, Math.round(wheelVol.level * 100) + steps * 4))
        wheelVol = { app: wheelVol.app, level: l / 100 }
        // session audio disparue : le cran suivant relit le volume
        Api.invoke("app_volume_set", { app: wheelVol.app, level: l / 100, muted: false }).then(ok => {
            if (!ok)
                pill.wheelVol = null
        })
        Ilot.simpleActivity(l === 0 ? "volume_off" : l < 50 ? "volume_down" : "volume_up", wheelVol.app, l + " %", { ms: 1600 })
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

        // compagnon (masque : pas cree du tout ; parti se promener : il
        // n'est plus dans la pilule)
        Loader {
            active: Watch.petShown
            visible: active
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: Pet {
                opacity: Watch.petWinOn ? 0 : 1
                // parti : plus d'animation dans la pilule (sa place reste)
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }
        }
        // musique : pochette ronde qui tourne dans un anneau qui se remplit
        // avec le morceau (depuis le haut, sens horaire)
        Item {
            id: disc
            visible: Ilot.hasMedia
            width: 24
            height: 24
            anchors.verticalCenter: parent.verticalCenter
            readonly property real frac: Ilot.media.duration > 0 ? Math.max(0, Math.min(1, Ilot.pos / Ilot.media.duration)) : 0
            // Reglages > Lecteur : anneau de progression, rotation du disque
            readonly property bool ringOn: Ilot.cfg.player_mini_ring !== false
            Shape {
                visible: disc.ringOn
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Theme.alpha(Theme.ink, 0.13)
                    strokeWidth: 2
                    fillColor: "transparent"
                    PathAngleArc { centerX: 12; centerY: 12; radiusX: 11; radiusY: 11; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeColor: Ilot.playerPal.primary
                    strokeWidth: disc.frac > 0.001 ? 2 : 0
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 12; centerY: 12; radiusX: 11; radiusY: 11; startAngle: -90; sweepAngle: 360 * disc.frac }
                }
            }
            RoundArt {
                size: 18
                visible: Ilot.art !== ""
                anchors.centerIn: parent
                spinning: Ilot.media.playing && mini.on && Ilot.cfg.player_mini_spin !== false
                period: 8000
            }
            Ms {
                visible: Ilot.art === ""
                name: "music_note"
                size: 14
                color: Ilot.playerPal.primary
                anchors.centerIn: parent
            }
            // replie, Ilot.pos n'est plus relu (timer `progress`) : l'anneau
            // le relit toutes les 2 s, seulement quand il se voit
            Timer {
                interval: 2000
                repeat: true
                triggeredOnStart: true
                running: disc.visible && disc.ringOn && mini.on && Ilot.media.playing && !Ilot.fullscreen
                onTriggered: Ilot.pos = Ilot.position()
            }
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
        // Claude Code au travail : animation a gauche de l'heure, temps a droite
        ClaudeMark {
            opacity: Watch.ccShown ? 1 : 0
            scale: 0.6 + 0.4 * opacity
            visible: opacity > 0
            anchors.verticalCenter: parent.verticalCenter
            Behavior on opacity { NumberAnimation { duration: 350 } }
        }
        PillClock {
            anchors.verticalCenter: parent.verticalCenter
        }
        Txt {
            text: Watch.ccText
            px: 12
            weight: Font.Medium
            tnum: true
            color: Theme.inkVariant
            opacity: Watch.ccShown ? 1 : 0
            scale: 0.6 + 0.4 * opacity
            visible: opacity > 0
            anchors.verticalCenter: parent.verticalCenter
            Behavior on opacity { NumberAnimation { duration: 350 } }
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

        // titre en cours : pochette, titre, artiste, barre de progression,
        // precedent / lecture / suivant, sans ouvrir le panneau
        Item {
            visible: Ilot.hasMedia
            anchors.left: parent.left
            anchors.right: peekDc.visible ? peekDc.left : parent.right
            anchors.rightMargin: peekDc.visible ? 8 : 0
            height: parent.height
            Rectangle {
                id: peekArt
                width: 52
                height: 52
                radius: 14
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceHigh
                ArtImage {
                    anchors.fill: parent
                    radius: 14
                }
                transform: Translate { id: swipeX }
                // Reglages > Apparence > Lecteur : glisser la pochette vers la
                // gauche = suivant, vers la droite = precedent ; clic : ouvrir
                MouseArea {
                    anchors.fill: parent
                    enabled: !!Ilot.cfg.player_swipe
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    property real x0: 0
                    property real dx: 0
                    onPressed: m => {
                        x0 = mapToItem(null, m.x, 0).x
                        dx = 0
                    }
                    onPositionChanged: m => {
                        dx = (mapToItem(null, m.x, 0).x - x0) / Ilot.pillK
                        swipeX.x = Math.max(-14, Math.min(14, dx * 0.5))
                    }
                    onReleased: {
                        swipeX.x = 0
                        if (Math.abs(dx) >= 30) {
                            if ((dx < 0 ? Ilot.media.can_next : Ilot.media.can_prev) !== false)
                                Ilot.mediaAction(dx < 0 ? "next" : "prev")
                        }
                        else
                            Ilot.pillClicked()
                    }
                    onCanceled: swipeX.x = 0
                }
            }
            Column {
                anchors.left: peekArt.right
                anchors.leftMargin: 12
                anchors.right: peekCtrls.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    width: parent.width
                    text: Ilot.media.title || "Sans titre"
                    px: 14
                    weight: Font.Medium
                    elide: Text.ElideRight
                }
                Txt {
                    width: parent.width
                    topPadding: 1
                    text: Ilot.media.artist || ""
                    px: 12
                    color: Ilot.playerPal.primary
                    elide: Text.ElideRight
                }
                SeekBar {
                    width: parent.width
                    small: true
                }
            }
            MediaControls {
                id: peekCtrls
                compact: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // heure, date, meteo, mails
        Row {
            visible: !Ilot.hasMedia && !Watch.actShown
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: peekDc.visible ? -35 : 0
            spacing: 10
            // le compagnon, en plus grand : il suit la souris des yeux, se
            // laisse caresser (appui long) et fait des tours (clic, double clic)
            Loader {
                active: Watch.petShown && pill.peek
                visible: active && !Watch.petWinOn
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: Pet {
                    k: 1.45
                    interactive: true
                    tip: Watch.petName + " " + (Watch.petMoodLabels[Watch.mood] || "") + " · niveau " + Watch.petLevel + " — clic, double clic ou appui long"
                    onPoked: Watch.petLoved(1, false)
                    onCaressed: Watch.petLoved(2, true)
                }
            }
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
