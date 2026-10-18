import QtQuick
import QtQuick.Effects

// Media : fond (pochette floutee, couleur, degrade), grande pochette, titre,
// progression, commandes, volume de l'appli, visualiseur, paroles
// synchronisees ; playlists favorites dans un panneau lateral
Rectangle {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "media"
    readonly property string bg: Ilot.cfg.media_bg || "art"
    radius: 22
    color: bg === "color" ? Theme.primaryContainer : Theme.surfaceC
    clip: true
    gradient: bg === "gradient" ? grad : null
    Gradient {
        id: grad
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Theme.mix(Theme.primaryContainer, Theme.surfaceC, 0.85) }
        GradientStop { position: 1; color: Theme.mix(Theme.tertiaryContainer, Theme.surfaceC, 0.6) }
    }

    // ------------------------------------------------ volume de l'appli
    // session audio Windows de l'appli qui joue (Spotify, Chrome...)
    property var appVol: null
    property string volApp: ""
    function refreshAppVolume() {
        volApp = Ilot.hasMedia ? Ilot.media.app : ""
        if (!volApp) {
            appVol = null
            return
        }
        Api.invoke("app_volume_get", { app: volApp }).then(v => { page.appVol = v })
    }
    onShownChanged: if (shown) refreshAppVolume()
    Connections {
        target: Ilot
        function onMediaChanged() {
            if (page.shown && (Ilot.hasMedia ? Ilot.media.app : "") !== page.volApp)
                page.refreshAppVolume()
        }
    }

    // ------------------------------------------- paroles synchronisees
    // src/lyrics.rs (lrclib.net, puis NetEase) ; la ligne en cours suit la
    // position du lecteur. Affichees ou non : garde dans ui.json
    readonly property bool lyricsOn: Ilot.ui.lyrics !== false
    property var ly: ({ key: "", lines: [], state: "" })
    property string lyErr: ""
    readonly property string lyKey: (Ilot.media.artist || "") + "|" + (Ilot.media.title || "")
    function parseLrc(t) {
        const out = []
        for (const row of t.split(/\r?\n/)) {
            const re = /\[(\d+):(\d+(?:[.:]\d+)?)\]/g
            const tags = []
            let m
            while ((m = re.exec(row)) !== null)
                tags.push(m)
            if (!tags.length)
                continue
            const text = row.replace(/\[[^\]]*\]/g, "").trim()
            for (const g of tags)
                out.push({ t: Number(g[1]) * 60 + parseFloat(g[2].replace(":", ".")), text: text })
        }
        return out.sort((a, b) => a.t - b.t)
    }
    function loadLyrics() {
        const key = lyKey
        if (!Ilot.hasMedia || !Ilot.media.title) {
            ly = { key: key, lines: [], state: "none" }
            return
        }
        if (ly.key === key && ly.state !== "error")
            return
        ly = { key: key, lines: [], state: "loading" }
        Api.invoke("lyrics_get", { artist: Ilot.media.artist || "", title: Ilot.media.title, album: Ilot.media.album || "", duration: Ilot.media.duration || 0 }).then(r => {
            if (page.ly.key !== key)
                return
            const synced = r.synced ? page.parseLrc(r.synced) : []
            const lines = synced.length ? synced : r.plain.split(/\r?\n/).map(t => ({ t: -1, text: t }))
            page.ly = { key: key, lines: r.instrumental ? [] : lines, state: r.instrumental ? "instr" : synced.length ? "synced" : r.plain ? "plain" : "none" }
        }, () => {
            if (page.ly.key !== key)
                return
            // serveurs de paroles surcharges : nouvel essai tout seul dans 30 s
            page.ly = { key: key, lines: [], state: "error" }
            Ilot.later(30000, () => { if (page.ly.key === key && page.ly.state === "error") page.loadLyrics() })
        })
    }
    // ligne en cours (petite avance : la ligne s'allume avec la voix)
    readonly property int lyOn: {
        if (ly.state !== "synced")
            return -1
        const p = Ilot.pos + 0.25
        let i = -1
        while (i + 1 < ly.lines.length && ly.lines[i + 1].t <= p)
            i++
        return i
    }
    Timer {
        interval: 200
        repeat: true
        running: page.shown && page.lyricsOn
        onTriggered: {
            Ilot.pos = Ilot.position()
            if (page.lyKey !== page.ly.key)
                page.loadLyrics()
        }
    }

    // pochette floutee (.mp-bg : inset -40px, blur 40px, saturate 1.3)
    Item {
        id: bgSrc
        anchors.fill: parent
        anchors.margins: -40
        visible: false
        Image {
            anchors.fill: parent
            source: Ilot.hasMedia ? Ilot.art : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 400
        }
    }
    MultiEffect {
        anchors.fill: bgSrc
        source: bgSrc
        visible: page.bg === "art" && Ilot.hasMedia && Ilot.art !== "" && page.visible
        blurEnabled: true
        blurMax: 64
        blur: 1
        saturation: 0.3
        opacity: Theme.light ? 0.22 : 0.35
    }

    VizBars {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.38
        opacity: 0.5
        mirror: true
        active: page.shown
    }

    Row {
        id: main
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        // avec les paroles (.ly-on) : le bandeau prend le bas, pochette de 190 px
        anchors.topMargin: page.lyricsOn ? 14 : 24
        anchors.bottomMargin: page.lyricsOn ? 96 : 24
        Behavior on anchors.topMargin { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
        spacing: 28
        property real artMax: page.lyricsOn ? 190 : 260
        Behavior on artMax { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
        readonly property real artSize: Math.min(artMax, height)

        // grande pochette, inclinee en 3D au survol
        Item {
            id: art
            width: main.artSize
            height: main.artSize
            anchors.verticalCenter: parent.verticalCenter
            property real rx: 0
            property real ry: 0
            Behavior on rx { NumberAnimation { duration: 200 } }
            Behavior on ry { NumberAnimation { duration: 200 } }
            transform: [
                Rotation { origin.x: art.width / 2; origin.y: art.height / 2; axis { x: 1; y: 0; z: 0 } angle: art.rx },
                Rotation { origin.x: art.width / 2; origin.y: art.height / 2; axis { x: 0; y: 1; z: 0 } angle: art.ry }
            ]
            MouseArea {
                id: tilt
                anchors.fill: parent
                hoverEnabled: !Theme.reduced
                acceptedButtons: Qt.NoButton
                onPositionChanged: m => {
                    art.ry = (m.x / width - 0.5) * 22
                    art.rx = (0.5 - m.y / height) * 22
                }
                onContainsMouseChanged: if (!containsMouse) { art.rx = 0; art.ry = 0 }
            }
            RectangularShadow {
                anchors.fill: parent
                radius: 28
                offset.y: 12
                blur: 40
                color: Qt.rgba(0, 0, 0, Theme.light ? 0.18 : 0.35)
            }
            Rectangle {
                anchors.fill: parent
                radius: 28
                color: Theme.surfaceHighest
                Ms {
                    anchors.centerIn: parent
                    name: "music_note"
                    size: 64
                    color: Theme.inkVariant
                }
                ArtImage {
                    anchors.fill: parent
                    radius: 28
                }
                // reflet qui suit la souris
                Glow {
                    visible: tilt.containsMouse
                    width: parent.width * 1.2
                    height: width
                    x: tilt.mouseX - width / 2
                    y: tilt.mouseY - height / 2
                    core: 0
                    color: Qt.rgba(1, 1, 1, 0.18)
                }
            }
        }

        Column {
            width: parent.width - main.artSize - 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Chip {
                text: Ilot.hasMedia ? Ilot.media.app || "" : ""
            }
            Item {
                width: 1
                height: 4
                visible: Ilot.hasMedia && !!Ilot.media.app
            }
            Txt {
                width: parent.width
                text: Ilot.hasMedia ? Ilot.media.title || "Sans titre" : "Rien en lecture"
                px: 24
                weight: Font.DemiBold
                lineHeightMode: Text.FixedHeight
                lineHeight: 24 * 1.15
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Txt {
                width: parent.width
                visible: text !== ""
                text: Ilot.hasMedia ? Ilot.media.artist || "" : ""
                px: 15
                color: Theme.primary
                elide: Text.ElideRight
            }
            Txt {
                width: parent.width
                height: Math.max(15, implicitHeight)
                text: Ilot.hasMedia ? Ilot.media.album || "" : ""
                px: 12
                color: Theme.inkVariant
                elide: Text.ElideRight
            }
            Item {
                width: 1
                height: page.lyricsOn ? 6 : 14
            }
            // progression (glisser pour se deplacer dans le titre)
            M3Slider {
                id: seek
                width: parent.width
                to: 1000
                trackH: 6
                thumbH: 18
                readonly property real pct: Ilot.media.duration ? Ilot.pos / Ilot.media.duration : 0
                Binding on value {
                    when: !seek.dragging
                    value: Math.round(seek.pct * 1000)
                }
                onReleased: v => Ilot.seek(v / 1000 * (Ilot.media.duration || 0))
            }
            Item {
                width: parent.width
                height: 18
                Txt {
                    y: 4
                    text: Ilot.fmtTime(seek.dragging ? seek.value / 1000 * (Ilot.media.duration || 0) : Ilot.pos)
                    px: 11
                    tnum: true
                    color: Theme.inkVariant
                }
                Txt {
                    y: 4
                    anchors.right: parent.right
                    text: Ilot.fmtTime(Ilot.media.duration || 0)
                    px: 11
                    tnum: true
                    color: Theme.inkVariant
                }
            }
            Item {
                width: 1
                height: 6
            }
            MediaControls {
                big: true
                anchors.horizontalCenter: parent.horizontalCenter
            }
            // volume de l'appli qui joue
            Row {
                visible: !!page.appVol
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 6
                spacing: 8
                IconBtn {
                    small: true
                    readonly property int n: page.appVol ? Math.round(page.appVol.level * 100) : 0
                    icon: !page.appVol || page.appVol.muted || !n ? "volume_off" : n < 50 ? "volume_down" : "volume_up"
                    tip: "Couper le son de l'appli"
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        const m = !page.appVol.muted
                        page.appVol = { level: page.appVol.level, muted: m }
                        Api.invoke("app_volume_set", { app: page.volApp, muted: m })
                    }
                }
                M3Slider {
                    id: appSlider
                    width: 160
                    trackH: 8
                    thumbH: 18
                    wheelStep: 5
                    anchors.verticalCenter: parent.verticalCenter
                    fill: page.appVol && page.appVol.muted ? 0 : value / 100
                    Binding on value {
                        when: !appSlider.dragging
                        value: page.appVol ? Math.round(page.appVol.level * 100) : 0
                    }
                    onMoved: v => {
                        page.appVol = { level: v / 100, muted: false }
                        Api.invoke("app_volume_set", { app: page.volApp, level: v / 100, muted: false })
                    }
                }
                Txt {
                    width: 26
                    text: page.appVol ? (page.appVol.muted ? "–" : Math.round(page.appVol.level * 100)) : ""
                    px: 11
                    tnum: true
                    color: Theme.inkVariant
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // paroles : bandeau en bas de la page (.ly-bar), la ligne chantee au centre
    Rectangle {
        id: lyBox
        visible: page.lyricsOn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 104
        bottomLeftRadius: page.radius
        bottomRightRadius: page.radius
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.3; color: Theme.alpha(Theme.surface, 0.55) }
            GradientStop { position: 1; color: Theme.alpha(Theme.surface, 0.55) }
        }
        Txt {
            visible: page.ly.state !== "synced" && page.ly.state !== "plain"
            anchors.centerIn: parent
            px: 12.5
            color: Theme.inkVariant
            text: ({ loading: "Recherche des paroles…", none: "Pas de paroles trouvées pour ce morceau.", instr: "♪ Morceau instrumental",
                error: "Serveurs de paroles occupés, nouvel essai dans 30 s…" })[page.ly.state] || ""
        }
        ListView {
            id: lyList
            readonly property bool synced: page.ly.state === "synced"
            anchors.fill: parent
            anchors.leftMargin: 32
            anchors.rightMargin: 32
            visible: synced || page.ly.state === "plain"
            clip: true
            model: page.ly.lines
            spacing: 4
            topMargin: synced ? 36 : 8
            bottomMargin: topMargin
            interactive: !synced
            boundsBehavior: Flickable.StopAtBounds
            highlightRangeMode: synced ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
            preferredHighlightBegin: height / 2 - 12
            preferredHighlightEnd: height / 2 + 12
            highlightMoveDuration: 400
            currentIndex: Math.max(0, page.lyOn)
            delegate: Btn {
                id: line
                required property var modelData
                required property int index
                readonly property bool on: index === page.lyOn
                // fondu en haut et en bas du bandeau (mask-image : transparent, 32 %, 68 %, transparent)
                readonly property real mid: y - lyList.contentY + height / 2
                readonly property real edge: lyList.synced ? Math.max(0, Math.min(1, Math.min(mid, lyList.height - mid) / (lyList.height * 0.32))) : 1
                width: lyList.width
                height: txt.implicitHeight
                active: lyList.synced && modelData.t >= 0
                color: "transparent"
                opacity: edge
                // clic sur une ligne : le lecteur y saute
                onClicked: Ilot.seek(modelData.t)
                Txt {
                    id: txt
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeightMode: Text.FixedHeight
                    lineHeight: px * 1.3
                    text: line.modelData.text || "♪"
                    px: !lyList.synced ? 13 : line.modelData.text ? 15 : 12
                    weight: line.on ? Font.DemiBold : Font.Normal
                    color: line.on ? Theme.primary : Theme.inkVariant
                    opacity: line.on ? 1 : !lyList.synced ? 0.9 : line.hovered ? 0.85 : 0.5
                    scale: line.on ? 1.12 : 1
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    Behavior on color { ColorAnimation { duration: 300 } }
                    Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                }
            }
        }
    }
    onLyricsOnChanged: if (lyricsOn) { ly = { key: "", lines: [], state: "" }; loadLyrics() }
    Component.onCompleted: if (lyricsOn) loadLyrics()

    // paroles
    IconBtn {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.rightMargin: 52
        icon: "lyrics"
        on: page.lyricsOn
        color: on ? Theme.secondaryContainer : hovered ? Theme.mix(Theme.alpha(Theme.ink, 0.1), Theme.alpha(Theme.surface, 0.55), 0.5) : Theme.alpha(Theme.surface, 0.55)
        tip: "Paroles"
        onClicked: Ilot.saveUi({ lyrics: !page.lyricsOn })
    }
    // playlists
    IconBtn {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        icon: "queue_music"
        color: hovered ? Theme.mix(Theme.alpha(Theme.ink, 0.1), Theme.alpha(Theme.surface, 0.55), 0.5) : Theme.alpha(Theme.surface, 0.55)
        tip: "Playlists"
        onClicked: lists.visible = !lists.visible
    }

    // ------------------------------------------- playlists favorites
    // %LOCALAPPDATA%\Ilot\playlists.json : [{ name, url }]
    Rectangle {
        id: lists
        visible: false
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
        width: 300
        radius: 20
        color: Theme.surfaceHigh
        z: 3
        onVisibleChanged: if (visible) slideIn.restart()
        transform: Translate { id: slide; x: 0 }
        ParallelAnimation {
            id: slideIn
            NumberAnimation { target: slide; property: "x"; from: 24; to: 0; duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph }
            NumberAnimation { target: lists; property: "opacity"; from: 0; to: 1; duration: 250 }
        }
        RectangularShadow {
            z: -1
            anchors.fill: parent
            radius: parent.radius
            offset.y: 10
            blur: 34
            color: Qt.rgba(0, 0, 0, 0.45)
        }
        function plIcon(url) {
            return /spotify/.test(url) ? "music_note" : /deezer/.test(url) ? "graphic_eq" : /youtu/.test(url) ? "smart_display" : "queue_music"
        }
        // les liens open.spotify.com s'ouvrent directement dans l'appli Spotify
        function plTarget(url) {
            const m = url.match(/open\.spotify\.com\/(?:intl-\w+\/)?(playlist|album|artist|track)\/(\w+)/)
            return m ? "spotify:" + m[1] + ":" + m[2] : url
        }
        function save() {
            Api.invoke("store_set", { key: "playlists", value: Ilot.playlists })
        }

        Flickable {
            id: plFlick
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            contentHeight: plCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: plCol
                width: parent.width
                spacing: 8
                Item {
                    width: parent.width
                    height: 26
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Playlists"
                        px: 14
                        weight: Font.Bold
                    }
                    IconBtn {
                        anchors.right: parent.right
                        small: true
                        icon: "close"
                        tip: "Fermer"
                        onClicked: lists.visible = false
                    }
                }
                Txt {
                    visible: Ilot.playlists.length === 0
                    text: "Aucune playlist enregistrée."
                    px: 11.5
                    color: Theme.inkVariant
                }
                Column {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: Ilot.playlists
                        Row {
                            required property var modelData
                            required property int index
                            width: plCol.width
                            spacing: 4
                            Btn {
                                width: parent.width - 30
                                height: 38
                                radius: hovered ? 18 : 12
                                Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                                color: Theme.surfaceHighest
                                tip: modelData.url
                                onClicked: {
                                    Api.invoke("open_url", { url: lists.plTarget(modelData.url) })
                                    Ilot.setMode("collapsed")
                                }
                                Row {
                                    x: 10
                                    spacing: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    Ms {
                                        name: lists.plIcon(modelData.url)
                                        color: Theme.primary
                                    }
                                    Txt {
                                        width: parent.parent.width - 50
                                        text: modelData.name
                                        elide: Text.ElideRight
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                            IconBtn {
                                small: true
                                icon: "close"
                                tip: "Retirer"
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: {
                                    const l = Ilot.playlists.slice()
                                    l.splice(index, 1)
                                    Ilot.playlists = l
                                    lists.save()
                                }
                            }
                        }
                    }
                }
                // ajout
                Column {
                    width: parent.width
                    spacing: 6
                    topPadding: 4
                    Field {
                        id: plName
                        width: parent.width
                        height: 38
                        radius: 10
                        pad: 10
                        bg: Theme.surfaceC
                        focusRing: true
                        placeholder: "Nom (ex. Chill)"
                        onFocused: Ilot.pinned = true
                        onAccepted: plUrl.input.forceActiveFocus()
                    }
                    Field {
                        id: plUrl
                        width: parent.width
                        height: 38
                        radius: 10
                        pad: 10
                        bg: Theme.surfaceC
                        focusRing: true
                        placeholder: "Lien Spotify, Deezer, YouTube…"
                        onFocused: Ilot.pinned = true
                        onEdited: bad = false
                        onAccepted: plAdd.clicked(null)
                    }
                    TextBtn {
                        id: plAdd
                        anchors.right: parent.right
                        primary: true
                        icon: "add"
                        text: "Ajouter"
                        onClicked: {
                            const url = plUrl.text.trim()
                            const name = plName.text.trim()
                            if (!name) {
                                plName.input.forceActiveFocus()
                                return
                            }
                            if (!/^(https?:\/\/|spotify:|deezer:\/\/)/.test(url)) {
                                plUrl.bad = true
                                return
                            }
                            Ilot.playlists = Ilot.playlists.concat([{ name: name, url: url }])
                            lists.save()
                            plName.text = ""
                            plUrl.text = ""
                        }
                    }
                }
                Txt {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Dans Spotify : clic droit sur une playlist › Partager › Copier le lien."
                    px: 11.5
                    lineHeight: 1.2
                    color: Theme.inkVariant
                }
            }
        }
    }
}
