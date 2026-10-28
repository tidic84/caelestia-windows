import QtQuick

// Carte de la colonne de droite de l'onglet PC : titre, bouton facultatif,
// contenu en colonne
Card {
    id: c
    property string title
    property string tool: ""
    property string toolTip: ""
    property bool toolBusy: false
    default property alias content: inner.data
    signal toolClicked()
    width: parent ? parent.width : 0
    height: inner.y + inner.height + 14
    Txt {
        x: 14
        y: 16
        text: c.title
        px: 11.5
        weight: Font.Medium
        color: Theme.inkVariant
    }
    IconBtn {
        visible: c.tool !== ""
        x: parent.width - width - 10
        y: 9
        small: true
        icon: c.tool
        tip: c.toolTip
        onClicked: c.toolClicked()
        RotationAnimator on rotation {
            running: c.toolBusy
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
            // finit le tour en cours : l'icone ne reste pas penchee
            alwaysRunToEnd: true
        }
    }
    Column {
        id: inner
        x: 14
        y: 38
        width: parent.width - 28
        spacing: 6
    }
}
