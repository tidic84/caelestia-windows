import QtQuick

// Sphere d'Akira (shader akira.frag). L'eclat, les ondes et la vitesse
// suivent l'etat d'Akira (Watch.akState). Cadencee par l'horloge
// d'ambiance (Ilot.amb) : figee quand personne ne regarde.
ShaderEffect {
    id: orb
    implicitWidth: 22
    implicitHeight: 22
    // etat a afficher (par defaut celui d'Akira ; `state` est deja pris par Item)
    property string mood: Watch.akState
    property real t: (Ilot.amb % 600000) / 1000
    property size size: Qt.size(Math.max(1, width), Math.max(1, height))
    property real energy: ({ veille: 0.35, ecoute: 0.7, reflexion: 0.85, parole: 1 })[mood] || 0.35
    property real wave: mood === "parole" ? 1 : 0
    property real spin: mood === "reflexion" ? 3 : mood === "veille" ? 0.6 : 1
    Behavior on energy { NumberAnimation { duration: 500 } }
    Behavior on wave { NumberAnimation { duration: 600 } }
    Behavior on spin { NumberAnimation { duration: 800 } }
    blending: true
    fragmentShader: "qrc:/shaders/akira.frag.qsb"
}
