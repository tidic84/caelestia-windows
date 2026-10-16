import QtQuick
import QtQuick.Effects

// Media : pochette floutee en fond, grande pochette, titre, progression,
// commandes, visualiseur ; playlists favorites dans un panneau lateral
Rectangle {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "media"
    radius: 22
    color: Theme.surfaceC
    clip: true

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
        visible: Ilot.hasMedia && Ilot.art !== "" && page.visible
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
        height: 120
        opacity: Theme.light ? 0.22 : 0.3
        active: page.shown
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 24
        anchors.bottomMargin: 24
        spacing: 28

        // grande pochette
        Item {
            width: 260
            height: 260
            anchors.verticalCenter: parent.verticalCenter
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
            }
        }

        Column {
            width: parent.width - 260 - 28
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
                height: 14
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
        }
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
