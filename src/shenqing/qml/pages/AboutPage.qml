import QtQuick
import "../theme"
import "../components"
import "../glass"
import "../components/Constants.js" as C

// 关于页（v0.6，参考 CW2 / ClassWidgets2 关于页）
// - 头部卡片：大 logo + 「深清 Clarity」+ 版本 + 一句简介 + 一排操作按钮
// - 更新日志卡片：App.changelog（version/date/tag/items），默认展开最新版本，旧版本点击折叠/展开
// - 下面依次是使用说明 / 帮助与反馈 / 开源许可与第三方组件 / 数据目录
// - 页面进入动画由 Main.qml 的 AnimatedPage 负责；这里只做折叠展开 180ms 动画
Item {
    id: page

    property Item glassSource: null
    // Main.pageTransitions 传入；false 时折叠/展开动画瞬时
    property bool animationsEnabled: true

    readonly property string appVersion: (typeof App !== "undefined" && App.version !== undefined)
                                         ? String(App.version) : "0.6.0"
    readonly property string appNameText: (typeof App !== "undefined" && App.appName !== undefined)
                                          ? String(App.appName) : qsTr("深清")
    readonly property string repoUrl: "https://github.com/Kryon2025/Clarity"

    // ---------- 更新日志 ----------
    // 展开状态按版本号记录（语言切换重建列表时仍保留）
    property var expandedVersions: ({})
    property int expandTick: 0

    readonly property var changelogData: {
        // 读语言属性：切换语言时重新求值（后端 changelog 通知也是 languageChanged）
        var lang = (typeof App !== "undefined" && App.language !== undefined) ? String(App.language) : ""
        if (typeof App !== "undefined" && App.changelog && App.changelog.length > 0)
            return App.changelog
        return [
            {
                version: "0.6.0",
                date: "2025-11-03",
                tag: "beta",
                items: [
                    qsTr("空间页改为浅清 / 覆清 / 深清三个标签页，卡片两列列表式布局，支持新增 / 删除 / 就地改名空间"),
                    qsTr("全局搜索：窗口右上角常驻，支持空间 / 主题 / 模式 / 插件 / 设置（Ctrl+K）"),
                    qsTr("完善全局动画：页面切换、标签指示器、卡片增删、浮层、遮罩与主题切换过渡")
                ]
            },
            {
                version: "0.5.0",
                date: "2025-11-03",
                tag: "",
                items: [qsTr("三档空间模型：浅清 / 覆清 / 深清各一个空间")]
            }
        ]
    }

    function versionExpanded(version, index) {
        var key = String(version)
        if (page.expandedVersions[key] !== undefined)
            return page.expandedVersions[key] === true
        return index === 0
    }

    function toggleVersionAt(index) {
        var list = page.changelogData
        if (index < 0 || index >= list.length) return
        var version = String(list[index].version)
        var map = page.expandedVersions
        map[version] = !page.versionExpanded(version, index)
        page.expandedVersions = map
        page.expandTick++
    }

    // ---------- 检查更新（后端未接：本地提示） ----------
    property bool updateHintVisible: false
    property string updateHintText: ""
    Timer {
        id: updateHintTimer
        interval: 2800
        repeat: false
        onTriggered: page.updateHintVisible = false
    }
    function checkUpdate() {
        page.updateHintText = qsTr("已是最新版本 v%1 · 自动更新将在后续版本提供").arg(page.appVersion)
        page.updateHintVisible = true
        updateHintTimer.restart()
    }

    function openFeedback(kind) {
        if (typeof App !== "undefined" && typeof App.openFeedback === "function")
            App.openFeedback(String(kind))
    }

    // ---------- 下方信息分区 ----------
    readonly property var sections: [
        {
            key: "usage",
            title: qsTr("使用说明"),
            icon: "leaf",
            items: [
                { label: qsTr("标签页切换档位"), desc: qsTr("三个标签页代表三档强度，切换后下方两列卡片只显示该档位的空间。") },
                { label: qsTr("多空间：浅清 / 覆清"), desc: qsTr("浅清与覆清可以新增多个空间，每个空间各自保存名称、时长与白名单；点空间名可就地改名（最多 20 字）。") },
                { label: qsTr("深清固定一个空间"), desc: qsTr("深清只有一个固定空间「深清空间」，不可新增、删除或改名，只能改时长与白名单。") },
                { label: qsTr("白名单按空间独立"), desc: qsTr("每个空间各自保存允许使用的应用，命中白名单的进程不会被结束。") },
                { label: qsTr("深清不可提前结束"), desc: qsTr("深清开始后会显示全屏倒计时遮罩，没有暂停与提前结束，到点自动结束。") },
                { label: qsTr("关闭窗口进托盘"), desc: qsTr("点窗口关闭按钮不会退出深清，专注继续在后台运行；真正退出要走托盘或速启面板。") },
                { label: qsTr("专注记录"), desc: qsTr("完成的专注可以在「数据」页查看历史与统计。") }
            ]
        },
        {
            key: "feedback",
            title: qsTr("帮助与反馈"),
            icon: "wave",
            items: [
                { label: qsTr("反馈入口"), desc: qsTr("点击页面顶部的「功能请求」或「Bug 反馈」按钮，会在浏览器中打开 GitHub Issues。") },
                { label: qsTr("参与讨论"), desc: qsTr("使用问题与想法可以到 GitHub Discussions 交流；也可以先查看 README 与 docs/ 下的文档。") }
            ]
        },
        {
            key: "license",
            title: qsTr("开源许可与第三方组件"),
            icon: "sparkle",
            items: [
                { label: qsTr("深清（Clarity）"), desc: qsTr("专有软件（Proprietary），保留所有权利。") },
                { label: "Qt / PySide6", desc: qsTr("LGPLv3") },
                { label: "RinUI", desc: "MIT" }
            ]
        },
        {
            key: "data",
            title: qsTr("数据目录"),
            icon: "grid",
            items: [
                { label: "%APPDATA%\\ShenQing\\", desc: qsTr("空间、设置、插件与专注统计都保存在本机，不上传云端。") }
            ]
        }
    ]

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageColumn.height + 64
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: pageColumn
            width: Math.min(flick.width - 96, 820)
            x: (flick.width - width) / 2
            y: 24
            spacing: 16

            // ================= 头部卡片 =================
            GlassCard {
                id: headerCard
                objectName: "AboutHeaderCard"
                width: pageColumn.width
                height: headerColumn.implicitHeight + 44
                radius: 24
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: headerColumn
                    x: 22
                    y: 22
                    width: parent.width - 44
                    spacing: 16

                    Row {
                        width: parent.width
                        spacing: 18

                        Rectangle {
                            width: 76
                            height: 76
                            radius: 24
                            anchors.verticalCenter: parent.verticalCenter
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#7FE7DA" }
                                GradientStop { position: 0.55; color: "#2ED3C6" }
                                GradientStop { position: 1.0; color: "#1F6FD0" }
                            }
                            border.width: 1
                            border.color: "#66FFFFFF"

                            Glyph {
                                anchors.centerIn: parent
                                kind: "drop"
                                size: 38
                                color: "#04222B"
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Row {
                                spacing: 10

                                Text {
                                    text: page.appNameText
                                    color: AppTheme.textPrimary
                                    font.pixelSize: 32
                                    font.weight: Font.Bold
                                    font.family: C.numFont
                                    font.letterSpacing: 2
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Clarity"
                                    color: AppTheme.textSecondary
                                    font.pixelSize: 18
                                    font.family: C.numFont
                                    font.letterSpacing: 1
                                }
                            }

                            Text {
                                text: qsTr("v%1 · Windows 专注锁机工具").arg(page.appVersion)
                                color: AppTheme.accent
                                font.pixelSize: 13
                                font.family: C.numFont
                            }

                            Text {
                                width: headerColumn.width - 100
                                text: qsTr("选好模式与时长，时间没到不开门。三档空间、各自白名单，专注记录保存在本机。")
                                color: AppTheme.textSecondary
                                font.pixelSize: 12
                                font.family: C.numFont
                                wrapMode: Text.WordWrap
                                lineHeight: 1.2
                            }
                        }
                    }

                    // 一排操作按钮（无 hover 动画；GlassButton 自带按下反馈）
                    Row {
                        spacing: 10

                        GlassButton {
                            text: qsTr("检查更新")
                            tone: "tinted"
                            fontSize: 13
                            padH: 18
                            minHeight: 36
                            onClicked: page.checkUpdate()
                        }

                        GlassButton {
                            text: qsTr("项目主页")
                            tone: "ghost"
                            fontSize: 13
                            padH: 18
                            minHeight: 36
                            onClicked: Qt.openUrlExternally(page.repoUrl)
                        }

                        GlassButton {
                            text: qsTr("功能请求")
                            tone: "ghost"
                            fontSize: 13
                            padH: 18
                            minHeight: 36
                            onClicked: page.openFeedback("request")
                        }

                        GlassButton {
                            text: qsTr("Bug 反馈")
                            tone: "ghost"
                            fontSize: 13
                            padH: 18
                            minHeight: 36
                            onClicked: page.openFeedback("bug")
                        }
                    }

                    // 检查更新的本地提示（后端暂未接自动更新）
                    Text {
                        width: parent.width
                        text: page.updateHintText
                        color: AppTheme.accent
                        font.pixelSize: 12
                        font.family: C.numFont
                        visible: opacity > 0.01
                        opacity: page.updateHintVisible ? 1 : 0
                        Behavior on opacity {
                            enabled: page.animationsEnabled !== false
                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            // ================= 更新日志卡片 =================
            GlassCard {
                id: changelogCard
                objectName: "ChangelogCard"
                width: pageColumn.width
                height: changelogColumn.implicitHeight + 40
                radius: 22
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: changelogColumn
                    x: 20
                    y: 20
                    width: parent.width - 40
                    spacing: 12

                    Item {
                        width: parent.width
                        height: 26

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 9

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                kind: "clock"
                                size: 16
                                color: AppTheme.accent
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("更新日志")
                                color: AppTheme.textPrimary
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                font.family: C.numFont
                            }
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("共 %1 个版本").arg(page.changelogData.length)
                            color: AppTheme.textTertiary
                            font.pixelSize: 11
                            font.family: C.numFont
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: AppTheme.divider
                    }

                    Column {
                        id: changelogEntries
                        width: parent.width
                        spacing: 4

                        Repeater {
                            id: changelogRepeater
                            model: page.changelogData

                            delegate: Item {
                                id: entry
                                objectName: "ChangelogEntry"
                                width: changelogEntries.width
                                height: entryHeader.height + entryBody.height

                                readonly property int entryIndex: index
                                readonly property var entryData: modelData
                                readonly property string entryVersion: entryData.version !== undefined
                                                                       ? String(entryData.version) : ""
                                readonly property string entryDate: entryData.date !== undefined
                                                                    ? String(entryData.date) : ""
                                readonly property string entryTag: entryData.tag !== undefined
                                                                   ? String(entryData.tag) : ""
                                readonly property var entryItems: entryData.items !== undefined
                                                                  ? entryData.items : []
                                readonly property bool expanded: {
                                    // 依赖 expandTick，点击后重新求值
                                    var tick = page.expandTick
                                    return page.versionExpanded(entry.entryVersion, entry.entryIndex)
                                }

                                // ---- 版本行 ----
                                Item {
                                    id: entryHeader
                                    x: 0
                                    y: 0
                                    width: parent.width
                                    height: 42

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: headerArea.containsMouse
                                               ? (AppTheme.glass ? "#10FFFFFF" : AppTheme.cardBgAlt)
                                               : "transparent"
                                    }

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        Rectangle {
                                            width: versionLabel.implicitWidth + 18
                                            height: 22
                                            radius: 11
                                            color: AppTheme.glass ? "#262ED3C6" : "#E4F4F2"
                                            border.width: 1
                                            border.color: AppTheme.accent

                                            Text {
                                                id: versionLabel
                                                anchors.centerIn: parent
                                                text: "v" + entry.entryVersion
                                                color: AppTheme.accent
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                font.family: C.numFont
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: entry.entryDate
                                            color: AppTheme.textTertiary
                                            font.pixelSize: 11
                                            font.family: C.numFont
                                        }

                                        Rectangle {
                                            visible: entry.entryTag !== ""
                                            width: tagLabel.implicitWidth + 14
                                            height: 19
                                            radius: 9.5
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: AppTheme.glass ? "#1FFFFFFF" : AppTheme.chipBg
                                            border.width: 1
                                            border.color: AppTheme.cardBorder

                                            Text {
                                                id: tagLabel
                                                anchors.centerIn: parent
                                                text: entry.entryTag
                                                color: AppTheme.textSecondary
                                                font.pixelSize: 10
                                                font.family: C.numFont
                                            }
                                        }
                                    }

                                    Glyph {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        kind: "chevron"
                                        size: 12
                                        color: entry.expanded ? AppTheme.accent : AppTheme.textTertiary
                                        rotation: entry.expanded ? 90 : 0
                                        Behavior on rotation {
                                            enabled: page.animationsEnabled !== false
                                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                        }
                                    }

                                    MouseArea {
                                        id: headerArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: page.toggleVersionAt(entry.entryIndex)
                                    }
                                }

                                // ---- 展开内容（180ms 高度动画 + 淡入） ----
                                Item {
                                    id: entryBody
                                    objectName: "ChangelogEntryBody"
                                    x: 0
                                    y: entryHeader.height
                                    width: parent.width
                                    height: entry.expanded ? entryBodyColumn.implicitHeight + 10 : 0
                                    clip: true
                                    opacity: entry.expanded ? 1 : 0

                                    Behavior on height {
                                        enabled: page.animationsEnabled !== false
                                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on opacity {
                                        enabled: page.animationsEnabled !== false
                                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                    }

                                    Column {
                                        id: entryBodyColumn
                                        x: 8
                                        y: 6
                                        width: parent.width - 16
                                        spacing: 6

                                        Repeater {
                                            model: entry.entryItems

                                            delegate: Row {
                                                width: entryBodyColumn.width
                                                spacing: 8

                                                Rectangle {
                                                    width: 4
                                                    height: 4
                                                    radius: 2
                                                    anchors.top: parent.top
                                                    anchors.topMargin: 7
                                                    color: AppTheme.accent
                                                }

                                                Text {
                                                    width: parent.width - 12
                                                    text: String(modelData)
                                                    color: AppTheme.textSecondary
                                                    font.pixelSize: 12
                                                    font.family: C.numFont
                                                    wrapMode: Text.WordWrap
                                                    lineHeight: 1.25
                                                }
                                            }
                                        }
                                    }
                                }

                                // 版本之间细分隔线
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 1
                                    color: AppTheme.divider
                                    visible: entry.entryIndex < page.changelogData.length - 1
                                }
                            }
                        }
                    }
                }
            }

            // ================= 分区卡片：使用说明 / 帮助与反馈 / 许可 / 数据目录 =================
            Repeater {
                model: page.sections

                delegate: GlassCard {
                    id: sectionCard
                    width: pageColumn.width
                    height: sectionColumn.implicitHeight + 40
                    radius: 20
                    interactive: false
                    glassSource: page.glassSource

                    readonly property var sectionData: modelData

                    Column {
                        id: sectionColumn
                        x: 20
                        y: 20
                        width: parent.width - 40
                        spacing: 12

                        Row {
                            width: parent.width
                            spacing: 9

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                kind: sectionCard.sectionData.icon !== undefined
                                      ? String(sectionCard.sectionData.icon) : "sparkle"
                                size: 16
                                color: AppTheme.accent
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: sectionCard.sectionData.title !== undefined
                                      ? String(sectionCard.sectionData.title) : ""
                                color: AppTheme.textPrimary
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                font.family: C.numFont
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: AppTheme.divider
                        }

                        Column {
                            width: parent.width
                            spacing: 10

                            Repeater {
                                model: sectionCard.sectionData.items

                                delegate: Item {
                                    width: parent.width
                                    height: entryColumn.implicitHeight + 2

                                    Row {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        spacing: 10

                                        Rectangle {
                                            width: 5
                                            height: 5
                                            radius: 2.5
                                            anchors.top: parent.top
                                            anchors.topMargin: 6
                                            color: AppTheme.accent
                                        }

                                        Column {
                                            id: entryColumn
                                            width: parent.width - 15
                                            spacing: 2

                                            Text {
                                                width: parent.width
                                                text: modelData.label !== undefined ? String(modelData.label) : ""
                                                color: AppTheme.textPrimary
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                font.family: C.numFont
                                                wrapMode: Text.WordWrap
                                            }

                                            Text {
                                                width: parent.width
                                                visible: modelData.desc !== undefined && String(modelData.desc) !== ""
                                                text: modelData.desc !== undefined ? String(modelData.desc) : ""
                                                color: AppTheme.textSecondary
                                                font.pixelSize: 12
                                                font.family: C.numFont
                                                wrapMode: Text.WordWrap
                                                lineHeight: 1.25
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- 底部说明 ----------
            Text {
                width: parent.width
                text: qsTr("%1（Clarity）v%2 · 界面 v0.6 · 数据保存在 %APPDATA%\\ShenQing\\")
                      .arg(page.appNameText).arg(page.appVersion)
                color: AppTheme.textTertiary
                font.pixelSize: 11
                font.family: C.numFont
                wrapMode: Text.WordWrap
            }

            Item { width: parent.width; height: 2 }
        }
    }

    // 纤细滚动指示
    Rectangle {
        id: scrollThumb
        visible: flick.contentHeight > flick.height + 4
        width: 4
        radius: 2
        color: AppTheme.glass ? "#26FFFFFF" : AppTheme.divider
        x: flick.width - 14
        height: Math.max(48, flick.height * flick.height / Math.max(1, flick.contentHeight))
        y: 18 + Math.max(0, Math.min(1, flick.contentY / Math.max(1, flick.contentHeight - flick.height)))
           * Math.max(1, flick.height - 36 - height)
    }
}
