import QtQuick
import "../components"
import "../glass"
import "../components/Constants.js" as C

// 白名单应用：搜索 + 分类 chips + 应用列表开关
Item {
    id: page
    property string spaceId: ""
    property Item glassSource: null
    property string searchText: ""
    property string activeCategory: "全部应用"

    signal backRequested()

    // key 与 Python core/app_catalog.py 的分类值一致（用于过滤），label 才是界面文案
    readonly property var categories: [
        { key: "全部应用", label: qsTr("全部应用") },
        { key: "办公软件", label: qsTr("办公软件") },
        { key: "教育学习", label: qsTr("教育学习") },
        { key: "实用工具", label: qsTr("实用工具") },
        { key: "其他", label: qsTr("其他") }
    ]
    readonly property var catalog: App.appCatalog || []

    readonly property var spaceData: {
        var list = App.spaces || []
        for (var i = 0; i < list.length; i++) {
            if (String(list[i].id) === String(page.spaceId)) return list[i]
        }
        return null
    }
    readonly property var allowedList: spaceData !== null && spaceData.allowed_apps !== undefined
                                       ? spaceData.allowed_apps : []

    function isAllowed(exe) {
        var target = String(exe).toLowerCase()
        for (var i = 0; i < allowedList.length; i++) {
            if (String(allowedList[i]).toLowerCase() === target) return true
        }
        return false
    }

    function categoryOf(app) {
        var value = app !== null && app.category !== undefined ? String(app.category) : ""
        return value.length > 0 ? value : "其他"  // 数据分类值，不翻译
    }

    readonly property var filteredApps: {
        var out = []
        var query = String(page.searchText).trim().toLowerCase()
        var list = page.catalog
        for (var i = 0; i < list.length; i++) {
            var app = list[i]
            if (page.activeCategory !== "全部应用" && page.categoryOf(app) !== page.activeCategory)
                continue
            if (query.length > 0) {
                var name = String(app.name !== undefined ? app.name : "").toLowerCase()
                var exe = String(app.exe !== undefined ? app.exe : "").toLowerCase()
                if (name.indexOf(query) < 0 && exe.indexOf(query) < 0) continue
            }
            out.push(app)
        }
        return out
    }

    // ---------- 背景板 ----------
    Rectangle {
        anchors.fill: parent
        radius: 26
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#FD0A0F18" }
            GradientStop { position: 1.0; color: "#FD070A12" }
        }
        border.width: 1
        border.color: "#26FFFFFF"
    }

    // ---------- 顶栏 ----------
    Item {
        id: header
        anchors.top: parent.top
        anchors.topMargin: 22
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 26
        anchors.rightMargin: 26
        height: 46

        Item {
            id: backButton
            width: 42
            height: 42
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                anchors.fill: parent
                radius: 21
                color: backArea.containsMouse ? "#1FFFFFFF" : "#12FFFFFF"
                border.width: 1
                border.color: backArea.containsMouse ? "#3DFFFFFF" : C.glassBorder
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Glyph {
                anchors.centerIn: parent
                kind: "back"
                size: 18
                color: "#DCE5F5"
            }
            MouseArea {
                id: backArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.backRequested()
            }
        }

        Text {
            anchors.left: backButton.right
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("白名单应用")
            color: C.textPrimary
            font.pixelSize: 22
            font.weight: Font.Bold
            font.family: C.numFont
        }

    }

    // ---------- 搜索框 ----------
    Rectangle {
        id: searchBox
        anchors.top: header.bottom
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 26
        anchors.rightMargin: 26
        height: 48
        radius: 16
        color: "#14FFFFFF"
        border.width: 1
        border.color: searchInput.activeFocus ? "#4D8FB2FF" : C.glassBorder
        Behavior on border.color { ColorAnimation { duration: 160 } }

        Glyph {
            id: searchGlyph
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            kind: "search"
            size: 17
            color: "#8A99B4"
        }

        TextInput {
            id: searchInput
            anchors.left: searchGlyph.right
            anchors.leftMargin: 12
            anchors.right: clearButton.visible ? clearButton.left : parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: page.searchText
            color: C.textPrimary
            font.pixelSize: 15
            font.family: C.numFont
            selectionColor: C.accent
            selectedTextColor: "#FFFFFF"
            selectByMouse: true
            onTextChanged: page.searchText = text

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("搜索应用")
                color: C.textTertiary
                font.pixelSize: 15
                font.family: C.numFont
                visible: searchInput.text.length === 0
            }
        }

        Item {
            id: clearButton
            width: 30
            height: 30
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            visible: searchInput.text.length > 0
            Rectangle {
                anchors.fill: parent
                radius: 15
                color: clearArea.containsMouse ? "#1FFFFFFF" : "transparent"
            }
            Glyph {
                anchors.centerIn: parent
                kind: "close"
                size: 12
                color: "#8A99B4"
            }
            MouseArea {
                id: clearArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    page.searchText = ""
                    searchInput.text = ""
                }
            }
        }
    }

    // ---------- 分类 chips ----------
    Flickable {
        id: chipBar
        anchors.top: searchBox.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 26
        anchors.rightMargin: 26
        height: 40
        contentWidth: chipsRow.width
        contentHeight: height
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: chipsRow
            height: parent.height
            spacing: 8

            Repeater {
                model: page.categories
                delegate: Item {
                    width: chipText.implicitWidth + 34
                    height: 38
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property bool chosen: page.activeCategory === modelData.key

                    LiquidGlass {
                        anchors.fill: parent
                        sourceItem: page.glassSource
                        radius: 19
                        depth: 0.75
                        frost: 0.02
                        aberration: 0.3
                        highlight: chosen ? 0.95 : 0.55
                        whiten: 0.04
                        tintAlpha: chosen ? 0.34 : 0.17
                        tint: chosen ? C.accentSoft : C.glassTint
                        sheen: 0.4
                        hover: chipArea.pressed ? 0.3 : 0
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: page.glassSource === null
                        radius: 19
                        color: chosen ? C.accent : "#12FFFFFF"
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 19
                        color: "transparent"
                        border.width: 1
                        border.color: chosen ? "#7AFFFFFF" : "#33FFFFFF"
                    }

                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: modelData.label
                        color: chosen ? "#FFFFFF" : "#B7C3D9"
                        font.pixelSize: 13
                        font.weight: chosen ? Font.DemiBold : Font.Normal
                        font.family: C.numFont
                    }

                    MouseArea {
                        id: chipArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.activeCategory = modelData.key
                    }
                }
            }
        }
    }

    // ---------- 应用列表 ----------
    Item {
        id: listHost
        anchors.top: chipBar.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 26
        anchors.rightMargin: 26
        anchors.bottom: footer.top
        anchors.bottomMargin: 14

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: "#0DFFFFFF"
            border.width: 1
            border.color: "#1FFFFFFF"
        }

        ListView {
            id: appList
            anchors.fill: parent
            anchors.margins: 8
            clip: true
            spacing: 0
            model: page.filteredApps
            boundsBehavior: Flickable.StopAtBounds


            delegate: Item {
                id: appRow
                required property var modelData
                required property int index
                width: appList.width
                height: 62

                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: rowArea.containsMouse ? "#0BFFFFFF" : "transparent"
                }

                AppIcon {
                    id: appIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    size: 40
                    iconUrl: modelData.iconUrl !== undefined ? String(modelData.iconUrl) : ""
                    appName: modelData.name !== undefined ? String(modelData.name) : ""
                }

                Column {
                    anchors.left: appIcon.right
                    anchors.leftMargin: 14
                    anchors.right: rowSwitch.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: modelData.name !== undefined ? String(modelData.name) : ""
                        color: C.textPrimary
                        font.pixelSize: 15
                        font.family: C.numFont
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        text: modelData.exe !== undefined ? String(modelData.exe) : ""
                        color: C.textTertiary
                        font.pixelSize: 11
                        font.family: C.numFont
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                GlassSwitch {
                    id: rowSwitch
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    checked: page.isAllowed(modelData.exe)
                    onClicked: App.toggleSpaceAllowedApp(page.spaceId, String(modelData.exe),
                                                         !page.isAllowed(modelData.exe))
                }

                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    anchors.rightMargin: 78
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: App.toggleSpaceAllowedApp(page.spaceId, String(modelData.exe),
                                                         !page.isAllowed(modelData.exe))
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 62
                    anchors.bottom: parent.bottom
                    height: 1
                    color: "#0FFFFFFF"
                    visible: index < appList.count - 1
                }
            }
        }

        // 空状态
        Column {
            anchors.centerIn: parent
            spacing: 12
            visible: page.filteredApps.length === 0

            Glyph {
                anchors.horizontalCenter: parent.horizontalCenter
                kind: "grid"
                size: 34
                color: "#5F6C84"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.catalog.length === 0 ? qsTr("暂无应用") : qsTr("没有匹配的应用")
                color: "#C6D0E2"
                font.pixelSize: 16
                font.family: C.numFont
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(listHost.width - 80, 420)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: page.catalog.length === 0
                      ? qsTr("还没有扫描到本机应用。点「刷新应用清单」扫描一次（约 1–6 秒）。")
                      : qsTr("换个关键词，或切到「全部应用」分类看看。")
                color: C.textTertiary
                font.pixelSize: 12
                font.family: C.numFont
            }
            GlassButton {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.catalog.length === 0 ? qsTr("刷新应用清单") : qsTr("清空筛选")
                tone: "ghost"
                fontSize: 13
                padH: 18
                minHeight: 36
                onClicked: {
                    if (page.catalog.length === 0) App.refreshAppCatalog()
                    else {
                        page.searchText = ""
                        page.activeCategory = "全部应用"
                    }
                }
            }
        }
    }

    // ---------- 底栏 ----------
    Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 26
        anchors.rightMargin: 26
        anchors.bottomMargin: 20
        height: 34

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("已选择 %1 个应用 · 命中白名单的进程不会被结束").arg(page.allowedList.length)
            color: C.textTertiary
            font.pixelSize: 12
            font.family: C.numFont
        }

        GlassButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("刷新应用清单")
            tone: "ghost"
            fontSize: 12
            padH: 14
            minHeight: 32
            onClicked: App.refreshAppCatalog()
        }
    }

    Component.onCompleted: searchInput.forceActiveFocus()
}