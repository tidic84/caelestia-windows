import QtQuick

// Addon « Claude » : limites de l'abonnement Claude (src/claude.rs, `usage`),
// comme `/usage` dans Claude Code : session de 5 h et semaine. Relu a
// l'ouverture puis toutes les 2 min tant que la page se voit.
Item {
    id: page
    readonly property bool shown: Ilot.mode === "open" && Ilot.currentTab === "cusage"
    property var usage: null
    property string err: ""
    property bool busy: false
    // relu pour faire avancer les comptes a rebours
    property real now: Date.now()

    function load(fresh) {
        busy = true
        Api.invoke("cc_usage", { fresh: fresh }).then(v => {
            page.usage = v
            page.err = ""
            page.busy = false
        }, e => {
            page.err = String(e)
            page.busy = false
        })
    }
    Component.onCompleted: if (shown) load(false)
    onShownChanged: if (shown) load(false)
    Timer {
        interval: 120000
        repeat: true
        running: page.shown
        onTriggered: page.load(false)
    }
    Timer {
        interval: 30000
        repeat: true
        running: page.shown
        onTriggered: page.now = Date.now()
    }

    // « dans 1 h 12 · 16:40 », « dans 2 j 5 h · lun. 11:00 »
    function resetText(iso) {
        if (!iso)
            return ""
        const t = new Date(iso)
        const m = Math.max(0, Math.round((t.getTime() - now) / 60000))
        const left = m >= 1440 ? Math.floor(m / 1440) + " j " + Math.floor(m % 1440 / 60) + " h"
            : m >= 60 ? Math.floor(m / 60) + " h " + Ilot.pad(m % 60)
            : m + " min"
        return "Remise à zéro dans " + left + " · " + fmtWhen(t)
    }
    // « 16:40 » aujourd'hui, sinon « lun. 11:00 »
    function fmtWhen(t) {
        const today = new Date(now).toDateString() === t.toDateString()
        return (today ? "" : t.toLocaleDateString(Qt.locale("fr_FR"), "ddd") + " ") + Ilot.pad(t.getHours()) + ":" + Ilot.pad(t.getMinutes())
    }
    // Projection au rythme moyen depuis le debut de la fenetre (5 h ou 7 j) :
    // { pct } a la remise a zero, `hit` = heure ou la limite serait atteinte
    // (0 si jamais). null tant que moins de 5 % de la fenetre s'est ecoule.
    function project(key, lim) {
        if (!lim.resets)
            return null
        const win = (key === "session" ? 5 * 3600 : 7 * 86400) * 1000
        const left = Math.max(0, new Date(lim.resets).getTime() - now)
        const spent = win - left
        if (spent < win * 0.05)
            return null
        const pct = lim.pct * win / spent
        const hit = pct >= 100 && lim.pct < 100 ? now + (100 - lim.pct) * spent / Math.max(0.01, lim.pct) : 0
        return { pct: pct, hit: hit }
    }
    function projText(p, lim) {
        if (lim.pct >= 100)
            return "Limite atteinte"
        if (!p)
            return "Projection : pas encore assez de recul"
        if (p.hit)
            return "À ce rythme : limite atteinte vers " + fmtWhen(new Date(p.hit))
        return "À ce rythme : ≈ " + Math.round(p.pct) + " % à la remise à zéro"
    }
    readonly property var limits: !usage ? [] : [
        { key: "session", icon: "schedule", title: "Session (5 h)" },
        { key: "week", icon: "calendar_month", title: "Semaine" },
        { key: "week_opus", icon: "calendar_month", title: "Semaine · Opus" },
        { key: "week_sonnet", icon: "calendar_month", title: "Semaine · Sonnet" }
    ].filter(l => usage[l.key] && usage[l.key].pct !== null && usage[l.key].pct !== undefined)

    // limite affichee dans le graphique
    property string chartKey: "week"
    readonly property var chartLim: usage && usage[chartKey] && usage[chartKey].pct !== null && usage[chartKey].pct !== undefined ? usage[chartKey] : null
    readonly property var chartProj: chartLim ? project(chartKey, chartLim) : null
    // phrase d'etat au-dessus du graphique : [icone, titre, detail, couleur]
    readonly property var verdict: {
        const l = chartLim, p = chartProj
        if (!l)
            return ["", "", "", Theme.ink]
        if (l.pct >= 100)
            return ["do_not_disturb_on", "Limite atteinte", resetText(l.resets), Theme.error]
        if (!p)
            return ["hourglass_top", "Pas encore assez de recul", "La prévision apparaît après 5 % de la fenêtre.", Theme.inkVariant]
        if (p.hit)
            return ["error", "Limite atteinte vers " + fmtWhen(new Date(p.hit)), "À ce rythme, avant la remise à zéro : ralentis un peu.", Theme.error]
        if (p.pct >= 90)
            return ["error_outline", "Rythme serré", "À ce rythme, ≈ " + Math.round(p.pct) + " % à la remise à zéro.", Theme.warn]
        return ["verified", "De la marge jusqu'à la remise à zéro", "À ce rythme, ≈ " + Math.round(p.pct) + " % à la remise à zéro.", Theme.ok]
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
    Column {
        id: col
        width: parent.width
        spacing: 12

        Item {
            width: parent.width
            height: 36
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: "Utilisation de Claude"
                px: 18
                weight: Font.Medium
            }
            Txt {
                anchors.right: refresh.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: !!page.usage
                text: page.usage ? (page.usage.plan ? "Abonnement " + page.usage.plan.charAt(0).toUpperCase() + page.usage.plan.slice(1) + " · " : "")
                    + "relevé à " + Ilot.pad(new Date(page.usage.at).getHours()) + ":" + Ilot.pad(new Date(page.usage.at).getMinutes()) : ""
                px: 12
                color: Theme.inkVariant
            }
            IconBtn {
                id: refresh
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                icon: "refresh"
                tip: "Actualiser"
                onClicked: page.load(true)
                RotationAnimator on rotation {
                    running: page.busy
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) parent.rotation = 0
                }
            }
        }

        Empty {
            visible: !page.usage && page.err !== ""
            width: parent.width
            icon: "cloud_off"
            text: page.err
        }

        Flow {
            visible: page.limits.length > 0
            width: parent.width
            spacing: 10
            Repeater {
                model: page.limits
                Card {
                    id: card
                    required property var modelData
                    readonly property var lim: page.usage[modelData.key]
                    readonly property real frac: Math.max(0, Math.min(1, lim.pct / 100))
                    readonly property color tone: frac >= 0.9 ? Theme.error : frac >= 0.7 ? Theme.warn : Theme.primary
                    readonly property var proj: page.project(modelData.key, lim)
                    readonly property real projFrac: proj ? Math.max(frac, Math.min(1, proj.pct / 100)) : frac
                    readonly property color projTone: proj && proj.pct >= 100 ? Theme.error : proj && proj.pct >= 70 ? Theme.warn : Theme.primary
                    width: (parent.width - 10) / 2
                    height: 152
                    Ms {
                        x: 16
                        y: 16
                        name: card.modelData.icon
                        size: 18
                        color: Theme.inkVariant
                    }
                    Txt {
                        x: 40
                        y: 16
                        height: 18
                        text: card.modelData.title
                        px: 12.5
                        weight: Font.Medium
                        color: Theme.inkVariant
                    }
                    Txt {
                        x: 16
                        y: 42
                        text: Math.round(card.lim.pct) + " %"
                        px: 30
                        weight: Font.Medium
                        tnum: true
                        color: card.frac >= 0.9 ? Theme.error : Theme.ink
                    }
                    Rectangle {
                        id: track
                        x: 16
                        y: 88
                        width: parent.width - 32
                        height: 8
                        radius: 4
                        color: Theme.surfaceHighest
                        // projection : partie claire jusqu'au niveau prevu
                        Rectangle {
                            width: Math.max(card.projFrac > 0 ? height : 0, parent.width * card.projFrac)
                            height: parent.height
                            radius: 4
                            color: Theme.alpha(card.projTone, 0.35)
                            Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
                        }
                        Rectangle {
                            width: Math.max(card.frac > 0 ? height : 0, parent.width * card.frac)
                            height: parent.height
                            radius: 4
                            color: card.tone
                            Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emph } }
                        }
                    }
                    Txt {
                        x: 16
                        y: 104
                        width: parent.width - 32
                        text: page.resetText(card.lim.resets)
                        px: 11.5
                        color: Theme.inkVariant
                        elide: Text.ElideRight
                    }
                    Txt {
                        x: 16
                        y: 124
                        width: parent.width - 32
                        text: page.projText(card.proj, card.lim)
                        px: 11.5
                        weight: Font.Medium
                        color: card.proj && card.proj.pct >= 100 || card.lim.pct >= 100 ? Theme.error : Theme.ink
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // graphique facon Agent Burn
        Card {
            visible: !!page.chartLim
            width: parent.width
            height: chartCol.height + 32
            Column {
                id: chartCol
                x: 16
                y: 16
                width: parent.width - 32
                spacing: 8
                Item {
                    width: parent.width
                    height: 32
                    Ms {
                        anchors.verticalCenter: parent.verticalCenter
                        name: page.verdict[0]
                        size: 20
                        color: page.verdict[3]
                    }
                    Txt {
                        x: 28
                        width: parent.width - 28 - seg.width - 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.verdict[1]
                        px: 15
                        weight: Font.Medium
                        color: page.verdict[3]
                        elide: Text.ElideRight
                    }
                    Seg {
                        id: seg
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        model: [{ id: "session", label: "Session" }, { id: "week", label: "Semaine" }]
                        current: page.chartKey
                        onPicked: id => page.chartKey = id
                    }
                }
                Txt {
                    width: parent.width
                    text: page.verdict[2]
                    px: 12.5
                    color: Theme.inkVariant
                    wrapMode: Text.Wrap
                }
                // legende
                Row {
                    spacing: 16
                    topPadding: 4
                    Repeater {
                        model: [["Relevé", []], ["Prévision", [6, 5]], ["Rythme régulier", [2, 4]]]
                        Row {
                            id: lg
                            required property var modelData
                            required property int index
                            spacing: 6
                            Canvas {
                                id: lgc
                                width: 18
                                height: 14
                                anchors.verticalCenter: parent.verticalCenter
                                onPaint: {
                                    const c = getContext("2d")
                                    c.reset()
                                    c.strokeStyle = lg.index === 2 ? Theme.alpha(Theme.ink, 0.35) : chart.tone
                                    c.lineWidth = lg.index === 2 ? 1.5 : 2.5
                                    c.setLineDash(lg.modelData[1])
                                    c.beginPath()
                                    c.moveTo(0, 7)
                                    c.lineTo(18, 7)
                                    c.stroke()
                                }
                                Connections {
                                    target: chart
                                    function onToneChanged() { lgc.requestPaint() }
                                }
                                // rythme regulier : trait couleur d'encre, suit le theme
                                Connections {
                                    target: Theme
                                    enabled: lg.index === 2
                                    function onInkChanged() { lgc.requestPaint() }
                                }
                            }
                            Txt {
                                text: lg.modelData[0]
                                px: 11.5
                                color: Theme.inkVariant
                            }
                        }
                    }
                }
                UsageChart {
                    id: chart
                    width: parent.width
                    lim: page.chartLim
                    hist: page.usage && page.usage.hist ? page.usage.hist[page.chartKey] || [] : []
                    win: (page.chartKey === "session" ? 5 * 3600 : 7 * 86400) * 1000
                    proj: page.chartProj
                    now: page.now
                }
                Txt {
                    width: parent.width
                    text: "L'historique se remplit au fil des relevés (toutes les 5 min tant que l'addon est activé)."
                    px: 11.5
                    color: Theme.inkVariant
                    wrapMode: Text.Wrap
                }
            }
        }

        Txt {
            visible: !!page.usage && page.err !== ""
            width: parent.width
            text: page.err
            px: 12
            color: Theme.error
            wrapMode: Text.Wrap
        }

        TextBtn {
            icon: "open_in_new"
            text: "Détails sur claude.ai"
            onClicked: Api.invoke("open_url", { url: "https://claude.ai/settings/usage" })
        }
    }
    }
}
