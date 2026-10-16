import QtQuick

// Gestionnaire des taches : processus regroupes par programme (src/tasks.rs),
// rafraichis toutes les 2 s tant que l'onglet est affiche
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "tasks"
    property var tasks: []
    property var netRate: ({ down: 0, up: 0 })
    property string sort: "cpu"
    property string armed: ""
    property bool busy: false
    property bool loaded: false

    onShownChanged: if (shown) refresh()
    Component.onCompleted: if (shown) refresh()
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
    function refresh() {
        if (busy)
            return
        busy = true
        Api.invoke("tasks_get").then(r => {
            page.tasks = r.list
            page.netRate = { down: r.net_down, up: r.net_up }
            page.loaded = true
        }).then(() => { page.busy = false }, () => { page.busy = false })
    }

    function fmtMem(b) {
        return b >= Math.pow(1024, 3) ? (b / Math.pow(1024, 3)).toFixed(1) + " Go" : Math.round(b / Math.pow(1024, 2)) + " Mo"
    }
    // debit reseau en bits/s, comme Windows
    function fmtNet(b) {
        const k = b * 8 / 1e3
        return k < 1 ? "0" : k < 1000 ? Math.round(k) + " k" : k < 10000 ? (k / 1e3).toFixed(1) + " M" : Math.round(k / 1e3) + " M"
    }
    function fmtRate(b) {
        return b < 0.05 * Math.pow(1024, 2) ? "0 Mo/s" : (b / Math.pow(1024, 2)).toFixed(1) + " Mo/s"
    }
    readonly property real diskFull: 100 * Math.pow(1024, 2)
    readonly property real netFull: 12.5 * Math.pow(1024, 2)
    readonly property real connFull: 40
    readonly property var hues: ({ cpu: 210, mem: 275, disk: 135, net: 30 })
    readonly property real memTotal: Ilot.sys ? Ilot.sys.mem_total : 16 * Math.pow(1024, 3)

    readonly property var list: {
        const q = Ilot.norm(filter.text.trim())
        const by = {
            cpu: (x, y) => y.cpu - x.cpu || y.mem - x.mem,
            mem: (x, y) => y.mem - x.mem,
            disk: (x, y) => y.disk - x.disk || y.cpu - x.cpu,
            net: (x, y) => y.net - x.net || y.cpu - x.cpu,
            name: (x, y) => x.name.localeCompare(y.name, "fr")
        }[sort]
        return tasks.filter(t => !q || Ilot.norm(t.name).includes(q)).sort(by)
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
            model: [{ id: "cpu", label: "CPU" }, { id: "mem", label: "Mémoire" }, { id: "disk", label: "Disque" }, { id: "net", label: "Réseau" }, { id: "name", label: "Nom" }]
            current: page.sort
            onPicked: id => page.sort = id
        }
        Txt {
            x: seg.x + seg.width + 8
            width: right.x - x - 8
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: page.tasks.reduce((n, t) => n + t.count, 0) + " processus"
            px: 12
            tnum: true
            color: Theme.inkVariant
            elide: Text.ElideRight
        }
        Row {
            id: right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle {
                width: 152
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

    // colonnes : icone, programme, CPU, memoire, disque, reseau, fin de tache
    readonly property var cols: [26, 0, 70, 80, 80, 116, 96]
    function colX(i) {
        let x = 12
        for (let k = 0; k < i; k++)
            x += (cols[k] || nameW) + 3
        return x
    }
    readonly property real nameW: width - 4 - 12 - (26 + 70 + 80 + 80 + 116 + 96) - 6 * 3

    // totaux colores, comme le Gestionnaire des taches
    Item {
        id: totals
        y: head.height + 10
        width: parent.width - 4
        height: 52
        Txt {
            x: page.colX(1)
            y: 6
            text: "Programme"
            px: 11
            color: Theme.inkVariant
        }
        readonly property real cpu: Math.min(100, page.tasks.reduce((n, t) => n + t.cpu, 0))
        readonly property real disk: page.tasks.reduce((n, t) => n + t.disk, 0)
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
            frac: totals.disk / page.diskFull
            value: page.loaded ? page.fmtRate(totals.disk) : "–"
            label: "Disque"
        }
        HeatCell {
            head: true
            x: page.colX(5)
            width: page.cols[5]
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
        model: page.list
        delegate: Btn {
            id: row
            required property var modelData
            width: rows.width
            height: 40
            radius: 14
            color: hovered || kill.hovered ? Theme.surfaceHigh : Theme.surfaceC
            active: true
            cursor: Qt.ArrowCursor
            Item {
                x: 12
                width: 22
                height: 22
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    anchors.fill: parent
                    visible: !!row.modelData.icon
                    source: row.modelData.icon || ""
                    sourceSize.width: 44
                    asynchronous: true
                    mipmap: true
                }
                Ms {
                    anchors.centerIn: parent
                    visible: !row.modelData.icon
                    name: "memory"
                    color: Theme.inkVariant
                }
            }
            Row {
                x: page.colX(1)
                width: page.nameW
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                Txt {
                    id: taskName
                    width: Math.min(implicitWidth, parent.width - (count.visible ? count.implicitWidth + 4 : 0))
                    text: row.modelData.name
                    elide: Text.ElideRight
                }
                Txt {
                    id: count
                    visible: row.modelData.count > 1
                    anchors.baseline: taskName.baseline
                    text: "(" + row.modelData.count + ")"
                    px: 11.5
                    color: Theme.inkVariant
                }
            }
            HeatCell {
                x: page.colX(2)
                width: page.cols[2]
                kind: "cpu"
                frac: row.modelData.cpu / 100
                value: row.modelData.cpu.toFixed(1) + " %"
            }
            HeatCell {
                x: page.colX(3)
                width: page.cols[3]
                kind: "mem"
                frac: row.modelData.mem / page.memTotal
                value: page.fmtMem(row.modelData.mem)
            }
            HeatCell {
                x: page.colX(4)
                width: page.cols[4]
                kind: "disk"
                frac: row.modelData.disk / page.diskFull
                value: page.fmtRate(row.modelData.disk)
            }
            HeatCell {
                x: page.colX(5)
                width: page.cols[5]
                kind: "net"
                frac: row.modelData.net / page.connFull
                value: row.modelData.net ? row.modelData.net + " conn." : "–"
            }
            // fin de tache : premier clic arme, second clic termine le programme
            Btn {
                id: kill
                readonly property bool armed: page.armed === row.modelData.name
                readonly property bool prot: !!row.modelData.protected
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: killRow.implicitWidth + 14
                height: 28
                radius: 14
                active: !prot
                opacity: armed ? 1 : prot ? (row.hovered ? 0.4 : 0) : (row.hovered || hovered ? 1 : 0)
                color: (hovered && !prot) || armed ? Theme.error : "transparent"
                tip: prot ? "Processus Windows protégé" : "Fin de tâche"
                onClicked: {
                    if (!armed) {
                        page.armed = row.modelData.name
                        disarm.restart()
                        return
                    }
                    page.armed = ""
                    Api.invoke("task_kill", { name: row.modelData.name }).then(() => page.refresh())
                }
                Row {
                    id: killRow
                    x: 7
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property color fg: (kill.hovered && !kill.prot) || kill.armed ? Theme.inkError : Theme.inkVariant
                    Ms {
                        name: kill.prot ? "shield" : "close"
                        size: 17
                        color: killRow.fg
                    }
                    Txt {
                        visible: kill.armed
                        text: "Confirmer"
                        px: 12
                        color: killRow.fg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
        Empty {
            visible: rows.count === 0
            width: rows.width
            text: page.loaded ? "Aucun processus" : "Chargement…"
        }
    }
    Scroller { flick: rows }

    // case coloree : une couleur par colonne, plus intense avec la charge ;
    // au-dela de 75 % la case vire au rouge
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
        height: head ? 46 : 40
        y: head ? 6 : 0
        radius: 8
        clip: true
        color: Qt.hsla(hue / 360, 0.85, 0.55, 0.1 + 0.6 * Math.sqrt(f))
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
                text: c.label
                px: 11
                color: c.hot ? "#ffffff" : Theme.inkVariant
            }
        }
        Btn {
            anchors.fill: parent
            visible: c.tip !== ""
            cursor: Qt.ArrowCursor
            tip: c.tip
        }
    }
}
