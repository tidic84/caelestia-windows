import QtQuick

// Graphique de l'addon « Claude » (facon Agent Burn) : utilisation sur toute
// la fenetre d'une limite (5 h ou 7 j). Releves en trait plein, prevision en
// tirets jusqu'a la remise a zero, rythme regulier en pointilles gris.
Item {
    id: ch
    // { pct, resets } de la limite, historique [[ms, pct], ...], fenetre en ms
    property var lim: null
    property var hist: []
    property real win: 0
    // prevision (ClaudeUsagePage.project) : { pct, hit } ou null
    property var proj: null
    property real now: Date.now()
    implicitHeight: 190

    readonly property real end: lim && lim.resets ? new Date(lim.resets).getTime() : 0
    readonly property real start: end - win
    readonly property color tone: proj && proj.pct >= 100 ? Theme.error : proj && proj.pct >= 90 ? Theme.warn : Theme.ok

    onLimChanged: cv.requestPaint()
    onHistChanged: cv.requestPaint()
    onProjChanged: cv.requestPaint()
    onNowChanged: cv.requestPaint()
    Connections {
        target: Theme
        function onPrimaryChanged() { cv.requestPaint() }
        function onInkChanged() { cv.requestPaint() }
    }

    Canvas {
        id: cv
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d")
            c.reset()
            if (!ch.lim || ch.end <= 0 || ch.win <= 0)
                return
            const L = 40, R = 8, T = 10, B = 24
            const w = width - L - R, h = height - T - B
            const X = t => L + Math.max(0, Math.min(1, (t - ch.start) / ch.win)) * w
            const Y = p => T + (1 - Math.max(0, Math.min(100, p)) / 100) * h
            c.font = "11px \"" + Theme.font + "\""

            // grille et graduations 0..100 %
            c.lineWidth = 1
            c.textAlign = "right"
            c.textBaseline = "middle"
            for (let p = 0; p <= 100; p += 25) {
                c.strokeStyle = Theme.alpha(Theme.ink, p === 100 ? 0.18 : 0.07)
                c.setLineDash(p === 100 ? [] : [2, 4])
                c.beginPath()
                c.moveTo(L, Y(p))
                c.lineTo(L + w, Y(p))
                c.stroke()
                c.fillStyle = Theme.inkVariant
                c.fillText(p + " %", L - 6, Y(p))
            }

            // graduations du temps : heures (5 h) ou jours (7 j)
            c.textAlign = "center"
            c.textBaseline = "top"
            c.fillStyle = Theme.inkVariant
            const day = ch.win > 86400000
            const step = day ? 86400000 : 3600000
            const first = new Date(ch.start)
            if (day)
                first.setHours(24, 0, 0, 0)
            else
                first.setMinutes(60, 0, 0)
            for (let t = first.getTime(); t < ch.end; t += step) {
                const d = new Date(t)
                // jour : etiquette a midi, au milieu de la journee
                const at = day ? t + step / 2 : t
                if (at > ch.end)
                    break
                c.fillText(day ? d.toLocaleDateString(Qt.locale("fr_FR"), "ddd") : Ilot.pad(d.getHours()) + "h", X(at), T + h + 7)
            }

            // rythme regulier : 0 % au debut, 100 % a la remise a zero
            c.strokeStyle = Theme.alpha(Theme.ink, 0.35)
            c.lineWidth = 1.5
            c.setLineDash([2, 4])
            c.beginPath()
            c.moveTo(X(ch.start), Y(0))
            c.lineTo(X(ch.end), Y(100))
            c.stroke()

            // releves (le dernier = la valeur actuelle)
            const pts = (ch.hist || []).filter(p => p[0] >= ch.start && p[0] <= ch.now)
            const last = [Math.min(ch.now, ch.end), ch.lim.pct]
            if (!pts.length || pts[pts.length - 1][0] < last[0])
                pts.push(last)
            c.setLineDash([])
            c.strokeStyle = ch.tone
            c.lineWidth = 2.5
            c.lineJoin = "round"
            c.beginPath()
            pts.forEach((p, i) => i ? c.lineTo(X(p[0]), Y(p[1])) : c.moveTo(X(p[0]), Y(p[1])))
            c.stroke()

            // prevision : jusqu'a la remise a zero, ou jusqu'a la limite
            if (ch.proj) {
                c.setLineDash([6, 5])
                c.beginPath()
                c.moveTo(X(last[0]), Y(last[1]))
                if (ch.proj.hit)
                    c.lineTo(X(ch.proj.hit), Y(100))
                else
                    c.lineTo(X(ch.end), Y(ch.proj.pct))
                c.stroke()
            }

            // repere « maintenant »
            c.setLineDash([])
            c.strokeStyle = Theme.alpha(Theme.ink, 0.15)
            c.lineWidth = 1
            c.beginPath()
            c.moveTo(X(last[0]), T)
            c.lineTo(X(last[0]), T + h)
            c.stroke()
            c.fillStyle = ch.tone
            c.beginPath()
            c.arc(X(last[0]), Y(last[1]), 5, 0, Math.PI * 2)
            c.fill()
        }
    }
}
