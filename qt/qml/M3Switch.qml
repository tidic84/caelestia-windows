import QtQuick

// .switch (Material 3)
Btn {
    id: s
    property bool checked: false
    property bool disabled: false
    signal toggled(bool on)
    active: !disabled
    opacity: disabled ? 0.5 : 1
    width: 52
    height: 32
    radius: 16
    color: checked ? Theme.primary : Theme.surfaceHighest
    border.width: checked ? 0 : 2
    border.color: Theme.outline
    Behavior on color { ColorAnimation { duration: 250 } }
    onClicked: toggled(!checked)

    Rectangle {
        readonly property real d: s.checked ? 24 : 16
        width: d
        height: d
        radius: d / 2
        x: s.checked ? 24 : 8
        y: (s.height - d) / 2
        color: s.checked ? Theme.inkPrimary : Theme.outline
        Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.spring } }
        Behavior on color { ColorAnimation { duration: 250 } }
    }
}
