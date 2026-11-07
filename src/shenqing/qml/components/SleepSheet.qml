import QtQuick
import "../theme"
import "../glass"
import "../components"
import "Constants.js" as C

// v0.13 睡眠模式设置面板（从设置页抽出，供清空间页复用）
Item {
    id: sheet
    objectName: "SleepSheet"
    property Item glassSource: null
    property bool animationsEnabled: true
    property bool opened: false

    property bool localSleepReminders: true
    property var localSleepTimes: ["23:30", "00:30"]
    property string newSleepTime: "23:30"
    property int clockClickCount: 0

    readonly property bool hasSleepBackend: (typeof App !== "undefined" && App.sleepScheduleItems !== undefined)
    readonly property var sleepItems: (typeof App !== "undefined" && App.sleepScheduleItems !== undefined)
                                      ? App.sleepScheduleItems : []
    readonly property var sleepTimes: hasSleepBackend ? sleepItems : sheet.localSleepTimes

    function open() {
        sheet.opened = true
        sheet.forceActiveFocus()
    }
    function close() { sheet.opened = false }
    function addSleepTime(timeText) {
        var text = String(timeText).trim()
        if (text.length < 4) return
        if (typeof App !== "undefined" && typeof App.addSleepSchedule === "function") {
            App.addSleepSchedule(text)
        } else {
            var list = sheet.localSleepTimes.slice()
            if (list.indexOf(text) < 0) list.push(text)
            sheet.localSleepTimes = list
        }
    }
    function removeSleepTime(item) {
        if (typeof App !== "undefined" && typeof App.removeSleepSchedule === "function") {
            var key = (item !== null && item.id !== undefined) ? String(item.id) : String(item)
            App.removeSleepSchedule(key)
        } else {
            var text = String(item)
            var list = sheet.localSleepTimes.slice()
            var idx = list.indexOf(text)
            if (idx >= 0) list.splice(idx, 1)
            sheet.localSleepTimes = list
        }
    }
    function toggleSleepReminders() {
        if (typeof App !== "undefined" && typeof App.setSleepReminders === "function")
            App.setSleepReminders(!(App.sleepRemindersEnabled === true))
        else
            sheet.localSleepReminders = !sheet.localSleepReminders
    }
    function clickSleepClock() {
        if (typeof App !== "undefined" && typeof App.clickClockForUnlock === "function") {
            App.clickClockForUnlock()
            sheet.clockClickCount = (sheet.clockClickCount % 10) + 1
        } else {
            sheet.clockClickCount = (sheet.clockClickCount + 1) % 11
        }
        clockClickReset.restart()
    }

    visible: sheet.opened || opacity > 0.01
    opacity: sheet.opened ? 1 : 0
    z: 80
    focus: sheet.opened
    Behavior on opacity {
        enabled: sheet.animationsEnabled
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
    Keys.onEscapePressed: sheet.close()
    Shortcut {
        sequence: "Escape"
        enabled: sheet.opened
        onActivated: sheet.close()
    }
    Timer {
        id: clockClickReset
        interval: 5000
        repeat: false
        onTriggered: sheet.clockClickCount = 0
    }

    Rectangle {
        anchors.fill: parent
        color: "#99040A10"
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: sheet.close()
    }

    GlassCard {
        width: Math.min(520, sheet.width - 56)
        implicitHeight: sheetColumn.implicitHeight + 40
        height: implicitHeight
        anchors.centerIn: parent
        radius: 24
        interactive: false
        glassSource: sheet.glassSource

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
        }

        Column {
            id: sheetColumn
            x: 24
            y: 20
            width: parent.width - 48
            spacing: 12

            Row {
                width: parent.width
                spacing: 9
                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    kind: "moon"
                    size: 17
                    color: AppTheme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("还清（睡眠模式）")
                    color: AppTheme.textPrimary
                    font.pixelSize: AppTheme.fs(16)
                    font.weight: Font.DemiBold
                    font.family: AppTheme.fontFamily
                }
                Item { width: parent.width - 280; height: 1 }
                Item {
                    width: 26
                    height: 26
                    Glyph {
                        anchors.centerIn: parent
                        kind: "close"
                        size: 11
                        color: closeArea.containsMouse ? AppTheme.textPrimary : AppTheme.textTertiary
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sheet.close()
                    }
                }
                GlassSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: (typeof App !== "undefined" && App.sleepRemindersEnabled !== undefined)
                             ? App.sleepRemindersEnabled : sheet.localSleepReminders
                    onClicked: sheet.toggleSleepReminders()
                }
            }

            Text {
                width: parent.width
                text: qsTr("到点自动进入深清锁定；右侧开关开启后会提前提醒。")
                color: AppTheme.textTertiary
                font.pixelSize: AppTheme.fs(11)
                font.family: AppTheme.fontFamily
                wrapMode: Text.WordWrap
            }

            Rectangle { width: parent.width; height: 1; color: AppTheme.divider }

            Repeater {
                model: sheet.sleepTimes
                delegate: Item {
                    width: sheetColumn.width
                    height: 32
                    readonly property string timeText: modelData.time !== undefined
                                                       ? String(modelData.time) : String(modelData)
                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: AppTheme.glass ? "#12FFFFFF" : AppTheme.cardBgAlt
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("%1 锁定").arg(timeText)
                        color: AppTheme.textPrimary
                        font.pixelSize: AppTheme.fs(13)
                        font.family: AppTheme.fontFamily
                    }
                    Item {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        Glyph {
                            anchors.centerIn: parent
                            kind: "close"
                            size: 11
                            color: sleepRemoveArea.containsMouse ? AppTheme.danger : AppTheme.textTertiary
                        }
                        MouseArea {
                            id: sleepRemoveArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sheet.removeSleepTime(modelData)
                        }
                    }
                }
            }

            Row {
                spacing: 8
                TextInput {
                    id: newSleepInput
                    width: 92
                    height: 32
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    text: sheet.newSleepTime
                    color: AppTheme.textPrimary
                    selectionColor: AppTheme.accentSoft
                    selectedTextColor: "#FFFFFF"
                    font.pixelSize: AppTheme.fs(13)
                    font.family: AppTheme.fontFamily
                    onTextChanged: sheet.newSleepTime = text
                    Keys.onReturnPressed: sheet.addSleepTime(text)
                    Rectangle {
                        anchors.fill: parent
                        z: -1
                        radius: 10
                        color: AppTheme.cardBgAlt
                        border.width: 1
                        border.color: newSleepInput.activeFocus ? AppTheme.accent : AppTheme.cardBorder
                    }
                }
                GlassButton {
                    text: qsTr("添加时间")
                    tone: "ghost"
                    fontSize: AppTheme.fs(12)
                    padH: 14
                    minHeight: 32
                    onClicked: sheet.addSleepTime(sheet.newSleepTime)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("提醒：提前 1 小时 / 30 分钟 / 1 分钟")
                    color: AppTheme.textTertiary
                    font.pixelSize: AppTheme.fs(10)
                    font.family: AppTheme.fontFamily
                }
            }

            Row {
                width: parent.width
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (typeof App !== "undefined" && App.unlockChanceLabel !== undefined)
                          ? String(App.unlockChanceLabel)
                          : qsTr("本月剩余解锁次数：%1").arg(2)
                    color: AppTheme.textSecondary
                    font.pixelSize: AppTheme.fs(12)
                    font.family: AppTheme.fontFamily
                }
                Item { width: parent.width - 360; height: 1 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("连续点击时钟 10 次解锁")
                    color: AppTheme.textTertiary
                    font.pixelSize: AppTheme.fs(10)
                    font.family: AppTheme.fontFamily
                }
                Item {
                    width: 28
                    height: 28
                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: sleepClockArea.containsMouse ? AppTheme.accentSoft : AppTheme.cardBgAlt
                        border.width: 1
                        border.color: AppTheme.cardBorder
                    }
                    Glyph {
                        anchors.centerIn: parent
                        kind: "clock"
                        size: 14
                        color: AppTheme.textPrimary
                    }
                    MouseArea {
                        id: sleepClockArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sheet.clickSleepClock()
                    }
                }
            }

            Item {
                width: parent.width
                height: 12
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4
                    radius: 2
                    color: AppTheme.glass ? "#1AFFFFFF" : AppTheme.divider
                }
                Rectangle {
                    width: parent.width * sheet.clockClickCount / 10
                    height: 4
                    radius: 2
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: AppTheme.accent
                    Behavior on width { NumberAnimation { duration: 120 } }
                }
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: sheet.clockClickCount + " / 10"
                    color: AppTheme.textTertiary
                    font.pixelSize: AppTheme.fs(9)
                    font.family: AppTheme.fontFamily
                }
            }
        }
    }
}
