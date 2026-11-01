import QtQuick
import "../glass"
import "Constants.js" as C

// 液态玻璃胶囊按钮 / 圆钮。
// 交互：没有任何补间动画；按住时玻璃朝指针方向「捏软」形变（pointer + pull），松手弹性回弹；
// hover 只做瞬时提亮。
Item {
    id: root
    property string text: ""
    property string tone: "light"      // light | ghost | accent | danger | tinted
    property int fontSize: 14
    property real padH: 20
    property real minHeight: 38
    property bool selected: false

    // 显式指定采样源（一般不用传，自动沿父链解析）
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

    // 按住形变：pointer = 控件内归一化坐标（0..1），pull = 0 原形 / 1 按住
    property bool held: false
    property point pressPoint: Qt.point(0.5, 0.5)
    function trackPointer(mx, my) {
        root.pressPoint = Qt.point(
            Math.max(0, Math.min(1, mx / Math.max(1, root.width))),
            Math.max(0, Math.min(1, my / Math.max(1, root.height))))
    }

    readonly property bool hovered: pointer.containsMouse

    signal clicked()

    implicitWidth: Math.max(minHeight * 2.1, label.implicitWidth + padH * 2)
    implicitHeight: minHeight

    width: implicitWidth
    height: implicitHeight

    opacity: root.enabled ? 1.0 : 0.45

    // ---------- 玻璃底 ----------
    LiquidGlass {
        anchors.fill: parent
        visible: root.glassSource !== null
        sourceItem: root.glassSource
        radius: root.height / 2
        depth: root.tone === "light" ? 1.3 : 1.15
        frost: 0.02
        aberration: root.tone === "light" ? 0.7 : 0.55
        highlight: root.tone === "light" ? 1.6 : 1.35
        whiten: root.tone === "light" ? 0.04
                : root.tone === "accent" ? 0.05 : 0.04
        tintAlpha: root.tone === "light" ? (root.selected ? 0.30 : 0.14)
                   : root.tone === "accent" ? 0.42
                   : root.tone === "danger" ? 0.42 : 0.12
        tint: root.tone === "light" ? "#E2F8F6"
              : root.tone === "accent" ? "#1F6FD0"
              : root.tone === "danger" ? "#3A0F16" : C.glassTint
        sheen: 0.5
        pointer: root.pressPoint
        pull: root.held ? 1 : 0
        Behavior on pull {
            NumberAnimation {
                duration: root.held ? 90 : 460
                easing.type: root.held ? Easing.OutCubic : Easing.OutElastic
                easing.amplitude: 0.9
                easing.period: 0.5
            }
        }
    }

    // ---------- 降级底（拿不到背景层时） ----------
    Rectangle {
        anchors.fill: parent
        visible: root.glassSource === null
        radius: height / 2
        color: {
            if (root.tone === "light") return "#EEF2FC"
            if (root.tone === "accent") return C.accent
            if (root.tone === "danger") return "#14FF6B7A"
            if (root.tone === "tinted") return "#18FFFFFF"
            return "#12FFFFFF"
        }
        border.width: (root.tone === "ghost" || root.tone === "tinted" || root.selected) ? 1 : 0
        border.color: root.selected ? "#66FFFFFF" : "#33FFFFFF"
    }

    // 内部高光：上半部一抹柔光（海水玻璃的「湿亮」感）
    Rectangle {
        anchors.fill: parent
        visible: root.glassSource !== null
        radius: height / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#38FFFFFF" }
            GradientStop { position: 0.42; color: "#0AFFFFFF" }
            GradientStop { position: 0.42; color: "#00FFFFFF" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
    }

    // 选中态：海玻璃青边（主题/语言这类单选按钮用）
    Rectangle {
        anchors.fill: parent
        visible: root.selected
        radius: height / 2
        color: "#142ED3C6"
        border.width: 1
        border.color: "#A62ED3C6"
    }

    // 1px 玻璃壳描边 + 顶部亮线
    Rectangle {
        anchors.fill: parent
        visible: root.glassSource !== null
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: root.tone === "light" ? "#5CFFFFFF" : "#38FFFFFF"
    }

    Rectangle {
        visible: root.glassSource !== null
        x: root.height * 0.42
        y: 1
        width: Math.max(0, root.width - root.height * 0.84)
        height: 1.2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#00FFFFFF" }
            GradientStop { position: 0.3; color: "#CCFFFFFF" }
            GradientStop { position: 0.8; color: "#4DFFFFFF" }
            GradientStop { position: 1.0; color: "#00FFFFFF" }
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.tone === "light"
               ? C.textOnLight
               : (root.tone === "danger" ? "#FF98A6" : "#EEF3FF")
        font.pixelSize: root.fontSize
        font.weight: Font.DemiBold
        font.family: C.numFont
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: (mouse) => {
            root.held = true
            root.trackPointer(mouse.x, mouse.y)
        }
        onReleased: root.held = false
        onCanceled: root.held = false
        onPositionChanged: (mouse) => {
            if (pointer.pressed || pointer.containsMouse)
                root.trackPointer(mouse.x, mouse.y)
        }
        onClicked: if (root.enabled) root.clicked()
    }
}