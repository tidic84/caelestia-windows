import QtQuick

// Info-bulle (attribut title des boutons), dans sa propre petite fenetre
// (TipWindow) : elle n'est pas coupee par les zones cliquables de l'ilot.
Item {
    id: tip
    property string text: ""
    property bool shown: false
    anchors.fill: parent

    Timer {
        interval: 700
        running: tip.shown && tip.text !== ""
        onTriggered: {
            const p = tip.mapToGlobal(tip.width / 2, tip.height)
            Ilot.tip = { text: tip.text, x: p.x, y: p.y + 6, owner: tip }
        }
    }
    function hide() {
        if (Ilot.tip && Ilot.tip.owner === tip)
            Ilot.tip = null
    }
    onShownChanged: if (!shown) hide()
    onTextChanged: if (Ilot.tip && Ilot.tip.owner === tip) Ilot.tip = Object.assign({}, Ilot.tip, { text: text })
    Component.onDestruction: hide()
}
