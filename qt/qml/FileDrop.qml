import QtQuick

// Fichiers glisses sur l'ilot : la pilule survolee ne montre qu'une rangee
// de zones de depot, une par action (src/files.rs). Lacher sur une zone
// lance l'action ; le resultat est cree a cote du fichier d'origine, puis
// propose (afficher, ouvrir, Discord). La zone « Applis » ouvre les applis
// (ranger dans un dossier). Affichee tant que Watch.dropOpen (Island.qml).
Item {
    id: page
    // fichiers en cours de glisser (gardes pendant l'action)
    readonly property var paths: Watch.dropPaths
    property int hot: -1
    property bool busy: false
    // { label, outs, ok } une fois l'action finie
    property var result: null

    // ouverture ou fermeture : etat remis a zero ; une action encore en
    // cours (gen perime) n'affichera pas son resultat
    property int gen: 0
    Connections {
        target: Watch
        function onDropOpenChanged() {
            page.gen++
            page.busy = false
            page.result = null
            page.hot = -1
        }
    }
    // glisser ressorti de l'ilot sans rien lacher : les zones s'effacent
    Connections {
        target: Ilot
        function onFileDragChanged() {
            if (!Ilot.fileDrag && !page.busy && !page.result)
                Watch.dropOpen = false
        }
    }

    // resultat affiche sans la souris sur l'ilot : il se replie seul
    Timer {
        running: !!page.result && !Ilot.hovered
        interval: 4000
        onTriggered: Ilot.close()
    }

    readonly property var imgs: paths.filter(f => /\.(png|jpe?g|webp|bmp|gif)$/i.test(f))
    readonly property var zones: [{ id: "convert", icon: "autorenew", label: "Convertir" }].concat(imgs.length ? [
        { id: "shrink", icon: "photo_size_select_large", label: "Réduire" }
    ] : [], [
        { id: "zip", icon: "folder_zip", label: "Zip" },
        { id: "discord", icon: "send", label: "Discord" },
        { id: "share", icon: "nearby", label: "Quick Share" },
        { id: "apps", icon: "apps", label: "Applis" }
    ])

    function run(id, list) {
        const g = gen
        const job = label => fn => {
            busy = true
            fn().then(outs => done(g, label, outs, true), e => done(g, "Échec : " + e, [], false))
        }
        const imgs = list.filter(f => /\.(png|jpe?g|webp|bmp|gif)$/i.test(f))
        switch (id) {
        case "convert":
            return Watch.openConvert(list)
        case "shrink":
            return job("Réduit")(() => Promise.all(imgs.map(f => Api.invoke("img_shrink", { path: f }))))
        case "zip":
            return job("Compressé")(() => Api.invoke("zip_files", { paths: list }).then(z => [z]))
        case "discord":
            return sendToDiscord(list)
        case "share":
            return Watch.openShare(list)
        case "apps":
            Ilot.pinned = true
            return Ilot.open("apps")
        }
    }
    function done(g, label, outs, ok) {
        if (g !== gen)
            return
        busy = false
        result = { label: label, outs: (outs || []).filter(Boolean), ok: ok }
    }
    // Discord n'a pas d'API d'envoi : les fichiers sont copies (comme dans
    // l'Explorateur), puis Discord passe au premier plan : il reste a coller
    function sendToDiscord(list) {
        const g = gen
        busy = true
        Api.invoke("files_copy", { paths: list }).then(ok => {
            if (ok)
                Api.invoke("open_url", { url: "discord://-/channels/@me" })
            done(g, ok ? "Copié, Ctrl+V dans Discord" : "Presse-papiers occupé", [], ok)
        }, e => done(g, "Échec : " + e, [], false))
    }

    // zone la plus proche : les espaces entre zones comptent pour la zone
    // voisine (un lacher n'y est jamais perdu)
    function zoneAt(x, y) {
        const p = row.mapFromItem(page, x, y)
        const cw = (row.width + row.spacing) / Math.max(1, zones.length)
        const i = Math.max(0, Math.min(zones.length - 1, Math.floor(p.x / cw)))
        return zones.length ? i : -1
    }

    // ------------------------------------------------------------ zones
    // les marges sont dans les rangees : la zone de depot couvre toute la
    // pilule (sinon un lacher sur le bord serait perdu)
    Row {
        id: row
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6
        opacity: page.busy || page.result ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(200) } }
        Repeater {
            model: page.zones
            Rectangle {
                id: zone
                required property var modelData
                required property int index
                readonly property bool on: page.hot === index
                width: (row.width - (page.zones.length - 1) * row.spacing) / page.zones.length
                height: row.height
                radius: 16
                color: on ? Theme.primary : Theme.alpha(Theme.primary, 0.1)
                scale: on ? 1.05 : 1
                Behavior on color { ColorAnimation { duration: Theme.dur(150) } }
                Behavior on scale { NumberAnimation { duration: Theme.dur(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.springCurve } }
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 8
                    spacing: 2
                    Ms {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: zone.modelData.icon
                        size: 24
                        color: zone.on ? Theme.inkPrimary : Theme.primary
                    }
                    Txt {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: zone.modelData.label
                        px: 12
                        weight: Font.Medium
                        color: zone.on ? Theme.inkPrimary : Theme.ink
                    }
                }
            }
        }
    }

    // « Applis » survolee un moment : on y passe, le glisser continue
    Timer {
        id: appsHover
        interval: 350
        onTriggered: page.run("apps", [])
    }

    DropArea {
        anchors.fill: parent
        enabled: !page.busy
        onEntered: d => {
            if (!d.hasUrls)
                return d.accepted = false
            Ilot.dragIn()
            // la pilule se replie si l'on ressort (aussi apres un resultat)
            Ilot.fileDragOpened = true
            page.result = null
            Watch.dropPaths = Ilot.dropPaths(d.urls)
        }
        onPositionChanged: d => {
            const z = page.zoneAt(d.x, d.y)
            if (z !== page.hot) {
                page.hot = z
                if (z >= 0 && page.zones[z].id === "apps")
                    appsHover.restart()
                else
                    appsHover.stop()
            }
        }
        onExited: {
            page.hot = -1
            appsHover.stop()
            Ilot.dragLeft()
        }
        onDropped: d => {
            appsHover.stop()
            const z = page.zoneAt(d.x, d.y)
            page.hot = -1
            const list = Ilot.dropPaths(d.urls)
            d.acceptProposedAction()
            // l'action d'abord : busy evite que la fin du glisser referme les zones
            if (z >= 0)
                page.run(page.zones[z].id, list)
            Ilot.dragDone()
        }
    }

    // ------------------------------------------------------------ resultat
    Row {
        id: res
        anchors.verticalCenter: parent.verticalCenter
        x: 16
        width: parent.width - 32
        spacing: 8
        opacity: page.busy || page.result ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(200) } }
        readonly property var outs: page.result ? page.result.outs : []
        Spinner {
            visible: page.busy
            size: 22
            anchors.verticalCenter: parent.verticalCenter
        }
        Ms {
            visible: !page.busy && !!page.result
            anchors.verticalCenter: parent.verticalCenter
            name: page.result && !page.result.ok ? "close" : "check"
            size: 22
            color: page.result && !page.result.ok ? Theme.error : Theme.primary
        }
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            width: res.width - 22 - btns.width - res.spacing * 2
            elide: Text.ElideMiddle
            weight: Font.Medium
            text: page.busy ? "En cours…" : !page.result ? ""
                : page.result.label + (page.result.outs.length > 1 ? " : " + page.result.outs.length + " fichiers"
                    : page.result.outs.length ? " : " + page.result.outs[0].split("\\").pop() : "")
        }
        Row {
            id: btns
            visible: !page.busy && !!page.result
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            IconBtn {
                visible: res.outs.length > 0
                icon: "folder_open"
                tip: "Afficher dans l’Explorateur"
                onClicked: Api.invoke("file_reveal", { path: res.outs[0] })
            }
            IconBtn {
                visible: res.outs.length === 1
                icon: "open_in_new"
                tip: "Ouvrir"
                onClicked: Api.invoke("file_open", { path: res.outs[0] })
            }
            IconBtn {
                visible: res.outs.length > 0
                icon: "send"
                tip: "Envoyer sur Discord"
                onClicked: page.sendToDiscord(res.outs)
            }
            IconBtn {
                icon: "close"
                tip: "Fermer"
                onClicked: Watch.dropOpen = false
            }
        }
    }
}
