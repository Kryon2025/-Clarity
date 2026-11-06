import QtQuick
import QtQuick.Window
import "../theme"
import "../glass"
import "../components"
import "../components/Constants.js" as C

// v0.9 全局 AI 助手浮层。
// 数据接口：App.aiConfigured / aiEnabled / aiState(idle|loading|ok|error) / aiAnswer / aiError / aiAsk(query)
Window {
    id: panel
    objectName: "AIPanel"
    title: qsTr("深清 · AI 助手")
    property bool animationsEnabled: true
    width: Screen.width
    height: Screen.height
    property bool showing: false
    property bool closing: false
    property string query: ""
    property string localError: ""
    property bool localMissingApi: false

    signal settingsRequested()

    readonly property bool configured: (typeof App !== "undefined")
                                       && (App.aiConfigured !== undefined
                                           ? App.aiConfigured === true
                                           : App.aiEnabled === true)
    readonly property string aiState: (typeof App !== "undefined" && App.aiState !== undefined)
                                      ? String(App.aiState) : (panel.localMissingApi ? "error" : "idle")
    readonly property string aiAnswer: (typeof App !== "undefined" && App.aiAnswer !== undefined)
                                       ? String(App.aiAnswer) : ""
    readonly property string aiError: {
        if (panel.localMissingApi) return panel.localError
        return (typeof App !== "undefined" && App.aiError !== undefined) ? String(App.aiError) : ""
    }

    visibility: (panel.showing || panel.closing) ? Window.FullScreen : Window.Hidden
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"

    function showPanel() {
        panel.showing = true
        panel.closing = false
        sceneRoot.opacity = panel.animationsEnabled ? 0 : 1
        panel.show()
        panel.raise()
        panel.requestActivate()
        if (panel.animationsEnabled) enterAnim.restart()
        if (panel.configured) inputField.forceActiveFocus()
    }
    function hide() {
        if (!panel.showing) return
        if (!panel.animationsEnabled) { panel.showing = false; return }
        panel.closing = true
        closeAnim.restart()
    }
    function send() {
        var text = String(panel.query).trim()
        if (text.length === 0) return
        panel.localMissingApi = false
        panel.localError = ""
        if (typeof App !== "undefined" && typeof App.aiAsk === "function") {
            App.aiAsk(text)
        } else {
            panel.localMissingApi = true
            panel.localError = qsTr("缺少 AI 对话接口（App.aiAsk）")
        }
    }
    function copyAnswer() {
        answerHelper.text = panel.aiAnswer
        answerHelper.selectAll()
        answerHelper.copy()
        copiedHint.visible = true
        copyTimer.restart()
    }

    Shortcut { sequence: "Escape"; onActivated: panel.hide() }

    Timer {
        id: copyTimer
        interval: 1600
        onTriggered: copiedHint.visible = false
    }
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: sceneRoot; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: closeAnim
        NumberAnimation { target: sceneRoot; property: "opacity"; to: 0; duration: 180; easing.type: Easing.OutCubic }
        onFinished: { panel.closing = false; panel.showing = false }
    }

    Item {
        id: sceneRoot
        anchors.fill: parent

        Rectangle { anchors.fill: parent; color: "#AA040A10" }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: panel.hide()
        }

        Rectangle {
            id: dialog
            width: Math.min(760, panel.width * 0.56)
            height: Math.min(600, panel.height * 0.76)
            anchors.centerIn: parent
            radius: 24
            color: AppTheme.glass ? "#F20A1B26" : AppTheme.cardBg
            border.width: 1
            border.color: AppTheme.glass ? "#4DFFFFFF" : AppTheme.cardBorderStrong
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: {} }

            // 标题
            Row {
                id: titleRow
                x: 24
                y: 20
                width: parent.width - 48
                spacing: 10
                Rectangle {
                    width: 30; height: 30; radius: 15
                    anchors.verticalCenter: parent.verticalCenter
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#7FE7DA" }
                        GradientStop { position: 1.0; color: "#2B86FF" }
                    }
                    Glyph { anchors.centerIn: parent; kind: "sparkle"; size: 16; color: "#04222B" }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("AI 助手")
                    color: AppTheme.textPrimary
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    font.family: C.numFont
                }
            }

            Item {
                id: closeButton
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 16
                anchors.topMargin: 16
                width: 30; height: 30
                Rectangle {
                    anchors.fill: parent
                    radius: 15
                    color: closeArea.containsMouse ? "#33FFFFFF" : "transparent"
                }
                Glyph { anchors.centerIn: parent; kind: "close"; size: 12; color: AppTheme.textTertiary }
                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.hide()
                }
            }

            Rectangle { x: 24; y: 58; width: parent.width - 48; height: 1; color: AppTheme.divider }

            // 未配置
            Column {
                visible: !panel.configured
                anchors.centerIn: parent
                width: parent.width - 80
                spacing: 16
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("还没有配置 AI 助手")
                    color: AppTheme.textPrimary
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    font.family: C.numFont
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("请在设置 → AI 助手中配置服务商与 API Key。")
                    color: AppTheme.textSecondary
                    font.pixelSize: 13
                    font.family: C.numFont
                    wrapMode: Text.WordWrap
                }
                GlassButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("打开 AI 设置")
                    tone: "light"
                    fontSize: 13
                    padH: 22
                    minHeight: 38
                    onClicked: { panel.hide(); panel.settingsRequested() }
                }
            }

            // 会话区
            Item {
                visible: panel.configured
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                anchors.topMargin: 74
                anchors.bottom: inputRow.top
                anchors.bottomMargin: 14

                Flickable {
                    id: answerFlick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: answerColumn.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: answerColumn
                        width: answerFlick.width
                        spacing: 12

                        Text {
                            visible: panel.aiState === "idle"
                            width: parent.width
                            text: qsTr("把问题交给深清：可以问专注方法、帮你整理思路，或随便聊聊。")
                            color: AppTheme.textSecondary
                            font.pixelSize: 13
                            font.family: C.numFont
                            wrapMode: Text.WordWrap
                        }

                        Row {
                            visible: panel.aiState === "loading"
                            spacing: 10
                            Item {
                                width: 18; height: 18
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    width: 18; height: 18; radius: 9
                                    color: "transparent"
                                    border.width: 2
                                    border.color: AppTheme.accent
                                    opacity: 0.35
                                }
                                Rectangle {
                                    width: 18; height: 18; radius: 9
                                    color: "transparent"
                                    border.width: 2
                                    border.color: AppTheme.accent
                                    rotation: 45
                                    Behavior on rotation { NumberAnimation { duration: 1 } }
                                }
                                RotationAnimation on rotation {
                                    running: panel.aiState === "loading"
                                    from: 0; to: 360; duration: 900; loops: Animation.Infinite
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("思考中…")
                                color: AppTheme.textSecondary
                                font.pixelSize: 13
                                font.family: C.numFont
                            }
                        }

                        TextEdit {
                            id: answerText
                            visible: panel.aiState === "ok"
                            width: parent.width
                            text: panel.aiAnswer
                            readOnly: true
                            textFormat: TextEdit.PlainText
                            wrapMode: TextEdit.Wrap
                            color: AppTheme.textPrimary
                            selectionColor: AppTheme.accentSoft
                            selectedTextColor: "#FFFFFF"
                            font.pixelSize: 14
                            font.family: C.numFont
                            selectByMouse: true
                        }

                        Text {
                            visible: panel.aiState === "error"
                            width: parent.width
                            text: panel.aiError !== "" ? panel.aiError : qsTr("AI 请求失败")
                            color: AppTheme.danger
                            font.pixelSize: 13
                            font.family: C.numFont
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // 输入区
            Item {
                id: inputRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                anchors.bottomMargin: 20
                height: 46
                visible: panel.configured

                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: AppTheme.glass ? "#1AFFFFFF" : AppTheme.cardBgAlt
                    border.width: 1
                    border.color: inputField.activeFocus ? AppTheme.accent : AppTheme.cardBorder
                }

                TextInput {
                    id: inputField
                    anchors.left: parent.left
                    anchors.right: sendButton.left
                    anchors.leftMargin: 16
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    color: AppTheme.textPrimary
                    selectionColor: AppTheme.accentSoft
                    selectedTextColor: "#FFFFFF"
                    font.pixelSize: 13
                    font.family: C.numFont
                    text: panel.query
                    onTextChanged: panel.query = text
                    enabled: panel.aiState !== "loading"
                    onAccepted: panel.send()
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: inputField.text.length === 0
                        text: qsTr("问点什么…（Enter 发送）")
                        color: AppTheme.textTertiary
                        font.pixelSize: 13
                        font.family: C.numFont
                    }
                }

                Item {
                    id: sendButton
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 76; height: 32
                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: sendArea.containsMouse ? AppTheme.accentSoft : AppTheme.accent
                    }
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("发送")
                        color: "#FFFFFF"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        font.family: C.numFont
                    }
                    MouseArea {
                        id: sendArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: panel.aiState !== "loading"
                        onClicked: panel.send()
                    }
                }
            }

            // 复制全文（有答案时）
            Item {
                visible: panel.configured && panel.aiState === "ok"
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.bottom: inputRow.top
                anchors.bottomMargin: 4
                width: 88; height: 26
                Text {
                    anchors.centerIn: parent
                    text: copiedHint.visible ? qsTr("已复制") : qsTr("复制全文")
                    color: copyArea.containsMouse ? AppTheme.accent : AppTheme.textTertiary
                    font.pixelSize: 11
                    font.family: C.numFont
                }
                MouseArea {
                    id: copyArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.copyAnswer()
                }
            }
        }
    }

    TextEdit {
        id: answerHelper
        visible: false
        width: 1
        height: 1
    }
    Text {
        id: copiedHint
        visible: false
        text: ""
    }
}
