import QtQuick

// Champ de saisie sur une ligne (input) : fond arrondi, bordure primaire au focus
Rectangle {
    id: f
    property alias text: input.text
    property alias placeholder: ph.text
    property alias input: input
    property bool password: false
    property bool bad: false
    property real pad: 14
    property real fontSize: 13
    property color bg: Theme.surfaceHighest
    // bordure au focus (formulaires : comptes mail, Discord, playlists)
    property bool focusRing: false
    signal accepted()
    signal edited()
    signal focused()
    // touches, avant le champ (fleches, Entree du lanceur)
    signal keyPressed(var event)
    implicitHeight: 34
    radius: height / 2
    color: bg
    border.width: (focusRing && input.activeFocus) || bad ? 2 : 0
    border.color: bad ? Theme.error : Theme.primary

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: f.pad
        anchors.rightMargin: f.pad
        verticalAlignment: Text.AlignVCenter
        font.family: Theme.font
        font.pointSize: f.fontSize * 0.75
        color: Theme.ink
        selectionColor: Theme.alpha(Theme.primary, 0.4)
        selectedTextColor: Theme.ink
        clip: true
        echoMode: f.password ? TextInput.Password : TextInput.Normal
        selectByMouse: true
        onAccepted: f.accepted()
        onTextEdited: f.edited()
        onActiveFocusChanged: if (activeFocus) f.focused()
        Keys.onPressed: e => f.keyPressed(e)
    }
    Txt {
        anchors.fill: input
        id: ph
        font.pointSize: f.fontSize * 0.75
        color: Theme.inkVariant
        elide: Text.ElideRight
        visible: input.text === "" && input.preeditText === ""
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        acceptedButtons: Qt.NoButton
    }
}
