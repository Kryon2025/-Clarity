import QtQuick
import QtQuick.Window
import "../theme"
import "../components"
import "../glass"
import "../components/Constants.js" as C

// v0.8 新用户引导（参考 CW2）：欢迎 → 三档空间 → 主题 → 插件 → 完成
// 首次启动自动显示；设置页可手动重新打开。完成状态优先 App.onboardingDone（后端），缺失时回退本地 Settings。
Window {
    id: overlay
    objectName: "Onboarding"
    title: qsTr("深清 · 新手引导")
    property bool animationsEnabled: true
    width: Screen.width
    height: Screen.height
    property bool showing: false
    property int pageIndex: 0
    readonly property int pageCount: 5
    readonly property var pages: [
        { icon: "drop", title: qsTr("欢迎使用深清"), body: qsTr("选好模式与时长，时间没到不开门。深清会帮你把注意力收回来。") },
        { icon: "ripple", title: qsTr("三档空间"), body: qsTr("浅清只屏蔽黑名单应用；覆清额外显示白名单 dock；深清只留倒计时，不可提前结束。") },
        { icon: "sparkle", title: qsTr("主题"), body: qsTr("纯色、清空间浅色、液态玻璃三种外观，可在左侧「主题」页随时切换。") },
        { icon: "grid", title: qsTr("插件"), body: qsTr("插件可以给深清加功能：番茄同步、专注统计，或自定义遮罩小组件。") },
        { icon: "check", title: qsTr("准备好了"), body: qsTr("开始第一轮专注吧。数据与设置都保存在本机，随时可以在设置里重新查看引导。") }
    ]

    // 后端缺失 onboardingDone 时的本地兜底（不持久化，仅本次运行）
    property bool localDone: false

    readonly property bool backendDone: (typeof App !== "undefined" && App.onboardingDone !== undefined)
                                        ? App.onboardingDone === true : false
    readonly property bool hasBackendDone: (typeof App !== "undefined" && App.onboardingDone !== undefined)

    visibility: overlay.showing ? Window.FullScreen : Window.Hidden
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"

    function showPages() {
        overlay.pageIndex = 0
        overlay.showing = true
        sceneRoot.opacity = overlay.animationsEnabled ? 0 : 1
        overlay.show()
        overlay.raise()
        overlay.requestActivate()
        if (overlay.animationsEnabled)
            enterAnim.restart()
    }
    function nextPage() {
        if (overlay.pageIndex < overlay.pageCount - 1) {
            overlay.pageIndex++
            pageAnim.restart()
        } else {
            overlay.finishGuide()
        }
    }
    function prevPage() {
        if (overlay.pageIndex > 0) {
            overlay.pageIndex--
            pageAnim.restart()
        }
    }
    function finishGuide() {
        // 优先写后端 settings；缺失时回退本地 Settings
        if (typeof App !== "undefined" && typeof App.setOnboardingDone === "function")
            App.setOnboardingDone(true)
        overlay.localDone = true
        if (overlay.animationsEnabled)
            closeAnim.restart()
        else
            overlay.showing = false
    }

    Component.onCompleted: {
        // 首次启动自动显示
        if (overlay.hasBackendDone) {
            if (!overlay.backendDone) overlay.showPages()
        } else if (!overlay.localDone) {
            overlay.showPages()
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: overlay.finishGuide()
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation {
            target: sceneRoot
            property: "opacity"
            from: 0
            to: 1
            duration: overlay.animationsEnabled ? 220 : 0
            easing.type: Easing.OutCubic
        }
    }
    ParallelAnimation {
        id: pageAnim
        NumberAnimation {
            target: pagePanel
            property: "opacity"
            from: 0.35
            to: 1
            duration: overlay.animationsEnabled ? 180 : 0
            easing.type: Easing.OutCubic
        }
    }
    ParallelAnimation {
        id: closeAnim
        NumberAnimation {
            target: sceneRoot
            property: "opacity"
            from: 1
            to: 0
            duration: overlay.animationsEnabled ? 180 : 0
            easing.type: Easing.OutCubic
        }
        onFinished: overlay.showing = false
    }

    Item {
        id: sceneRoot
        anchors.fill: parent
        opacity: 1

        Rectangle {
            anchors.fill: parent
            color: "#CC04121C"
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
        }

        Rectangle {
            id: dialog
            width: Math.min(880, overlay.width * 0.78)
            height: Math.min(600, overlay.height * 0.82)
            anchors.centerIn: parent
            radius: 26
            color: AppTheme.glass ? "#F20A1B26" : AppTheme.cardBg
            border.width: 1
            border.color: AppTheme.glass ? "#4DFFFFFF" : AppTheme.cardBorderStrong

            Item {
                id: pagePanel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: footer.top
                anchors.margins: 34

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 18

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 92
                        height: 92
                        radius: 28
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#7FE7DA" }
                            GradientStop { position: 0.55; color: "#2ED3C6" }
                            GradientStop { position: 1.0; color: "#1F6FD0" }
                        }
                        border.width: 1
                        border.color: "#66FFFFFF"
                        Glyph {
                            anchors.centerIn: parent
                            kind: overlay.pages[overlay.pageIndex].icon
                            size: 42
                            color: "#04222B"
                        }
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: overlay.pages[overlay.pageIndex].title
                        color: AppTheme.textPrimary
                        font.pixelSize: 28
                        font.weight: Font.Bold
                        font.family: C.numFont
                        font.letterSpacing: 1
                    }

                    Text {
                        width: Math.min(parent.width, 620)
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: overlay.pages[overlay.pageIndex].body
                        color: AppTheme.textSecondary
                        font.pixelSize: 15
                        font.family: C.numFont
                        wrapMode: Text.WordWrap
                        lineHeight: 1.5
                    }
                }
            }

            // 底部：跳过 / 圆点 / 上一步 / 下一步
            Item {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 26
                height: 44

                Item {
                    id: skipButton
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 74
                    height: 32
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("跳过")
                        color: skipArea.containsMouse ? AppTheme.textSecondary : AppTheme.textTertiary
                        font.pixelSize: 13
                        font.family: C.numFont
                    }
                    MouseArea {
                        id: skipArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: overlay.finishGuide()
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 10
                    Repeater {
                        model: overlay.pageCount
                        delegate: Item {
                            width: 9
                            height: 9
                            Rectangle {
                                anchors.fill: parent
                                radius: 4.5
                                color: index === overlay.pageIndex ? AppTheme.accent
                                                                   : (AppTheme.glass ? "#55FFFFFF" : AppTheme.cardBorderStrong)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: overlay.pageIndex = index
                            }
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    GlassButton {
                        visible: overlay.pageIndex > 0
                        text: qsTr("上一步")
                        tone: "ghost"
                        fontSize: 13
                        padH: 18
                        minHeight: 36
                        onClicked: overlay.prevPage()
                    }

                    GlassButton {
                        text: overlay.pageIndex === overlay.pageCount - 1 ? qsTr("进入深清") : qsTr("下一步")
                        tone: "light"
                        fontSize: 13
                        padH: 22
                        minHeight: 36
                        onClicked: overlay.nextPage()
                    }
                }
            }
        }
    }
}
