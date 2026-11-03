import QtQuick
import "../theme"
import "../glass"
import "Constants.js" as C

// 滑块。glass 主题：玻璃轨道 + 玻璃旋钮（直径 22），拖动时 hover 提亮；
// solid / light 主题：平面轨道 + 实心圆钮，不渲染折射/噪点。
Item {
    id: root
    property real from: 15
    property real to: 240
    property real step: 5
    property real value: 45
    property bool interactive: true

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

    readonly property bool useGlass: AppTheme.glass && root.glassSource !== null
    property bool hovered: false
    property bool held: false

    implicitWidth: 260
    implicitHeight: 30

    signal moved(real value)

    readonly property real ratio: {
        var span = root.to - root.from
        if (span <= 0) return 0
        return Math.max(0, Math.min(1, (root.value - root.from) / span))
    }

    function valueAt(px) {
        var w = Math.max(1, track.width)
        var r = Math.max(0, Math.min(1, px / w))
        var raw = root.from + r * (root.to - root.from)
        var snapped = Math.round((raw - root.from) / root.step) * root.step + root.from
        return Math.max(root.from, Math.min(root.to, snapped))
    }

    // ---------- 轨道 ----------
    Item {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        x: 1
        width: parent.width - 2
        height: 8

        // 平面轨道
        Rectangle {
            anchors.fill: parent
            visible: !root.useGlass
            radius: height / 2
            color: AppTheme.chipBg
            border.width: 1
            border.color: AppTheme.cardBorder
        }

        LiquidGlass {
            anchors.fill: parent
            visible: root.useGlass
            sourceItem: root.glassSource
            radius: height / 2
            depth: 0.45
            frost: 0.02
            aberration: 0.18
            highlight: 0.55
            whiten: 0.02
            tintAlpha: 0.2
            tint: AppTheme.glassTint
            sheen: 0.35
            hover: dragArea.pressed ? 0.6 : 0
        }

        // 已选进度
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: 0
            width: Math.max(4, root.ratio * track.width)
            height: parent.height
            radius: height / 2
            color: AppTheme.accentSoft
            opacity: root.useGlass ? 0.55 : 1.0
        }
    }

    // ---------- 旋钮 ----------
    Item {
        id: knob
        width: 22
        height: 22
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(track.width - width, root.ratio * track.width - width / 2))

        LiquidGlass {
            anchors.fill: parent
            visible: root.useGlass
            sourceItem: root.glassSource
            radius: knob.width / 2
            depth: 0.7
            frost: 0.02
            aberration: 0.3
            highlight: 1.45
            whiten: 0.18
            tintAlpha: 0.42
            tint: "#F3F7FF"
            sheen: 0.5
            hover: dragArea.pressed ? 0.6 : 0
        }

        // 平面主题的圆钮
        Rectangle {
            anchors.fill: parent
            visible: !root.useGlass
            radius: width / 2
            color: AppTheme.light ? "#FFFFFF" : "#F2FBFD"
            border.width: 1
            border.color: AppTheme.light ? AppTheme.cardBorderStrong : "#4DFFFFFF"
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: root.useGlass ? "#99FFFFFF" : "transparent"
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered = true
        onExited: root.hovered = false
        onPressed: (mouse) => root.moved(root.valueAt(mouse.x - track.x))
        onPositionChanged: (mouse) => {
            if (pressed) root.moved(root.valueAt(mouse.x - track.x))
        }
    }
}
