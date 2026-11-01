import QtQuick
import "../glass"
import "Constants.js" as C

// 小号圆形玻璃按钮（灵动岛控制键、面板快捷键）：无 hover 动效，按住形变
Item {
    id: root
    property string glyph: "play"
    property real size: 34
    property Item glassSourceOverride: null

    readonly property Item glassSource: {
        if (glassSourceOverride !== null) return glassSourceOverride
        var p = root.parent
        var guard = 0
        while (p && guard < 64) {
            if (p.glassSource !== undefined && p.glassSource !== null) return p.glassSource
            p = p.parent
            guard++
        }
        return null
    }

    property bool held: false
    property point pressPoint: Qt.point(0.5, 0.5)
    signal clicked()

    width: size
    height: size

    LiquidGlass {
        anchors.fill: parent
        visible: root.glassSource !== null
        sourceItem: root.glassSource
        radius: root.size / 2
        depth: 1.15
        frost: 0.02
        aberration: 0.55
        highlight: 1.45
        whiten: 0.05
        tintAlpha: 0.14
        tint: C.glassTint
        sheen: 0.5
        pointer: root.pressPoint
        pull: root.held ? 1 : 0
        Behavior on pull {
            NumberAnimation {
                duration: root.held ? 90 : 420
                easing.type: root.held ? Easing.OutCubic : Easing.OutElastic
                easing.amplitude: 0.9
                easing.period: 0.5
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.glassSource === null
        radius: width / 2
        color: "#1FFFFFFF"
        border.width: 1
        border.color: "#4DFFFFFF"
    }

    Rectangle {
        anchors.fill: parent
        visible: root.glassSource !== null
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: "#45FFFFFF"
    }

    Glyph {
        anchors.centerIn: parent
        kind: root.glyph
        size: Math.round(root.size * 0.44)
        color: "#EAF8FB"
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (mouse) => {
            root.held = true
            root.pressPoint = Qt.point(
                Math.max(0, Math.min(1, mouse.x / Math.max(1, root.width))),
                Math.max(0, Math.min(1, mouse.y / Math.max(1, root.height))))
        }
        onReleased: root.held = false
        onCanceled: root.held = false
        onPositionChanged: (mouse) => {
            if (pointer.pressed) {
                root.pressPoint = Qt.point(
                    Math.max(0, Math.min(1, mouse.x / Math.max(1, root.width))),
                    Math.max(0, Math.min(1, mouse.y / Math.max(1, root.height))))
            }
        }
        onClicked: root.clicked()
    }
}
