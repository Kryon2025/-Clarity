import QtQuick
import QtQuick.Window
import QtQuick.Effects
import "../glass"
import "Constants.js" as C

// 专注全屏遮罩（所有会话都进入；App.locked 由 Python 控制）
// 左侧：大号倒计时 + 空间名 + 水波进度；右上：灵动岛；右下：轻度/中度允许暂停/结束
Window {
    id: overlay
    objectName: "LockOverlay"
    title: qsTr("深清 · 专注中")
    visibility: App.locked ? Window.FullScreen : Window.Hidden
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: C.bgTop

    onClosing: function (close) {
        if (App.locked) close.accepted = false
    }

    // 通知 Python：遮罩打开/关闭（Python 侧借此隐藏任务栏、装低级键盘钩子）
    onVisibleChanged: {
        if (visible) {
            if (typeof App.overlayOpened === "function") App.overlayOpened()
        } else {
            if (typeof App.overlayClosed === "function") App.overlayClosed()
        }
    }

    readonly property bool hasMedia: App.mediaHasSession === true
    readonly property string mediaTitleText: App.mediaTitle !== undefined ? String(App.mediaTitle) : ""
    readonly property string mediaArtistText: App.mediaArtist !== undefined ? String(App.mediaArtist) : ""
    readonly property string mediaAlbumText: App.mediaAlbum !== undefined ? String(App.mediaAlbum) : ""
    readonly property string mediaAppText: App.mediaApp !== undefined ? String(App.mediaApp) : ""
    readonly property bool mediaPlayingValue: App.mediaPlaying === true
    readonly property real mediaPositionValue: App.mediaPosition !== undefined ? Number(App.mediaPosition) : 0
    readonly property real mediaDurationValue: App.mediaDuration !== undefined ? Number(App.mediaDuration) : 0

    readonly property real progressValue: {
        var p = Number(App.progress)
        if (!isFinite(p)) return 0
        return Math.max(0, Math.min(1, p))
    }
    readonly property int percentValue: Math.round(overlay.progressValue * 100)
    readonly property int remainingMinutesValue: {
        var s = Number(App.remainingSeconds)
        if (!isFinite(s)) s = 0
        return Math.max(0, Math.ceil(s / 60))
    }

    // 重度（主空间）不给暂停/结束按钮
    readonly property bool heavyLock: {
        var sid = String(App.activeSpaceId || "")
        var list = App.spaces || []
        for (var i = 0; i < list.length; i++) {
            if (String(list[i].id) === sid)
                return list[i].super === true
        }
        return false
    }

    // ================= 海水背景 + 极慢水光 =================
    Item {
        id: water
        anchors.fill: parent
        clip: true

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: C.bgTop }
                GradientStop { position: 0.55; color: "#06202C" }
                GradientStop { position: 1.0; color: C.bgBottom }
            }
        }

        Rectangle {
            id: glowA
            visible: false
            width: Math.max(680, overlay.width * 0.72)
            height: width
            radius: width / 2
            x: 0
            y: 0
            color: C.waterBlue
        }
        MultiEffect {
            source: glowA
            width: glowA.width
            height: glowA.height
            blurEnabled: true
            blur: 1.0
            blurMax: 128
            opacity: 0.20
            SequentialAnimation on x {
                loops: Animation.Infinite
                NumberAnimation { from: -overlay.width * 0.34; to: -overlay.width * 0.06; duration: 64000; easing.type: Easing.InOutSine }
                NumberAnimation { from: -overlay.width * 0.06; to: -overlay.width * 0.34; duration: 64000; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { from: -overlay.height * 0.30; to: -overlay.height * 0.10; duration: 52000; easing.type: Easing.InOutSine }
                NumberAnimation { from: -overlay.height * 0.10; to: -overlay.height * 0.30; duration: 52000; easing.type: Easing.InOutSine }
            }
        }

        Rectangle {
            id: glowB
            visible: false
            width: Math.max(560, overlay.width * 0.58)
            height: width
            radius: width / 2
            x: 0
            y: 0
            color: C.waterTeal
        }
        MultiEffect {
            source: glowB
            width: glowB.width
            height: glowB.height
            blurEnabled: true
            blur: 1.0
            blurMax: 128
            opacity: 0.16
            SequentialAnimation on x {
                loops: Animation.Infinite
                NumberAnimation { from: overlay.width * 0.42; to: overlay.width * 0.58; duration: 72000; easing.type: Easing.InOutSine }
                NumberAnimation { from: overlay.width * 0.58; to: overlay.width * 0.42; duration: 72000; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { from: overlay.height * 0.34; to: overlay.height * 0.56; duration: 58000; easing.type: Easing.InOutSine }
                NumberAnimation { from: overlay.height * 0.56; to: overlay.height * 0.34; duration: 58000; easing.type: Easing.InOutSine }
            }
        }

        Rectangle {
            id: glowC
            visible: false
            width: Math.max(420, overlay.width * 0.4)
            height: width
            radius: width / 2
            x: 0
            y: 0
            color: C.waterSand
        }
        MultiEffect {
            source: glowC
            width: glowC.width
            height: glowC.height
            blurEnabled: true
            blur: 1.0
            blurMax: 128
            opacity: 0.10
            SequentialAnimation on x {
                loops: Animation.Infinite
                NumberAnimation { from: overlay.width * 0.10; to: overlay.width * 0.26; duration: 80000; easing.type: Easing.InOutSine }
                NumberAnimation { from: overlay.width * 0.26; to: overlay.width * 0.10; duration: 80000; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { from: overlay.height * 0.62; to: overlay.height * 0.72; duration: 66000; easing.type: Easing.InOutSine }
                NumberAnimation { from: overlay.height * 0.72; to: overlay.height * 0.62; duration: 66000; easing.type: Easing.InOutSine }
            }
        }

        Image {
            anchors.fill: parent
            source: "../assets/img/noise.png"
            fillMode: Image.Tile
            smooth: false
            opacity: 0.10
        }
    }

    // ================= 内容层 =================
    Item {
        id: content
        anchors.fill: parent
        property Item glassSource: water

        Column {
            id: mainInfo
            anchors.left: parent.left
            anchors.leftMargin: Math.round(overlay.width * 0.085)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(overlay.width * 0.6, 1000)
            spacing: 16

            Row {
                spacing: 10

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "ripple"
                    size: 18
                    color: "#8FE6E0"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: App.activeSpaceName !== "" ? String(App.activeSpaceName) : qsTr("专注中")
                    color: "#BFE6EC"
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    font.family: C.numFont
                    font.letterSpacing: 2
                }
            }

            Text {
                text: App.remainingText
                color: "#F4FDFF"
                font.family: C.monoFont
                font.pixelSize: Math.max(84, Math.min(overlay.width * 0.16, overlay.height * 0.26))
                font.weight: Font.Light
                font.letterSpacing: 3
            }

            Item {
                width: parent.width
                height: 12

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: "#1AFFFFFF"
                    border.width: 1
                    border.color: "#2BFFFFFF"
                }
                Rectangle {
                    width: parent.width * overlay.progressValue
                    height: parent.height
                    radius: parent.height / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#2B86FF" }
                        GradientStop { position: 0.55; color: "#2ED3C6" }
                        GradientStop { position: 1.0; color: "#7FE7DA" }
                    }
                    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                }
            }

            Text {
                text: qsTr("已完成 %1% · 剩余 %2 分钟").arg(overlay.percentValue).arg(overlay.remainingMinutesValue)
                color: "#9FC3CE"
                font.pixelSize: 14
                font.family: C.numFont
            }

            Item { width: 1; height: 10 }

            Text {
                text: qsTr("把这件事做完，再抬头。")
                color: "#7FA3AF"
                font.pixelSize: 15
                font.family: C.numFont
            }

            Text {
                text: overlay.heavyLock ? qsTr("本轮结束后窗口自动关闭") : qsTr("可以暂停，但时间不会等你")
                color: "#5E818E"
                font.pixelSize: 12
                font.family: C.numFont
            }
        }

        MediaIsland {
            id: island
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 28
            anchors.topMargin: 28
            glassSource: content.glassSource
            hasMedia: overlay.hasMedia
            mediaTitle: overlay.mediaTitleText
            mediaArtist: overlay.mediaArtistText
            mediaAlbum: overlay.mediaAlbumText
            mediaApp: overlay.mediaAppText
            mediaPlaying: overlay.mediaPlayingValue
            mediaPosition: overlay.mediaPositionValue
            mediaDuration: overlay.mediaDurationValue
            focusLine: qsTr("专注中 · 剩余 %1").arg(App.remainingText)
            focusSub: App.activeSpaceName !== ""
                      ? qsTr("%1 · 已完成 %2%").arg(String(App.activeSpaceName)).arg(overlay.percentValue)
                      : qsTr("已完成 %1%").arg(overlay.percentValue)
            onTogglePlay: if (typeof App.mediaToggle === "function") App.mediaToggle()
            onNextTrack: if (typeof App.mediaNext === "function") App.mediaNext()
            onPrevTrack: if (typeof App.mediaPrev === "function") App.mediaPrev()
        }

        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 32
            anchors.bottomMargin: 32
            spacing: 12
            visible: !overlay.heavyLock

            GlassButton {
                text: App.state === "paused" ? qsTr("继续") : qsTr("暂停")
                tone: "light"
                fontSize: 14
                padH: 24
                minHeight: 46
                onClicked: {
                    if (App.state === "paused") App.resumeSession()
                    else App.pauseSession()
                }
            }

            GlassButton {
                text: qsTr("提前结束")
                tone: "ghost"
                fontSize: 14
                padH: 24
                minHeight: 46
                onClicked: App.stopSession()
            }
        }
    }
}