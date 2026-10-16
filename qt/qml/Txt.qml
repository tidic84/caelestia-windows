import QtQuick

// Texte en Rubik 13 px (corps de l'interface)
Text {
    // chiffres a chasse fixe (font-variant-numeric: tabular-nums)
    property bool tnum: false
    property int weight: Font.Normal
    font.family: Theme.font
    // taille en pixels CSS (fractionnaire : 11.5, 12.5...) ; 1 pt = 4/3 px
    property real px: 13
    font.pointSize: px * 0.75
    font.weight: weight
    font.features: tnum ? { "tnum": 1 } : {}
    color: Theme.ink
    verticalAlignment: Text.AlignVCenter
}
