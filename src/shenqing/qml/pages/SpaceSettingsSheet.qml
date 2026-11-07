import QtQuick
import "../theme"
import "../components"
import "../components/Constants.js" as C

// 空间设置浮层：取消 / 空间设置 / 完成 + 名称 / 时长 / 氛围 / 允许应用 / 删除
GlassSheet {
    id: sheetRoot

    property string spaceId: ""
    property bool newSpace: false
    property string spaceName: ""
    property int minutes: 45
    property string atmosphere: "静谧"
    property int armedDelete: 0

    title: qsTr("空间设置")
    deleteText: qsTr("删除空间")
    deleteArmed: sheetRoot.armedDelete === 1

    signal closeRequested()
    signal committed()
    signal deleteConfirmed()
    signal whitelistRequested()

    readonly property int minMinutes: 15
    readonly property int maxMinutes: 240
    readonly property int minuteStep: 5
    readonly property int nameLimit: 20

    // 白名单数量：直接读 App.spaces 里的实时数据（白名单页开关后能同步）
    readonly property var spaceData: {
        var list = App.spaces || []
        for (var i = 0; i < list.length; i++) {
            if (String(list[i].id) === sheetRoot.spaceId) return list[i]
        }
        return null
    }
    readonly property var allowedList: spaceData !== null && spaceData.allowed_apps !== undefined
                                       ? spaceData.allowed_apps : []
    readonly property int allowedCount: allowedList.length

    // 氛围值来自 App.atmospheres（数据侧是中文 value），显示时映射成可翻译文案。
    // 写成绑定而不是函数，这样切换语言时 Qt 的 retranslate 会重新求值。
    readonly property string atmosphereText: {
        var v = String(sheetRoot.atmosphere)
        if (v === "静谧") return qsTr("静谧")
        if (v === "秩序") return qsTr("秩序")
        if (v === "探索") return qsTr("探索")
        if (v === "专注") return qsTr("专注")
        return v
    }

    function spaceById(id) {
        var list = App.spaces || []
        for (var i = 0; i < list.length; i++) {
            if (String(list[i].id) === String(id)) return list[i]
        }
        return null
    }

    function iconForApp(exe) {
        var catalog = App.appCatalog || []
        for (var i = 0; i < catalog.length; i++) {
            if (String(catalog[i].exe).toLowerCase() === String(exe).toLowerCase())
                return String(catalog[i].iconUrl || "")
        }
        return ""
    }

    function nameForApp(exe) {
        var catalog = App.appCatalog || []
        for (var i = 0; i < catalog.length; i++) {
            if (String(catalog[i].exe).toLowerCase() === String(exe).toLowerCase())
                return String(catalog[i].name || exe)
        }
        return String(exe)
    }

    property bool loaded: false

    onVisibleChanged: {
        if (!visible) {
            sheetRoot.loaded = false
        } else if (!sheetRoot.loaded && sheetRoot.spaceId !== "") {
            sheetRoot.open(sheetRoot.spaceId, sheetRoot.newSpace)
        }
    }

    // 打开浮层：从 draftSpace 取初值（读不到就退回 App.spaces）
    function open(id, isNew) {
        sheetRoot.loaded = true
        sheetRoot.spaceId = String(id)
        sheetRoot.newSpace = Boolean(isNew)
        var draft = App.draftSpace || ({})
        var src = null
        if (draft.id !== undefined && String(draft.id) === sheetRoot.spaceId) src = draft
        else src = sheetById(sheetRoot.spaceId)

        sheetRoot.spaceName = src !== null && src.name !== undefined ? String(src.name) : "新空间"
        sheetRoot.minutes = src !== null && src.minutes !== undefined
                             ? Number(src.minutes) : 45
        sheetRoot.atmosphere = src !== null && src.atmosphere !== undefined
                              ? String(src.atmosphere) : "静谧"
        sheetRoot.minutesExpanded = false
        sheetRoot.atmosphereExpanded = false
        sheetRoot.armedDelete = 0
        nameInput.text = sheetRoot.spaceName
    }

    function sheetById(id) {
        return sheetRoot.spaceById(id)
    }

    function commit() {
        var name = nameInput.text.trim()
        if (name.length === 0) name = "新空间"
        if (name.length > sheetRoot.nameLimit) name = name.slice(0, sheetRoot.nameLimit)
        App.updateSpace(sheetRoot.spaceId, name, Math.round(sheetRoot.minutes), sheetRoot.atmosphere)
        App.commitEditSpace()
        sheetRoot.committed()
    }

    function cancel() {
        App.cancelEditSpace()
        sheetRoot.closeRequested()
    }

    // 展开态
    property bool minutesExpanded: false
    property bool atmosphereExpanded: false

    Timer {
        id: disarmTimer
        interval: 3200
        repeat: false
        onTriggered: sheetRoot.armedDelete = 0
    }

    onCancelRequested: sheetRoot.cancel()
    onDoneRequested: sheetRoot.commit()
    onDeleteRequested: {
        if (sheetRoot.armedDelete === 1) {
            sheetRoot.armedDelete = 0
            App.deleteSpace(sheetRoot.spaceId)
            sheetRoot.deleteConfirmed()
        } else {
            sheetRoot.armedDelete = 1
            disarmTimer.restart()
        }
    }

    // ================= 内容 =================
    Column {
        id: body
        width: parent.width
        spacing: 12

        // ---- 空间名称 ----
        GlassCard {
            width: parent.width
            height: 86
            radius: 20
            interactive: false

            Item {
                anchors.fill: parent
                anchors.margins: 20
                anchors.topMargin: 16
                anchors.bottomMargin: 16

                Text {
                    id: nameLabel
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: qsTr("空间名称")
                    color: AppTheme.textSecondary
                    font.pixelSize: AppTheme.fs(13)
                    font.family: AppTheme.fontFamily
                }

                TextInput {
                    id: nameInput
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: 56
                    anchors.top: nameLabel.bottom
                    anchors.topMargin: 4
                    text: sheetRoot.spaceName
                    color: AppTheme.textPrimary
                    font.pixelSize: AppTheme.fs(20)
                    font.weight: Font.DemiBold
                    font.family: AppTheme.fontFamily
                    selectionColor: AppTheme.accent
                    selectedTextColor: "#FFFFFF"
                    cursorDelegate: Item {
                        width: 2
                        Rectangle {
                            width: 2
                            height: nameInput.height * 0.8
                            y: nameInput.height * 0.1
                            color: AppTheme.accent
                            visible: nameInput.cursorVisible && nameInput.activeFocus
                        }
                    }
                    maximumLength: sheetRoot.nameLimit
                    selectByMouse: true
                    onTextChanged: {
                        if (text.length > sheetRoot.nameLimit) {
                            var clipped = text.slice(0, sheetRoot.nameLimit)
                            text = clipped
                            return
                        }
                        if (text !== sheetRoot.spaceName) sheetRoot.spaceName = text
                        placeholder.visible = text.length === 0
                        counter.text = text.length + "/" + sheetRoot.nameLimit
                    }
                }

                Text {
                    id: placeholder
                    anchors.left: nameInput.left
                    anchors.top: nameInput.top
                    anchors.topMargin: 2
                    text: qsTr("给空间起个名字")
                    color: AppTheme.textTertiary
                    font.pixelSize: AppTheme.fs(18)
                    font.family: AppTheme.fontFamily
                    visible: nameInput.text.length === 0
                }

                Text {
                    id: counter
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: nameInput.text.length + "/" + sheetRoot.nameLimit
                    color: AppTheme.textTertiary
                    font.pixelSize: AppTheme.fs(12)
                    font.family: AppTheme.fontFamily
                }
            }
        }

        // ---- 时长 / 氛围 / 白名单 ----
        GlassCard {
            width: parent.width
            height: groupColumn.implicitHeight + 12
            radius: 20
            interactive: false

            Column {
                id: groupColumn
                width: parent.width
                anchors.top: parent.top
                anchors.topMargin: 6

                GlassRow {
                    width: parent.width
                    rowHeight: 58
                    title: qsTr("使用时长")
                    value: qsTr("%1 分钟").arg(sheetRoot.minutes)
                    expandable: true
                    expanded: sheetRoot.minutesExpanded
                    onClicked: {
                        sheetRoot.minutesExpanded = !sheetRoot.minutesExpanded
                        if (sheetRoot.minutesExpanded) sheetRoot.atmosphereExpanded = false
                    }
                }

                Item {
                    id: minutesBox
                    width: parent.width
                    height: sheetRoot.minutesExpanded ? 100 : 0
                    clip: true
                    visible: height > 0.5
                    Behavior on height {
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }

                    Row {
                        id: stepperRow
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 20

                        Item {
                            width: 38
                            height: 38
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                anchors.fill: parent
                                radius: 19
                                color: minusArea.containsMouse ? "#1FFFFFFF" : "#12FFFFFF"
                                border.width: 1
                                border.color: minusArea.containsMouse ? "#47FFFFFF" : C.glassBorder
                                Behavior on color { ColorAnimation { duration: 140 } }
                            }
                            Glyph {
                                anchors.centerIn: parent
                                kind: "minus"
                                size: 15
                                color: "#D9E2F5"
                            }
                            MouseArea {
                                id: minusArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sheetRoot.minutes = Math.max(sheetRoot.minMinutes,
                                                                        sheetRoot.minutes - sheetRoot.minuteStep)
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 110
                            horizontalAlignment: Text.AlignHCenter
                            text: qsTr("%1 分钟").arg(sheetRoot.minutes)
                            color: AppTheme.textPrimary
                            font.pixelSize: AppTheme.fs(21)
                            font.weight: Font.DemiBold
                            font.family: AppTheme.fontFamily
                        }

                        Item {
                            width: 38
                            height: 38
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                anchors.fill: parent
                                radius: 19
                                color: plusArea.containsMouse ? "#1FFFFFFF" : "#12FFFFFF"
                                border.width: 1
                                border.color: plusArea.containsMouse ? "#47FFFFFF" : C.glassBorder
                                Behavior on color { ColorAnimation { duration: 140 } }
                            }
                            Glyph {
                                anchors.centerIn: parent
                                kind: "plus"
                                size: 15
                                color: "#D9E2F5"
                            }
                            MouseArea {
                                id: plusArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sheetRoot.minutes = Math.min(sheetRoot.maxMinutes,
                                                                        sheetRoot.minutes + sheetRoot.minuteStep)
                            }
                        }
                    }

                    GlassSlider {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 22
                        anchors.rightMargin: 22
                        anchors.top: stepperRow.bottom
                        anchors.topMargin: 10
                        from: sheetRoot.minMinutes
                        to: sheetRoot.maxMinutes
                        step: sheetRoot.minuteStep
                        value: sheetRoot.minutes
                        onMoved: (value) => sheetRoot.minutes = value
                    }
                }

                Rectangle {
                    width: parent.width - 28
                    x: 14
                    height: 1
                    color: AppTheme.divider
                }

                GlassRow {
                    width: parent.width
                    rowHeight: 58
                    title: qsTr("氛围")
                    value: sheetRoot.atmosphereText
                    expandable: true
                    expanded: sheetRoot.atmosphereExpanded
                    onClicked: {
                        sheetRoot.atmosphereExpanded = !sheetRoot.atmosphereExpanded
                        if (sheetRoot.atmosphereExpanded) sheetRoot.minutesExpanded = false
                    }
                }

                Item {
                    id: atmosphereBox
                    width: parent.width
                    height: sheetRoot.atmosphereExpanded ? 52 : 0
                    clip: true
                    visible: height > 0.5
                    Behavior on height {
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Repeater {
                            model: App.atmospheres || []
                            delegate: Item {
                                width: (parent.width - 3 * 8) / 4
                                height: 40
                                readonly property bool chosen: String(modelData.value) === sheetRoot.atmosphere

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 14
                                    color: chosen ? "#24FFFFFF" : (atmArea.containsMouse ? "#12FFFFFF" : "#0AFFFFFF")
                                    border.width: 1
                                    border.color: chosen
                                                  ? String(modelData.color !== undefined ? modelData.color : AppTheme.accent)
                                                  : "#22FFFFFF"
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 7
                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: String(modelData.color !== undefined ? modelData.color : AppTheme.accent)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: {
                                            var v = String(modelData.value)
                                            if (v === "静谧") return qsTr("静谧")
                                            if (v === "秩序") return qsTr("秩序")
                                            if (v === "探索") return qsTr("探索")
                                            if (v === "专注") return qsTr("专注")
                                            return v
                                        }
                                        color: chosen ? "#FFFFFF" : "#B7C3D9"
                                        font.pixelSize: AppTheme.fs(13)
                                        font.weight: chosen ? Font.DemiBold : Font.Normal
                                        font.family: AppTheme.fontFamily
                                    }
                                }

                                MouseArea {
                                    id: atmArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: sheetRoot.atmosphere = String(modelData.value)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width - 28
                    x: 14
                    height: 1
                    color: AppTheme.divider
                }

                GlassRow {
                    width: parent.width
                    rowHeight: 58
                    title: qsTr("允许使用的应用")
                    value: sheetRoot.allowedCount > 0 ? qsTr("%1 个应用").arg(sheetRoot.allowedCount) : qsTr("未选择")
                    onClicked: sheetRoot.whitelistRequested()
                }
            }
        }
    }

    Component.onCompleted: {
        if (sheetRoot.spaceId !== "") sheetRoot.open(sheetRoot.spaceId, sheetRoot.newSpace)
    }
}