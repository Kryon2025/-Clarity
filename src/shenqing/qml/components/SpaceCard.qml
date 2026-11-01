import QtQuick
import QtQuick.Effects
import "../glass"
import "Constants.js" as C

// 空间卡片：super=true 时为海水蓝渐变的「主空间」大卡，否则为海玻璃卡
Item {
    id: root
    property string spaceName: ""
    property int minutes: 180
    property bool superCard: false
    property color accentColor: C.accent
    property Item glassSource: null

    signal editRequested()
    signal startRequested()

    implicitHeight: superCard ? 148 : 108

    // 点击卡片本体 → 编辑；内部「开始」按钮优先吃掉点击
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.editRequested()
    }

    Item {
        id: lift
        anchors.fill: parent
        scale: pointer.pressed ? 0.978 : 1.0
        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutBack }
        }
        transform: Translate {
            y: pointer.containsMouse ? -2 : 0
            Behavior on y {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }

        // ---- 底 ----
        // 普通空间卡：真·液态玻璃（有背景层时）
        LiquidGlass {
            anchors.fill: parent
            visible: !root.superCard && root.glassSource !== null
            sourceItem: root.glassSource
            radius: C.radiusCard
            depth: 1.0
            frost: 0.03
            aberration: 0.42
            highlight: 0.7
            whiten: 0.015
            tintAlpha: 0.16
            tint: C.glassTint
            sheen: 0.3
        }

        // 普通空间卡：轻微暗色 tint，保证文字对比度（无玻璃层时）
        Rectangle {
            anchors.fill: parent
            radius: C.radiusCard
            visible: !root.superCard && root.glassSource === null
            color: pointer.containsMouse ? "#28050A12" : "#22050A12"
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        Rectangle {
            id: surface
            anchors.fill: parent
            visible: root.superCard || root.glassSource === null
            radius: root.superCard ? C.radiusSuper : C.radiusCard
            gradient: root.superCard ? superGradient : lightGradient

            Gradient {
                id: superGradient
                GradientStop { position: 0.0; color: Qt.lighter(C.accentDeep, 1.1) }
                GradientStop { position: 0.55; color: C.accentDeep }
                GradientStop { position: 1.0; color: Qt.darker(C.accentDeep, 1.18) }
            }

            Gradient {
                id: lightGradient
                GradientStop {
                    position: 0.0
                    color: pointer.containsMouse ? "#12FFFFFF" : "#0BFFFFFF"
                }
                GradientStop { position: 0.52; color: "#06FFFFFF" }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.06)
                }
            }

            border.width: 1
            border.color: root.superCard
                          ? (pointer.containsMouse ? "#85FFFFFF" : "#6BFFFFFF")
                          : (pointer.containsMouse ? "#4DFFFFFF" : "#2EFFFFFF")
            Behavior on border.color {
                ColorAnimation { duration: 180 }
            }
        }

        // ---- 主空间卡：内部海水光晕装饰（避开圆角，避免方形裁切） ----
        Rectangle {
            id: superGlowA
            visible: false
            width: 240
            height: 240
            radius: 120
            x: root.width - 300
            y: -70
            color: "#4D9FC2FF"
        }
        MultiEffect {
            source: superGlowA
            anchors.fill: superGlowA
            visible: root.superCard
            blurEnabled: true
            blur: 1.0
            blurMax: 64
        }

        Rectangle {
            id: superGlowB
            visible: false
            width: 220
            height: 220
            radius: 110
            x: root.width * 0.36
            y: root.height - 120
            color: "#33223F9E"
        }
        MultiEffect {
            source: superGlowB
            anchors.fill: superGlowB
            visible: root.superCard
            blurEnabled: true
            blur: 1.0
            blurMax: 64
        }

        // ---- 顶部镜面高光（两端渐隐的 1.5px 亮线） ----
        Rectangle {
            x: surface.radius * 1.1
            y: 1.0
            width: Math.max(0, parent.width * 0.56)
            height: 1.1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#00FFFFFF" }
                GradientStop {
                    position: 0.18
                    color: root.superCard
                           ? (pointer.containsMouse ? "#8AFFFFFF" : "#6BFFFFFF")
                           : (pointer.containsMouse ? "#8AFFFFFF" : "#6BFFFFFF")
                }
                GradientStop { position: 0.7; color: "#1FFFFFFF" }
                GradientStop { position: 1.0; color: "#00FFFFFF" }
            }
        }

        // 斜向反光：液态玻璃的「光带」
        Item {
            anchors.fill: parent
            clip: true
            Rectangle {
                width: parent.width * 0.62
                height: root.superCard ? 44 : 30
                x: -parent.width * 0.08
                y: root.superCard ? -12 : -8
                rotation: -14
                opacity: root.superCard ? 0.42 : (pointer.containsMouse ? 0.5 : 0.34)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#00FFFFFF" }
                    GradientStop { position: 0.42; color: root.superCard ? "#26FFFFFF" : "#16FFFFFF" }
                    GradientStop { position: 1.0; color: "#00FFFFFF" }
                }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
        }

        // ---- 文案 ----
        Column {
            anchors.left: parent.left
            anchors.leftMargin: 26
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.superCard ? 10 : 8
            width: parent.width - 190

            Text {
                text: root.spaceName
                color: root.superCard ? "#FFFFFF" : C.textPrimary
                font.pixelSize: root.superCard ? 27 : 20
                font.weight: Font.Bold
                font.family: C.numFont
                elide: Text.ElideRight
                width: parent.width
            }

            Row {
                spacing: 6
                Text {
                    text: qsTr("%1 分钟").arg(root.minutes)
                    color: root.superCard ? "#DCE7FF" : C.textSecondary
                    font.pixelSize: root.superCard ? 15 : 14
                    font.family: C.numFont
                }
                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "chevron"
                    size: 13
                    color: root.superCard ? "#DCE7FF" : C.textSecondary
                }
            }
        }

        // ---- 开始按钮 ----
        GlassButton {
            anchors.right: parent.right
            anchors.rightMargin: root.superCard ? 26 : 22
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("开始")
            tone: "light"
            fontSize: root.superCard ? 16 : 15
            padH: root.superCard ? 26 : 22
            minHeight: root.superCard ? 44 : 40
            onClicked: root.startRequested()
        }
    }
}