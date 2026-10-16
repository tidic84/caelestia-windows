import QtQuick
import QtQuick.Effects

// Barre facon Waybar : a gauche le lanceur, les bureaux virtuels et les
// fenetres ouvertes ; a droite l'etat du systeme. Chaque module ouvre
// l'onglet de l'ilot qui va avec (un second clic le referme). La meme barre
// sert dans la fenetre de l'ilot (ilot au centre) et sur les autres ecrans
// (Bar.qml : l'heure au centre).
Item {
    id: bar
    property string label: "island"
    // fenetre de l'ilot : le centre reste libre pour lui
    property bool hasIsland: true
    // affichee (sinon remontee hors de l'ecran)
    property bool shown: true
    readonly property bool islands: !!Ilot.cfg.bar_islands
    readonly property bool showTasks: !!Ilot.cfg.bar_tasks
    signal layoutChanged()
    readonly property bool previewOpen: preview.open
    height: Ilot.barH

    // 0 : masquee ; anime, pour garder la barre visible pendant qu'elle sort
    property real vis: shown ? 1 : 0
    Behavior on vis { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
    onVisChanged: if (vis === 0 || vis === 1) layoutChanged()
    onShownChanged: {
        if (!shown)
            preview.hideNow()
        layoutChanged()
    }

    // zones cliquables, en coordonnees de la fenetre
    function hitRects() {
        const out = []
        // des qu'elle commence a entrer : le masque de la fenetre coupe aussi
        // l'affichage, la barre n'apparaitrait qu'a la fin de l'animation
        if ((!shown && vis <= 0.01) || !visible)
            return out
        if (!islands)
            out.push({ x: 0, y: 0, w: width, h: Ilot.barH })
        else {
            // ilots separes : les clics passent entre eux
            for (const side of [left, right, center]) {
                if (!side.visible)
                    continue
                for (let i = 0; i < side.children.length; i++) {
                    const c = side.children[i]
                    if (!c.visible || c.width <= 0 || c.isRepeater)
                        continue
                    const p = c.mapToItem(bar, 0, 0)
                    out.push({ x: p.x - 2, y: 0, w: c.width + 4, h: Ilot.barH })
                }
            }
        }
        if (preview.open)
            out.push(preview.rect())
        return out
    }

    // flou acrylique (WinCtl.setBackdrop) : la barre pleine, ou chaque ilot
    // separe, en coordonnees de la fenetre
    function backdropShapes() {
        const out = []
        if (vis <= 0.01 || !visible)
            return out
        if (!islands) {
            out.push({ kind: "rect", x: 0, y: slide.y, w: width, h: Ilot.barH })
            return out
        }
        for (const side of [left, right, center]) {
            if (!side.visible)
                continue
            for (let i = 0; i < side.children.length; i++) {
                const c = side.children[i]
                if (!c.visible || c.width <= 0 || c.isRepeater || c.bare)
                    continue
                const p = c.mapToItem(bar, 0, 0)
                out.push({ kind: "round", x: p.x, y: p.y, w: c.width, h: c.height, r: c.radius })
            }
        }
        return out
    }

    // ouvre l'onglet de l'ilot (sur l'ecran de l'ilot pour les autres barres)
    function openTab(tab) {
        if (hasIsland)
            Ilot.openFromBar(tab)
        else
            Api.invoke("bar_open", { tab: tab }, label)
    }

    Item {
        id: slide
        width: parent.width
        height: Ilot.barH
        opacity: bar.vis
        y: -Ilot.barH * (1 - bar.vis)

        Rectangle {
            anchors.fill: parent
            visible: !bar.islands
            color: Theme.islandBg
        }

        // ------------------------------------------------------- gauche
        Row {
            id: left
            x: bar.islands ? 6 : 5
            height: parent.height
            spacing: bar.islands ? 6 : 5
            onWidthChanged: bar.layoutChanged()
            onXChanged: bar.layoutChanged()

            // lanceur
            BarBtn {
                width: bar.islands ? 30 : 34
                launch: true
                icon: "apps"
                tip: "Applications (Ctrl+Alt+Espace ou touche Windows)"
                onClicked: {
                    if (bar.hasIsland) {
                        Ilot.openFromBar("apps")
                        if (Ilot.mode === "open")
                            Ilot.later(60, () => Ilot.focusSearch())
                    } else {
                        Api.invoke("bar_open", { tab: "launcher" }, bar.label)
                    }
                }
            }

            // bureaux virtuels : des points, l'actif s'allonge
            Group {
                id: ws
                tip: "Bureaux virtuels"
                width: wsRow.width + 10
                Row {
                    id: wsRow
                    x: 5
                    height: parent.height
                    Repeater {
                        model: Ilot.barWins.desktops
                        Btn {
                            required property int index
                            readonly property bool on: index === Ilot.barWins.desktop
                            width: on ? 30 : 14
                            height: parent.height
                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                            tip: "Bureau " + (index + 1)
                            onClicked: Api.invoke("desktop_go", { index: index })
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.on ? 22 : 8
                                height: 8
                                radius: 4
                                color: parent.on ? Theme.primary : parent.hovered ? Theme.outline : Theme.outlineVariant
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
                                Behavior on color { ColorAnimation { duration: 250 } }
                            }
                        }
                    }
                }
                property real wheelAt: 0
                WheelHandler {
                    onWheel: e => {
                        if (Date.now() - ws.wheelAt < 350)
                            return
                        const t = Ilot.barWins
                        const i = Math.max(0, Math.min(t.desktops - 1, t.desktop - Math.sign(e.angleDelta.y)))
                        if (i === t.desktop)
                            return
                        ws.wheelAt = Date.now()
                        Api.invoke("desktop_go", { index: i })
                    }
                }
            }

            // fenetres ouvertes, regroupees par appli
            Group {
                id: tasks
                visible: bar.showTasks && groups.length > 0
                bare: !bar.islands
                width: Math.min(tasksRow.implicitWidth + (bar.islands ? 4 : 0), bar.sideMax - (tasks.x))
                clip: true
                readonly property var groups: bar.showTasks ? Ilot.taskGroups(Ilot.barWins) : []
                HoverHandler {
                    id: tasksHover
                    onHoveredChanged: if (!hovered) preview.leave()
                }
                Row {
                    id: tasksRow
                    x: bar.islands ? 2 : 0
                    height: parent.height
                    spacing: 2
                    Repeater {
                        model: tasks.groups
                        BarTask {
                            required property var modelData
                            group: modelData
                            anchors.verticalCenter: parent.verticalCenter
                            onHoveredChanged: if (hovered) preview.soon(modelData.key, this)
                            onClicked: {
                                // plusieurs fenetres : chaque clic passe a la suivante
                                const wins = modelData.wins
                                const i = wins.findIndex(w => w.id === Ilot.barWins.active)
                                const w = i >= 0 && wins.length > 1 ? wins[(i + 1) % wins.length] : wins[0]
                                preview.hideNow()
                                Api.invoke("task_activate", { id: w.id })
                            }
                            // clic molette : fermer, comme dans Waybar (fenetre seule)
                            onMiddleClicked: if (modelData.wins.length === 1) Api.invoke("task_close", { id: modelData.wins[0].id })
                        }
                    }
                }
            }
        }

        // ----------------------------------------- centre (autres ecrans)
        Row {
            id: center
            visible: !bar.hasIsland
            anchors.horizontalCenter: parent.horizontalCenter
            height: parent.height
            Group {
                button: true
                width: clockText.implicitWidth + 20
                onClicked: bar.openTab("home")
                Txt {
                    id: clockText
                    anchors.centerIn: parent
                    text: Ilot.hm(Ilot.now)
                    px: 12
                    weight: Font.Medium
                    tnum: true
                }
            }
        }

        // ------------------------------------------------------- droite
        Row {
            id: right
            anchors.right: parent.right
            anchors.rightMargin: bar.islands ? 6 : 5
            height: parent.height
            spacing: bar.islands ? 6 : 5
            layoutDirection: Qt.LeftToRight
            onWidthChanged: bar.layoutChanged()

            // zone de notification : applis en arriere-plan, depliees par la fleche
            Group {
                id: tray
                property bool open: false
                visible: Tray.icons.length > 0
                width: trayRow.implicitWidth + 6
                Row {
                    id: trayRow
                    x: 3
                    height: parent.height
                    Item {
                        height: parent.height
                        width: tray.open ? trayIcons.implicitWidth : 0
                        clip: true
                        Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
                        Row {
                            id: trayIcons
                            anchors.right: parent.right
                            height: parent.height
                            Repeater {
                                model: Tray.icons
                                Btn {
                                    required property var modelData
                                    width: 24
                                    height: 22
                                    radius: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: hovered ? Theme.surfaceHigh : "transparent"
                                    tip: modelData.tip
                                    onHoveredChanged: if (hovered) Tray.click(modelData.id, "hover")
                                    onClicked: Tray.click(modelData.id, "left")
                                    onRightClicked: Tray.click(modelData.id, "right")
                                    doubleClick: true
                                    onDoubleClicked: Tray.click(modelData.id, "double")
                                    Image {
                                        anchors.centerIn: parent
                                        width: 16
                                        height: 16
                                        source: "image://tray/" + modelData.id + "-" + modelData.rev
                                        sourceSize.width: Math.ceil(16 * Screen.devicePixelRatio)
                                        sourceSize.height: Math.ceil(16 * Screen.devicePixelRatio)
                                        cache: false
                                        smooth: true
                                        mipmap: true
                                    }
                                }
                            }
                        }
                    }
                    StatusBtn {
                        icon: tray.open ? "chevron_right" : "chevron_left"
                        tip: tray.open ? "Masquer les applications en arrière-plan" : "Applications en arrière-plan"
                        onClicked: tray.open = !tray.open
                    }
                }
            }

            // processeur, memoire
            Group {
                button: true
                tip: "Processeur · mémoire"
                width: resRow.implicitWidth + 20
                onClicked: bar.openTab("home")
                Row {
                    id: resRow
                    anchors.centerIn: parent
                    spacing: 5
                    readonly property var r: Ilot.sys
                    Ms { name: "memory"; size: 15; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                    Txt {
                        text: resRow.r ? Math.round(resRow.r.cpu) + "%" : "–"
                        px: 12
                        weight: Font.Medium
                        tnum: true
                        width: Math.max(26, implicitWidth)
                        color: resRow.r && resRow.r.cpu > 90 ? Theme.error : Theme.ink
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: 2; height: 1 }
                    Ms { name: "developer_board"; size: 15; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                    Txt {
                        text: resRow.r ? Math.round(resRow.r.mem_used / resRow.r.mem_total * 100) + "%" : "–"
                        px: 12
                        weight: Font.Medium
                        tnum: true
                        width: Math.max(26, implicitWidth)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Wi-Fi, Bluetooth, volume, batterie
            Group {
                width: statusRow.implicitWidth + 6
                Row {
                    id: statusRow
                    x: 3
                    height: parent.height
                    readonly property var n: Ilot.net
                    StatusBtn {
                        visible: statusRow.n.radios.wifi !== null
                        icon: "wifi"
                        off: !statusRow.n.radios.wifi || !statusRow.n.ssid
                        tip: statusRow.n.radios.wifi ? statusRow.n.ssid || "Wi-Fi : non connecté" : "Wi-Fi désactivé"
                        onClicked: bar.openTab("ctrl")
                    }
                    StatusBtn {
                        visible: !!statusRow.n.radios.bluetooth
                        icon: statusRow.n.bt_devices.length ? "bluetooth_connected" : "bluetooth"
                        tip: statusRow.n.bt_devices.length ? statusRow.n.bt_devices.join(", ") : "Bluetooth"
                        onClicked: bar.openTab("ctrl")
                    }
                    StatusBtn {
                        readonly property int v: Math.round(Ilot.vol.level * 100)
                        icon: Ilot.vol.muted || v === 0 ? "volume_off" : v < 50 ? "volume_down" : "volume_up"
                        text: Ilot.vol.muted ? "–" : v + "%"
                        off: Ilot.vol.muted
                        tip: "Clic : couper · molette : volume"
                        onClicked: Ilot.setVolume(undefined, !Ilot.vol.muted)
                        onWheel: w => {
                            const level = Math.max(0, Math.min(1, Math.round((Ilot.vol.level + Math.sign(w.angleDelta.y) * 0.05) * 100) / 100))
                            Ilot.setVolume(level, false)
                        }
                    }
                    StatusBtn {
                        readonly property var r: Ilot.sys
                        visible: !!r && r.battery >= 0
                        icon: !r ? "" : r.charging ? "battery_charging_full" : r.battery <= 20 ? "battery_std" : "battery_full"
                        text: r ? r.battery + "%" : ""
                        tip: r && r.charging ? "En charge" : "Sur batterie"
                        onClicked: bar.openTab("home")
                    }
                }
            }

            // notifications
            Group {
                id: bell
                button: true
                readonly property int n: Ilot.notifs.length
                readonly property bool has: n > 0 && !Ilot.cfg.dnd
                tip: "Notifications"
                fill: has ? Theme.tertiaryContainer : ""
                width: bellRow.implicitWidth + 20
                onClicked: bar.openTab("ctrl")
                Row {
                    id: bellRow
                    anchors.centerIn: parent
                    spacing: 5
                    Ms {
                        name: Ilot.cfg.dnd ? "do_not_disturb_on" : bell.n ? "notifications" : "notifications_none"
                        size: 15
                        color: bell.has ? Theme.inkTertiaryContainer : Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Txt {
                        visible: bell.has
                        text: bell.n > 9 ? "9+" : bell.n
                        px: 12
                        weight: Font.Medium
                        tnum: true
                        color: Theme.inkTertiaryContainer
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // date
            Group {
                button: true
                width: dateText.implicitWidth + 20
                onClicked: bar.openTab("home")
                Txt {
                    id: dateText
                    anchors.centerIn: parent
                    text: Ilot.upperFirst(Ilot.fmt(Ilot.now, "ddd d MMM"))
                    px: 12
                    weight: Font.Medium
                }
            }

            // barre des taches Windows affichee temporairement
            BarBtn {
                visible: !!Ilot.cfg.hide_taskbar
                width: bar.islands ? 30 : 28
                icon: "desktop_windows"
                on: Ilot.taskbarPeek
                tip: Ilot.taskbarPeek ? "Masquer la barre des tâches Windows" : "Afficher la barre des tâches Windows"
                onClicked: Api.invoke("taskbar_peek", { show: !Ilot.taskbarPeek })
            }
            BarBtn {
                width: bar.islands ? 30 : 28
                icon: "power_settings_new"
                tip: "Session"
                onClicked: bar.openTab("home")
            }
        }
    }

    // largeur maximale d'un cote : le centre reste libre pour l'ilot
    readonly property real sideMax: hasIsland ? width / 2 - 190 : width / 2 - 50

    // ------------------------------------------- apercu des fenetres
    TaskPreview {
        id: preview
        bar: bar
        y: Ilot.barH - 2
        onOpenChanged: bar.layoutChanged()
        onRectChangedSig: bar.layoutChanged()
    }

    // composants locaux
    component Group: Btn {
        id: g
        property bool button: false
        // ilots separes : chaque groupe a son fond et son ombre
        property bool bare: false
        property string fill: ""
        readonly property bool isRepeater: false
        active: button || tip !== ""
        cursor: button ? Qt.PointingHandCursor : Qt.ArrowCursor
        height: bar.islands ? 24 : 22
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        radius: height / 2
        color: fill !== "" ? fill
            : bare ? "transparent"
            : (button && hovered) ? Theme.surfaceHigh
            : bar.islands ? Theme.islandBg : Theme.surfaceC
        RectangularShadow {
            z: -1
            visible: bar.islands && !g.bare
            anchors.fill: parent
            radius: g.radius
            offset.y: 2
            blur: 10
            color: Qt.rgba(0, 0, 0, 0.28)
        }
    }

    component BarBtn: Btn {
        id: bb
        property alias icon: ic.name
        property bool launch: false
        property bool on: false
        width: 28
        height: bar.islands ? 24 : 22
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        radius: height / 2
        color: launch ? (hovered ? Theme.lift(Theme.primary) : Theme.primary)
            : on ? Theme.secondaryContainer
            : hovered ? Theme.surfaceHigh
            : bar.islands ? Theme.islandBg : "transparent"
        RectangularShadow {
            z: -1
            visible: bar.islands
            anchors.fill: parent
            radius: bb.radius
            offset.y: 2
            blur: 10
            color: Qt.rgba(0, 0, 0, 0.28)
        }
        Ms {
            id: ic
            anchors.centerIn: parent
            size: 17
            color: bb.launch ? Theme.inkPrimary : bb.on ? Theme.inkSecondaryContainer : bb.hovered ? Theme.ink : Theme.inkVariant
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    component StatusBtn: Btn {
        id: sb
        property alias icon: sic.name
        property alias text: st.text
        property bool off: false
        height: 22
        width: srow.implicitWidth + 12
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        radius: 11
        color: hovered ? Theme.surfaceHigh : "transparent"
        Row {
            id: srow
            anchors.centerIn: parent
            spacing: 4
            Ms {
                id: sic
                size: 15
                color: sb.off ? Theme.inkVariant : Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            Txt {
                id: st
                visible: text !== ""
                px: 12
                weight: Font.Medium
                tnum: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
