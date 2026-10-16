import QtQuick

// Fonds d'ecran : ceux de Windows (Images\Wallpapers) et ceux de Wallpaper
// Engine s'il est installe ; la palette suit le fond visible
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "walls"
    // "win" | "we"
    property string src: "win"
    property var cache: ({})
    property bool loading: false
    property bool randomBusy: false
    property string applying: ""
    readonly property var list: cache[src] || []
    readonly property var kinds: ({ scene: "Scène", video: "Vidéo", web: "Web", application: "Appli" })

    function samePath(a, b) {
        return !!a && !!b && a.replace(/\//g, "\\").toLowerCase() === b.replace(/\//g, "\\").toLowerCase()
    }
    property bool chosen: false
    Component.onCompleted: if (shown) firstShow()
    onShownChanged: if (shown) firstShow()
    function firstShow() {
        // Wallpaper Engine tourne : on montre ses fonds
        if (!chosen && Ilot.we.installed && Ilot.we.running)
            src = "we"
        chosen = true
        if (!cache[src])
            load(false)
    }
    onSrcChanged: if (shown && !cache[src]) load(false)
    function load(force) {
        const s = src
        if (!force && cache[s])
            return
        loading = true
        Api.invoke(s === "we" ? "we_walls" : "walls_get").then(l => {
            const c = Object.assign({}, page.cache)
            c[s] = l
            page.cache = c
        }).then(() => { page.loading = false }, () => { page.loading = false })
    }
    // le fond a pu changer ailleurs (rotation, WE) : on relit l'etat
    Connections {
        target: Ilot
        function onWallChanged(w) {
            if (page.cache.win) {
                const c = Object.assign({}, page.cache)
                c.win = c.win.map(x => Object.assign({}, x, { cur: !!w && page.samePath(x.path, w.path) }))
                page.cache = c
            }
        }
    }
    function isCur(w) {
        return src === "we" ? samePath(w.path, Ilot.we.current) : !!w.cur
    }
    function pick(w) {
        if (isCur(w) || applying)
            return
        applying = w.path
        const isWe = src === "we"
        // la palette ne suit que le fond reellement visible
        if (isWe || !Ilot.we.running)
            Ilot.themeFrom(w.thumb)
        Api.invoke(isWe ? "we_set" : "wall_set", { path: w.path }).then(ok => {
            // WE met un instant a charger le fond : on garde l'indicateur un peu
            Ilot.later(isWe ? 700 : 0, () => {
                page.applying = ""
                if (!ok) {
                    if (Ilot.currentThumb)
                        Ilot.themeFrom(Ilot.currentThumb)
                    return
                }
                if (isWe) {
                    Ilot.we = Object.assign({}, Ilot.we, { current: w.path, running: true })
                } else {
                    const c = Object.assign({}, page.cache)
                    c.win = (c.win || []).map(x => Object.assign({}, x, { cur: x.path === w.path }))
                    page.cache = c
                }
                if (isWe || !Ilot.we.running)
                    Ilot.currentThumb = w.thumb
            })
        })
    }

    Item {
        id: head
        width: parent.width
        height: 32
        Seg {
            id: seg
            x: 4
            visible: Ilot.we.installed
            anchors.verticalCenter: parent.verticalCenter
            model: [{ id: "win", label: "Windows" }, { id: "we", label: "Wallpaper Engine" }]
            current: page.src
            onPicked: id => page.src = id
        }
        Txt {
            x: seg.visible ? seg.x + seg.width + 8 : 4
            width: buttons.x - x - 8
            anchors.verticalCenter: parent.verticalCenter
            text: page.src === "win" && Ilot.we.running ? "Masqué par Wallpaper Engine" : Ilot.we.installed ? "" : "Les couleurs suivent le fond d'écran"
            px: 12
            color: Theme.inkVariant
            elide: Text.ElideRight
        }
        Row {
            id: buttons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            TextBtn {
                icon: "shuffle"
                text: "Au hasard"
                disabled: page.randomBusy
                onClicked: {
                    page.randomBusy = true
                    Api.invoke("wall_random").then(() => { page.randomBusy = false }, () => { page.randomBusy = false })
                }
            }
            TextBtn {
                icon: "refresh"
                text: "Actualiser"
                onClicked: page.load(true)
            }
            TextBtn {
                visible: page.src === "win"
                icon: "folder_open"
                text: "Dossier"
                onClicked: {
                    Api.invoke("walls_open_folder")
                    Ilot.setMode("collapsed")
                }
            }
        }
    }

    GridView {
        id: grid
        y: head.height + 10
        // la derniere colonne a aussi sa gouttiere (hors de la vue)
        width: parent.width - 4 + 10
        height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cellWidth: width / 4
        cellHeight: 104 + 10
        model: page.list
        delegate: Btn {
            id: wall
            required property var modelData
            readonly property bool cur: page.isCur(modelData)
            readonly property bool busy: page.applying === modelData.path
            width: grid.cellWidth - 10
            height: 104
            radius: busy ? 30 : hovered ? 26 : 18
            Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            color: Theme.surfaceHigh
            scale: busy ? 0.93 : 1
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            tip: modelData.title || modelData.path.split("\\").pop()
            onClicked: page.pick(modelData)

            RoundImage {
                anchors.fill: parent
                radius: wall.radius
                source: wall.modelData.thumb || ""
                zoom: wall.hovered ? 1.06 : 1
                Behavior on zoom { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
            }
            // legende au survol
            Rectangle {
                visible: !!wall.modelData.title
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 46
                bottomLeftRadius: wall.radius
                bottomRightRadius: wall.radius
                opacity: wall.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.7) }
                }
                Row {
                    x: 10
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 7
                    width: parent.width - 20 - (wall.cur ? 30 : 0)
                    spacing: 6
                    Txt {
                        width: parent.width - (kind.visible ? kind.width + 6 : 0)
                        text: wall.modelData.title || ""
                        px: 11.5
                        weight: Font.Medium
                        color: "#ffffff"
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        id: kind
                        visible: !!page.kinds[wall.modelData.kind]
                        width: kindText.implicitWidth + 14
                        height: 17
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.22)
                        anchors.verticalCenter: parent.verticalCenter
                        Txt {
                            id: kindText
                            anchors.centerIn: parent
                            text: page.kinds[wall.modelData.kind] || ""
                            px: 10
                            color: "#ffffff"
                        }
                    }
                }
            }
            // fond actuel : contour et coche
            Rectangle {
                anchors.fill: parent
                radius: wall.radius
                color: "transparent"
                border.width: 3
                border.color: wall.cur ? Theme.primary : "transparent"
            }
            Rectangle {
                visible: wall.cur
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                width: 26
                height: 26
                radius: 13
                color: Theme.primary
                scale: visible ? 1 : 0
                Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                Ms {
                    anchors.centerIn: parent
                    name: "check"
                    size: 17
                    color: Theme.inkPrimary
                }
            }
            // application en cours
            Rectangle {
                anchors.fill: parent
                visible: wall.busy
                radius: wall.radius
                color: Theme.alpha(Theme.surface, 0.45)
                Spinner {
                    anchors.centerIn: parent
                }
            }
        }
        Empty {
            visible: grid.count === 0
            width: grid.width - 10
            text: page.loading || !page.cache[page.src] ? "Chargement…"
                : page.src === "we" ? "Aucun fond Wallpaper Engine trouvé." : "Ajoutez des images dans Images\\Wallpapers."
        }
    }
    Scroller { flick: grid }
}
