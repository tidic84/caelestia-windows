import QtQuick

// Animation « Claude travaille » de la pilule (shader claude.frag, maquette
// docs/design/claude-code). Cadencee par l'horloge d'ambiance (25 i/s, en
// pause sans activite) : rien ne tourne quand aucune tache n'est en cours.
ShaderEffect {
    implicitWidth: 20
    implicitHeight: 20
    property real t: (Ilot.amb % 5000) / 1000
    property size size: Qt.size(Math.max(1, width), Math.max(1, height))
    property real px: 1 / Math.max(1, Screen.devicePixelRatio)
    fragmentShader: "qrc:/shaders/claude.frag.qsb"
}
