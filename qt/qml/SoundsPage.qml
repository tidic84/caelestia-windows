import QtQuick

// Soundboard pour le vocal Discord (src/soundboard.rs) : le vrai micro et les
// sons passent dans la sortie d'un cable virtuel, choisi comme micro dans
// Discord. Liste des sons et reglages dans %LOCALAPPDATA%\Ilot\sounds.json.
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "sounds"
    property var sb: ({ list: [], cfg: { on: false, cable: "", mic: "", monitor: true, mic_gain: 1, exclusive: true } })
    property var devs: ({ outputs: [], inputs: [] })
    property var playing: ({})
    property bool setupOpen: false
    property string hint: ""
    property bool busy: false
    readonly property var colors: ["primary", "secondary", "tertiary"]

    function save() {
        sb = Object.assign({}, sb)
        Api.invoke("store_set", { key: "sounds", value: sb })
    }
    function sendCfg() {
        const c = sb.cfg
        Api.invoke("sb_config", { cfg: { on: !!c.on, cable: c.cable || "", mic: c.mic || "", monitor: c.monitor !== false, mic_gain: c.mic_gain || 1 } })
    }
    // micro du cable : meme nom entre parentheses que la sortie
    // (« Haut-parleurs (Steam Streaming Microphone) » -> « Microphone (Steam Streaming Microphone) »)
    function inner(n) {
        const m = n.match(/\(([^()]*(?:\([^()]*\)[^()]*)*)\)\s*$/)
        return m ? m[1] : n
    }
    function cableInput(out) {
        return out ? devs.inputs.find(i => inner(i.name) === inner(out.name)) || null : null
    }
    readonly property var cableRes: [/CABLE Input/i, /Steam Streaming Microphone/i, /Voicemod/i, /virtual|virtuel/i]
    function pickCable() {
        for (const re of cableRes) {
            const o = devs.outputs.find(d => re.test(d.name) && cableInput(d))
            if (o)
                return o.id
        }
        return ""
    }
    function refreshDevices() {
        return Api.invoke("sb_devices").then(d => {
            page.devs = d
            // premier lancement : cable trouve tout seul
            if (!page.sb.cfg.cable || !d.outputs.some(x => x.id === page.sb.cfg.cable)) {
                const c = page.pickCable()
                if (c !== page.sb.cfg.cable) {
                    page.sb.cfg.cable = c
                    page.save()
                    page.sendCfg()
                }
            }
        })
    }
    readonly property var cableOut: devs.outputs.find(d => d.id === sb.cfg.cable) || null
    readonly property var cableIn: cableInput(cableOut)
    readonly property bool active: !!sb.cfg.on && !!sb.cfg.cable

    // sons choisis ou deposes : decodes cote Rust (mp3, wav, ogg, flac, m4a)
    function importPaths(paths) {
        const list = paths.filter(p => /\.(mp3|wav|ogg|oga|m4a|flac|aac|mp4)$/i.test(p))
        if (!list.length) {
            hint = "⚠ Format non pris en charge (mp3, wav, ogg, flac, m4a)"
            return
        }
        busy = true
        let chain = Promise.resolve()
        for (const p of list) {
            chain = chain.then(() => Api.invoke("sb_import", { path: p }).then(r => {
                page.sb.list.push({ id: r.id, name: r.name, dur: r.dur, vol: 1, color: page.colors[page.sb.list.length % 3] })
                page.save()
            }, e => { page.hint = "⚠ " + p.split("\\").pop() + " : " + e }))
        }
        chain.then(() => { page.busy = false })
    }
    function add() {
        Api.invoke("sb_pick").then(paths => { if (paths.length) page.importPaths(paths) })
    }
    function play(s) {
        if (playing[s.id])
            return Api.invoke("sb_stop", { id: s.id })
        Api.invoke("sb_play", { id: s.id, volume: s.vol === undefined ? 1 : s.vol, exclusive: sb.cfg.exclusive !== false })
    }

    Component.onCompleted: {
        Api.listen("sb-playing", l => {
            const p = {}
            for (const id of l)
                p[id] = true
            page.playing = p
        })
        Api.invoke("store_get", { key: "sounds" }).then(v => {
            if (v && typeof v === "object")
                page.sb = { list: v.list || [], cfg: Object.assign({}, page.sb.cfg, v.cfg || {}) }
            return page.refreshDevices()
        }).then(() => page.sendCfg())
    }

    // ------------------------------------------------------------- en-tete
    Item {
        id: head
        width: parent.width
        height: 36
        Row {
            spacing: 10
            anchors.verticalCenter: parent.verticalCenter
            Btn {
                width: onRow.implicitWidth + 24
                height: 34
                radius: 17
                color: page.active ? Theme.primary : Theme.surfaceHigh
                tip: page.active ? "Désactiver : Discord n'entend plus que ton vrai micro (remets-le dans Discord)" : "Activer : ta voix et les sons passent par le micro virtuel"
                onClicked: {
                    if (!page.sb.cfg.cable) {
                        page.refreshDevices().then(() => { page.setupOpen = true })
                        return
                    }
                    page.sb.cfg.on = !page.sb.cfg.on
                    page.save()
                    page.sendCfg()
                }
                Row {
                    id: onRow
                    anchors.centerIn: parent
                    spacing: 6
                    Ms {
                        name: page.active ? "mic" : "mic_off"
                        size: 18
                        color: page.active ? Theme.inkPrimary : Theme.ink
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Txt {
                        text: page.active ? "Active dans Discord" : "Désactivée"
                        color: page.active ? Theme.inkPrimary : Theme.ink
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
            Txt {
                width: head.width - 180 - x - 150
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                px: 11.5
                color: page.hint ? Theme.error : Theme.inkVariant
                text: page.hint || (!page.sb.cfg.cable ? "Aucun micro virtuel trouvé : choisis-le dans les réglages"
                    : page.active ? "Dans Discord, micro : " + (page.cableIn ? page.cableIn.name : "(câble virtuel)")
                    : "Désactivée : les sons ne sont joués que pour toi")
            }
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            TextBtn {
                icon: "stop_circle"
                text: "Stop"
                tip: "Couper tous les sons"
                onClicked: Api.invoke("sb_stop", {})
            }
            IconBtn {
                icon: "tune"
                on: page.setupOpen
                tip: "Réglages"
                onClicked: {
                    if (page.setupOpen)
                        return page.setupOpen = false
                    page.refreshDevices().then(() => { page.setupOpen = true })
                }
            }
            TextBtn {
                primary: true
                icon: "add"
                text: "Ajouter"
                busy: page.busy
                onClicked: page.add()
            }
        }
    }

    // ---------------------------------------------------------- sons
    GridView {
        id: grid
        y: head.height + 12
        width: parent.width - (page.setupOpen ? 300 : 0)
        height: parent.height - y
        clip: true
        readonly property int cols: Math.max(2, Math.floor(width / 150))
        cellWidth: width / cols
        cellHeight: 92
        model: page.sb.list
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: grid.cellWidth
            height: grid.cellHeight
            readonly property bool on: !!page.playing[modelData.id]
            readonly property string tone: modelData.color || "primary"
            readonly property color bg: tone === "secondary" ? Theme.secondaryContainer : tone === "tertiary" ? Theme.tertiaryContainer : Theme.primaryContainer
            readonly property color fg: tone === "secondary" ? Theme.inkSecondaryContainer : tone === "tertiary" ? Theme.inkTertiaryContainer : Theme.inkPrimaryContainer
            Btn {
                anchors.fill: parent
                anchors.margins: 4
                radius: hovered || cell.on ? 24 : 18
                Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                color: cell.bg
                clip: true
                scale: pressed ? 0.95 : 1
                Behavior on scale { NumberAnimation { duration: 200 } }
                onClicked: page.play(cell.modelData)
                onRightClicked: m => page.menu(cell.modelData, mapToItem(page, m.x, m.y))
                // progression du son en cours
                Rectangle {
                    id: prog
                    height: parent.height
                    color: Theme.alpha(cell.fg, 0.15)
                    property real frac: 0
                    width: parent.width * frac
                    NumberAnimation on frac {
                        id: progAnim
                        running: false
                        from: 0
                        to: 1
                        duration: (cell.modelData.dur || 1) * 1000
                    }
                }
                Column {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28
                    spacing: 2
                    Ms {
                        name: cell.on ? "graphic_eq" : "play_arrow"
                        color: cell.fg
                    }
                    Txt {
                        width: parent.width
                        text: cell.modelData.name
                        weight: Font.Medium
                        elide: Text.ElideRight
                        color: cell.fg
                    }
                    Txt {
                        text: (cell.modelData.dur || 0).toFixed(1).replace(".", ",") + " s" + ((cell.modelData.vol === undefined ? 1 : cell.modelData.vol) !== 1 ? " · " + Math.round(cell.modelData.vol * 100) + " %" : "")
                        px: 11
                        color: cell.fg
                        opacity: 0.75
                    }
                }
            }
            onOnChanged: {
                if (on)
                    progAnim.restart()
                else {
                    progAnim.stop()
                    prog.frac = 0
                }
            }
        }
        Empty {
            visible: !page.sb.list.length
            width: grid.width
            text: "Aucun son. « Ajouter » ou dépose des fichiers audio ici (mp3, wav, ogg, flac, m4a…)."
        }
    }
    Scroller { flick: grid }

    // fichiers audio deposes sur l'onglet
    DropArea {
        anchors.fill: grid
        onEntered: d => {
            if (!d.hasUrls)
                return d.accepted = false
            Ilot.dragIn()
        }
        onExited: Ilot.dragLeft()
        onDropped: d => {
            Ilot.dragDone()
            page.importPaths(Ilot.dropPaths(d.urls))
        }
    }

    // ---------------------------------------------------------- reglages
    Card {
        id: setup
        visible: page.setupOpen
        x: parent.width - width
        y: grid.y
        width: 290
        height: parent.height - y
        color: Theme.surfaceHigh
        Flickable {
            id: sf
            anchors.fill: parent
            anchors.margins: 14
            contentHeight: sc.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: sc
                width: sf.width
                spacing: 6
                Item {
                    width: parent.width
                    height: 26
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Réglages de la soundboard"
                        weight: Font.Bold
                    }
                    IconBtn {
                        anchors.right: parent.right
                        small: true
                        icon: "close"
                        onClicked: page.setupOpen = false
                    }
                }
                Sec { text: "Micro virtuel (sortie où l'îlot envoie ta voix + les sons)" }
                Pick {
                    model: [{ id: "", name: "— Aucun —" }].concat(page.devs.outputs)
                    current: page.sb.cfg.cable || ""
                    onPicked: id => {
                        page.sb.cfg.cable = id
                        page.save()
                        page.sendCfg()
                    }
                }
                Sec { text: "Ton vrai micro" }
                Pick {
                    // le micro du cable ne peut pas etre « ton vrai micro » (larsen)
                    model: [{ id: "", name: "Micro par défaut de Windows" }].concat(page.devs.inputs.filter(d => d !== page.cableIn))
                    current: page.sb.cfg.mic || ""
                    onPicked: id => {
                        page.sb.cfg.mic = id
                        page.save()
                        page.sendCfg()
                    }
                }
                Sec { text: "Volume de ton micro : " + Math.round((page.sb.cfg.mic_gain || 1) * 100) + " %" }
                M3Slider {
                    width: parent.width
                    ringColor: Theme.surfaceHigh
                    from: 0
                    to: 200
                    value: Math.round((page.sb.cfg.mic_gain || 1) * 100)
                    onMoved: v => {
                        page.sb.cfg.mic_gain = Math.max(0.01, v / 100)
                        page.sb = Object.assign({}, page.sb)
                    }
                    onReleased: {
                        page.save()
                        page.sendCfg()
                    }
                }
                Sec { text: "Entendre les sons dans mon casque" }
                Seg {
                    model: [{ id: true, label: "Oui" }, { id: false, label: "Non" }]
                    current: page.sb.cfg.monitor !== false
                    onPicked: v => {
                        page.sb.cfg.monitor = v
                        page.save()
                        page.sendCfg()
                    }
                }
                Sec { text: "Plusieurs sons" }
                Seg {
                    model: [{ id: true, label: "Un à la fois" }, { id: false, label: "Superposer" }]
                    current: page.sb.cfg.exclusive !== false
                    onPicked: v => {
                        page.sb.cfg.exclusive = v
                        page.save()
                    }
                }
                Txt {
                    width: parent.width
                    topPadding: 6
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    px: 11.5
                    color: Theme.inkVariant
                    text: "<b>Dans Discord</b> : Paramètres › Voix et vidéo › Périphérique d'entrée : <i>" + (page.cableIn ? "« " + page.cableIn.name + " »" : "le micro du câble virtuel") + "</i>.<br>"
                        + "Mets aussi la <b>suppression de bruit</b> sur « Standard » ou « Aucune » : Krisp coupe tout ce qui n'est pas une voix, sons compris.<br>"
                        + "Soundboard désactivée = Discord n'entend plus ton micro : remets ton vrai micro dans Discord si tu fermes l'îlot."
                }
            }
        }
        Scroller { flick: sf }
    }

    // ---------------------------------------------------------- menu
    function menu(s, p) {
        const vol = s.vol === undefined ? 1 : s.vol
        ctx.show(p.x, p.y, [
            { type: "title", label: s.name },
            { icon: "edit", label: "Renommer", run: () => ctx.show(p.x, p.y, [{ type: "title", label: "Nom du son" }, { type: "input", value: s.name, done: n => { s.name = n; page.save() } }]) }
        ].concat([0.5, 0.75, 1, 1.5].map(v => ({ icon: vol === v ? "check" : "volume_up", label: "Volume " + v * 100 + " %", run: () => { ctx.hide(); s.vol = v; page.save() } })), [
            { icon: "palette", label: "Changer de couleur", run: () => { ctx.hide(); s.color = page.colors[(page.colors.indexOf(s.color) + 1) % 3]; page.save() } },
            { type: "sep" },
            { icon: "delete", label: "Supprimer", danger: true, confirm: "Confirmer", run: () => {
                ctx.hide()
                page.sb.list = page.sb.list.filter(x => x !== s)
                Api.invoke("sb_delete", { id: s.id })
                page.save()
            } }
        ]))
    }
    CtxMenu {
        id: ctx
        area: page
    }
    MouseArea {
        anchors.fill: parent
        z: 9
        visible: ctx.visible
        onPressed: ctx.hide()
    }

    component Sec: Txt {
        width: parent ? parent.width : 0
        topPadding: 6
        wrapMode: Text.Wrap
        px: 11.5
        weight: Font.Medium
        color: Theme.inkVariant
    }
    // liste de choix (peripheriques) : une ligne par entree
    component Pick: Column {
        id: pk
        property var model: []
        property var current
        signal picked(var id)
        width: parent ? parent.width : 0
        spacing: 2
        Repeater {
            model: pk.model
            Btn {
                required property var modelData
                readonly property bool on: modelData.id === pk.current
                width: pk.width
                height: 30
                radius: 10
                color: on ? Theme.secondaryContainer : hovered ? Theme.surfaceHighest : "transparent"
                onClicked: pk.picked(modelData.id)
                Txt {
                    x: 10
                    width: parent.width - 20
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.name
                    px: 12
                    elide: Text.ElideRight
                    color: parent.on ? Theme.inkSecondaryContainer : Theme.ink
                }
            }
        }
    }
}
