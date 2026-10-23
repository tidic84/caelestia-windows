import QtQuick
import QtQuick.Effects
import "ical.mjs" as Ical

// Accueil : utilisateur, meteo, horloge, calendrier, lecteur, ressources,
// volume, session
Item {
    id: home
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "home"
    readonly property real gap: 10
    readonly property real col1: Ilot.big ? 180 : 130
    readonly property real col3: Ilot.big ? 300 : 230
    readonly property real col2: width - col1 - col3 - gap * 2
    readonly property real row1: 62
    readonly property real row3: 68
    readonly property real row4: 52
    readonly property real row2: height - row1 - row3 - row4 - gap * 3

    onShownChanged: if (shown) Ilot.refreshEvents()
    Component.onCompleted: if (shown) Ilot.refreshEvents()

    // ------------------------------------------------- utilisateur, meteo
    Card {
        id: userCard
        width: (col1 + gap + col2 - gap) / 2
        height: row1
        Row {
            x: 10
            spacing: 12
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                width: 42
                height: 42
                radius: 21
                color: Theme.tertiaryContainer
                Txt {
                    anchors.centerIn: parent
                    visible: !Ilot.user.avatar
                    text: ((Ilot.user.name || "?").trim()[0] || "?").toUpperCase()
                    px: 18
                    weight: Font.DemiBold
                    color: Theme.inkTertiaryContainer
                }
                RoundImage {
                    anchors.fill: parent
                    radius: 21
                    visible: !!Ilot.user.avatar
                    source: Ilot.user.avatar || ""
                }
            }
            Column {
                spacing: 2
                width: userCard.width - 42 - 12 - 24
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    width: parent.width
                    text: Ilot.user.name || "Bonjour"
                    px: 14
                    weight: Font.Medium
                    elide: Text.ElideRight
                }
                Txt {
                    text: Ilot.sys ? "Allumé depuis " + Ilot.fmtUptime(Ilot.sys.uptime) : ""
                    px: 12
                    color: Theme.inkVariant
                }
            }
        }
    }
    Card {
        id: wxCard
        x: userCard.width + gap
        width: col1 + gap + col2 - userCard.width - gap
        height: row1
        color: wxBtn.hovered ? Theme.surfaceHigh : Theme.surfaceC
        Behavior on color { ColorAnimation { duration: 200 } }
        Btn {
            id: wxBtn
            anchors.fill: parent
            radius: parent.radius
            onClicked: {
                Ilot.showTab("settings")
                Ilot.later(80, () => Ilot.focusCity())
            }
        }
        Row {
            x: 14
            spacing: 10
            anchors.verticalCenter: parent.verticalCenter
            readonly property var w: Ilot.weather
            Ms {
                name: parent.w ? parent.w.icon : "location_on"
                size: 32
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            Txt {
                visible: !!parent.w
                text: parent.w ? parent.w.temp + "°" : ""
                px: 22
                weight: Font.Medium
                tnum: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Column {
                spacing: 2
                width: wxCard.width - 14 - 32 - 30 - (parent.w ? 60 : 0)
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    width: parent.width
                    text: parent.parent.w ? parent.parent.w.label : "Météo"
                    weight: Font.Medium
                    elide: Text.ElideRight
                }
                Txt {
                    width: parent.width
                    readonly property var w: Ilot.weather
                    text: w ? Ilot.cfg.city.name + " · " + w.min + "° / " + w.max + "°" : Ilot.cfg.city ? Ilot.cfg.city.name : "Choisir une ville"
                    px: 12
                    color: Theme.inkVariant
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ------------------------------------------------------- horloge
    Card {
        id: clockCard
        y: row1 + gap
        width: col1
        height: row2
        color: Theme.primaryContainer
        Column {
            anchors.centerIn: parent
            spacing: 10
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Ilot.pad(Ilot.now.getHours())
                    px: Ilot.big ? 72 : 54
                    weight: Font.DemiBold
                    tnum: true
                    // line-height: .95
                    height: px * 0.95
                    color: Theme.inkPrimaryContainer
                }
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Ilot.pad(Ilot.now.getMinutes())
                    px: Ilot.big ? 72 : 54
                    weight: Font.DemiBold
                    tnum: true
                    // line-height: .95
                    height: px * 0.95
                    color: Theme.alpha(Theme.inkPrimaryContainer, 0.7)
                }
            }
            Txt {
                width: clockCard.width - 28
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Ilot.capitalize(Ilot.fmt(Ilot.now, "dddd d MMMM"))
                px: 12
                opacity: 0.85
                color: Theme.inkPrimaryContainer
            }
        }
    }

    // ---------------------------------------------------- calendrier
    Card {
        id: cal
        x: col1 + gap
        y: row1 + gap
        width: col2
        height: row2
        clip: true

        property int offset: 0
        property bool dayOpen: false
        onDayOpenChanged: {
            if (dayOpen)
                Ilot.overlay = "day"
            else if (Ilot.overlay === "day")
                Ilot.overlay = ""
        }
        Connections {
            target: Ilot
            function onCloseDay() { cal.dayOpen = false }
            function onModeChanged() { if (Ilot.mode !== "open") cal.dayOpen = false }
        }

        readonly property date today: Ilot.now
        readonly property var range: {
            const now = today
            const first = new Date(now.getFullYear(), now.getMonth() + offset, 1)
            const start = new Date(first)
            start.setDate(1 - ((first.getDay() + 6) % 7)) // lundi en premier
            const end = new Date(start)
            end.setDate(start.getDate() + 42)
            return { first: first, start: start, end: end }
        }
        function dayKey(d) {
            return d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate()
        }
        // jours avec des evenements (agendas iCal)
        readonly property var busy: {
            const set = {}
            if (!Ilot.icalTexts.length)
                return set
            const r = range
            for (const e of Ical.eventsBetween(Ilot.icalTexts, r.start, r.end)) {
                const d = new Date(Math.max(e.start, r.start))
                while (d < e.end && d < r.end) {
                    set[dayKey(d)] = true
                    d.setDate(d.getDate() + 1)
                    d.setHours(0, 0, 0, 0)
                }
                if (e.end - e.start <= 0)
                    set[dayKey(e.start)] = true
            }
            return set
        }
        readonly property var days: {
            const out = []
            const d = new Date(range.start)
            for (let i = 0; i < 42; i++) {
                out.push(new Date(d))
                d.setDate(d.getDate() + 1)
            }
            return out
        }

        Item {
            id: monthView
            anchors.fill: parent
            anchors.margins: 14
            Item {
                id: calHead
                width: parent.width
                height: 26
                IconBtn {
                    small: true
                    icon: "chevron_left"
                    tip: "Mois précédent"
                    onClicked: cal.offset--
                }
                Txt {
                    anchors.centerIn: parent
                    text: Ilot.capitalize(Ilot.fmt(cal.range.first, "MMMM yyyy"))
                    weight: Font.Medium
                }
                IconBtn {
                    anchors.right: parent.right
                    small: true
                    icon: "chevron_right"
                    tip: "Mois suivant"
                    onClicked: cal.offset++
                }
            }
            Grid {
                id: grid
                y: calHead.height + 6
                width: parent.width
                height: parent.height - y
                columns: 7
                readonly property real cw: width / 7
                readonly property real ch: height / 7
                Repeater {
                    model: ["L", "M", "M", "J", "V", "S", "D"]
                    Txt {
                        required property string modelData
                        width: grid.cw
                        height: grid.ch
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        px: 11
                        weight: Font.Medium
                        color: Theme.inkVariant
                    }
                }
                Repeater {
                    model: cal.days
                    Item {
                        id: cell
                        required property var modelData
                        required property int index
                        width: grid.cw
                        height: grid.ch
                        readonly property bool out: modelData.getMonth() !== cal.range.first.getMonth()
                        readonly property bool isToday: modelData.toDateString() === cal.today.toDateString()
                        readonly property bool we: index % 7 >= 5
                        readonly property bool ev: !!cal.busy[cal.dayKey(modelData)]
                        readonly property string note: Ilot.calNotes[home.noteKey(modelData)] || ""
                        Btn {
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            radius: 13
                            tip: cell.note
                            color: cell.isToday ? Theme.primary : hovered ? Theme.surfaceHighest : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            onClicked: home.showDay(cell.modelData)
                            Txt {
                                anchors.centerIn: parent
                                text: cell.modelData.getDate()
                                px: 12
                                tnum: true
                                weight: cell.isToday ? Font.DemiBold : Font.Normal
                                opacity: cell.out ? 0.5 : 1
                                color: cell.isToday ? Theme.inkPrimary : cell.out ? Theme.outline : cell.we ? Theme.tertiary : Theme.ink
                            }
                            // evenement (en bas), note (en haut)
                            Rectangle {
                                visible: cell.ev
                                width: 4
                                height: 4
                                radius: 2
                                x: 11
                                y: 21
                                color: cell.isToday ? Theme.inkPrimary : Theme.tertiary
                            }
                            Rectangle {
                                visible: cell.note !== ""
                                width: 4
                                height: 4
                                radius: 2
                                x: 11
                                y: 1
                                color: cell.isToday ? Theme.inkPrimary : Theme.primary
                            }
                        }
                    }
                }
            }
        }

        // jour choisi : evenements et note
        Rectangle {
            id: dayView
            anchors.fill: parent
            color: Theme.surfaceC
            radius: cal.radius
            opacity: cal.dayOpen ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            transform: Translate {
                x: cal.dayOpen ? 0 : 30
                Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
            }
            property date day: new Date()
            property var events: []
            property string key: ""

            Item {
                id: dayHead
                x: 14
                y: 14
                width: parent.width - 28
                height: 26
                IconBtn {
                    small: true
                    icon: "arrow_back"
                    tip: "Retour"
                    onClicked: cal.dayOpen = false
                }
                Txt {
                    anchors.centerIn: parent
                    text: Ilot.capitalize(Ilot.fmt(dayView.day, "dddd d MMMM"))
                    weight: Font.Medium
                }
            }
            Flickable {
                id: evList
                x: 14
                y: dayHead.y + dayHead.height + 6
                width: parent.width - 28
                height: parent.height - y - 64 - 8 - 14
                contentHeight: evCol.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: evCol
                    width: parent.width
                    spacing: 6
                    Empty {
                        visible: dayView.events.length === 0
                        width: parent.width
                        small: true
                        text: Ilot.cfg.icals.length ? "Aucun événement" : "Ajoutez un agenda iCal dans les réglages pour voir vos événements."
                    }
                    Repeater {
                        model: dayView.events
                        Rectangle {
                            required property var modelData
                            width: evCol.width
                            height: 46
                            radius: 14
                            color: Theme.surfaceHigh
                            Rectangle {
                                x: 10
                                y: 8
                                width: 4
                                height: parent.height - 16
                                radius: 2
                                color: Theme.tertiary
                            }
                            Column {
                                x: 24
                                width: parent.width - 34
                                spacing: 2
                                anchors.verticalCenter: parent.verticalCenter
                                Txt {
                                    width: parent.width
                                    text: modelData.title || "Sans titre"
                                    weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Txt {
                                    width: parent.width
                                    text: modelData.when
                                    px: 11.5
                                    color: Theme.inkVariant
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
            Area {
                id: note
                x: 14
                y: parent.height - 14 - 64
                width: parent.width - 28
                height: 64
                fontSize: 12.5
                placeholder: "Note pour ce jour…"
                onFocused: Ilot.pinned = true
                onEdited: {
                    const n = Object.assign({}, Ilot.calNotes)
                    if (text.trim())
                        n[dayView.key] = text
                    else
                        delete n[dayView.key]
                    Ilot.calNotes = n
                    Api.invoke("store_set", { key: "calnotes", value: n })
                }
            }
        }
    }
    function noteKey(d) {
        return d.getFullYear() + "-" + Ilot.pad(d.getMonth() + 1) + "-" + Ilot.pad(d.getDate())
    }
    function showDay(d) {
        const from = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const to = new Date(from)
        to.setDate(to.getDate() + 1)
        const evs = (Ilot.icalTexts.length ? Ical.eventsBetween(Ilot.icalTexts, from, new Date(to - 1)) : []).filter(e => e.end > from && e.start < to)
        dayView.events = evs.map(e => {
            const when = e.allDay || (e.start <= from && e.end >= to) ? "Journée" : Ilot.hm(e.start) + " – " + Ilot.hm(e.end)
            return { title: e.title, when: e.location ? when + " · " + e.location : when }
        })
        dayView.day = from
        dayView.key = noteKey(from)
        note.text = Ilot.calNotes[dayView.key] || ""
        cal.dayOpen = true
    }

    // -------------------------------------------------------- lecteur
    // carte « En lecture » (maquette atelier, accueil C) : fond de pochette
    // floutee, pochette arrondie, titre qui defile, lecture / pause et etat,
    // precedent / suivant, progression
    Card {
        id: mediaCard
        x: col1 + col2 + gap * 2
        width: col3
        height: row1 + row2 + row3 + gap * 2
        clip: true
        readonly property bool paused: Ilot.hasMedia && !Ilot.media.playing

        // fond (.wash) : pochette tres floue (decodee en 48 px) et saturee, qui
        // deborde de 30 px ; flou calcule une fois, masque aux coins de la carte
        Item {
            id: washSrc
            anchors.fill: parent
            anchors.margins: -30
            visible: false
            Image {
                anchors.fill: parent
                source: Ilot.hasMedia ? Ilot.art : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                sourceSize.width: 48
            }
        }
        Item {
            id: washMask
            anchors.fill: washSrc
            visible: false
            layer.enabled: washFx.visible
            Rectangle {
                anchors.fill: parent
                anchors.margins: 30
                radius: mediaCard.radius
            }
        }
        MultiEffect {
            id: washFx
            anchors.fill: washSrc
            source: washSrc
            visible: home.shown && Ilot.hasMedia && Ilot.art !== ""
            blurEnabled: true
            blurMax: 64
            blur: 1
            saturation: 0.6
            opacity: 0.4
            maskEnabled: true
            maskSource: washMask
        }

        Column {
            x: 16
            y: 18
            width: parent.width - 32
            spacing: 3
            // .lbl
            Txt {
                width: parent.width
                text: "EN LECTURE" + (Ilot.hasMedia && Ilot.media.app ? " · " + Ilot.media.app : "")
                px: 10
                weight: Font.DemiBold
                font.letterSpacing: 1.4
                color: Ilot.playerPal.primary
                elide: Text.ElideRight
            }
            // pochette 198 (marges 8 / 10) : reduite et assombrie en pause
            Item {
                width: parent.width
                height: 8 + 198 + 10
                Item {
                    y: 8
                    width: 198
                    height: 198
                    anchors.horizontalCenter: parent.horizontalCenter
                    scale: mediaCard.paused ? 0.92 : 1
                    // --spatial
                    Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1] } }
                    RectangularShadow {
                        anchors.fill: parent
                        radius: 18
                        offset.y: 8
                        blur: 20
                        color: Qt.rgba(0, 0, 0, 0.4)
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: Theme.surfaceHighest
                        Ms {
                            anchors.centerIn: parent
                            name: "music_note"
                            size: 44
                            color: Theme.inkVariant
                        }
                    }
                    ArtImage {
                        anchors.fill: parent
                        radius: 18
                    }
                    // voile de pause (brightness .6)
                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: "black"
                        visible: opacity > 0
                        opacity: mediaCard.paused ? 0.4 : 0
                        Behavior on opacity { NumberAnimation { duration: 400 } }
                    }
                }
            }
            // titre : defile s'il est trop long (comme l'onglet Media)
            Item {
                id: mTitleBox
                width: parent.width
                height: mTitle.implicitHeight
                clip: true
                readonly property real over: mTitle.implicitWidth - width
                property real shift: 0
                Txt {
                    id: mTitle
                    x: mScroll.running ? mTitleBox.shift : 0
                    text: Ilot.hasMedia ? Ilot.media.title || "Sans titre" : "Rien en lecture"
                    px: 17
                    weight: Font.Bold
                }
                SequentialAnimation {
                    id: mScroll
                    running: mTitleBox.over > 4 && home.shown && !Theme.reduced
                    loops: Animation.Infinite
                    onRunningChanged: mTitleBox.shift = 0
                    PauseAnimation { duration: 2500 }
                    NumberAnimation { target: mTitleBox; property: "shift"; from: 0; to: -mTitleBox.over; duration: Math.max(1500, mTitleBox.over * 30); easing.type: Easing.InOutSine }
                    PauseAnimation { duration: 1500 }
                    NumberAnimation { target: mTitleBox; property: "shift"; to: 0; duration: 600; easing.type: Easing.InOutCubic }
                }
            }
            Txt {
                width: parent.width
                height: Math.max(15, implicitHeight)
                text: Ilot.hasMedia ? Ilot.media.artist || "" : ""
                px: 12.5
                color: Theme.inkVariant
                elide: Text.ElideRight
            }
            // lecture / pause, etat, precedent / suivant (marge haute 8)
            Item {
                width: parent.width
                height: 8 + 42
                PlayBtn {
                    id: mPlay
                    y: 8
                    size: 42
                }
                Txt {
                    x: mPlay.width + 8
                    y: 8
                    width: mPrev.x - x - 8
                    height: 42
                    text: Ilot.media.playing ? "Pause" : "Lecture"
                    px: 13
                    weight: Font.Medium
                    elide: Text.ElideRight
                }
                IconBtn {
                    id: mPrev
                    x: mNext.x - 8 - width
                    y: 8 + 5
                    width: 32
                    height: 32
                    iconSize: 20
                    icon: "skip_previous"
                    readonly property bool can: !Ilot.hasMedia || Ilot.media.can_prev !== false
                    opacity: can ? 1 : 0.35
                    tip: "Précédent"
                    // grise : le clic est pris quand meme (pas d'ouverture du panneau)
                    onClicked: if (can) Ilot.mediaAction("prev")
                    onMiddleClicked: Ilot.mediaAction("toggle")
                }
                IconBtn {
                    id: mNext
                    x: parent.width - width
                    y: 8 + 5
                    width: 32
                    height: 32
                    iconSize: 20
                    icon: "skip_next"
                    readonly property bool can: !Ilot.hasMedia || Ilot.media.can_next !== false
                    opacity: can ? 1 : 0.35
                    tip: "Suivant"
                    onClicked: if (can) Ilot.mediaAction("next")
                    onMiddleClicked: Ilot.mediaAction("toggle")
                }
            }
            // progression (marge haute 4), seulement avec un titre
            Item {
                visible: Ilot.hasMedia
                width: parent.width
                height: 4 + 20
                SeekBar {
                    y: 4
                    width: parent.width
                    small: true
                }
            }
        }
    }

    // ----------------------------------------------------- ressources
    Card {
        id: resCard
        y: row1 + row2 + gap * 2
        width: col1 + col2 + gap
        height: row3
        readonly property var r: Ilot.sys
        Row {
            anchors.centerIn: parent
            readonly property real n: resCard.r && resCard.r.battery >= 0 ? 4 : 3
            spacing: (resCard.width - 16 - cpu.width - mem.width - disk.width - (bat.visible ? bat.width : 0)) / (n)
            Gauge {
                id: cpu
                icon: "memory"
                label: "CPU"
                animate: home.shown
                frac: resCard.r ? resCard.r.cpu / 100 : 0
                value: resCard.r ? Math.round(resCard.r.cpu) + " %" : "-"
            }
            Gauge {
                id: mem
                icon: "developer_board"
                label: "RAM"
                animate: home.shown
                frac: resCard.r ? resCard.r.mem_used / resCard.r.mem_total : 0
                value: resCard.r ? Ilot.gb(resCard.r.mem_used) + " / " + Ilot.gb(resCard.r.mem_total) + " Go" : "-"
            }
            // tous les disques : lettre, occupation, place libre (survol : nom du volume)
            Column {
                id: disk
                width: 190
                spacing: 3
                anchors.verticalCenter: parent.verticalCenter
                readonly property var list: resCard.r && resCard.r.disks ? resCard.r.disks.slice(0, 3) : []
                function free(b) {
                    return b >= Math.pow(1024, 4) ? (b / Math.pow(1024, 4)).toFixed(2).replace(".", ",") + " To" : Math.round(b / Math.pow(1024, 3)) + " Go"
                }
                Repeater {
                    model: disk.list
                    Btn {
                        id: dk
                        required property var modelData
                        readonly property real frac: modelData.used / Math.max(1, modelData.total)
                        width: disk.width
                        height: 16
                        cursor: Qt.ArrowCursor
                        tip: (modelData.label ? modelData.label + " (" + modelData.mount + ")" : modelData.mount) + "\n"
                            + disk.free(modelData.used) + " utilisés sur " + disk.free(modelData.total)
                        Ms {
                            name: dk.modelData.removable ? "usb" : "hard_drive"
                            size: 14
                            color: dk.frac > 0.9 ? Theme.bad : Theme.inkVariant
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Txt {
                            x: 18
                            text: dk.modelData.mount
                            px: 11.5
                            weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            x: 40
                            width: parent.width - 40 - 64
                            height: 6
                            radius: 3
                            color: Theme.surfaceHighest
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                width: parent.width * Math.min(1, dk.frac)
                                height: parent.height
                                radius: 3
                                color: dk.frac > 0.9 ? Theme.bad : Theme.primary
                            }
                        }
                        Txt {
                            anchors.right: parent.right
                            text: disk.free(dk.modelData.total - dk.modelData.used) + " libres"
                            px: 10.5
                            tnum: true
                            color: Theme.inkVariant
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
            Gauge {
                id: bat
                visible: !!resCard.r && resCard.r.battery >= 0
                icon: "battery_full"
                label: "Batt."
                animate: home.shown
                frac: resCard.r ? resCard.r.battery / 100 : 0
                value: resCard.r ? resCard.r.battery + (resCard.r.charging ? " % ⚡" : " %") : "-"
            }
        }
    }

    // --------------------------------------------------------- volume
    Card {
        id: volCard
        y: row1 + row2 + row3 + gap * 3
        width: col1 + col2 + gap
        height: row4
        radius: height / 2
        // 0-100 % : volume Windows ; jusqu'a 200 % avec Equalizer APO (Watch.boost)
        readonly property int v: Math.round(Watch.level * 100)
        readonly property int max: Watch.boost === null ? 100 : 200
        onVisibleChanged: if (visible) Watch.refreshBoost()
        IconBtn {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            icon: Ilot.vol.muted || volCard.v === 0 ? "volume_off" : volCard.v > 100 ? "campaign" : volCard.v < 50 ? "volume_down" : "volume_up"
            tip: "Couper / rétablir"
            onClicked: Ilot.setVolume(undefined, !Ilot.vol.muted)
        }
        M3Slider {
            id: volSlider
            x: 10 + 36 + 10
            width: parent.width - x - 10 - 28 - 18
            anchors.verticalCenter: parent.verticalCenter
            wheelStep: 5
            to: volCard.max
            value: volCard.v
            fill: Ilot.vol.muted ? 0 : value / volCard.max
            onMoved: v => Watch.setLevel(v / 100, false)
            onReleased: v => Watch.setLevel(v / 100, true)
            Binding on value {
                when: !volSlider.dragging
                value: volCard.v
            }
        }
        Txt {
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            horizontalAlignment: Text.AlignRight
            text: Ilot.vol.muted ? "–" : volCard.v
            tnum: true
            color: Theme.inkVariant
        }
    }

    // -------------------------------------------------------- session
    Card {
        id: sessCard
        x: col1 + col2 + gap * 2
        y: row1 + row2 + row3 + gap * 3
        width: col3
        height: row4 - 2
        radius: height / 2
        property string armed: ""
        Timer {
            id: disarm
            interval: 3000
            onTriggered: sessCard.armed = ""
        }
        Row {
            anchors.fill: parent
            anchors.margins: 6
            spacing: (width - 5 * 38) / 4
            Repeater {
                model: [
                    { id: "lock", icon: "lock", tip: "Verrouiller" },
                    { id: "sleep", icon: "bedtime", tip: "Veille" },
                    { id: "logout", icon: "logout", tip: "Déconnexion", confirm: true },
                    { id: "restart", icon: "restart_alt", tip: "Redémarrer", confirm: true },
                    { id: "shutdown", icon: "power_settings_new", tip: "Éteindre", confirm: true, danger: true }
                ]
                Btn {
                    required property var modelData
                    readonly property bool armed: sessCard.armed === modelData.id
                    readonly property bool red: armed || (!!modelData.danger && hovered)
                    width: 38
                    height: 38
                    radius: red || hovered ? 14 : 19
                    Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                    color: red ? Theme.error : hovered ? Theme.surfaceHighest : "transparent"
                    tip: modelData.tip + (armed ? " ?" : "")
                    // les actions lourdes demandent un second clic
                    onClicked: {
                        if (modelData.confirm && !armed) {
                            sessCard.armed = modelData.id
                            disarm.restart()
                            return
                        }
                        sessCard.armed = ""
                        Ilot.setMode("collapsed")
                        Api.invoke("session_action", { action: modelData.id })
                    }
                    Ms {
                        anchors.centerIn: parent
                        name: parent.modelData.icon
                        color: parent.red ? Theme.inkError : parent.hovered ? Theme.ink : Theme.inkVariant
                    }
                }
            }
        }
    }
}
