import QtQuick
import QtQuick.Window

// 液态玻璃面板：采样「背后那一层」（Backdrop / 页面底色），做圆角透镜折射 + 色散 + 高光。
//
// 用法：
//   LiquidGlass {
//       anchors.fill: parent
//       sourceItem: backdropItem     // 必须是被采样层（通常在卡片外层，避免递归）
//       radius: 22
//       depth: 0.9                   // 折射强度，越大边缘弯折越明显
//       frost: 0.08                  // 磨砂，默认几乎关闭
//   }
//
// 注意：sourceItem 必须是 root 的「兄弟/祖先背景」而不是包含 LiquidGlass 的容器本身，
// 否则会出现递归采样（Qt 会打印 recursive 警告并且画面异常）。
Item {
    id: root

    property Item sourceItem: null
    // 采样外扩：让边缘折射能取到卡片外侧的内容（太小会出暗色楔形）
    property real pad: Math.max(12, Math.min(32, Math.round(Math.min(width, height) * 0.35)))
    property real radius: 22
    property real depth: 0.9
    property real frost: 0.08
    property real aberration: 0.35
    property real highlight: 1.05
    property real whiten: 0.03
    property real tintAlpha: 0.12
    property color tint: "#0B1220"
    property real sheen: 0.7
    // 悬停/按下强度（0..1）：由使用方在 onHoveredChanged / onPressedChanged 里驱动
    property real hover: 0
    // 流动高光位置（-1 = 关闭，0..1 = 位置）
    property real sweep: -1
    // 液态形变：pointer 为指针在控件内的归一化坐标，pull 为按住强度（0 = 原形）
    property point pointer: Qt.point(0.5, 0.5)
    property real pull: 0
    property bool live: false

    ShaderEffectSource {
        id: texture
        // 只作为纹理提供者，绝不能画进场景（否则会把裁剪出的矩形背景画在卡片上，表现为黑框/暗楔形）
        visible: false
        anchors.fill: parent
        sourceItem: root.sourceItem
        live: root.live
        hideSource: false
        recursive: false
        sourceRect: {
            if (!root.sourceItem)
                return Qt.rect(0, 0, 1, 1)
            var p = root.mapToItem(root.sourceItem, 0, 0)
            return Qt.rect(p.x - root.pad, p.y - root.pad,
                            root.width + root.pad * 2, root.height + root.pad * 2)
        }
    }

    ShaderEffect {
        anchors.fill: parent
        property variant source: texture
        // 属性顺序必须与 shader 里的 uniform buf 一致
        property vector2d size: Qt.vector2d(root.width, root.height)
        property real dpr: Screen.devicePixelRatio
        property real pad: root.pad
        property real radius: root.radius
        property real depth: root.depth
        property real frost: root.frost
        property real aberration: root.aberration
        property real highlight: root.highlight
        property real whiten: root.whiten
        property real tintAlpha: root.tintAlpha
        property real sheen: root.sheen
        property real hover: root.hover
        property real sweep: root.sweep
        property vector2d pointer: Qt.vector2d(root.pointer.x, root.pointer.y)
        property real pull: root.pull
        property color tintColor: root.tint

        vertexShader: "shaders/liquid_glass.vert.qsb"
        fragmentShader: "shaders/liquid_glass.frag.qsb"
        supportsAtlasTextures: false
    }
}
