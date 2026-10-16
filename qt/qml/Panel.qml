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
    readonly property var tabList: [
        { id: "home", icon: "dashboard", label: "Accueil" },
        { id: "media", icon: "music_note", label: "Média" },
        { id: "ctrl", icon: "tune", label: "Contrôles" },
        { id: "apps", icon: "apps", label: "Apps" },
        { id: "mail", icon: "mail", label: "Mail" },
        { id: "pc", icon: "sports_esports", label: "PC" },
        { id: "sounds", icon: "graphic_eq", label: "Soundboard" },
        { id: "tasks", icon: "monitoring", label: "Tâches" },
        { id: "clips", icon: "content_paste", label: "Presse-papiers" },
        { id: "assist", icon: "translate", label: "Assistant", tip: "Traduction, sous-titres en direct et Claude" },
        { id: "walls", icon: "wallpaper", label: "Fonds" },
        { id: "settings", icon: "settings", label: "", tip: "Réglages" }
    ]

    // partage avec le telephone (QR code), a gauche
    IconBtn {
        id: shareBtn
        x: 18
        y: 12
        z: 2
        width: 34
        height: 34
        iconSize: 19
        on: Watch.shareOpen
        fg: on ? Theme.inkSecondaryContainer : Theme.inkVariant
        icon: "phonelink"
        tip: "Partager avec le téléphone (QR code)"
        onClicked: Watch.shareOpen ? (Watch.shareOpen = false) : Watch.openShare([])
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
                    readonly property bool on: Ilot.currentTab === modelData.id
                    // panneau normal : trop d'onglets pour tous les nommer, seul
                    // l'onglet actif garde son nom (les autres l'ont en info-bulle)
                    readonly property bool named: modelData.label !== "" && (Ilot.big || on)
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

        Repeater {
            model: panel.tabList
            Loader {
                id: page
                required property var modelData
                required property int index
                readonly property bool on: Ilot.currentTab === modelData.id
                // une page n'est creee qu'a sa premiere ouverture, puis gardee
                property bool wanted: false
                active: wanted
                onOnChanged: if (on) wanted = true
                Component.onCompleted: if (on) wanted = true
                width: pages.width
                height: pages.height
                source: {
                    const names = { home: "HomePage", media: "MediaPage", ctrl: "CtrlPage", apps: "AppsPage", mail: "MailPage",
                        pc: "PcPage", sounds: "SoundsPage", tasks: "TasksPage", clips: "ClipsPage", assist: "AssistPage",
                        walls: "WallsPage", settings: "SettingsPage" }
                    return names[modelData.id] + ".qml"
                }
                opacity: on ? 1 : 0
                visible: opacity > 0
                enabled: on
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.std } }
                // la page arrivante glisse du cote de l'onglet choisi
                property real dx: on ? 0 : -Ilot.tabDir * 24
                transform: Translate {
                    x: page.dx
                    Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
                }
            }
        }

        // partage avec le telephone, par-dessus la page
        SharePop {
            anchors.fill: parent
            z: 10
        }
    }
}
