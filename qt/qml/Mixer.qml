import QtQuick
import QtQuick.Layouts

// Melangeur de la carte audio (Controles) : une pastille par sortie (volume,
// filtre multiple, cible de depot), puis les applis groupees par sortie
// (etiquettes collantes et repliables, point = changer de sortie, poignee
// a glisser sur une pastille ou une etiquette).
Item {
    id: mx
    property bool shown: false

    // [{id, name, default, level, muted, apps:[{pids, name, icon, level, muted}]}]
    property var devs: []
    // infos d'affichage par id de sortie (nom court, icone, couleur, applis)
    property var chanMap: ({})
    property var filter: []
    property var closed: ({})
    property string openKey: ""
    property string flashKey: ""
    readonly property bool multi: chanModel.count > 1
    // sorties masquees (hors essentiel) et bouton « +N » pour les montrer
    property int hiddenCount: 0
    property bool showAll: false
    onShowAllChanged: rebuild()
    readonly property bool filtering: filter.length > 0

    // glisser d'une appli : { key, name, icon, pids, from }
    property var drag: null
    property real dragX: 0
    property real dragY: 0
    property string dropId: ""
    property var targets: []
    property bool sliding: false
    readonly property bool busy: drag !== null || sliding

    function refresh() {
        // pas pendant un glisser, ni avant l'envoi du dernier volume
        if (busy || outTimer.running)
            return
        Api.invoke("mixer_all").then(l => {
            if (!mx.busy && !outTimer.running && Array.isArray(l))
                mx.devs = mx.withPending(l)
        })
    }
    Timer {
        interval: 2000
        repeat: true
        running: mx.shown
        onTriggered: mx.refresh()
    }

    onDevsChanged: rebuild()
    onFilterChanged: rebuild()

    // Echap vide le filtre avant de refermer l'ilot
    readonly property bool wantOverlay: filtering && shown
    onWantOverlayChanged: {
        if (wantOverlay && Ilot.overlay === "")
            Ilot.overlay = "mixfilter"
        else if (!wantOverlay && Ilot.overlay === "mixfilter")
            Ilot.overlay = ""
    }
    Component.onDestruction: {
        flush()
        if (Ilot.overlay === "mixfilter")
            Ilot.overlay = ""
    }
    Connections {
        target: Ilot
        function onEscapeOverlay(what) { if (what === "mixfilter") mx.filter = [] }
        // une feuille refermee rend la main au filtre
        function onOverlayChanged() { if (Ilot.overlay === "" && mx.wantOverlay) Ilot.overlay = "mixfilter" }
    }

    // ------------------------------------------------------------ donnees
    readonly property var neutral: ["#cac4d0", "#ffb59c", "#b5d0f0", "#c8e6a0", "#f0d8a0"]
    function chanInfo(d, n) {
        const m = /sonar\s*-\s*(gaming|game|chat|media|aux|microphone)/i.exec(d.name)
        if (m) {
            const k = m[1].toLowerCase()
            const s = {
                gaming: ["Game", "sports_esports", "#cfbdfe"], game: ["Game", "sports_esports", "#cfbdfe"],
                chat: ["Chat", "forum", "#a8c8ff"], media: ["Media", "music_note", "#9ad8a8"], aux: ["Aux", "tune", "#efb8c8"],
                microphone: ["Micro", "mic", "#a0dcd8"]
            }[k]
            return { short: s[0], label: "Sonar · " + s[0], icon: s[1], col: s[2], sonar: true }
        }
        const hdmi = /hdmi|displayport/i.exec(d.name)
        const s = hdmi ? (hdmi[0].toLowerCase() === "hdmi" ? "HDMI" : "DisplayPort") : d.name.replace(/\s*\([^)]*\)/g, "").trim() || d.name
        return {
            short: s,
            // « Speakers (High Definition Audio Device) » → « Speakers »
            label: d.name.replace(/\s*\([^()]*\)\s*$/, "") || d.name,
            icon: /casque|headphone|headset|écouteur|airpods|buds/i.test(d.name) ? "headphones" : hdmi ? "monitor" : "speaker",
            col: neutral[n % neutral.length],
            sonar: false
        }
    }
    // met a jour un ListModel sur place (les delegues survivent au sondage)
    function sync(model, arr) {
        for (let i = 0; i < arr.length; i++) {
            const o = arr[i]
            let j = -1
            for (let k = i; k < model.count; k++) {
                if (model.get(k).key === o.key) {
                    j = k
                    break
                }
            }
            if (j < 0) {
                model.insert(i, o)
                continue
            }
            if (j !== i)
                model.move(j, i, 1)
            const cur = model.get(i)
            for (const p in o) {
                if (cur[p] !== o[p])
                    model.setProperty(i, p, o[p])
            }
        }
        if (model.count > arr.length)
            model.remove(arr.length, model.count - arr.length)
    }
    function rebuild() {
        const map = {}
        const chans = []
        let n = 0
        // canaux Sonar d'abord, dans leur ordre, puis les autres sorties
        const rank = d => {
            const i = ["Game", "Chat", "Media", "Aux", "Micro"].indexOf(chanInfo(d, 0).sonar ? chanInfo(d, 0).short : "")
            return i < 0 ? 9 : i
        }
        const ordered = devs.map((d, i) => [rank(d), i, d]).sort((a, b) => a[0] - b[0] || a[1] - b[1]).map(x => x[2])
        // l'essentiel : avec Sonar, ses canaux Game / Chat / Media / Aux (les
        // sorties physiques sont alimentees par Sonar) ; sinon la sortie par
        // defaut. Plus toute sortie ou joue une vraie appli. « +N » montre tout.
        const sonar = ordered.some(d => { const ci = chanInfo(d, 0); return ci.sonar && ci.short !== "Micro" })
        let hidden = 0
        for (const d of ordered) {
            const c = chanInfo(d, n)
            if (!c.sonar)
                n++
            c.id = d.id
            c.name = d.name
            c.def = !!d.default
            // chaque sortie a ses « Sons système » : seuls ceux de la sortie
            // par defaut comptent
            c.apps = (d.apps || []).filter(a => c.def || !(a.icon === "" && a.name === "Sons système"))
            // noms courts en double (deux sorties HDMI...) : « HDMI », « HDMI 2 »
            const same = chans.filter(x => map[x.key].baseShort === c.short).length
            c.baseShort = c.short
            if (same) {
                c.short += " " + (same + 1)
                c.label += " " + (same + 1)
            }
            map[d.id] = c
            const real = c.apps.some(a => !(a.icon === "" && a.name === "Sons système"))
            c.shown = showAll || real || c.def || (sonar && c.sonar && c.baseShort !== "Micro")
            if (!c.shown) {
                hidden++
                continue
            }
            chans.push({
                key: d.id, name: d.name, label: c.label, shortName: c.short, icon: c.icon, col: c.col,
                def: c.def, level: d.level, muted: !!d.muted, count: c.apps.length
            })
        }
        hiddenCount = hidden
        const f = filter.filter(id => !!map[id] && map[id].shown)
        if (f.length !== filter.length || (f.length && f.length === chans.length)) {
            filter = f.length === chans.length ? [] : f
            return
        }
        chanMap = map
        sync(chanModel, chans)
        const rows = []
        for (const d of ordered) {
            const c = map[d.id]
            if (!c.shown || (filter.length ? !filter.includes(d.id) : !c.apps.length))
                continue
            if (!c.apps.length)
                rows.push({ key: d.id + "|", chan: d.id, kind: "empty", name: "", icon: "", pids: "", level: 0, muted: false })
            const seen = {}
            for (const a of c.apps) {
                let k = d.id + "|" + a.name
                seen[k] = (seen[k] || 0) + 1
                if (seen[k] > 1)
                    k += "#" + seen[k]
                rows.push({
                    key: k, chan: d.id, kind: a.icon === "" && a.name === "Sons système" ? "sys" : "app",
                    name: a.name, icon: a.icon || "", pids: a.pids.join(","), level: a.level, muted: !!a.muted
                })
            }
        }
        sync(rowModel, rows)
    }
    function pidsOf(s) {
        return s === "" ? [] : s.split(",").map(Number)
    }
    function toggleFilter(id) {
        const f = filter.slice()
        const i = f.indexOf(id)
        if (i >= 0)
            f.splice(i, 1)
        else
            f.push(id)
        filter = f.length === chanModel.count ? [] : f
        list.contentY = list.originY
    }
    function toggleClosed(id) {
        const c = Object.assign({}, closed)
        if (c[id])
            delete c[id]
        else
            c[id] = true
        closed = c
    }
    function setChanLevel(i, v) {
        v = Math.max(0, Math.min(100, Math.round(v)))
        chanModel.setProperty(i, "level", v / 100)
        chanModel.setProperty(i, "muted", false)
        send("dev|" + chanModel.get(i).key, "device_volume_set", { id: chanModel.get(i).key, level: v / 100, muted: false })
    }
    // volumes pendant un glisser : seule la derniere valeur part, toutes les
    // 60 ms (les appels du pool pourraient sinon arriver dans le desordre)
    property var outq: ({})
    function send(k, cmd, args) {
        outq[k] = [cmd, args]
        if (!outTimer.running)
            outTimer.start()
    }
    Timer {
        id: outTimer
        interval: 60
        onTriggered: mx.flush()
    }
    function flush() {
        const q = outq
        outq = {}
        for (const k in q)
            Api.invoke(q[k][0], q[k][1])
    }
    // appli vers une autre sortie : deplacee tout de suite dans la liste,
    // puis relue (la session met un peu de temps a migrer)
    // changements de sortie en cours : la session met un peu de temps a
    // migrer, la liste les montre deja pendant 2,5 s
    property var pending: []
    function moveApp(l, name, pids, from, to) {
        const src = l.find(d => d.id === from)
        const dst = l.find(d => d.id === to)
        if (!src || !dst || dst.apps.some(x => x.name === name))
            return
        const i = src.apps.findIndex(a => a.name === name && a.pids.some(p => pids.includes(p)))
        if (i < 0)
            return
        dst.apps.push(src.apps.splice(i, 1)[0])
    }
    function withPending(l) {
        const now = Date.now()
        pending = pending.filter(p => p.until > now)
        for (const p of pending)
            moveApp(l, p.name, p.pids, p.from, p.to)
        return l
    }
    function route(app, to) {
        openKey = ""
        if (app.from === to)
            return
        const l = JSON.parse(JSON.stringify(devs))
        moveApp(l, app.name, app.pids, app.from, to)
        const p = { name: app.name, pids: app.pids, from: app.from, to: to, until: Date.now() + 2500 }
        pending = pending.filter(x => x.name !== app.name).concat([p])
        if (closed[to])
            toggleClosed(to)
        flashKey = to + "|" + app.name
        devs = l
        Ilot.later(1200, () => { mx.flashKey = "" })
        // vers la sortie par defaut : l'appli la suit de nouveau (id vide)
        const def = !!(chanMap[to] && chanMap[to].def)
        Api.invoke("app_route", { pids: app.pids, device: def ? "" : to }).then(ok => {
            if (!ok) {
                mx.pending = mx.pending.filter(x => x !== p)
                mx.refresh()
                return
            }
            const c = mx.chanMap[to]
            mx.note = app.name + " → " + (c ? c.short : "") + ". Si le son ne bascule pas, relance l'appli."
            noteTimer.restart()
        })
        Ilot.later(300, mx.refresh)
        Ilot.later(1500, mx.refresh)
        Ilot.later(2700, mx.refresh)
    }

    // ------------------------------------------------------------ glisser
    function beginDrag(a) {
        openKey = ""
        drag = a
        hitTest()
    }
    function moveDrag(p) {
        dragX = p.x
        dragY = p.y
        hitTest()
    }
    function hitTest() {
        let id = ""
        if (drag) {
            for (const t of targets) {
                if (t.tid !== drag.from && t.hit(dragX, dragY)) {
                    id = t.tid
                    break
                }
            }
        }
        dropId = id
    }
    function endDrag() {
        const a = drag
        const to = dropId
        drag = null
        dropId = ""
        if (a && to)
            route(a, to)
    }
    function addTarget(t) {
        targets = targets.concat([t])
    }
    function removeTarget(t) {
        targets = targets.filter(x => x !== t)
    }
    // defilement automatique pres des bords de la liste
    Timer {
        interval: 16
        repeat: true
        running: mx.drag !== null
        onTriggered: {
            const p = list.mapFromItem(mx, mx.dragX, mx.dragY)
            if (p.x < 0 || p.x > list.width)
                return
            const lo = list.originY
            const hi = list.originY + Math.max(0, list.contentHeight - list.height)
            if (p.y < 30 && p.y > -10)
                list.contentY = Math.max(lo, list.contentY - 8)
            else if (p.y > list.height - 30 && p.y < list.height + 10)
                list.contentY = Math.min(hi, list.contentY + 8)
        }
    }

    ListModel { id: chanModel }
    ListModel { id: rowModel }

    // ----------------------------------------------------------- pastilles
    Row {
        id: pills
        visible: mx.multi || mx.hiddenCount > 0 || mx.showAll
        width: parent.width
        height: visible ? 46 : 0
        spacing: 6
        readonly property bool wide: chanModel.count <= 3
        Repeater {
            model: chanModel
            Rectangle {
                id: pill
                required property int index
                required property string key
                required property string name
                required property string shortName
                required property string icon
                required property string col
                required property bool def
                required property real level
                required property bool muted
                required property int count
                readonly property color cc: col
                readonly property bool sel: mx.filter.includes(key)
                readonly property bool target: mx.drag !== null && mx.drag.from !== key
                readonly property bool hot: target && mx.dropId === key
                readonly property int pct: Math.round(level * 100)
                readonly property string tid: key
                function hit(x, y) {
                    return contains(mapFromItem(mx, x, y))
                }
                Component.onCompleted: mx.addTarget(pill)
                Component.onDestruction: {
                    mx.removeTarget(pill)
                    if (pma.pressed)
                        mx.sliding = false
                }
                width: (pills.width - (more.visible ? more.width + pills.spacing : 0) - pills.spacing * (chanModel.count - 1)) / Math.max(1, chanModel.count)
                height: 46
                radius: 14
                color: hot ? Theme.mix(cc, Theme.surfaceHigh, 0.16) : Theme.surfaceHigh
                opacity: mx.filtering && !sel && !target ? 0.45 : 1
                Behavior on opacity { NumberAnimation { duration: 250 } }
                scale: hot ? 1.08 : target ? 1.04 : 1
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
                activeFocusOnTab: true
                Accessible.role: Accessible.Slider
                Accessible.name: name

                // remplissage = volume (vertical, ou horizontal en pastilles larges)
                Item {
                    clip: true
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    width: pills.wide ? parent.width * (pill.muted ? 0 : pill.level) : parent.width
                    height: pills.wide ? parent.height : parent.height * (pill.muted ? 0 : pill.level)
                    Rectangle {
                        y: parent.height - pill.height
                        width: pill.width
                        height: pill.height
                        radius: pill.radius
                        color: Theme.alpha(pill.cc, 0.24)
                    }
                }
                Txt {
                    visible: !pills.wide
                    anchors.top: parent.top
                    anchors.topMargin: 3
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    // niveau dans le coin, le nom en entier dessous
                    text: pill.muted ? "–" : pill.pct
                    px: 9.5
                    tnum: true
                    color: Theme.outline
                }
                Column {
                    visible: !pills.wide
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 3
                    Ms {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: pill.icon
                        size: 17
                        color: pill.cc
                    }
                    Txt {
                        width: parent.width - 12
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        // pastilles etroites (toutes les sorties) : icone seule
                        text: pill.width < 52 ? "" : pill.shortName
                        px: 10.5
                        tnum: true
                        elide: Text.ElideRight
                        color: Theme.inkVariant
                    }
                }
                Row {
                    visible: pills.wide
                    x: 12
                    width: parent.width - 12 - wideVal.width - 14 - 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Ms {
                        id: wideIcon
                        anchors.verticalCenter: parent.verticalCenter
                        name: pill.icon
                        size: 17
                        color: pill.cc
                    }
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - wideIcon.width - 8 - wideStar.width - wideCount.implicitWidth - 4)
                        text: pill.shortName
                        px: 11.5
                        weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Ms {
                        id: wideStar
                        visible: pill.def
                        width: visible ? 12 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        name: "star"
                        size: 12
                        color: Theme.primary
                    }
                    Txt {
                        id: wideCount
                        anchors.verticalCenter: parent.verticalCenter
                        text: " · " + pill.count
                        px: 11.5
                        color: Theme.outline
                    }
                }
                Txt {
                    id: wideVal
                    visible: pills.wide
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.muted ? "–" : pill.pct
                    px: 12
                    tnum: true
                    color: Theme.inkVariant
                }
                // choisie dans le filtre, ou cible de depot
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 2
                    border.color: pill.cc
                    visible: pill.sel || pill.hot
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -2
                    radius: parent.radius + 2
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.primary
                    visible: pill.activeFocus
                }
                MouseArea {
                    id: pma
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: pills.wide ? Qt.SizeHorCursor : Qt.SizeVerCursor
                    property real x0: 0
                    property real y0: 0
                    property real l0: 0
                    property bool moved: false
                    onPressed: m => {
                        x0 = m.x
                        y0 = m.y
                        l0 = pill.pct
                        moved = false
                        mx.sliding = true
                    }
                    onPositionChanged: m => {
                        if (!pressed)
                            return
                        const d = pills.wide ? m.x - x0 : y0 - m.y
                        if (Math.abs(d) > 3)
                            moved = true
                        if (moved)
                            mx.setChanLevel(pill.index, l0 + (pills.wide ? d / (pill.width / 100) : d / 1.2))
                    }
                    onReleased: {
                        mx.sliding = false
                        if (!moved) {
                            pill.forceActiveFocus()
                            mx.toggleFilter(pill.key)
                        }
                    }
                    onCanceled: mx.sliding = false
                    onWheel: w => mx.setChanLevel(pill.index, pill.pct + (w.angleDelta.y > 0 ? 5 : -5))
                }
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Up || e.key === Qt.Key_Right)
                        mx.setChanLevel(index, pct + 5)
                    else if (e.key === Qt.Key_Down || e.key === Qt.Key_Left)
                        mx.setChanLevel(index, pct - 5)
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)
                        mx.toggleFilter(key)
                    else
                        return
                    e.accepted = true
                }
                Tip {
                    text: pill.name + (pill.def ? " (par défaut)" : "") + "\nGlisser " + (pills.wide ? "↔" : "↕") + " ou molette : volume · clic : filtrer (plusieurs possibles)"
                    shown: pma.containsMouse && !pma.pressed && mx.drag === null
                }
            }
        }
        // « +N » : sorties hors essentiel (sorties physiques sous Sonar, HDMI...)
        Btn {
            id: more
            visible: mx.hiddenCount > 0 || mx.showAll
            width: visible ? 40 : 0
            height: 46
            radius: 14
            color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
            onClicked: mx.showAll = !mx.showAll
            Txt {
                anchors.centerIn: parent
                visible: !mx.showAll
                text: "+" + mx.hiddenCount
                px: 12
                weight: Font.Medium
                tnum: true
                color: Theme.inkVariant
            }
            Ms {
                anchors.centerIn: parent
                visible: mx.showAll
                name: "close"
                size: 17
                color: Theme.inkVariant
            }
            Tip {
                text: mx.showAll ? "Ne garder que l'essentiel" : mx.hiddenCount + " autre" + (mx.hiddenCount > 1 ? "s" : "") + " sortie" + (mx.hiddenCount > 1 ? "s" : "") + " (physiques, HDMI…)"
                shown: more.hovered
            }
        }
    }

    // --------------------------------------------------------------- liste
    ListView {
        id: list
        y: pills.visible ? pills.height + 4 : 0
        width: parent.width - 4
        height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // garde tous les delegues (le glisser ne doit pas perdre le sien)
        cacheBuffer: 4000
        model: rowModel
        section.property: "chan"
        section.criteria: ViewSection.FullString
        section.labelPositioning: ViewSection.InlineLabels | ViewSection.CurrentLabelAtStart
        section.delegate: Item {
            id: sec
            required property string section
            readonly property var info: mx.chanMap[section] || null
            readonly property color cc: info ? info.col : Theme.outline
            readonly property bool shut: !!mx.closed[section]
            readonly property string tid: section
            readonly property bool target: mx.drag !== null && mx.drag.from !== section
            readonly property bool hot: target && mx.dropId === section
            function hit(x, y) {
                return visible && list.contains(list.mapFromItem(mx, x, y)) && lab.contains(lab.mapFromItem(mx, x, y))
            }
            Component.onCompleted: mx.addTarget(sec)
            Component.onDestruction: mx.removeTarget(sec)
            width: list.width
            height: 30
            Btn {
                id: lab
                width: parent.width
                height: 28
                radius: 9
                color: sec.hot ? Theme.mix(sec.cc, Theme.surfaceC, 0.16) : hovered ? Theme.mix(sec.cc, Theme.surfaceC, 0.1) : Theme.surfaceC
                border.width: sec.hot ? 2 : sec.target ? 1.5 : 0
                border.color: sec.hot ? sec.cc : Theme.outlineVariant
                tip: (sec.shut ? "Déplier" : "Replier") + " · on peut y lâcher une appli"
                onClicked: mx.toggleClosed(sec.section)
                RowLayout {
                    x: 6
                    width: parent.width - 10
                    height: parent.height
                    spacing: 6
                    Ms {
                        name: "expand_more"
                        size: 17
                        color: Theme.outline
                        rotation: sec.shut ? -90 : 0
                        Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
                    }
                    Ms {
                        name: sec.info ? sec.info.icon : "speaker"
                        size: 15
                        color: sec.cc
                    }
                    Txt {
                        Layout.maximumWidth: implicitWidth
                        Layout.fillWidth: true
                        Layout.preferredWidth: implicitWidth
                        text: sec.info ? sec.info.label : ""
                        px: 11
                        color: sec.cc
                        elide: Text.ElideRight
                    }
                    Ms {
                        visible: !!sec.info && sec.info.def
                        name: "star"
                        size: 12
                        color: sec.cc
                    }
                    Txt {
                        text: "· " + (sec.info ? sec.info.apps.length : 0)
                        px: 11
                        color: Theme.outline
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 8
                        Layout.preferredHeight: 1
                        color: Theme.alpha(sec.cc, 0.3)
                    }
                    Row {
                        visible: sec.shut
                        spacing: 3
                        Repeater {
                            model: sec.shut && sec.info ? sec.info.apps.slice(0, 6) : []
                            Item {
                                required property var modelData
                                width: 16
                                height: 16
                                Image {
                                    anchors.fill: parent
                                    visible: !!parent.modelData.icon
                                    source: parent.modelData.icon || ""
                                    sourceSize.width: 32
                                    asynchronous: true
                                    mipmap: true
                                }
                                Ms {
                                    anchors.centerIn: parent
                                    visible: !parent.modelData.icon
                                    name: "notifications"
                                    size: 14
                                    color: Theme.inkVariant
                                }
                            }
                        }
                    }
                    Btn {
                        visible: mx.filtering
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 8
                        color: hovered ? Theme.surfaceHighest : "transparent"
                        tip: "Retirer ce canal du filtre (Échap : tout afficher)"
                        onClicked: mx.toggleFilter(sec.section)
                        Ms {
                            anchors.centerIn: parent
                            name: "close"
                            size: 16
                            color: parent.hovered ? Theme.ink : Theme.outline
                        }
                    }
                }
            }
        }
        delegate: Item {
            id: row
            required property int index
            required property string key
            required property string chan
            required property string kind
            required property string name
            required property string icon
            required property string pids
            required property real level
            required property bool muted
            readonly property var info: mx.chanMap[chan] || null
            readonly property color cc: info ? info.col : Theme.outline
            readonly property bool movable: mx.multi && kind === "app"
            readonly property bool open: mx.openKey === key && movable
            readonly property bool hov: rowHover.hovered || slider.activeFocus || dot.activeFocus
            width: list.width
            height: mx.closed[chan] ? 0 : kind === "empty" ? 28 : 34 + (open ? 42 : 0)
            Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
            clip: true
            opacity: mx.drag !== null && mx.drag.key === key ? 0.35 : 1
            onLevelChanged: if (!slider.dragging) slider.value = Math.round(level * 100)
            Component.onDestruction: {
                if (slider.dragging)
                    mx.sliding = false
                if (mx.drag !== null && mx.drag.key === key)
                    mx.drag = null
            }
            Component.onCompleted: {
                if (mx.flashKey === key) {
                    mx.flashKey = ""
                    flash.start()
                }
            }
            function setMuted(m) {
                rowModel.setProperty(index, "muted", m)
                // meme file que le volume : un niveau en attente ne la defait pas
                mx.send("app|" + key, "mixer_set", { device: chan, pids: mx.pidsOf(pids), muted: m })
            }
            function setLevel(v) {
                v = Math.max(0, Math.min(100, Math.round(v)))
                slider.value = v
                rowModel.setProperty(index, "level", v / 100)
                rowModel.setProperty(index, "muted", false)
                mx.send("app|" + key, "mixer_set", { device: chan, pids: mx.pidsOf(pids), level: v / 100, muted: false })
            }

            HoverHandler { id: rowHover }
            Rectangle {
                anchors.fill: parent
                radius: 12
                color: row.open ? Theme.surfaceHigh : "transparent"
                Behavior on color { ColorAnimation { duration: 250 } }
            }
            Rectangle {
                id: flashBg
                anchors.fill: parent
                radius: 12
                color: Theme.primaryContainer
                opacity: 0
                OpacityAnimator {
                    id: flash
                    target: flashBg
                    from: 1
                    to: 0
                    duration: 1100
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.emph
                }
            }
            Txt {
                visible: row.kind === "empty"
                x: 44
                height: 28
                text: "Aucune application. Glisse-en une ici."
                px: 11.5
                color: Theme.outline
            }
            Item {
                visible: row.kind !== "empty"
                width: parent.width
                height: 34
                Btn {
                    id: ico
                    x: 4
                    width: 30
                    height: 30
                    radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    color: hovered ? Theme.surfaceHigh : "transparent"
                    tip: row.muted ? "Rétablir le son" : "Couper le son"
                    onClicked: row.setMuted(!row.muted)
                    Image {
                        anchors.centerIn: parent
                        visible: !!row.icon
                        width: 22
                        height: 22
                        source: row.icon
                        sourceSize.width: 44
                        asynchronous: true
                        mipmap: true
                    }
                    Ms {
                        anchors.centerIn: parent
                        visible: !row.icon
                        name: "notifications"
                        size: 19
                        color: Theme.inkVariant
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: row.muted
                        radius: 9
                        color: Theme.alpha(Theme.surfaceC, 0.7)
                        Ms {
                            anchors.centerIn: parent
                            name: "volume_off"
                            size: 18
                            color: Theme.error
                        }
                    }
                }
                Txt {
                    id: nameTxt
                    x: 4 + 30 + 8
                    width: (mx.multi ? dot.x : slider.x) - 6 - x
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.name
                    px: 12
                    elide: Text.ElideRight
                    color: row.muted ? Theme.outline : Theme.ink
                    HoverHandler { id: nameHov }
                    Tip {
                        text: row.name
                        shown: nameHov.hovered && nameTxt.truncated
                    }
                }
                // point de la couleur de la sortie, chevron au survol : choisir la sortie
                Btn {
                    id: dot
                    visible: mx.multi
                    active: row.movable
                    anchors.right: slider.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    radius: 8
                    color: hovered && row.movable ? Theme.alpha(row.cc, 0.18) : "transparent"
                    tip: row.movable && row.info ? row.info.label + " · changer de sortie" : ""
                    activeFocusOnTab: row.movable
                    readonly property bool chev: row.movable && (row.hov || row.open)
                    onClicked: mx.openKey = row.open ? "" : row.key
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space)
                            mx.openKey = row.open ? "" : row.key
                        else if (e.key === Qt.Key_Escape && row.open)
                            mx.openKey = ""
                        else
                            return
                        e.accepted = true
                    }
                    Rectangle {
                        visible: row.kind === "app"
                        x: 8
                        y: 8
                        width: 8
                        height: 8
                        radius: 4
                        color: row.cc
                        opacity: dot.chev ? 0 : 1
                        scale: dot.chev ? 0.4 : 1
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
                    }
                    Ms {
                        anchors.centerIn: parent
                        name: "expand_more"
                        size: 17
                        color: row.cc
                        opacity: dot.chev ? 1 : 0
                        rotation: row.open ? 180 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
                    }
                }
                M3Slider {
                    id: slider
                    anchors.right: valTxt.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 140
                    trackH: 8
                    thumbH: 18
                    ringColor: row.open ? Theme.surfaceHigh : Theme.surfaceC
                    accent: row.muted ? Theme.outline : Theme.primary
                    fill: row.muted ? 0 : value / 100
                    Component.onCompleted: value = Math.round(row.level * 100)
                    onDraggingChanged: mx.sliding = dragging
                    onMoved: v => row.setLevel(v)
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Slider
                    Accessible.name: "Volume de " + row.name
                    Keys.onPressed: e => {
                        const st = (e.modifiers & Qt.ShiftModifier) ? 1 : 5
                        const v = value
                        if (e.key === Qt.Key_Right || e.key === Qt.Key_Up)
                            row.setLevel(v + st)
                        else if (e.key === Qt.Key_Left || e.key === Qt.Key_Down)
                            row.setLevel(v - st)
                        else if (e.key === Qt.Key_PageUp)
                            row.setLevel(v + 10)
                        else if (e.key === Qt.Key_PageDown)
                            row.setLevel(v - 10)
                        else if (e.key === Qt.Key_Home)
                            row.setLevel(0)
                        else if (e.key === Qt.Key_End)
                            row.setLevel(100)
                        else if (e.key === Qt.Key_M)
                            row.setMuted(!row.muted)
                        else
                            return
                        e.accepted = true
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -3
                        radius: 6
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.primary
                        visible: slider.activeFocus
                    }
                }
                Txt {
                    id: valTxt
                    anchors.right: grip.left
                    anchors.rightMargin: mx.multi ? 6 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    horizontalAlignment: Text.AlignRight
                    text: row.muted ? "–" : Math.round(row.level * 100)
                    px: 12
                    tnum: true
                    color: Theme.inkVariant
                }
                // poignee : glisser l'appli sur une pastille ou une etiquette
                Rectangle {
                    id: grip
                    anchors.right: parent.right
                    anchors.rightMargin: mx.multi ? 2 : 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: mx.multi ? 22 : 0
                    height: 26
                    radius: 8
                    visible: row.movable
                    color: gma.containsMouse ? Theme.surfaceHighest : "transparent"
                    opacity: row.hov || gma.pressed ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Ms {
                        anchors.centerIn: parent
                        name: "drag_indicator"
                        size: 17
                        color: gma.containsMouse ? Theme.ink : Theme.outline
                    }
                    MouseArea {
                        id: gma
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property point p0
                        onPressed: m => { p0 = mapToItem(mx, m.x, m.y) }
                        onPositionChanged: m => {
                            if (!pressed)
                                return
                            const p = mapToItem(mx, m.x, m.y)
                            if (mx.drag === null) {
                                if (Math.hypot(p.x - p0.x, p.y - p0.y) < 4)
                                    return
                                mx.beginDrag({ key: row.key, name: row.name, icon: row.icon, pids: mx.pidsOf(row.pids), from: row.chan })
                            }
                            mx.moveDrag(p)
                        }
                        onReleased: if (mx.drag !== null) mx.endDrag()
                        onCanceled: mx.drag = null
                    }
                    Tip {
                        text: "Glisser vers une pastille ou une étiquette"
                        shown: gma.containsMouse && !gma.pressed
                    }
                }
            }
            // selecteur segmente des sorties
            Loader {
                active: row.open
                x: 40
                y: 34
                width: parent.width - 46
                height: 36
                sourceComponent: Rectangle {
                    radius: 12
                    color: Theme.surfaceC
                    Row {
                        x: 3
                        y: 3
                        spacing: 2
                        Repeater {
                            model: chanModel
                            Btn {
                                id: seg
                                required property string key
                                required property string name
                                required property string label
                                required property string shortName
                                required property string icon
                                required property string col
                                readonly property color cc: col
                                readonly property bool cur: key === row.chan
                                width: (row.width - 46 - 6 - 2 * (chanModel.count - 1)) / chanModel.count
                                height: 30
                                radius: 9
                                color: cur ? Theme.alpha(cc, 0.2) : hovered ? Theme.surfaceHighest : "transparent"
                                tip: name
                                onClicked: mx.route({ key: row.key, name: row.name, icon: row.icon, pids: mx.pidsOf(row.pids), from: row.chan }, key)
                                Row {
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, parent.width - 8)
                                    spacing: 4
                                    Ms {
                                        id: segIcon
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: seg.icon
                                        size: 16
                                        color: seg.cur ? seg.cc : Theme.inkVariant
                                    }
                                    Txt {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, seg.width - 8 - segIcon.width - 4)
                                        text: chanModel.count <= 3 ? seg.label : seg.shortName
                                        px: 11
                                        elide: Text.ElideRight
                                        color: seg.cur ? seg.cc : Theme.inkVariant
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Scroller {
        flick: list
    }
    Empty {
        visible: rowModel.count === 0
        y: list.y
        width: list.width
        small: true
        text: "Aucune application ne joue de son."
    }

    // info discrete apres un changement de sortie
    property string note: ""
    Timer {
        id: noteTimer
        interval: 5000
        onTriggered: mx.note = ""
    }
    Rectangle {
        z: 10
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 8
        height: noteRow.height + 14
        radius: 12
        color: Theme.inkPrimaryContainer
        opacity: mx.note !== "" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
        Row {
            id: noteRow
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Ms {
                anchors.verticalCenter: parent.verticalCenter
                name: "swap_horiz"
                size: 17
                color: Theme.inkPrimary
            }
            Txt {
                width: noteRow.parent.width - 20 - 17 - 8
                anchors.verticalCenter: parent.verticalCenter
                text: mx.note
                px: 11.5
                weight: Font.Medium
                wrapMode: Text.Wrap
                color: Theme.inkPrimary
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: mx.note = ""
        }
    }

    // vignette qui suit le pointeur pendant le glisser
    Rectangle {
        visible: mx.drag !== null
        z: 20
        x: mx.dragX + 12
        y: mx.dragY - 14
        width: ghostRow.width + 18
        height: 34
        radius: 12
        color: Theme.surfaceHighest
        Row {
            id: ghostRow
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Image {
                visible: !!mx.drag && !!mx.drag.icon
                width: 22
                height: 22
                source: mx.drag ? mx.drag.icon : ""
                sourceSize.width: 44
                asynchronous: true
                mipmap: true
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: mx.drag ? mx.drag.name : ""
                px: 12
            }
        }
    }
}
