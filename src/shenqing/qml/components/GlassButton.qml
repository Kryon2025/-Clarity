import QtQuick
import "../theme"
import "../glass"
import "Constants.js" as C

// 胶囊按钮 / 圆钮。
// glass 主题：液态玻璃 + 按住朝指针方向「捏软」形变，松手弹性回弹。
// solid / light 主题：平面实底 + 细描边，按下 0.98 缩放反馈，不渲染折射/噪点。
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

    // 只有玻璃主题且拿得到背景层时才走液态玻璃
    readonly property bool useGlass: AppTheme.glass && root.glassSource !== null
    readonly property bool flat: !root.useGlass

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

    // 纯色/浅色：按下简单缩放；玻璃：形变交给 LiquidGlass
    scale: root.flat && pointer.pressed && root.enabled ? 0.98 : 1.0
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    // ---------- 平面底（solid / light，或玻璃主题拿不到背景层时） ----------
    Rectangle {
        id: flatBase
        anchors.fill: parent
        visible: root.flat
        radius: height / 2
        color: {
            if (root.tone === "light")
                return root.hovered ? (AppTheme.light ? "#F7FCFD" : "#F2FBFD")
                                    : (AppTheme.light ? "#FFFFFF" : "#E9F4F6")
            if (root.tone === "accent")
                return root.hovered ? Qt.lighter(AppTheme.accentSoft, 1.08) : AppTheme.accentSoft
            if (root.tone === "danger")
                return root.hovered ? Qt.lighter(AppTheme.danger, 1.06) : AppTheme.danger
            if (root.tone === "tinted")
                return root.hovered ? AppTheme.buttonBgAlt : AppTheme.chipBg
            return root.hovered ? AppTheme.chipBg : "transparent"
        }
        border.width: root.selected || root.tone === "ghost" || root.tone === "tinted"
                      || (root.tone === "light" && AppTheme.light) ? 1 : 0
        border.color: root.selected ? AppTheme.accent : AppTheme.cardBorder
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    // ---------- 玻璃底 ----------
    LiquidGlass {
        anchors.fill: parent
        visible: root.useGlass
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
              : root.tone === "danger" ? "#3A0F16" : AppTheme.glassTint
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

    // 内部高光：上半部一抹柔光（海水玻璃的「湿亮」感，仅玻璃主题）
    Rectangle {
        anchors.fill: parent
        visible: root.useGlass
        radius: height / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#38FFFFFF" }
            GradientStop { position: 0.42; color: "#0AFFFFFF" }
            GradientStop { position: 0.42; color: "#00FFFFFF" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
    }

    // 选中态（两种主题都显示）
    Rectangle {
        anchors.fill: parent
        visible: root.selected
        radius: height / 2
        color: root.useGlass ? "#142ED3C6" : "transparent"
        border.width: 1
        border.color: root.useGlass ? "#A62ED3C6" : AppTheme.accent
        opacity: root.useGlass ? 1.0 : 0.9
    }

    // 1px 玻璃壳描边 + 顶部亮线（仅玻璃）
    Rectangle {
        anchors.fill: parent
        visible: root.useGlass
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: root.tone === "light" ? "#5CFFFFFF" : "#38FFFFFF"
    }

    Rectangle {
        visible: root.useGlass
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
        color: {
            if (AppTheme.glass)
                return root.tone === "light"
                       ? AppTheme.textOnLight
                       : (root.tone === "danger" ? "#FF98A6" : "#EEF3FF")
            if (root.tone === "light") return AppTheme.textOnLight
            if (root.tone === "accent") return "#FFFFFF"
            if (root.tone === "danger") return "#FFFFFF"
            return AppTheme.textPrimary
        }
        font.pixelSize: AppTheme.fs(root.fontSize)
        font.weight: Font.DemiBold
        font.family: AppTheme.fontFamily
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
