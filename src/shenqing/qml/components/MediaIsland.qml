import QtQuick
import "../theme"
import "../glass"
import "Constants.js" as C

// 灵动岛：右上角胶囊条。收起 = 小图标 + 一行标题 + 播放/暂停；
// 悬停展开 = 应用名 + 标题 + 艺术家 + 上一首/播放/下一首 + 细进度条。
// glass 主题用液态玻璃；solid / light 主题用实底卡片 + 细描边，不做折射。
// 没有媒体会话时：收起显示专注态文案，展开显示空间名与完成度，不显示播放控制。
Item {
    id: island

    property Item glassSource: null
    property bool hasMedia: false
    property string mediaTitle: ""
    property string mediaArtist: ""
    property string mediaAlbum: ""
    property string mediaApp: ""
    property bool mediaPlaying: false
    property real mediaPosition: 0
    property real mediaDuration: 0

    property string focusLine: qsTr("专注中")
    property string focusSub: ""

    property bool forceExpanded: false
    // 用 HoverHandler 判定悬停：指针落在展开态的按钮/子项上时依然算「在岛上」，
    // 不会出现「悬停展开 → 按钮盖住热区 → 判定离开 → 收起 → 再展开」的抽搐循环
    readonly property bool expanded: forceExpanded || islandHover.hovered || hoverLatch

    signal togglePlay()
    signal nextTrack()
    signal prevTrack()

    implicitWidth: expanded ? 360 : 276
    implicitHeight: expanded ? 160 : 52
    width: implicitWidth
    height: implicitHeight

    readonly property bool useGlass: AppTheme.glass && island.glassSource !== null

    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    // 平面底（solid / light）
    Rectangle {
        anchors.fill: parent
        visible: !island.useGlass
        radius: island.expanded ? 26 : height / 2
        color: AppTheme.cardBg
        border.width: 1
        border.color: AppTheme.cardBorder
        Behavior on radius { NumberAnimation { duration: 200 } }
    }

    LiquidGlass {
        anchors.fill: parent
        visible: island.useGlass
        sourceItem: island.glassSource
        radius: island.expanded ? 26 : island.height / 2
        depth: 1.0
        frost: 0.03
        aberration: 0.5
        highlight: 1.15
        whiten: 0.05
        tintAlpha: 0.24
        tint: AppTheme.glassTint
        sheen: 0.5
        Behavior on radius { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        anchors.fill: parent
        visible: island.useGlass
        radius: island.expanded ? 26 : height / 2
        color: "transparent"
        border.width: 1
        border.color: "#4DFFFFFF"
        Behavior on radius { NumberAnimation { duration: 200 } }
    }

    // 悬停判定用 HoverHandler：指针落在展开态的按钮上时依然算「在岛上」
    HoverHandler {
        id: islandHover
        onHoveredChanged: {
            if (hovered) {
                hoverLatch = true
                collapseTimer.stop()
            } else {
                collapseTimer.restart()
            }
        }
    }

    // 指针离开后延迟 260ms 再收起，避免边缘抖动导致反复展开/收起
    property bool hoverLatch: false
    Timer {
        id: collapseTimer
        interval: 260
        repeat: false
        onTriggered: if (!islandHover.hovered) hoverLatch = false
    }

    // ---------- 收起态 ----------
    Item {
        anchors.fill: parent
        opacity: island.expanded ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 13
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Rectangle {
                width: 30
                height: 30
                radius: 10
                anchors.verticalCenter: parent.verticalCenter
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#7FE7DA" }
                    GradientStop { position: 1.0; color: "#1F6FD0" }
                }
                Glyph {
                    anchors.centerIn: parent
                    kind: island.hasMedia ? "wave" : "ripple"
                    size: 16
                    color: "#04222B"
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 30 - 10 - (island.hasMedia ? 44 : 0)
                text: island.hasMedia ? island.mediaTitle : island.focusLine
                color: AppTheme.textPrimary
                font.pixelSize: 13
                font.family: C.numFont
                elide: Text.ElideRight
            }

            MiniGlassButton {
                anchors.verticalCenter: parent.verticalCenter
                size: 30
                glyph: island.mediaPlaying ? "pause" : "play"
                visible: island.hasMedia
                onClicked: island.togglePlay()
            }
        }
    }

    // ---------- 展开态 ----------
    Item {
        anchors.fill: parent
        opacity: island.expanded ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 6

            // 应用 / 专辑行
            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: 22
                    height: 22
                    radius: 7
                    anchors.verticalCenter: parent.verticalCenter
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#7FE7DA" }
                        GradientStop { position: 1.0; color: "#1F6FD0" }
                    }
                    Glyph {
                        anchors.centerIn: parent
                        kind: island.hasMedia ? "wave" : "ripple"
                        size: 12
                        color: "#04222B"
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 30
                    text: island.hasMedia
                          ? (island.mediaApp !== "" ? island.mediaApp
                                                    : (island.mediaAlbum !== "" ? island.mediaAlbum : qsTr("正在播放")))
                          : (island.focusSub !== "" ? island.focusSub : island.focusLine)
                    color: AppTheme.textTertiary
                    font.pixelSize: 11
                    font.family: C.numFont
                    elide: Text.ElideRight
                }
            }

            Text {
                width: parent.width
                text: island.hasMedia ? island.mediaTitle : island.focusLine
                color: AppTheme.textPrimary
                font.pixelSize: 16
                font.weight: Font.DemiBold
                font.family: C.numFont
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: island.hasMedia
                      ? (island.mediaArtist !== "" ? island.mediaArtist
                                                   : (island.mediaAlbum !== "" ? island.mediaAlbum : ""))
                      : ""
                visible: text !== ""
                color: AppTheme.textSecondary
                font.pixelSize: 12
                font.family: C.numFont
                elide: Text.ElideRight
            }

            // 进度条（有进度才显示）
            Item {
                width: parent.width
                height: 3
                visible: island.hasMedia && island.mediaDuration > 0

                Rectangle {
                    anchors.fill: parent
                    radius: 2
                    color: island.useGlass ? "#26FFFFFF" : AppTheme.divider
                }
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, island.mediaPosition / Math.max(1, island.mediaDuration)))
                    height: parent.height
                    radius: 2
                    color: AppTheme.accent
                }
            }

            // 控制键（仅媒体会话）
            Row {
                spacing: 12
                visible: island.hasMedia

                MiniGlassButton {
                    size: 34
                    glyph: "chevronLeft"
                    onClicked: island.prevTrack()
                }
                MiniGlassButton {
                    size: 38
                    glyph: island.mediaPlaying ? "pause" : "play"
                    onClicked: island.togglePlay()
                }
                MiniGlassButton {
                    size: 34
                    glyph: "chevron"
                    onClicked: island.nextTrack()
                }
            }
        }
    }
}
