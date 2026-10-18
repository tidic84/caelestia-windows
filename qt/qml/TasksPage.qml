import QtQuick

// Gestionnaire des taches : processus regroupes par programme (src/tasks.rs),
// avec les memes chiffres et sections que l'onglet Processus de Windows,
// rafraichis toutes les 2 s tant que l'onglet est affiche. La liste est un
// ListModel mis a jour sur place (cle : nom de l'exe), pour garder le
// defilement, le survol et les lignes d'un rafraichissement a l'autre.
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "tasks" && !Watch.shareOpen
    property var tasks: []
    property var netRate: ({ down: 0, up: 0 })
    // totaux de l'en-tete (compteurs de Windows)
    property var tot: ({ cpu: 0, gpu: 0, disk: 0, procs: 0 })
    property string sort: "cpu"
    property string armed: ""
    property bool busy: false
    property bool loaded: false
    // groupes developpes (nom en minuscules -> true), gardes d'un affichage a l'autre
    property var opened: ({})
    // un rafraichissement demande pendant un autre : relance a la fin
    property bool again: false
    // message bref dans l'en-tete (resultat d'une fin de tache)
    property string notice: ""

    onShownChanged: {
        if (shown) {
            refresh()
            return
        }
        // onglet cache : le Rust libere ses compteurs et ses caches par pid
        Api.invoke("tasks_stop")
        ctx.hide()
        armed = ""
    }
    Component.onCompleted: if (shown) refresh()
    onSortChanged: rebuild()
    Timer {
        interval: 2000
        repeat: true
        running: page.shown
        onTriggered: page.refresh()
    }
    Timer {
        id: disarm
        interval: 3000
        onTriggered: page.armed = ""
    }
    Timer {
        id: noticeOff
        interval: 3500
        onTriggered: page.notice = ""
    }
    function refresh() {
        if (busy) {
            again = true
            return
        }
        busy = true
        again = false
        // le detail par processus n'est demande que pour les groupes ouverts
        Api.invoke("tasks_get", { expanded: Object.keys(opened) }).then(r => {
            page.tasks = r.list
            page.netRate = { down: r.net_down, up: r.net_up }
            page.tot = { cpu: r.cpu, gpu: r.gpu, disk: r.disk_active, procs: r.procs }
            page.loaded = true
            page.rebuild()
        }).then(() => { page.done() }, () => { page.done() })
    }
    // une reponse arrivee apres la fermeture de l'onglet a pu recreer l'etat Rust
    function done() {
        busy = false
        if (!shown)
            Api.invoke("tasks_stop")
        else if (again)
            refresh()
    }
    function toggle(name) {
        const k = name.toLowerCase()
        const o = Object.assign({}, opened)
        if (o[k]) {
            delete o[k]
            // un bouton arme dans le groupe replie ne doit pas le rester
            if (armed.startsWith(k + "/"))
                armed = ""
        } else
            o[k] = true
        opened = o
        rebuild()
        refresh()
    }
    // t : la ligne (copiee, elle peut disparaitre avant la reponse) ;
    // une sous-ligne (pid non nul) ne termine que ce processus
    function kill(c) {
        const t = { name: c.name, label: c.pid ? "PID " + c.pid : c.label }
        page.armed = ""
        Api.invoke("task_kill", c.pid ? { name: t.name, pid: c.pid, created: c.created } : { name: t.name }).then(r => {
            if (r.killed === 0)
                page.say(r.denied ? "Accès refusé : " + t.label : t.label + " est déjà fermé")
            else if (r.denied)
                page.say(r.killed + " fermé(s), " + r.denied + " refusé(s)")
            page.refresh()
        }, () => page.say("Échec de la fin de tâche"))
    }
    function say(s) {
        notice = s
        noticeOff.restart()
    }

    // nombres a la francaise : virgule decimale
    function fmt1(v) {
        return v.toFixed(1).replace(".", ",")
    }
    function fmtPct(v) {
        return v >= 0.05 ? fmt1(v) + " %" : "0 %"
    }
    function fmtMem(b) {
        return b >= Math.pow(1024, 3) ? fmt1(b / Math.pow(1024, 3)) + " Go" : Math.round(b / Math.pow(1024, 2)) + " Mo"
    }
    // debit reseau en bits/s, comme Windows
    function fmtNet(b) {
        const k = b * 8 / 1e3
        return k < 1 ? "0" : k < 1000 ? Math.round(k) + " k" : k < 10000 ? fmt1(k / 1e3) + " M" : Math.round(k / 1e3) + " M"
    }
    function fmtRate(b) {
        return b < 0.05 * Math.pow(1024, 2) ? "0 Mo/s" : fmt1(b / Math.pow(1024, 2)) + " Mo/s"
    }
    readonly property real diskFull: 100 * Math.pow(1024, 2)
    readonly property real netFull: 12.5 * Math.pow(1024, 2)
    readonly property real connFull: 40
    readonly property var hues: ({ cpu: 210, mem: 275, disk: 135, gpu: 330, net: 30 })
    readonly property real memTotal: Ilot.sys ? Ilot.sys.mem_total : 16 * Math.pow(1024, 3)

    // ------------------------------------------------------ liste affichee
    ListModel { id: rowsModel }
    // cles des lignes du modele, dans l'ordre (miroir JS, evite les get())
    property var keys: []

    // filtre + tri + sections, puis mise a jour du modele sur place
    function rebuild() {
        const q = Ilot.norm(filter.text.trim())
        // dernier critere toujours stable : le nom
        const by = {
            cpu: (x, y) => y.cpu - x.cpu || y.mem - x.mem,
            mem: (x, y) => y.mem - x.mem,
            disk: (x, y) => y.disk - x.disk || y.cpu - x.cpu || y.mem - x.mem,
            gpu: (x, y) => y.gpu - x.gpu || y.cpu - x.cpu || y.mem - x.mem,
            net: (x, y) => y.net - x.net || y.cpu - x.cpu || y.mem - x.mem,
            name: () => 0
        }[sort]
        const cmp = (x, y) => by(x, y) || x.label.localeCompare(y.label, "fr") || x.name.localeCompare(y.name)
        const all = tasks.filter(t => !q || Ilot.norm(t.label).includes(q) || Ilot.norm(t.name).includes(q)).sort(cmp)
        // memes sections que l'onglet Processus du Gestionnaire des taches
        const out = []
        for (const k of [["app", "Applications"], ["bg", "Processus en arrière-plan"], ["win", "Processus Windows"]]) {
            const part = all.filter(t => t.kind === k[0])
            if (!part.length)
                continue
            out.push(row("#" + k[0], k[1] + " (" + part.length + ")", null, null, false))
            for (const t of part) {
                const key = t.name.toLowerCase()
                const open = !!opened[key] && t.count > 1
                out.push(row(key, "", t, null, open))
                // groupe developpe : un processus par ligne, juste dessous
                if (open && t.procs)
                    for (const s of t.procs.slice().sort((x, y) => by(x, y) || x.pid - y.pid))
                        out.push(row(key + "/" + s.pid, "", t, s, false))
            }
        }
        sync(out)
    }
    // une ligne du modele : memes roles et memes types pour toutes
    // s : un processus d'un groupe developpe (sous-ligne), sinon null
    function row(key, header, t, s, open) {
        const v = s || t
        return {
            key: key, header: header,
            name: t ? t.name : "", label: t ? t.label : "", kind: t ? t.kind : "",
            n: s ? 1 : t ? t.count : 0, cpu: v ? v.cpu : 0, mem: v ? v.mem : 0, disk: v ? v.disk : 0,
            gpu: v ? v.gpu : 0, net: v ? v.net : 0, icon: t && !s ? t.icon : "", path: t ? t.path : "",
            prot: t ? !!t.protected : false,
            pid: s ? s.pid : 0, created: s ? s.created : 0, title: s ? s.title : "", expanded: !!open
        }
    }
    function sync(items) {
        const want = new Set(items.map(it => it.key))
        for (let i = keys.length - 1; i >= 0; i--) {
            if (!want.has(keys[i])) {
                rowsModel.remove(i)
                keys.splice(i, 1)
            }
        }
        for (let i = 0; i < items.length; i++) {
            const it = items[i]
            const j = keys.indexOf(it.key, i)
            if (j < 0) {
                rowsModel.insert(i, it)
                keys.splice(i, 0, it.key)
                continue
            }
            if (j !== i) {
                rowsModel.move(j, i, 1)
                keys.splice(j, 1)
                keys.splice(i, 0, it.key)
            }
            // set() ne signale que les roles qui ont change
            rowsModel.set(i, it)
        }
    }

    function showMenu(c, p) {
        const t = { name: c.name, label: c.label, n: c.n, prot: c.prot, path: c.path, pid: c.pid, created: c.created }
        const title = t.label + (t.pid ? " · PID " + t.pid : t.n > 1 ? " (" + t.n + " processus)" : "")
        let entries = [{ type: "title", label: title }]
        if (t.prot)
            entries.push({ type: "title", label: "Processus Windows protégé" })
        else
            entries.push({ icon: "close", label: t.pid ? "Fin du processus" : "Fin de tâche", danger: true, confirm: t.n > 1 ? "Confirmer (" + t.n + ")" : "Confirmer", run: () => { ctx.hide(); page.kill(t) } })
        if (t.path)
            entries.push({ icon: "folder_open", label: "Ouvrir l’emplacement du fichier", run: () => {
                ctx.hide()
                Api.invoke("file_reveal", { path: t.path })
                Ilot.setMode("collapsed")
            } })
        entries.push({ icon: "travel_explore", label: "Rechercher en ligne", run: () => {
            ctx.hide()
            Qt.openUrlExternally("https://www.bing.com/search?q=" + encodeURIComponent(t.name + ".exe"))
            Ilot.setMode("collapsed")
        } })
        ctx.show(p.x, p.y, entries)
    }

    // ----------------------------------------------------------- en-tete
    Item {
        id: head
        width: parent.width
        height: 32
        Seg {
            id: seg
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            model: [{ id: "cpu", label: "CPU" }, { id: "mem", label: "Mémoire" }, { id: "disk", label: "Disque" }, { id: "gpu", label: "GPU" }, { id: "net", label: "Réseau" }, { id: "name", label: "Nom" }]
            current: page.sort
            onPicked: id => page.sort = id
        }
        Txt {
            x: seg.x + seg.width + 8
            width: right.x - x - 8
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: page.notice || ((page.tot.procs || page.tasks.reduce((n, t) => n + t.count, 0)) + " processus")
            px: 12
            tnum: true
            color: page.notice ? Theme.primary : Theme.inkVariant
            elide: Text.ElideRight
        }
        Row {
            id: right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle {
                width: 128
                height: 32
                radius: 16
                color: Theme.surfaceHigh
                Ms {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    size: 17
                    color: Theme.inkVariant
                }
                Field {
                    id: filter
                    x: 10 + 17
                    width: parent.width - x - 4
                    height: parent.height
                    bg: "transparent"
                    pad: 6
                    fontSize: 12.5
                    placeholder: "Filtrer…"
                    onTextChanged: page.rebuild()
                    // Echap vide le filtre
                    onKeyPressed: e => {
                        if (e.key === Qt.Key_Escape && text !== "") {
                            text = ""
                            e.accepted = true
                        }
                    }
                }
            }
            TextBtn {
                icon: "open_in_new"
                text: "Windows"
                tip: "Ouvrir le Gestionnaire des tâches de Windows"
                onClicked: {
                    Api.invoke("taskmgr_open")
                    Ilot.setMode("collapsed")
                }
            }
        }
    }

    // colonnes : icone, programme, CPU, memoire, disque, GPU, reseau, fin de tache
    readonly property var cols: [26, 0, 62, 74, 74, 58, 118, 36]
    function colX(i) {
        let x = 12
        for (let k = 0; k < i; k++)
            x += (cols[k] || nameW) + 3
        return x
    }
    readonly property real nameW: width - 4 - 12 - (26 + 62 + 74 + 74 + 58 + 118 + 36) - 7 * 3

    // totaux colores, comme le Gestionnaire des taches ; un clic trie la colonne
    Item {
        id: totals
        y: head.height + 10
        width: parent.width - 4
        height: 52
        Btn {
            x: page.colX(1) - 6
            y: 2
            width: progLabel.implicitWidth + 12
            height: 22
            radius: 8
            color: hovered ? Theme.alpha(Theme.ink, 0.08) : "transparent"
            tip: "Trier par nom"
            onClicked: page.sort = "name"
            Txt {
                id: progLabel
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                text: "Programme" + (page.sort === "name" ? " ▴" : "")
                px: 11
                color: page.sort === "name" ? Theme.primary : Theme.inkVariant
            }
        }
        readonly property real cpu: page.tot.cpu || Math.min(100, page.tasks.reduce((n, t) => n + t.cpu, 0))
        readonly property real memUsed: Ilot.sys ? Ilot.sys.mem_used : page.tasks.reduce((n, t) => n + t.mem, 0)
        HeatCell {
            head: true
            x: page.colX(2)
            width: page.cols[2]
            kind: "cpu"
            frac: totals.cpu / 100
            value: page.loaded ? Math.round(totals.cpu) + " %" : "–"
            label: "CPU"
        }
        HeatCell {
            head: true
            x: page.colX(3)
            width: page.cols[3]
            kind: "mem"
            frac: totals.memUsed / page.memTotal
            value: page.loaded ? Math.round(totals.memUsed / page.memTotal * 100) + " %" : "–"
            label: "Mémoire"
        }
        HeatCell {
            head: true
            x: page.colX(4)
            width: page.cols[4]
            kind: "disk"
            frac: page.tot.disk / 100
            value: page.loaded ? Math.round(page.tot.disk) + " %" : "–"
            label: "Disque"
            tip: "Activité du disque le plus occupé ; par programme : lecture + écriture"
        }
        HeatCell {
            head: true
            x: page.colX(5)
            width: page.cols[5]
            kind: "gpu"
            frac: page.tot.gpu / 100
            value: page.loaded ? Math.round(page.tot.gpu) + " %" : "–"
            label: "GPU"
        }
        HeatCell {
            head: true
            x: page.colX(6)
            width: page.cols[6]
            kind: "net"
            frac: (page.netRate.down + page.netRate.up) / page.netFull
            value: page.loaded ? "↓" + page.fmtNet(page.netRate.down) + " ↑" + page.fmtNet(page.netRate.up) : "–"
            label: "Réseau (bit/s)"
            tip: "Débit total ↓ réception / ↑ envoi ; par programme : connexions actives"
        }
    }

    ListView {
        id: rows
        y: totals.y + totals.height + 4
        width: parent.width - 4
        height: parent.height - y
        clip: true
        spacing: 3
        boundsBehavior: Flickable.StopAtBounds
        model: rowsModel
        delegate: Item {
            id: cell
            required property string key
            required property int pid
            required property real created
            required property string title
            required property bool expanded
            required property string header
            required property string name
            required property string label
            required property int n
            required property real cpu
            required property real mem
            required property real disk
            required property real gpu
            required property int net
            required property string icon
            required property string path
            required property bool prot
            width: rows.width
            height: header ? 30 : pid ? 32 : 40
            Txt {
                visible: cell.header !== ""
                x: 8
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: cell.header
                px: 12
                weight: Font.DemiBold
                color: Theme.primary
            }
            Loader {
                active: cell.header === ""
                anchors.fill: parent
                sourceComponent: Btn {
                    id: row
                    radius: 14
                    color: hovered || kill.hovered ? Theme.surfaceHigh : cell.pid ? Theme.alpha(Theme.surfaceC, 0.5) : Theme.surfaceC
                    active: true
                    cursor: cell.n > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    tip: cell.pid ? "" : cell.label !== cell.name ? cell.name + ".exe" : ""
                    // clic sur un groupe : un processus par ligne, dessous
                    onClicked: if (cell.n > 1 && !cell.pid) page.toggle(cell.name)
                    // clic droit : menu comme le Gestionnaire des taches
                    onRightClicked: m => page.showMenu(cell, row.mapToItem(page, m.x, m.y))
                    Item {
                        visible: !cell.pid
                        x: 12
                        width: 22
                        height: 22
                        anchors.verticalCenter: parent.verticalCenter
                        Image {
                            anchors.fill: parent
                            visible: cell.icon !== ""
                            source: cell.icon
                            sourceSize.width: 44
                            asynchronous: true
                            mipmap: true
                        }
                        Ms {
                            anchors.centerIn: parent
                            visible: cell.icon === ""
                            name: "memory"
                            color: Theme.inkVariant
                        }
                    }
                    // groupe de plusieurs processus : chevron a gauche du nom
                    Ms {
                        visible: cell.n > 1 && !cell.pid
                        x: page.colX(1) - 18
                        anchors.verticalCenter: parent.verticalCenter
                        name: cell.expanded ? "expand_more" : "chevron_right"
                        size: 16
                        color: Theme.inkVariant
                    }
                    Row {
                        // sous-ligne : en retrait sous le nom du groupe
                        x: page.colX(1) + (cell.pid ? 14 : 0)
                        width: page.nameW - (cell.pid ? 14 : 0)
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter
                        Txt {
                            id: taskName
                            width: Math.min(implicitWidth, parent.width - (count.visible ? count.implicitWidth + 4 : 0))
                            text: cell.pid ? (cell.title || cell.label || cell.name) : (cell.label || cell.name)
                            color: cell.pid && !cell.title ? Theme.inkVariant : Theme.ink
                            elide: Text.ElideRight
                        }
                        Txt {
                            id: count
                            visible: cell.n > 1 || cell.pid > 0
                            anchors.baseline: taskName.baseline
                            text: cell.pid ? "PID " + cell.pid : "(" + cell.n + ")"
                            px: 11.5
                            tnum: true
                            color: Theme.inkVariant
                        }
                    }
                    HeatCell {
                        height: row.height
                        x: page.colX(2)
                        width: page.cols[2]
                        kind: "cpu"
                        frac: cell.cpu / 100
                        value: page.fmtPct(cell.cpu)
                    }
                    HeatCell {
                        height: row.height
                        x: page.colX(3)
                        width: page.cols[3]
                        kind: "mem"
                        frac: cell.mem / page.memTotal
                        value: page.fmtMem(cell.mem)
                    }
                    HeatCell {
                        height: row.height
                        x: page.colX(4)
                        width: page.cols[4]
                        kind: "disk"
                        frac: cell.disk / page.diskFull
                        value: page.fmtRate(cell.disk)
                    }
                    HeatCell {
                        height: row.height
                        x: page.colX(5)
                        width: page.cols[5]
                        kind: "gpu"
                        frac: cell.gpu / 100
                        value: page.fmtPct(cell.gpu)
                    }
                    HeatCell {
                        height: row.height
                        x: page.colX(6)
                        width: page.cols[6]
                        kind: "net"
                        frac: cell.net / page.connFull
                        value: cell.net ? cell.net + " conn." : "–"
                    }
                    // fin de tache : premier clic arme, second clic termine le programme
                    Btn {
                        id: kill
                        readonly property bool armed: page.armed === cell.key
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: killRow.implicitWidth + 14
                        height: Math.min(28, row.height - 4)
                        radius: height / 2
                        active: !cell.prot
                        opacity: armed ? 1 : cell.prot ? (row.hovered ? 0.4 : 0) : (row.hovered || hovered ? 1 : 0)
                        color: (hovered && !cell.prot) || armed ? Theme.error : "transparent"
                        tip: cell.prot ? "Processus Windows protégé" : cell.pid ? "Fin du processus " + cell.pid : cell.n > 1 ? "Fin de tâche (" + cell.n + " processus)" : "Fin de tâche"
                        onClicked: {
                            if (!armed) {
                                page.armed = cell.key
                                disarm.restart()
                                return
                            }
                            page.kill(cell)
                        }
                        Row {
                            id: killRow
                            x: 7
                            spacing: 4
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property color fg: (kill.hovered && !cell.prot) || kill.armed ? Theme.inkError : Theme.inkVariant
                            Ms {
                                name: cell.prot ? "shield" : "close"
                                size: 17
                                color: killRow.fg
                            }
                            Txt {
                                visible: kill.armed
                                text: cell.n > 1 ? "Confirmer (" + cell.n + ")" : "Confirmer"
                                px: 12
                                color: killRow.fg
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
    Item {
        Empty {
            y: rows.y
            visible: rows.count === 0
            width: rows.width
            text: !page.loaded ? "Chargement…" : filter.text.trim() ? "Aucun résultat" : "Aucun processus"
        }
    }
    Scroller { flick: rows }

    // ---------------------------------------------------- menu contextuel
    // clic hors du menu : il se ferme
    MouseArea {
        anchors.fill: parent
        visible: ctx.visible
        z: 9
        acceptedButtons: Qt.AllButtons
        onPressed: m => {
            ctx.hide()
            m.accepted = false
        }
    }
    CtxMenu {
        id: ctx
        area: page
    }
    Keys.onEscapePressed: e => {
        e.accepted = ctx.visible
        ctx.hide()
    }

    // case coloree : une couleur par colonne, plus intense avec la charge ;
    // au-dela de 75 % la case vire au rouge. En-tete : un clic trie la colonne.
    component HeatCell: Rectangle {
        id: c
        property string kind
        property real frac: 0
        property string value
        property string label: ""
        property bool head: false
        property string tip: ""
        readonly property real f: Math.max(0, Math.min(1, frac || 0))
        readonly property real hue: f >= 0.75 ? 0 : (page.hues[kind] !== undefined ? page.hues[kind] : 50)
        readonly property bool hot: f >= 0.5
        readonly property bool sorted: head && page.sort === kind
        height: head ? 46 : 40
        y: head ? 6 : 0
        radius: 8
        clip: true
        color: Qt.hsla(hue / 360, 0.85, 0.55, 0.1 + 0.6 * Math.sqrt(f))
        border.width: sorted ? 1.5 : 0
        border.color: Theme.primary
        Behavior on color { ColorAnimation { duration: 400 } }
        Rectangle {
            anchors.bottom: parent.bottom
            height: 3
            radius: 2
            width: parent.width * Math.max(c.f, c.f > 0.002 ? 0.03 : 0)
            color: Qt.hsla(c.hue / 360, 0.9, 0.6, 1)
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
        }
        Txt {
            visible: !c.head
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: c.value
            px: 12.5
            tnum: true
            weight: c.hot ? Font.DemiBold : Font.Normal
            color: c.hot ? "#ffffff" : Theme.ink
        }
        Column {
            visible: c.head
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            Txt {
                anchors.right: parent.right
                text: c.value
                px: 14
                weight: Font.DemiBold
                tnum: true
                color: c.hot ? "#ffffff" : Theme.ink
            }
            Txt {
                anchors.right: parent.right
                text: c.label + (c.sorted ? " ▾" : "")
                px: 11
                color: c.hot ? "#ffffff" : c.sorted ? Theme.primary : Theme.inkVariant
            }
        }
        // seulement dans l'en-tete : pas de zone cliquable par ligne
        Loader {
            anchors.fill: parent
            active: c.head
            sourceComponent: Btn {
                tip: c.tip || "Trier par " + c.label.toLowerCase()
                onClicked: page.sort = c.kind
            }
        }
    }
}
