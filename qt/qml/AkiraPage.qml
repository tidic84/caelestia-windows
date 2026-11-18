import QtQuick

// Onglet Akira (addon, src/akira.rs) : la conversation en « scene »
// (maquette AkiraVoice/mockup/ilot-akira.html, direction Scene). La sphere
// au centre, l'etat, la derniere phrase entendue, la reponse en grand, l'outil
// en cours ; en bas les taches Claude lancees par Akira, le micro (reveil ou
// mise en veille), la latence et le cout. L'historique s'ouvre a droite.
Item {
    id: page
    readonly property var info: Watch.akInfo || {}
    readonly property var st: Watch.akStatus || {}
    readonly property bool online: Watch.akOnline
    readonly property bool live: Watch.akLive
    property bool histOpen: false
    property bool tasksOpen: false

    // « Gemini Live · Kore » (model_name d'Akira : « <modele>, voix <voix> »)
    readonly property string engine: {
        const names = { "gemini-live": "Gemini Live", "gpt-live": "GPT-Live", "openai-realtime": "Realtime" }
        const voice = String(info.model || "").split(", voix ")[1] || ""
        return [names[info.backend] || info.backend || "", voice].filter(Boolean).join(" · ")
    }
    readonly property string hint: info.wakeword ? "Dis « Akira », ou touche le micro."
        : "Touche le micro" + (info.hotkey ? " ou " + String(info.hotkey).replace(/[<>]/g, "").replace(/\+/g, " + ") : "") + "."
    function money(v) {
        return v.toFixed(2).replace(".", ",") + " $"
    }

    // ---------------------------------------------------------- en haut
    Rectangle {
        visible: page.online && page.engine !== ""
        x: 0
        y: 0
        width: engRow.implicitWidth + 24
        height: 30
        radius: 10
        color: Theme.surfaceHigh
        Row {
            id: engRow
            anchors.centerIn: parent
            spacing: 6
            Ms {
                name: "bolt"
                size: 16
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            Txt {
                text: page.engine
                px: 12.5
                color: Theme.inkVariant
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    IconBtn {
        anchors.right: parent.right
        y: -3
        icon: page.histOpen ? "close" : "history"
        tip: page.histOpen ? "Fermer l'historique" : "Historique de la conversation"
        onClicked: page.histOpen = !page.histOpen
    }

    // ---------------------------------------------------------- scene
    Column {
        id: scene
        width: parent.width
        y: 0
        spacing: 0
        opacity: page.histOpen ? 0.25 : 1
        Behavior on opacity { NumberAnimation { duration: 250 } }

        AkiraOrb {
            id: orb
            readonly property real side: Math.min(230, page.height * 0.46)
            width: side * 1.6
            height: side
            anchors.horizontalCenter: parent.horizontalCenter
            mood: page.online ? Watch.akState : "veille"
            opacity: page.online ? 1 : 0.45
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            bottomPadding: 8
            Spinner {
                visible: page.online && Watch.akState === "reflexion"
                size: 11
                stroke: 2
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                visible: page.online && Watch.akState !== "reflexion"
                width: 7
                height: 7
                radius: 4
                color: Watch.akState === "ecoute" ? Theme.mic : Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
            Txt {
                text: !page.online ? (page.st.running ? "Démarrage" : "Hors ligne")
                    : (Watch.akStates[Watch.akState] || {}).label || ""
                px: 11.5
                weight: Font.DemiBold
                color: Theme.primary
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 5
            }
        }
        Txt {
            width: Math.min(parent.width, 620)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: page.online && Watch.akYou ? "« " + Watch.akYou + " »" : ""
            px: 13.5
            color: Theme.inkVariant
            elide: Text.ElideLeft
            maximumLineCount: 1
            height: 20
        }
        Txt {
            width: Math.min(parent.width, 660)
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 6
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            px: 19
            weight: Font.Light
            lineHeight: 1.2
            // la consigne de reveil seulement en veille
            text: !page.online ? "" : Watch.akAi || (page.live ? "" : page.hint)
            color: Theme.ink
        }
        // outil en cours
        Item {
            width: parent.width
            height: 44
            Rectangle {
                visible: page.online && !!Watch.akTool
                anchors.centerIn: parent
                width: toolRow.implicitWidth + 26
                height: 32
                radius: 10
                color: Theme.tertiaryContainer
                Row {
                    id: toolRow
                    anchors.centerIn: parent
                    spacing: 8
                    Spinner {
                        size: 12
                        stroke: 2
                        color: Theme.inkTertiaryContainer
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Txt {
                        text: Watch.akTool ? Watch.akToolInfo(Watch.akTool.name).label : ""
                        px: 12.5
                        color: Theme.inkTertiaryContainer
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    // Akira absente : dossier a choisir, demarrage, erreur
    Column {
        visible: !page.online
        width: Math.min(parent.width - 40, 520)
        anchors.horizontalCenter: parent.horizontalCenter
        y: orb.height + 40
        spacing: 12
        Txt {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: page.st.error ? Theme.bad : Theme.inkVariant
            text: page.st.error ? page.st.error
                : !page.st.dir ? "Choisis le dossier d'AkiraVoice dans les Réglages pour que l'îlot lance Akira."
                : page.st.running ? "Akira démarre…" : "Akira n'est pas lancée."
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            TextBtn {
                icon: "settings"
                text: "Réglages"
                onClicked: Ilot.openSettings("addons")
            }
            TextBtn {
                visible: !!page.st.dir
                icon: "restart_alt"
                text: "Relancer"
                onClicked: Api.invoke("akira_restart")
            }
        }
    }

    // ---------------------------------------------------------- en bas
    Item {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 56
        visible: page.online

        // taches Claude lancees par Akira
        Btn {
            id: tasksChip
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: tasksRow.implicitWidth + 24
            height: 32
            radius: 10
            color: hovered ? Theme.surfaceHighest : Theme.surfaceHigh
            onClicked: page.tasksOpen = !page.tasksOpen
            Row {
                id: tasksRow
                anchors.centerIn: parent
                spacing: 6
                Ms {
                    name: "terminal"
                    size: 16
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
                Txt {
                    px: 12.5
                    color: Theme.inkVariant
                    anchors.verticalCenter: parent.verticalCenter
                    text: !Watch.akTasks.length ? "Aucune tâche Claude"
                        : Watch.akRunning ? Watch.akRunning + (Watch.akRunning > 1 ? " tâches Claude en cours" : " tâche Claude en cours")
                        : Watch.akTasks.length + (Watch.akTasks.length > 1 ? " tâches Claude terminées" : " tâche Claude terminée")
                }
            }
        }

        // micro : reveille Akira, ou la remet en veille
        Btn {
            id: mic
            anchors.centerIn: parent
            width: 56
            height: 56
            radius: 20
            readonly property bool on: Watch.akLive
            color: on ? Theme.primary : hovered ? Theme.lift(Theme.primaryContainer) : Theme.primaryContainer
            scale: pressed ? 0.92 : hovered ? 1.05 : 1
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
            tip: on ? "Remettre Akira en veille" : "Parler à Akira"
            onClicked: Watch.akToggle()
            Ms {
                anchors.centerIn: parent
                name: mic.on ? "mic_off" : "mic"
                size: 26
                color: mic.on ? Theme.inkPrimary : Theme.inkPrimaryContainer
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle {
                visible: Watch.akLatency > 0
                width: latRow.implicitWidth + 24
                height: 32
                radius: 10
                color: Theme.surfaceHigh
                Row {
                    id: latRow
                    anchors.centerIn: parent
                    spacing: 6
                    Ms {
                        name: "timer"
                        size: 16
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Txt {
                        text: Watch.akLatency + " ms"
                        px: 12.5
                        tnum: true
                        color: Theme.inkVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Tip {
                    text: "Latence de la dernière réponse (silence de fin de phrase compris)"
                    shown: latHover.containsMouse
                }
                MouseArea {
                    id: latHover
                    anchors.fill: parent
                    hoverEnabled: true
                }
            }
            Rectangle {
                width: costTxt.implicitWidth + 24
                height: 32
                radius: 10
                color: Theme.surfaceHigh
                Txt {
                    id: costTxt
                    anchors.centerIn: parent
                    text: page.money(Watch.akSpent + Watch.akSession)
                    px: 12.5
                    tnum: true
                    color: Theme.inkVariant
                }
                Tip {
                    text: "Coût estimé depuis le lancement d'Akira"
                    shown: costHover.containsMouse
                }
                MouseArea {
                    id: costHover
                    anchors.fill: parent
                    hoverEnabled: true
                }
            }
        }
    }

    // liste des taches, au-dessus de leur pastille
    Rectangle {
        visible: page.tasksOpen && page.online
        x: 0
        width: Math.min(380, parent.width)
        height: Math.min(260, tasksCol.implicitHeight + 28)
        y: bar.y + (bar.height - 32) / 2 - height - 8
        radius: 20
        color: Theme.surfaceHigh
        clip: true
        Flickable {
            id: tasksFlick
            anchors.fill: parent
            anchors.margins: 14
            contentHeight: tasksCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: tasksCol
                width: parent.width
                spacing: 8
                Txt {
                    text: "Tâches lancées par Akira"
                    weight: Font.DemiBold
                }
                Txt {
                    visible: !Watch.akTasks.length
                    text: "Aucune pour l'instant. Demande par exemple : « Lance une tâche avec Opus dans lightcraft… »"
                    width: parent.width
                    wrapMode: Text.WordWrap
                    px: 12.5
                    color: Theme.inkVariant
                }
                Repeater {
                    model: Watch.akTasks
                    Row {
                        id: trow
                        required property var modelData
                        width: tasksCol.width
                        spacing: 10
                        Ms {
                            name: "terminal"
                            size: 18
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            width: parent.width - 28 - badge.width - 10
                            anchors.verticalCenter: parent.verticalCenter
                            Txt {
                                width: parent.width
                                text: trow.modelData.instruction || ""
                                elide: Text.ElideRight
                            }
                            Txt {
                                width: parent.width
                                text: [trow.modelData.project, trow.modelData.model].filter(Boolean).join(" · ")
                                px: 11.5
                                color: Theme.inkVariant
                                elide: Text.ElideRight
                            }
                        }
                        Rectangle {
                            id: badge
                            readonly property bool run: trow.modelData.status === "en cours"
                            readonly property bool bad: trow.modelData.status === "échec"
                            width: badgeTxt.implicitWidth + 18
                            height: 22
                            radius: 11
                            anchors.verticalCenter: parent.verticalCenter
                            color: bad ? Theme.error : run ? Theme.secondaryContainer : Theme.tertiaryContainer
                            Txt {
                                id: badgeTxt
                                anchors.centerIn: parent
                                text: trow.modelData.status || ""
                                px: 11
                                color: badge.bad ? Theme.inkError : badge.run ? Theme.inkSecondaryContainer : Theme.inkTertiaryContainer
                            }
                        }
                    }
                }
            }
        }
        Scroller { flick: tasksFlick }
    }

    // ------------------------------------------------------ historique
    Rectangle {
        id: drawer
        anchors.right: parent.right
        y: 40
        width: Math.min(340, parent.width)
        height: parent.height - y - (bar.visible ? bar.height + 8 : 0)
        radius: 22
        color: Theme.surfaceLow
        opacity: page.histOpen ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        transform: Translate {
            x: page.histOpen ? 0 : 24
            Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
        }
        Txt {
            visible: !Watch.akLog.length
            anchors.centerIn: parent
            text: "Rien pour l'instant"
            color: Theme.inkVariant
        }
        ListView {
            id: logView
            anchors.fill: parent
            anchors.margins: 14
            anchors.rightMargin: 10
            spacing: 8
            clip: true
            model: Watch.akLog
            boundsBehavior: Flickable.StopAtBounds
            // a 80 messages, count ne change plus : on suit le modele
            onModelChanged: Qt.callLater(positionViewAtEnd)
            onVisibleChanged: if (visible) Qt.callLater(positionViewAtEnd)
            delegate: Item {
                id: msg
                required property var modelData
                readonly property bool you: modelData.kind === "you"
                readonly property bool bubble: modelData.kind === "you" || modelData.kind === "ai"
                width: logView.width - 8
                height: bubble ? bub.height : side.implicitHeight + 2
                Rectangle {
                    id: bub
                    visible: msg.bubble
                    anchors.right: msg.you ? parent.right : undefined
                    width: Math.min(msg.width * 0.86, bubTxt.implicitWidth + 26)
                    height: bubTxt.implicitHeight + 18
                    radius: 18
                    color: msg.you ? Theme.primaryContainer : Theme.surfaceHigh
                    Txt {
                        id: bubTxt
                        x: 13
                        y: 9
                        width: Math.min(msg.width * 0.86 - 26, implicitWidth)
                        text: msg.modelData.text
                        wrapMode: Text.WordWrap
                        px: 13
                        color: msg.you ? Theme.inkPrimaryContainer : Theme.ink
                    }
                }
                Row {
                    id: side
                    visible: !msg.bubble
                    spacing: 6
                    Ms {
                        name: msg.modelData.kind === "tool" ? "build" : "check"
                        size: 15
                        color: Theme.tertiary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Txt {
                        text: msg.modelData.text
                        px: 12
                        color: Theme.inkVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
        Scroller { flick: logView }
    }
}
