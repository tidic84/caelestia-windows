import QtQuick

// Zone de texte sur plusieurs lignes (textarea), avec defilement
Rectangle {
    id: a
    property alias text: edit.text
    property alias placeholder: ph.text
    property alias edit: edit
    property real fontSize: 13
    property real padX: 10
    property real padY: 8
    signal edited()
    signal focused()
    // touches, avant la zone de texte (Entree pour envoyer...)
    signal keyPressed(var event)
    radius: 14
    color: Theme.surfaceHigh
    border.width: 2
    border.color: edit.activeFocus ? Theme.primary : "transparent"
    Behavior on border.color { ColorAnimation { duration: 200 } }

    Flickable {
        id: fl
        anchors.fill: parent
        anchors.leftMargin: a.padX
        anchors.rightMargin: a.padX
        anchors.topMargin: a.padY
        anchors.bottomMargin: a.padY
        contentHeight: edit.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        function ensureVisible(r) {
            if (contentY >= r.y)
                contentY = r.y
            else if (contentY + height <= r.y + r.height)
                contentY = r.y + r.height - height
        }
        TextEdit {
            id: edit
            width: fl.width
            wrapMode: TextEdit.Wrap
            font.family: Theme.font
            font.pointSize: a.fontSize * 0.75
            color: Theme.ink
            selectionColor: Theme.alpha(Theme.primary, 0.4)
            selectedTextColor: Theme.ink
            selectByMouse: true
            onCursorRectangleChanged: fl.ensureVisible(cursorRectangle)
            onTextChanged: if (activeFocus) a.edited()
            onActiveFocusChanged: if (activeFocus) a.focused()
            Keys.onPressed: e => a.keyPressed(e)
        }
        Txt {
            id: ph
            width: fl.width
            wrapMode: Text.Wrap
            font.pointSize: a.fontSize * 0.75
            color: Theme.inkVariant
            visible: edit.text === ""
        }
    }
    Scroller { flick: fl }
}
