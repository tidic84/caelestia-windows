import QtQuick

// Conversion des fichiers deposes (src/files.rs, file_convert), a la maniere
// de Convertio : une ligne par fichier avec le format voulu (choisi dans une
// liste par categorie), « Tout convertir en », puis Convertir. Les images
// passent par le crate image, l'audio et la video par ffmpeg (s'il est
// installe). Prend la place de la page en cours tant que Watch.convertOpen.
Item {
    id: page

    // { path, name, kind, to, status ("", "busy", "done", "err"), out, err }
    property var items: []
    property bool ffmpeg: true
    property bool running: false
    // fermeture : une conversion encore en cours ne met plus la liste a jour
    property int gen: 0

    readonly property var exts: ({
        image: ["png", "jpg", "jpeg", "webp", "bmp", "gif", "tif", "tiff", "ico", "heic", "avif"],
        audio: ["mp3", "wav", "flac", "ogg", "m4a", "opus", "aac", "wma"],
        video: ["mp4", "mkv", "mov", "webm", "avi", "wmv", "flv", "m4v"]
    })
    readonly property var cats: [
        { id: "image", label: "Image", icon: "image", formats: ["png", "jpg", "webp", "bmp", "gif"] },
        { id: "audio", label: "Audio", icon: "audiotrack", formats: ["mp3", "wav", "flac", "ogg", "m4a", "opus"] },
        { id: "video", label: "Vidéo", icon: "movie", formats: ["mp4", "mkv", "webm", "avi", "mov", "gif"] }
    ]
    // categories de sortie possibles pour un type de fichier (une video
    // donne aussi son audio)
    function targets(kind) {
        return kind === "image" ? ["image"] : kind === "audio" ? ["audio"] : kind === "video" ? ["video", "audio"] : []
    }
    function kindOf(path) {
        const ext = path.split(".").pop().toLowerCase()
        for (const k in exts)
            if (exts[k].indexOf(ext) >= 0)
                return k
        return ""
    }
    // une categorie qui demande ffmpeg (tout sauf image -> image)
    function needsFfmpeg(kind, cat) {
        return !(kind === "image" && cat === "image")
    }
    function usable(kind, cat) {
        return targets(kind).indexOf(cat) >= 0 && (ffmpeg || !needsFfmpeg(kind, cat))
    }

    function reset(paths) {
        gen++
        running = false
        items = paths.map(p => ({ path: p, name: p.split("\\").pop(), kind: kindOf(p), to: "", status: "", out: "", err: "" }))
        picker.hide()
    }
    function add(paths) {
        const have = items.map(i => i.path)
        items = items.concat(paths.filter(p => have.indexOf(p) < 0)
            .map(p => ({ path: p, name: p.split("\\").pop(), kind: kindOf(p), to: "", status: "", out: "", err: "" })))
    }
    function setItem(i, patch) {
        const list = items.slice()
        list[i] = Object.assign({}, list[i], patch)
        items = list
    }
    function remove(i) {
        const list = items.slice()
        list.splice(i, 1)
        items = list
    }
    // « Tout convertir en » : les categories communes a tous les fichiers convertibles
    readonly property var convertible: items.filter(i => i.kind !== "")
    readonly property var commonCats: cats.map(c => c.id).filter(c => convertible.length > 0 && convertible.every(i => usable(i.kind, c)))
    readonly property int ready: items.filter(i => i.to !== "" && i.status !== "done" && i.status !== "busy").length
    readonly property int doneCount: items.filter(i => i.status === "done").length

    Connections {
        target: Watch
        function onConvertOpenChanged() {
            if (Watch.convertOpen) {
                page.reset(Watch.convertPaths)
                Api.invoke("ffmpeg_ok").then(ok => page.ffmpeg = !!ok)
            } else {
                page.gen++
                page.running = false
                picker.hide()
            }
        }
    }

    // un fichier apres l'autre (ffmpeg peut etre lourd) ; un echec n'arrete
    // pas les suivants, et n'est pas reessaye dans la meme passe
    function pending(from) {
        return items.findIndex((x, k) => k >= from && x.to !== "" && (x.status === "" || x.status === "err"))
    }
    function convertAll() {
        if (running)
            return
        const g = gen
        const step = j => {
            if (g !== gen)
                return
            if (j < 0)
                return running = false
            setItem(j, { status: "busy", err: "" })
            Api.invoke("file_convert", { path: items[j].path, to: items[j].to }).then(out => {
                if (g !== gen)
                    return
                setItem(j, { status: "done", out: out })
                step(pending(j + 1))
            }, e => {
                if (g !== gen)
                    return
                setItem(j, { status: "err", err: String(e) })
                step(pending(j + 1))
            })
        }
        running = true
        step(pending(0))
    }

    function fileIcon(kind) {
        return kind === "image" ? "image" : kind === "audio" ? "audiotrack" : kind === "video" ? "movie" : "description"
    }

    // ------------------------------------------------------------ en-tete
    Item {
        id: head
        width: parent.width
        height: 40
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Ms {
                anchors.verticalCenter: parent.verticalCenter
                name: "autorenew"
                size: 24
                color: Theme.primary
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: "Convertir"
                px: 18
                weight: Font.Medium
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: page.items.length > 1 ? page.items.length + " fichiers" : ""
                color: Theme.inkVariant
            }
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            TextBtn {
                id: allBtn
                visible: page.items.length > 1 && page.commonCats.length > 0
                icon: "expand_more"
                text: "Tout convertir en…"
                onClicked: picker.show(-1, allBtn)
            }
            TextBtn {
                primary: true
                icon: "autorenew"
                text: page.running ? "Conversion…" : "Convertir"
                busy: page.running
                disabled: page.running || page.ready === 0
                onClicked: page.convertAll()
            }
        }
    }

    Txt {
        id: noFf
        visible: !page.ffmpeg && page.items.some(i => i.kind === "audio" || i.kind === "video")
        y: head.height + 4
        width: parent.width
        height: visible ? 22 : 0
        wrapMode: Text.WordWrap
        px: 12
        color: Theme.inkVariant
        text: "L’audio et la vidéo demandent ffmpeg (winget install ffmpeg), introuvable sur ce PC."
    }

    // ------------------------------------------------------------ fichiers
    ListView {
        id: list
        y: head.height + noFf.height + 10
        width: parent.width
        height: parent.height - y
        clip: true
        spacing: 6
        model: page.items
        boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
            id: rowItem
            required property var modelData
            required property int index
            width: list.width - (list.contentHeight > list.height ? 10 : 0)
            height: 52
            radius: 16
            color: Theme.surfaceC
            Ms {
                id: ic
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                name: page.fileIcon(rowItem.modelData.kind)
                size: 22
                color: Theme.inkVariant
            }
            Column {
                x: ic.x + ic.width + 12
                anchors.verticalCenter: parent.verticalCenter
                width: fmtBtn.x - x - 12
                spacing: 1
                Txt {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: rowItem.modelData.name
                    weight: Font.Medium
                }
                Txt {
                    width: parent.width
                    elide: Text.ElideRight
                    px: 11.5
                    color: rowItem.modelData.status === "err" ? Theme.error : Theme.inkVariant
                    text: {
                        const it = rowItem.modelData
                        if (it.kind === "")
                            return "Format non pris en charge"
                        if (it.status === "busy")
                            return "Conversion en cours…"
                        if (it.status === "done")
                            return "Terminé : " + it.out.split("\\").pop()
                        if (it.status === "err")
                            return it.err
                        return it.to ? "Prêt" : "Choisis un format"
                    }
                }
            }
            // format voulu
            TextBtn {
                id: fmtBtn
                anchors.right: actions.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: rowItem.modelData.kind !== ""
                primary: rowItem.modelData.to === "" && rowItem.modelData.status !== "done"
                disabled: rowItem.modelData.status === "busy" || rowItem.modelData.status === "done"
                icon: "expand_more"
                text: rowItem.modelData.to ? rowItem.modelData.to.toUpperCase() : "Format…"
                onClicked: picker.show(rowItem.index, fmtBtn)
            }
            Row {
                id: actions
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Spinner {
                    visible: rowItem.modelData.status === "busy"
                    size: 20
                    anchors.verticalCenter: parent.verticalCenter
                }
                IconBtn {
                    visible: rowItem.modelData.status === "done"
                    icon: "folder_open"
                    tip: "Afficher dans l’Explorateur"
                    onClicked: Api.invoke("file_reveal", { path: rowItem.modelData.out })
                }
                IconBtn {
                    visible: rowItem.modelData.status === "done"
                    icon: "open_in_new"
                    tip: "Ouvrir"
                    onClicked: Api.invoke("file_open", { path: rowItem.modelData.out })
                }
                // pas pendant la conversion : les lignes suivantes changeraient d'indice
                IconBtn {
                    visible: !page.running
                    icon: "close"
                    tip: "Retirer"
                    onClicked: page.remove(rowItem.index)
                }
            }
        }
        Empty {
            visible: list.count === 0
            width: list.width
            text: "Dépose des fichiers ici pour les convertir"
        }
    }
    Scroller { flick: list; visible: list.contentHeight > list.height + 1 }

    // d'autres fichiers deposes sur la page s'ajoutent a la liste
    DropArea {
        id: drop
        anchors.fill: parent
        onEntered: d => {
            if (!d.hasUrls)
                return d.accepted = false
            Ilot.dragIn()
        }
        onExited: Ilot.dragLeft()
        onDropped: d => {
            Ilot.dragDone()
            d.acceptProposedAction()
            page.add(Ilot.dropPaths(d.urls))
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: 18
        color: Theme.alpha(Theme.primary, 0.09)
        border.width: 2
        border.color: Theme.primary
        opacity: drop.containsDrag ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(200) } }
    }

    // ------------------------------------------------- choix du format
    // clic hors de la liste : elle se referme
    MouseArea {
        anchors.fill: parent
        visible: picker.visible
        onClicked: picker.hide()
    }
    Rectangle {
        id: picker
        // ligne visee (-1 : tous les fichiers)
        property int target: -1
        property string cat: ""
        readonly property var kinds: target >= 0 ? (page.items[target] ? [page.items[target].kind] : []) : page.convertible.map(i => i.kind)
        // dans l'ordre du premier fichier (une video : Video, puis Audio)
        readonly property var catList: kinds.length ? page.targets(kinds[0]).filter(id => kinds.every(k => page.targets(k).indexOf(id) >= 0))
            .map(id => page.cats.find(c => c.id === id)) : []
        visible: false
        z: 20
        width: 300
        height: Math.max(catCol.height, fmtFlow.height + (ffNote.visible ? ffNote.height + 8 : 0)) + 20
        radius: 18
        color: Theme.surfaceHigh
        border.width: 1
        border.color: Theme.alpha(Theme.ink, 0.08)

        function show(i, anchor) {
            target = i
            const p = anchor.mapToItem(page, 0, anchor.height + 6)
            x = Math.max(0, Math.min(page.width - width, p.x + anchor.width - width))
            y = p.y + height > page.height ? anchor.mapToItem(page, 0, 0).y - height - 6 : p.y
            const cur = i >= 0 && page.items[i] ? page.items[i].to : ""
            const owner = page.cats.find(c => c.formats.indexOf(cur) >= 0 && catList.indexOf(c) >= 0)
            const first = catList.find(c => page.usable(kinds[0], c.id)) || catList[0]
            cat = owner ? owner.id : first ? first.id : ""
            visible = true
        }
        function hide() {
            visible = false
        }
        function pick(fmt) {
            if (target >= 0)
                page.setItem(target, { to: fmt, status: page.items[target].status === "err" ? "" : page.items[target].status })
            else
                page.items = page.items.map(it => it.kind !== "" && it.status !== "done" && it.status !== "busy"
                    && page.targets(it.kind).indexOf(picker.cat) >= 0 ? Object.assign({}, it, { to: fmt, status: "" }) : it)
            hide()
        }

        // categories a gauche, formats a droite (comme Convertio)
        Column {
            id: catCol
            x: 8
            y: 8
            width: 96
            spacing: 2
            Repeater {
                model: picker.catList
                Btn {
                    required property var modelData
                    readonly property bool on: picker.cat === modelData.id
                    readonly property bool ok: picker.kinds.every(k => page.usable(k, modelData.id))
                    width: catCol.width
                    height: 34
                    radius: 12
                    opacity: ok ? 1 : 0.45
                    color: on ? Theme.secondaryContainer : hovered ? Theme.surfaceHighest : "transparent"
                    onClicked: picker.cat = modelData.id
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 10
                        spacing: 8
                        Ms {
                            anchors.verticalCenter: parent.verticalCenter
                            name: modelData.icon
                            size: 18
                            color: parent.parent.on ? Theme.inkSecondaryContainer : Theme.inkVariant
                        }
                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: parent.parent.on ? Theme.inkSecondaryContainer : Theme.ink
                        }
                    }
                }
            }
        }
        Rectangle {
            x: catCol.x + catCol.width + 6
            y: 10
            width: 1
            height: parent.height - 20
            color: Theme.alpha(Theme.ink, 0.08)
        }
        Flow {
            id: fmtFlow
            x: catCol.x + catCol.width + 14
            y: 10
            width: parent.width - x - 10
            spacing: 6
            readonly property var cat: page.cats.find(c => c.id === picker.cat) || null
            readonly property bool ok: !!cat && picker.kinds.every(k => page.usable(k, cat.id))
            Repeater {
                model: fmtFlow.cat ? fmtFlow.cat.formats : []
                Btn {
                    required property var modelData
                    readonly property bool cur: picker.target >= 0 && page.items[picker.target] && page.items[picker.target].to === modelData
                    width: 56
                    height: 32
                    radius: 10
                    active: fmtFlow.ok
                    opacity: fmtFlow.ok ? 1 : 0.45
                    color: cur ? Theme.primary : hovered ? Theme.surfaceHighest : Theme.surfaceC
                    onClicked: picker.pick(modelData)
                    Txt {
                        anchors.centerIn: parent
                        text: modelData.toUpperCase()
                        px: 12
                        weight: Font.Medium
                        color: parent.cur ? Theme.inkPrimary : Theme.ink
                    }
                }
            }
        }
        Txt {
            id: ffNote
            visible: !fmtFlow.ok && !!fmtFlow.cat
            x: fmtFlow.x
            y: fmtFlow.y + fmtFlow.height + 8
            width: fmtFlow.width
            wrapMode: Text.WordWrap
            px: 11.5
            color: Theme.inkVariant
            text: "Demande ffmpeg, introuvable sur ce PC"
        }
    }
}
