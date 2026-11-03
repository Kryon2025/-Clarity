import QtQuick
import "../theme"
import "../glass"
import "Constants.js" as C

// 胶囊开关。glass 主题：轨道 = 玻璃 pill，滑块 = 独立圆形玻璃珠；
// solid / light 主题：平面轨道 + 实心圆钮，不渲染折射/噪点。
// checked 只读绑定（由 App 状态驱动），点击只发 clicked()，避免内部赋值破坏绑定。
Item {
    id: root
    property bool checked: false
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
    readonly property bool hovered: pointer.containsMouse
    property bool held: false

    signal clicked()

    implicitWidth: 50
    implicitHeight: 30

    // 纯色/浅色按下时轻微缩放
    scale: !root.useGlass && pointer.pressed && root.interactive ? 0.97 : 1.0
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    // ---------- 平面轨道（solid / light） ----------
    Rectangle {
        anchors.fill: parent
        visible: !root.useGlass
        radius: height / 2
        color: {
            if (root.checked) return AppTheme.accentSoft
            return root.hovered ? AppTheme.buttonBgAlt : AppTheme.chipBg
        }
        border.width: 1
        border.color: root.checked ? AppTheme.accentSoft : AppTheme.cardBorder
        Behavior on color { ColorAnimation { duration: 140 } }
    }

    // ---------- 玻璃轨道 ----------
    LiquidGlass {
        anchors.fill: parent
        visible: root.useGlass
        sourceItem: root.glassSource
        radius: height / 2
        depth: 0.7
        frost: 0.02
        aberration: 0.3
        highlight: root.hovered ? 0.9 : 0.6
        whiten: root.checked ? 0.06 : 0.02
        tintAlpha: root.checked ? 0.26 : 0.24
        tint: root.checked ? AppTheme.accentSoft : AppTheme.glassTint
        sheen: 0.4
        hover: root.held ? 0.3 : 0
    }

    // 玻璃轨道壳描边
    Rectangle {
        anchors.fill: parent
        visible: root.useGlass
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: root.checked ? "#59FFFFFF" : (root.hovered ? "#4DFFFFFF" : "#33FFFFFF")
        Behavior on border.color { ColorAnimation { duration: 160 } }
    }

    // ---------- 滑块 ----------
    Item {
        id: knobHolder
        width: 24
        height: 24
        y: (root.height - height) / 2
        x: root.checked ? root.width - width - 3 : 3
        Behavior on x {
            NumberAnimation { duration: 220; easing.type: Easing.OutBack }
        }

        LiquidGlass {
            anchors.fill: parent
            visible: root.useGlass
            sourceItem: root.glassSource
            radius: knobHolder.width / 2
            depth: 0.6
            frost: 0.02
            aberration: 0.28
            highlight: 1.45
            whiten: 0.18
            tintAlpha: 0.42
            tint: "#F3F7FF"
            sheen: 0.5
            hover: root.held ? 0.4 : 0
        }

        // 平面主题的圆钮：白底 + 细边，浅色主题里也能看清
        Rectangle {
            anchors.fill: parent
            visible: !root.useGlass
            radius: width / 2
            color: AppTheme.light ? "#FFFFFF" : "#F2FBFD"
            border.width: 1
            border.color: AppTheme.light ? AppTheme.cardBorderStrong : "#33FFFFFF"
        }

        // 玻璃珠的壳描边 + 一点内阴影，保证在深色轨道上也看得见
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: root.useGlass ? "#99FFFFFF" : "transparent"
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: (mouse) => root.held = true
        onReleased: root.held = false
        onCanceled: root.held = false
        onClicked: if (root.interactive) root.clicked()
    }
}
