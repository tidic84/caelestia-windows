import QtQuick
import IlotCore

// Panneau ouvert : onglets, outils (verrouiller, agrandir, quitter) et pages
Item {
    id: panel
    readonly property bool open: Ilot.mode === "open"
    readonly property var target: Ilot.big ? Ilot.bigSize : Ilot.openSize
    // Apparence > Taille du texte : tout le panneau est agrandi d'autant
    readonly property real k: Theme.textK
    width: target.w / k
    height: target.h / k
    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    Behavior on height { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
    enabled: open

    opacity: open ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: panel.open ? 60 : 0 }
            NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std }
        }
    }
    transform: [
        Scale {
            origin.x: panel.width / 2
            origin.y: 0
            xScale: panel.k
            yScale: panel.k
        },
        Scale {
            origin.x: panel.width / 2
            origin.y: 0
            xScale: panel.open ? 1 : 0.97
            yScale: xScale
            Behavior on xScale {
                SequentialAnimation {
                    PauseAnimation { duration: panel.open ? 60 : 0 }
                    NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph }
                }
            }
        },
        Translate {
            y: panel.open ? 0 : -24
            Behavior on y {
                SequentialAnimation {
                    PauseAnimation { duration: panel.open ? 60 : 0 }
                    NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph }
                }
            }
        }
    ]

    // ---------------------------------------------------------- onglets
    // essentiels + addons actives (Ilot.catalog, Reglages > Addons)
    readonly property var tabList: Ilot.tabItems
    // tous les onglets nommes s'ils tiennent entre le partage et les outils
    FontMetrics {
        id: tabFm
        font.family: Theme.font
        font.pointSize: 13 * 0.75
    }
    readonly property bool allNamed: {
        let w = 8 + (tabList.length - 1) * 4
        for (const t of tabList)
            w += 19 + 16 + (t.label ? Math.ceil(tabFm.advanceWidth(t.label)) + 6 : 0)
        return w <= tools.x - 12 - (shareBtn.x + shareBtn.width)
    }

    // Quick Share, a gauche. Des fichiers glisses sur l'ilot le font
    // s'allumer ; les garder 200 ms dessus ouvre Quick Share.
    IconBtn {
        id: shareBtn
        x: 18
        y: 12
        z: 2
        width: 34
        height: 34
        iconSize: 19
        readonly property bool lit: Ilot.fileDrag && !Watch.shareOpen
        on: Watch.shareOpen
        filled: lit
        fg: lit ? Theme.inkPrimary : on ? Theme.inkSecondaryContainer : Theme.inkVariant
        icon: "nearby"
        tip: "Quick Share : envoyer aux appareils à proximité, recevoir"
        onClicked: Watch.shareOpen ? (Watch.shareOpen = false) : Watch.openShare([])
        // une demande de reception attend
        readonly property bool asking: Watch.qs.transfers.some(t => t.status === "ask")
        property real pulse: 1
        scale: pressed ? 0.9 : shareDrop.containsDrag ? 1.2 : 1
        transform: Scale {
            origin.x: shareBtn.width / 2
            origin.y: shareBtn.height / 2
            xScale: shareBtn.pulse
            yScale: shareBtn.pulse
        }
        SequentialAnimation on pulse {
            running: (shareBtn.lit || shareBtn.asking) && !shareDrop.containsDrag && !Theme.reduced
            loops: Animation.Infinite
            NumberAnimation { to: 1.12; duration: 450; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) shareBtn.pulse = 1
        }
        // ondes autour du bouton, comme l'icone « a proximite »
        Repeater {
            model: shareBtn.lit && !Theme.reduced ? 2 : 0
            Rectangle {
                required property int index
                anchors.centerIn: parent
                width: shareBtn.width
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: Theme.primary
                z: -1
                opacity: 0
                SequentialAnimation on scale {
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 600 }
                    NumberAnimation { from: 1; to: 1.6; duration: 1200; easing.type: Easing.OutCubic }
                }
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 600 }
                    NumberAnimation { from: 0.8; to: 0; duration: 1200; easing.type: Easing.OutCubic }
                }
            }
        }
        Rectangle {
            visible: shareBtn.asking
            x: parent.width - 10
            y: 0
            width: 10
            height: 10
            radius: 5
            color: Theme.error
        }
        DropArea {
            id: shareDrop
            anchors.fill: parent
            anchors.margins: -8
            onEntered: d => {
                if (!d.hasUrls)
                    return d.accepted = false
                Ilot.dragIn()
                hoverOpen.restart()
            }
            onExited: {
                hoverOpen.stop()
                Ilot.dragLeft()
            }
            onDropped: d => {
                hoverOpen.stop()
                Ilot.dragDone()
                d.acceptProposedAction()
                Watch.openShare(Ilot.dropPaths(d.urls))
            }
        }
        Timer {
            id: hoverOpen
            interval: 200
            onTriggered: {
                // l'ilot ouvert par le glisser reste ouvert : on va deposer ici
                Ilot.fileDragOpened = false
                Watch.openShare([])
            }
        }
    }

    Rectangle {
        id: tabsBox
        y: 10
        // centre entre le bouton de partage et les outils de droite
        readonly property real minX: shareBtn.x + shareBtn.width + 6
        readonly property real maxX: tools.x - 6
        x: Math.max(minX, Math.min(maxX - width, (panel.width - width) / 2))
        width: tabsRow.width + 8
        height: tabsRow.height + 8
        radius: height / 2
        color: Theme.surfaceC

        // fermer en remontant la molette sur les onglets
        WheelHandler {
            onWheel: e => {
                if (e.angleDelta.y > 0)
                    Ilot.close()
            }
        }

        Rectangle {
            id: ind
            readonly property Item on: tabsRow.children[Ilot.tabs.indexOf(Ilot.currentTab)] || null
            // Quick Share ouvert : aucun onglet n'est actif
            opacity: Watch.shareOpen ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 200 } }
            x: on ? on.x + 4 : 4
            y: 4
            width: on ? on.width : 0
            height: tabsRow.height
            radius: height / 2
            color: Theme.primary
            Behavior on x { NumberAnimation { duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        }

        Row {
            id: tabsRow
            x: 4
            y: 4
            spacing: 4
            Repeater {
                model: panel.tabList
                Btn {
                    id: tab
                    required property var modelData
                    readonly property bool on: Ilot.currentTab === modelData.id && !Watch.shareOpen
                    // panneau normal : avec trop d'onglets pour tous les nommer, seul
                    // l'onglet actif garde son nom (les autres l'ont en info-bulle)
                    readonly property bool named: modelData.label !== "" && (Ilot.big || on || panel.allNamed)
                    readonly property real padX: Ilot.big ? 13 : 8
                    width: content.width + padX * 2
                    height: 35
                    radius: height / 2
                    tip: named ? "" : (modelData.tip || modelData.label)
                    readonly property color fg: on ? Theme.inkPrimary : hovered ? Theme.ink : Theme.inkVariant
                    onClicked: {
                        Ilot.showTab(modelData.id)
                        if (modelData.id === "apps")
                            Ilot.focusSearch()
                    }
                    Row {
                        id: content
                        anchors.centerIn: parent
                        spacing: 6
                        Ms {
                            name: tab.modelData.icon
                            size: 19
                            color: tab.fg
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 250 } }
                        }
                        Txt {
                            visible: tab.named
                            text: tab.modelData.label
                            color: tab.fg
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 250 } }
                        }
                    }
                    // pastille : notifications, mails non lus
                    Rectangle {
                        readonly property int n: tab.modelData.id === "ctrl" ? Ilot.notifs.length : tab.modelData.id === "mail" ? Ilot.unread : 0
                        visible: n > 0
                        x: parent.width - width - 6
                        y: 2
                        width: Math.max(16, badgeText.implicitWidth + 8)
                        height: 16
                        radius: 8
                        color: Theme.error
                        Txt {
                            id: badgeText
                            anchors.centerIn: parent
                            text: tab.modelData.id === "ctrl" ? (parent.n > 9 ? "9+" : parent.n) : (parent.n > 99 ? "99+" : parent.n)
                            px: 10
                            weight: Font.DemiBold
                            color: Theme.inkError
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- outils
    Row {
        id: tools
        anchors.right: parent.right
        anchors.rightMargin: 18
        y: 12
        spacing: 4
        z: 2
        IconBtn {
            width: 34
            iconSize: 19
            height: 34
            on: Ilot.locked
            fg: on ? Theme.inkSecondaryContainer : Theme.inkVariant
            icon: Ilot.locked ? "lock" : "lock_open"
            tip: Ilot.locked ? "Déverrouiller : l'îlot se replie quand la souris sort" : "Verrouiller : l'îlot reste ouvert"
            onClicked: Ilot.setLocked(!Ilot.locked)
        }
        IconBtn {
            width: 34
            iconSize: 19
            height: 34
            on: Ilot.big
            fg: on ? Theme.inkSecondaryContainer : Theme.inkVariant
            icon: Ilot.big ? "close_fullscreen" : "open_in_full"
            tip: Ilot.big ? "Réduire" : "Agrandir"
            onClicked: Ilot.setBig(!Ilot.big)
        }
        IconBtn {
            id: quit
            width: 34
            iconSize: 19
            height: 34
            // second clic pour confirmer
            armed: armTimer.running
            color: armed || hovered ? Theme.error : "transparent"
            radius: armed || hovered ? 12 : 17
            fg: armed || hovered ? Theme.inkError : Theme.inkVariant
            icon: "power_settings_new"
            tip: armed ? "Quitter l'îlot ?" : "Quitter l'îlot"
            onClicked: {
                if (!armTimer.running)
                    armTimer.start()
                else
                    Backend.quit()
            }
            Timer {
                id: armTimer
                interval: 3000
            }
        }
    }

    // ------------------------------------------------------------ pages
    Item {
        id: pages
        x: 16
        y: tabsBox.y + tabsBox.height + 12
        width: parent.width - 32
        height: parent.height - y - 16

        // tout le catalogue (et non les seuls onglets affiches) : activer un
        // addon ne recree pas les pages deja ouvertes
        Repeater {
            model: Ilot.catalog
            Loader {
                id: page
                required property var modelData
                required property int index
                readonly property bool on: Ilot.currentTab === modelData.id
                readonly property bool shown: on && !Watch.shareOpen
                // une page n'est creee qu'a sa premiere ouverture, puis gardee
                // tant que son addon reste active
                property bool wanted: false
                readonly property bool allowed: Ilot.tabs.indexOf(modelData.id) >= 0
                active: wanted && allowed
                onAllowedChanged: if (!allowed) wanted = false
                onOnChanged: if (on) wanted = true
                Component.onCompleted: if (on) wanted = true
                width: pages.width
                height: pages.height
                source: modelData.page + ".qml"
                opacity: shown ? 1 : 0
                visible: opacity > 0
                enabled: shown
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
                // la page arrivante glisse du cote de l'onglet choisi
                property real dx: on ? 0 : -Ilot.tabDir * 24
                transform: Translate {
                    x: page.dx
                    Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
                }
            }
        }

        // Quick Share, a la place de la page en cours
        QuickShare {
            id: quickShare
            anchors.fill: parent
            z: 10
            opacity: Watch.shareOpen ? 1 : 0
            visible: opacity > 0
            enabled: Watch.shareOpen
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
            transform: Translate {
                x: Watch.shareOpen ? 0 : -24
                Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
            }
        }
    }
}
