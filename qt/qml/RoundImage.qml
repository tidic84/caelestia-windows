import QtQuick

// Image aux coins arrondis (shader round.frag : ni calque ni masque).
// `cover` : remplit en rognant (object-fit: cover), sinon tout est montre.
Item {
    id: r
    property alias source: img.source
    property alias status: img.status
    property real radius: 0
    property bool cover: true
    // fondu a l'apparition (pochettes)
    property bool fade: false
    // taille de decodage (0 : celle de l'element)
    property real decode: 0
    // agrandissement dans le cadre (le cadre arrondi ne bouge pas)
    property real zoom: 1
    implicitWidth: img.implicitWidth
    implicitHeight: img.implicitHeight

    Image {
        id: img
        visible: false
        asynchronous: true
        smooth: true
        mipmap: true
        sourceSize.width: r.decode > 0 ? r.decode : Math.ceil(Math.max(r.width, r.height) * Screen.devicePixelRatio)
    }
    ShaderEffect {
        anchors.fill: parent
        readonly property bool ready: img.status === Image.Ready && img.source != ""
        visible: opacity > 0
        opacity: ready ? 1 : 0
        Behavior on opacity {
            enabled: r.fade
            NumberAnimation { duration: 400 }
        }
        property var source: img
        property size size: Qt.size(Math.max(1, width), Math.max(1, height))
        property size imgSize: Qt.size(Math.max(1, img.implicitWidth), Math.max(1, img.implicitHeight))
        property real radius: Math.min(r.radius, width / 2, height / 2)
        property real cover: r.cover ? 1 : 0
        property real zoom: r.zoom
        fragmentShader: "qrc:/shaders/round.frag.qsb"
    }
}
