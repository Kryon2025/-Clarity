import QtQuick
import "../glass"
import "Constants.js" as C

// 液态玻璃卡片：极轻白雾 + 轻微暗色 tint 保可读性 + 1px 高对比描边 + 顶部镜面高光 + 斜向反光
// hover 上浮 2px、点击 0.975 缩放（OutBack）
Item {
    id: root
    default property alias content: contentHost.data

    property real radius: C.radiusCard
    property bool interactive: true
    property bool hoverLiftEnabled: true
    property bool selected: false
    property real hoverLift: 2
    property color accentTint: "#00000000"
    // 传入「被采样的背景层」（通常是窗口 Backdrop）。传了就启用真·液态玻璃折射；
    // 不传则退回「暗色 tint + 极轻白雾 + 高光描边」的近似画法。
    property Item glassSource: null
    property real glassDepth: 0.95
    property real glassFrost: 0.03
    property real glassTintAlpha: 0.16
    property alias hovered: pointer.containsMouse
    property alias pressed: pointer.pressed

    implicitWidth: 400
    implicitHeight: 110

    signal clicked()

    // 点击热区放在最底层：卡片内部的按钮会自然优先吃掉点击
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.interactive) root.clicked()
    }

    Item {
        id: lift
        anchors.fill: parent
        scale: pointer.pressed && root.interactive ? 0.975 : 1.0
        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutBack }
        }
        transform: Translate {
            y: (root.interactive && root.hoverLiftEnabled && pointer.containsMouse) ? -root.hoverLift : 0
            Behavior on y {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }

        // 0) 真·液态玻璃：采样背景层做透镜折射 + 色散 + 边缘高光
        LiquidGlass {
            anchors.fill: parent
            visible: root.glassSource !== null
            sourceItem: root.glassSource
            radius: root.radius
            depth: root.glassDepth
            frost: root.glassFrost
            aberration: 0.4
            highlight: root.selected ? 1.0 : 0.7
            whiten: 0.015
            tintAlpha: root.selected ? 0.24 : root.glassTintAlpha
            tint: C.glassTint
            sheen: 0.3
        }

        // 1) 退回方案：轻微暗色 tint，保证文字对比度
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            visible: root.glassSource === null
            color: root.selected ? "#2A050A14" : (pointer.containsMouse ? "#26050A12" : "#22050A12")
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        // 2) 退回方案：极轻的垂直渐变（顶部略亮）
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            visible: root.glassSource === null
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#0FFFFFFF" }
                GradientStop { position: 0.45; color: "#07FFFFFF" }
                GradientStop {
                    position: 1.0
                    color: root.accentTint.a > 0.001 ? root.accentTint : "#04FFFFFF"
                }
            }
        }

        // 3) 边缘 1px：高对比，hover 更亮
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "transparent"
            border.width: 1
            border.color: root.selected
                          ? "#66FFFFFF"
                          : (pointer.containsMouse ? "#4DFFFFFF" : "#2EFFFFFF")
            Behavior on border.color { ColorAnimation { duration: 180 } }
        }

        // 4) 顶部镜面高光：一条两端渐隐的亮线（液态玻璃的关键特征）
        Rectangle {
            x: root.radius * 1.1
            y: 1.0
            width: Math.max(0, parent.width * 0.56)
            height: 1.1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#00FFFFFF" }
                GradientStop { position: 0.18; color: pointer.containsMouse ? "#8AFFFFFF" : "#6BFFFFFF" }
                GradientStop { position: 0.7; color: "#1FFFFFFF" }
                GradientStop { position: 1.0; color: "#00FFFFFF" }
            }
        }

        // 5) 左上斜向反光（很淡的一道）
        Item {
            anchors.fill: parent
            clip: true
            Rectangle {
                width: parent.width * 0.55
                height: 26
                x: -parent.width * 0.06
                y: -6
                rotation: -13
                opacity: pointer.containsMouse ? 0.5 : 0.36
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00FFFFFF" }
                    GradientStop { position: 0.45; color: "#14FFFFFF" }
                    GradientStop { position: 1.0; color: "#00FFFFFF" }
                }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
        }

        // 6) 底部内侧微暗线：做出玻璃厚度感
        Rectangle {
            x: root.radius * 0.7
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 0.8
            width: Math.max(0, parent.width - root.radius * 1.4)
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 0.5; color: "#33000000" }
                GradientStop { position: 1.0; color: "#00000000" }
            }
        }

        Item {
            id: contentHost
            anchors.fill: parent
        }
    }
}