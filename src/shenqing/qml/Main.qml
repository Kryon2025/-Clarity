import QtQuick
import "theme"
import RinUI
import "components"
import "pages"
import "glass"
import "components/Constants.js" as C

FluentWindow {
    id: win

    visible: true
    width: 1080
    height: 720
    minimumWidth: 960
    minimumHeight: 640
    title: qsTr("%1（%2）").arg(App.appName).arg(App.appAlias)

    // 关闭主窗口 = 收进托盘继续运行（真正退出走托盘/速启面板的「退出深清」）
    property bool allowClose: false
    onClosing: function (close) {
        if (!win.allowClose) {
            close.accepted = false
            win.hide()
        }
    }
    titleEnabled: false
    color: "transparent"
    appLayerEnabled: false

    // ================= 导航 / 页面 =================
    // navIndex 保持 0 空间 / 1 数据 / 2 插件 / 3 设置（与 Python 的 page 映射一致）
    // 主题页 / 关于页不占 navIndex，用 showThemePage / showAboutPage 叠加，避免改动 Python 侧映射
    property int navIndex: 0
    property bool showThemePage: false
    property bool showAboutPage: false
    property string overlayMode: "none"        // none | whitelist
    property string whitelistMode: ""           // 白名单浮层当前对应的档位（light / medium / heavy）
    property string whitelistSpaceId: ""        // 白名单浮层当前对应的具体空间 id（v0.6 多空间）
    readonly property int effectivePage: showAboutPage ? 5 : (showThemePage ? 4 : navIndex)

    // 导航轨展开/收起 + 插件入口
    property bool navExpanded: false
    property bool pluginListOpen: false
    property string activePluginPath: ""

    // ================= 全局搜索（v0.6：窗口右上角常驻，所有页面可见） =================
    property bool globalSearchOpen: false
    property string globalSearchText: ""
    readonly property bool globalSearchActive: win.globalSearchOpen
                                                   && win.globalSearchText.trim().length > 0
    readonly property var globalSearchResults: {
        var text = win.globalSearchText.trim()
        if (text.length === 0) return []
        if (typeof App === "undefined" || typeof App.search !== "function") return []
        var list = App.search(text)
        return list ? list : []
    }

    readonly property int railCollapsedWidth: 76
    readonly property int railExpandedWidth: 168
    readonly property int railWidth: navExpanded ? railExpandedWidth : railCollapsedWidth
    readonly property int navItemWidth: navExpanded ? railExpandedWidth - 20 : 56
    readonly property int navItemHeight: 62
    // 液态玻璃高亮块比菜单项大一圈（宽 +16 / 高 +10），圆角跟随
    readonly property int navHighlightWidth: navItemWidth + 16
    readonly property int navHighlightHeight: navItemHeight + 10

    // 页面切换动画开关（截图/低功耗场景可关闭，动画依赖渲染帧，被系统节流时会停在过渡态）
    property bool pageTransitions: true

    // ---------- 专注结束「今日专注卡片」状态 ----------
    property bool sessionWasLocked: false
    property string summarySpaceName: ""
    property string summaryLevel: ""
    property double summaryStartMs: 0
    property int summaryPlannedSeconds: 0

    // ================= 玻璃导航拖拽状态 =================
    property bool navDragActive: false
    property real navDragY: 0
    property int navDragIndex: 0
    property bool navDragSuppressClick: false
    property real navPressY: 0

    // ================= 主题 =================
    readonly property string resolvedThemeMode: (typeof App !== "undefined" && App.themeMode)
                                                ? String(App.themeMode) : "solid"

    // 主题切换：整窗 180ms 透明度脉冲（1 → 0.82 → 1），掩盖配色瞬变
    property real themePulse: 1
    property bool themePulseReady: false
    Timer {
        id: themePulseReadyTimer
        interval: 500
        repeat: false
        running: true
        onTriggered: win.themePulseReady = true
    }
    SequentialAnimation {
        id: themePulseAnim
        NumberAnimation {
            target: win
            property: "themePulse"
            to: 0.82
            duration: 80
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: win
            property: "themePulse"
            to: 1.0
            duration: 100
            easing.type: Easing.OutCubic
        }
    }
    onResolvedThemeModeChanged: {
        var next = win.resolvedThemeMode
        var changed = AppTheme.mode !== next
        AppTheme.mode = next
        if (changed && win.themePulseReady && win.pageTransitions)
            themePulseAnim.restart()
    }

    // 液态玻璃采样源：窗口背景层（渐变 + 光斑 + 噪点）
    readonly property Item glassSource: appBackdrop

    // 白名单归属的空间
    readonly property string spaceId: (typeof App !== "undefined" && App.space && App.space.id !== undefined)
                                      ? String(App.space.id) : ""

    // ---------- 左侧导航分组（v0.5） ----------
    // 上部一组：空间 / 数据 / 插件 / 主题（主题为次级项，视觉稍小）
    // 下部一组：设置 / 关于（贴底，两组之间用留白 + 分隔线分开）
    readonly property var primaryNav: [
        { key: "spaces", label: qsTr("空间"), icon: "ripple", page: 0, entry: 0, secondary: false },
        { key: "stats", label: qsTr("数据"), icon: "waveBars", page: 1, entry: 1, secondary: false },
        { key: "plugins", label: qsTr("插件"), icon: "grid", page: 2, entry: 2, secondary: false },
        { key: "themes", label: qsTr("主题"), icon: "sparkle", page: 4, entry: 3, secondary: true }
    ]
    readonly property var secondaryNav: [
        { key: "settings", label: qsTr("设置"), icon: "shell", page: 3, entry: 4, secondary: false },
        { key: "about", label: qsTr("关于"), icon: "drop", page: 5, entry: 5, secondary: false }
    ]

    // 当前高亮对应的导航项下标：0..3 上部（空间/数据/插件/主题），4..5 下部（设置/关于）
    readonly property int currentNavEntry: {
        if (win.showAboutPage) return 5
        if (win.showThemePage) return 3
        if (win.navIndex === 3) return 4
        return Math.max(0, Math.min(2, win.navIndex))
    }

    Component.onCompleted: {
        navigationView.visible = false
        navigationView.navigationBar.visible = false
        navigationView.navigationBar.titleBarEnabled = false
        if (typeof App.navExpanded !== "undefined")
            win.navExpanded = App.navExpanded === true
        AppTheme.mode = (typeof App !== "undefined" && App.themeMode) ? App.themeMode : "solid"
    }

    background: Backdrop { id: appBackdrop }

    // ================= 导航逻辑 =================
    function toggleNavExpanded() {
        win.navExpanded = !win.navExpanded
        if (typeof App.setNavExpanded === "function")
            App.setNavExpanded(win.navExpanded)
    }

    function selectNav(index) {
        var value = Number(index)
        if (!isFinite(value)) value = 0
        win.navIndex = Math.max(0, Math.min(3, Math.round(value)))
        win.showThemePage = false
        win.showAboutPage = false
        win.activePluginPath = ""
        if (win.navIndex === 2) {
            // 点「插件」：进入插件页并展开/收起入口列表
            win.pluginListOpen = !win.pluginListOpen
        } else {
            win.pluginListOpen = false
        }
    }

    // 直接跳页（搜索 / 拖拽吸附），不做插件列表的展开切换
    function goToPage(index) {
        var value = Number(index)
        if (!isFinite(value)) value = 0
        win.navIndex = Math.max(0, Math.min(3, Math.round(value)))
        win.showThemePage = false
        win.showAboutPage = false
        win.activePluginPath = ""
        win.pluginListOpen = win.navIndex === 2
    }

    function openThemePage(value) {
        win.showThemePage = true
        win.showAboutPage = false
        win.pluginListOpen = false
        win.activePluginPath = ""
        if (themePage && value !== undefined && value !== null && String(value) !== "")
            themePage.highlightValue = String(value)
    }

    function openAboutPage() {
        win.showAboutPage = true
        win.showThemePage = false
        win.pluginListOpen = false
        win.activePluginPath = ""
    }

    function openPluginPage(path, title) {
        win.navIndex = 2
        win.showThemePage = false
        win.showAboutPage = false
        win.pluginListOpen = true
        // 没有独立页面的插件入口：落到插件页（卡片上能看到它的状态/开关）
        win.activePluginPath = path ? String(path) : ""
    }

    // 导航项点击（0..5，含主题 / 关于）
    function selectNavEntry(entry) {
        var value = Number(entry)
        if (!isFinite(value)) return
        if (value === 3) {
            win.openThemePage("")
        } else if (value === 5) {
            win.openAboutPage()
        } else if (value === 4) {
            win.goToPage(3)
        } else {
            win.goToPage(value)
        }
    }

    // 搜索结果跳转（App.search 的 kind: page / theme / mode / plugin / action / space）
    function handleSearchResult(item) {
        if (!item) return
        var kind = String(item.kind !== undefined ? item.kind : "")
        if (kind === "page") {
            win.goToPage(Number(item.payload))
        } else if (kind === "theme") {
            var value = (item.payload !== undefined && item.payload !== null) ? String(item.payload) : ""
            win.openThemePage(value)
        } else if (kind === "mode") {
            // 跳到空间页并切到对应标签
            win.goToPage(0)
            var modeValue = (item.payload !== undefined && item.payload !== null) ? String(item.payload) : ""
            if (modeValue !== "" && spacesPage)
                spacesPage.selectMode(modeValue)
        } else if (kind === "space") {
            win.goToPage(0)
            var payload = item.payload
            var spaceMode = ""
            if (payload !== undefined && payload !== null) {
                if (typeof payload === "object")
                    spaceMode = (payload.mode !== undefined) ? String(payload.mode) : ""
                else
                    spaceMode = String(payload)
            }
            if ((spaceMode === "light" || spaceMode === "medium" || spaceMode === "heavy")
                    && spacesPage)
                spacesPage.selectMode(spaceMode)
        } else if (kind === "plugin") {
            win.goToPage(2)
            win.pluginListOpen = true
        } else if (kind === "action") {
            // 动作结果统一落到设置页，由设置页承接对应开关
            win.goToPage(3)
        }
    }

    // ---------- 全局搜索交互 ----------
    function focusGlobalSearch() {
        win.globalSearchOpen = true
        globalSearchInput.forceActiveFocus()
        globalSearchInput.selectAll()
    }

    function clearGlobalSearch() {
        win.globalSearchText = ""
        win.globalSearchOpen = false
        globalSearchInput.text = ""
        globalSearchInput.focus = false
    }

    function activateFirstSearchResult() {
        if (win.globalSearchResults.length > 0)
            win.applyGlobalSearchResult(win.globalSearchResults[0])
    }

    function applyGlobalSearchResult(item) {
        if (!item) return
        win.handleSearchResult(item)
        win.clearGlobalSearch()
    }

    function searchKindGlyph(kind) {
        if (kind === "page") return "space"
        if (kind === "theme") return "sparkle"
        if (kind === "mode") return "moon"
        if (kind === "space") return "ripple"
        if (kind === "plugin") return "grid"
        if (kind === "action") return "gear"
        return "dot"
    }

    // 专注结束：记录会话信息并弹出今日专注卡片
    function checkFocusSession() {
        var locked = (typeof App !== "undefined" && App.locked === true)
        if (locked && !win.sessionWasLocked) {
            win.sessionWasLocked = true
            win.summarySpaceName = (typeof App.activeSpaceName !== "undefined") ? String(App.activeSpaceName) : ""
            win.summaryLevel = (typeof App.sessionLevel !== "undefined") ? String(App.sessionLevel) : ""
            win.summaryStartMs = Date.now()
            win.summaryPlannedSeconds = (typeof App.totalSeconds !== "undefined") ? Number(App.totalSeconds) : 0
        } else if (!locked && win.sessionWasLocked) {
            win.sessionWasLocked = false
            if (typeof App.previewActive !== "undefined" && App.previewActive === true) return
            var info = (typeof App.lastSession !== "undefined" && App.lastSession !== null) ? App.lastSession : null
            var endMs = Date.now()
            var minutes = 1
            if (win.summaryStartMs > 0)
                minutes = Math.max(1, Math.round((endMs - win.summaryStartMs) / 60000))
            else if (win.summaryPlannedSeconds > 0)
                minutes = Math.max(1, Math.round(win.summaryPlannedSeconds / 60))
            var data = {
                spaceName: win.summarySpaceName,
                level: win.summaryLevel,
                minutes: minutes,
                startMs: win.summaryStartMs > 0 ? win.summaryStartMs : endMs - minutes * 60000,
                endMs: endMs,
                quote: (typeof App.dailyQuote !== "undefined" && App.dailyQuote !== null) ? String(App.dailyQuote) : "",
                avatarUrl: (typeof App.userAvatarUrl !== "undefined" && App.userAvatarUrl !== null) ? String(App.userAvatarUrl) : "",
                wallpaperUrl: (typeof App.bingWallpaperUrl !== "undefined" && App.bingWallpaperUrl !== null) ? String(App.bingWallpaperUrl) : ""
            }
            var card = (typeof App.todayFocusCard !== "undefined" && App.todayFocusCard !== null)
                       ? App.todayFocusCard : null
            if (card !== null) {
                if (card.spaceName !== undefined && String(card.spaceName) !== "")
                    data.spaceName = String(card.spaceName)
                if (card.quote !== undefined) data.quote = String(card.quote)
                if (card.date !== undefined && card.timeRange !== undefined)
                    data.dateText = String(card.date) + " " + String(card.timeRange)
            }
            if (info !== null) {
                if (info.spaceName !== undefined) data.spaceName = String(info.spaceName)
                if (info.level !== undefined) data.level = String(info.level)
                if (info.minutes !== undefined) data.minutes = Math.max(1, Math.round(Number(info.minutes)))
                if (info.startMs !== undefined) data.startMs = Number(info.startMs)
                if (info.endMs !== undefined) data.endMs = Number(info.endMs)
                if (info.quote !== undefined) data.quote = String(info.quote)
                if (info.avatarUrl !== undefined) data.avatarUrl = String(info.avatarUrl)
                if (info.wallpaperUrl !== undefined) data.wallpaperUrl = String(info.wallpaperUrl)
            }
            focusSummary.showSummary(data)
        }
    }

    // ================= 浮层控制 =================
    function openWhitelist(mode, spaceId) {
        win.whitelistMode = (mode !== undefined && mode !== null) ? String(mode) : ""
        win.whitelistSpaceId = (spaceId !== undefined && spaceId !== null) ? String(spaceId) : ""
        win.overlayMode = "whitelist"
    }

    function closeOverlay() {
        win.overlayMode = "none"
    }

    // ================= 导航高亮拖拽（仅液态玻璃主题） =================
    // 导航项中心（rail 坐标系）：上部 4 项与下部 2 项分别从 Repeater 拿实际位置。
    function navEntryCenter(entryIndex) {
        var value = Number(entryIndex)
        if (!isFinite(value)) value = 0
        if (value >= 0 && value <= 3) {
            var primary = primaryNavRepeater.itemAt(value)
            if (primary)
                return primary.mapToItem(rail, primary.width / 2, win.navItemHeight / 2).y
            return 58 + value * 72 + win.navItemHeight / 2
        }
        var secondary = secondaryNavRepeater.itemAt(value - 4)
        if (secondary)
            return secondary.mapToItem(rail, secondary.width / 2, win.navItemHeight / 2).y
        return rail.height - 150 + (value - 4) * 70
    }

    function nearestNavEntry(pointerY) {
        var best = 0
        var bestDistance = 1e9
        for (var i = 0; i < 6; i++) {
            var distance = Math.abs(win.navEntryCenter(i) - pointerY)
            if (distance < bestDistance) {
                bestDistance = distance
                best = i
            }
        }
        return best
    }

    function beginNavDrag(pointerY) {
        if (!AppTheme.glass) return
        win.navDragActive = true
        win.navDragSuppressClick = false
        win.updateNavDrag(pointerY)
    }

    function updateNavDrag(pointerY) {
        if (!win.navDragActive) return
        var first = win.navEntryCenter(0)
        var last = win.navEntryCenter(5)
        var clamped = Math.max(first, Math.min(last, pointerY))
        win.navDragY = clamped - win.navHighlightHeight / 2
        win.navDragIndex = win.nearestNavEntry(clamped)
    }

    function endNavDrag() {
        if (!win.navDragActive) return
        var target = win.navDragIndex
        win.navDragActive = false
        win.navDragSuppressClick = true
        navSuppressTimer.restart()
        // 松手吸附到经过的导航项并切换页面；尺寸由 Behavior 弹性回到 1.0
        win.selectNavEntry(target)
    }

    function cancelNavDrag() {
        win.navDragActive = false
        win.navDragSuppressClick = true
        navSuppressTimer.restart()
    }

    Timer {
        id: navSuppressTimer
        interval: 400
        repeat: false
        onTriggered: win.navDragSuppressClick = false
    }

    // ================= 主体 =================
    Item {
        id: windowRoot
        objectName: "WindowRoot"
        anchors.fill: parent
        // 主题切换时的 180ms 透明度脉冲（不逐项插值颜色）
        opacity: win.themePulse

        // ---------- 内容区（v0.5 去掉顶部菜单栏，导航与页面占满窗口） ----------
        Item {
            id: rootContent
            anchors.fill: parent
            // 让所有后代控件能沿父链自动找到液态玻璃采样源
            property Item glassSource: win.glassSource

            // ---------- 左侧导航玻璃条（可展开/收起） ----------
            LiquidGlass {
                id: railGlass
                visible: AppTheme.glass
                x: 12
                y: 10
                width: win.railWidth
                height: parent.height - 20
                sourceItem: win.glassSource
                radius: 26
                depth: 0.9
                frost: 0.03
                aberration: 0.38
                highlight: 0.7
                whiten: 0.015
                tintAlpha: 0.14
                tint: AppTheme.glassTint
                sheen: 0.3
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                id: railBg
                x: 12
                y: 10
                width: win.railWidth
                height: parent.height - 20
                radius: 26
                color: AppTheme.glass ? "transparent" : AppTheme.cardBg
                border.width: 1
                border.color: AppTheme.glass ? "#2BFFFFFF" : AppTheme.cardBorder
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }

            // 导航容器：不设置 clip，让玻璃高亮可以超出菜单项
            Item {
                id: rail
                x: 12
                y: 10
                width: win.railWidth
                height: parent.height - 20
                clip: false
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                // 展开/收起按钮
                Item {
                    id: railToggle
                    width: 40
                    height: 32
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 12

                    LiquidGlass {
                        anchors.fill: parent
                        visible: AppTheme.glass
                        sourceItem: win.glassSource
                        radius: 12
                        depth: 0.8
                        frost: 0.02
                        aberration: 0.3
                        highlight: 0.85
                        whiten: 0.03
                        tintAlpha: 0.14
                        tint: AppTheme.glassTint
                        sheen: 0.4
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: !AppTheme.glass
                        radius: 12
                        color: railToggleArea.containsMouse ? AppTheme.buttonBgAlt : AppTheme.buttonBg
                        border.width: 1
                        border.color: AppTheme.buttonBorder
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: AppTheme.glass
                        radius: 12
                        color: "transparent"
                        border.width: 1
                        border.color: "#3DFFFFFF"
                    }

                    Glyph {
                        anchors.centerIn: parent
                        kind: win.navExpanded ? "chevronLeft" : "chevron"
                        size: 14
                        color: AppTheme.glass ? "#CFE6EC" : AppTheme.textSecondary
                    }

                    MouseArea {
                        id: railToggleArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.toggleNavExpanded()
                    }
                }

                // 唯一的高亮块：随选中项平滑滑动；玻璃主题下可长按拖拽。
                // 尺寸比菜单项大一圈（宽 +16 / 高 +10），超出部分不被裁掉。
                Item {
                    id: navHighlight
                    objectName: "NavHighlight"
                    width: win.navHighlightWidth
                    height: win.navHighlightHeight
                    x: (rail.width - width) / 2
                    y: win.navDragActive ? win.navDragY
                                         : (win.navEntryCenter(win.currentNavEntry) - height / 2)
                    scale: win.navDragActive ? 1.12 : 1.0

                    Behavior on y {
                        enabled: win.pageTransitions && !win.navDragActive
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        enabled: win.pageTransitions
                        NumberAnimation { duration: 320; easing.type: Easing.OutElastic }
                    }
                    Behavior on width {
                        enabled: win.pageTransitions
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }
                    Behavior on x {
                        enabled: win.pageTransitions
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }

                    LiquidGlass {
                        anchors.fill: parent
                        visible: AppTheme.glass
                        sourceItem: win.glassSource
                        radius: 18
                        depth: 0.55
                        frost: 0.02
                        aberration: 0.28
                        highlight: 0.9
                        whiten: 0.05
                        tintAlpha: 0.3
                        tint: AppTheme.accentSoft
                        sheen: 0.35
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: !AppTheme.glass
                        radius: 18
                        color: AppTheme.accentSoft
                    }
                }

                // 导航项模板（上部 / 下部共用）
                Component {
                    id: navItemDelegate

                    Item {
                        id: navItem
                        width: win.navItemWidth
                        // 插件入口列表展开/收起由 pluginChildrenHost 的 height 动画（200ms）驱动
                        height: win.navItemHeight
                                + ((modelData.page === 2 && pluginChildrenHost.height > 0.01)
                                   ? pluginChildrenHost.height + 4 : 0)

                        readonly property int entryIndex: modelData.entry !== undefined
                                                          ? Number(modelData.entry) : 0
                        readonly property bool secondary: modelData.secondary === true
                        readonly property bool active: win.currentNavEntry === navItem.entryIndex
                        readonly property bool dragPassed: win.navDragActive && win.navDragIndex === navItem.entryIndex
                        readonly property color itemColor: (active || dragPassed)
                                                          ? "#FFFFFF"
                                                          : (AppTheme.glass ? "#9AA8C4" : AppTheme.textSecondary)
                        readonly property int iconSize: navItem.secondary ? 18 : 20
                        readonly property int labelSize: win.navExpanded
                                                        ? (navItem.secondary ? 11 : 12)
                                                        : (navItem.secondary ? 10 : 11)

                        Timer {
                            id: navLongPress
                            interval: 200
                            repeat: false
                            onTriggered: win.beginNavDrag(win.navPressY)
                        }

                        Item {
                            id: navItemBody
                            width: parent.width
                            height: win.navItemHeight

                            // 收起态：图标上、文字下；rail 展开/收起时 200ms 交叉淡变
                            Column {
                                visible: opacity > 0.01
                                opacity: win.navExpanded ? 0 : 1
                                Behavior on opacity {
                                    enabled: win.pageTransitions
                                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                }
                                anchors.centerIn: parent
                                spacing: navItem.secondary ? 4 : 5

                                Glyph {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    kind: modelData.icon
                                    size: navItem.iconSize
                                    color: navItem.itemColor
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    color: navItem.itemColor
                                    font.pixelSize: navItem.labelSize
                                    font.family: C.numFont
                                }
                            }

                            // 展开态：图标与文字并排；与收起态 200ms 交叉淡变
                            Row {
                                visible: opacity > 0.01
                                opacity: win.navExpanded ? 1 : 0
                                Behavior on opacity {
                                    enabled: win.pageTransitions
                                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                }
                                anchors.centerIn: parent
                                spacing: 10

                                Glyph {
                                    kind: modelData.icon
                                    size: navItem.iconSize
                                    color: navItem.itemColor
                                }
                                Text {
                                    text: modelData.label
                                    color: navItem.itemColor
                                    font.pixelSize: navItem.labelSize
                                    font.family: C.numFont
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onPressed: (mouse) => {
                                    if (!AppTheme.glass) return
                                    win.navPressY = mapToItem(rail, mouse.x, mouse.y).y
                                    navLongPress.restart()
                                }
                                onReleased: {
                                    navLongPress.stop()
                                    if (win.navDragActive) win.endNavDrag()
                                }
                                onCanceled: {
                                    navLongPress.stop()
                                    if (win.navDragActive) win.cancelNavDrag()
                                }
                                onPositionChanged: (mouse) => {
                                    if (!AppTheme.glass) return
                                    var point = mapToItem(rail, mouse.x, mouse.y)
                                    if (navLongPress.running || win.navDragActive) {
                                        win.navPressY = point.y
                                        if (win.navDragActive) win.updateNavDrag(point.y)
                                    }
                                }
                                onClicked: {
                                    if (win.navDragSuppressClick) {
                                        win.navDragSuppressClick = false
                                        return
                                    }
                                    win.selectNavEntry(navItem.entryIndex)
                                }
                            }
                        }

                        // 插件入口子项（仅「插件」项下）：高度 200ms 展开/收起
                        Item {
                            id: pluginChildrenHost
                            anchors.top: navItemBody.bottom
                            anchors.topMargin: 4
                            anchors.left: parent.left
                            anchors.right: parent.right
                            clip: true
                            height: (modelData.page === 2 && win.pluginListOpen) ? pluginChildren.implicitHeight : 0
                            visible: modelData.page === 2 && (win.pluginListOpen || height > 0.01)

                            Behavior on height {
                                enabled: win.pageTransitions
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }

                            Column {
                                id: pluginChildren
                                width: parent.width
                                spacing: 4

                                Repeater {
                                    model: (typeof App !== "undefined" && App.pluginNavItems !== undefined)
                                           ? App.pluginNavItems : []

                                    delegate: Item {
                                        width: parent.width
                                        height: 34
                                        readonly property string entryTitle: modelData.title !== undefined ? String(modelData.title) : ""

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 10
                                            color: pluginChildArea.containsMouse
                                                   ? (AppTheme.glass ? "#14FFFFFF" : AppTheme.cardBgAlt)
                                                   : "transparent"
                                        }

                                        Row {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: win.navExpanded ? 30 : 12
                                            spacing: 8

                                            Glyph {
                                                anchors.verticalCenter: parent.verticalCenter
                                                kind: (modelData.icon !== undefined && String(modelData.icon) !== "")
                                                      ? String(modelData.icon) : "grid"
                                                size: 14
                                                color: AppTheme.textSecondary
                                            }

                                            Text {
                                                visible: win.navExpanded
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: win.navItemWidth - 70
                                                text: modelData.title !== undefined ? String(modelData.title) : ""
                                                color: AppTheme.textSecondary
                                                font.pixelSize: 11
                                                font.family: C.numFont
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            id: pluginChildArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: win.openPluginPage(String(modelData.qmlPath),
                                                                          String(modelData.title))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 上部一组：空间 / 数据 / 插件 / 主题
                Column {
                    id: primaryNavColumn
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: railToggle.bottom
                    anchors.topMargin: 14
                    spacing: 10

                    Repeater {
                        id: primaryNavRepeater
                        model: win.primaryNav
                        delegate: navItemDelegate
                    }
                }

                // 下部一组：设置 / 关于（贴底，与上面一组用留白 + 分隔线分开）
                Column {
                    id: secondaryNavColumn
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: versionLabel.top
                    anchors.bottomMargin: 12
                    spacing: 8

                    Rectangle {
                        width: Math.round(win.navItemWidth * 0.62)
                        height: 1
                        x: Math.round((win.navItemWidth - width) / 2)
                        color: AppTheme.glass ? "#2BFFFFFF" : AppTheme.divider
                    }

                    Repeater {
                        id: secondaryNavRepeater
                        model: win.secondaryNav
                        delegate: navItemDelegate
                    }
                }

                Text {
                    id: versionLabel
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    text: "v" + App.version
                    color: AppTheme.textTertiary
                    font.pixelSize: 10
                    font.family: C.numFont
                }
            }

            // ---------- 页面区 ----------
            Item {
                id: pageHost
                anchors.left: rail.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                AnimatedPage {
                    anchors.fill: parent
                    z: win.effectivePage === 0 ? 2 : 1
                    active: win.effectivePage === 0
                    animationsEnabled: win.pageTransitions

                    SpacesPage {
                        id: spacesPage
                        anchors.fill: parent
                        glassSource: win.glassSource
                        animationsEnabled: win.pageTransitions
                        onWhitelistRequested: (mode, spaceId) => win.openWhitelist(mode, spaceId)
                    }
                }

                AnimatedPage {
                    anchors.fill: parent
                    z: win.effectivePage === 1 ? 2 : 1
                    active: win.effectivePage === 1
                    animationsEnabled: win.pageTransitions

                    StatsPage {
                        anchors.fill: parent
                        glassSource: win.glassSource
                    }
                }

                AnimatedPage {
                    anchors.fill: parent
                    z: win.effectivePage === 2 ? 2 : 1
                    active: win.effectivePage === 2
                    animationsEnabled: win.pageTransitions

                    PluginsPage {
                        anchors.fill: parent
                        glassSource: win.glassSource
                    }
                }

                // 插件注册的页面（App.pluginNavItems[].qmlPath，绝对 file:// 路径）
                Loader {
                    id: pluginPageLoader
                    anchors.fill: parent
                    z: 3
                    source: win.activePluginPath !== "" ? win.activePluginPath : ""
                    visible: win.activePluginPath !== ""
                    opacity: win.activePluginPath !== "" ? 1 : 0
                    Behavior on opacity {
                        enabled: win.pageTransitions
                        NumberAnimation { duration: win.activePluginPath !== "" ? 200 : 160; easing.type: Easing.OutCubic }
                    }
                }

                AnimatedPage {
                    anchors.fill: parent
                    z: win.effectivePage === 3 ? 2 : 1
                    active: win.effectivePage === 3
                    animationsEnabled: win.pageTransitions

                    SettingsPage {
                        anchors.fill: parent
                        glassSource: win.glassSource
                        onOnboardingRequested: onboarding.showPages()
                    }
                }

                // 主题页：不占 navIndex，showThemePage 时叠加（浮层式：额外 0.98→1 缩放）
                AnimatedPage {
                    anchors.fill: parent
                    z: win.effectivePage === 4 ? 4 : 1
                    active: win.effectivePage === 4
                    animationsEnabled: win.pageTransitions
                    scaleEnabled: true

                    ThemesPage {
                        id: themePage
                        anchors.fill: parent
                        glassSource: win.glassSource
                    }
                }

                // 关于页：独立 pageKey（effectivePage = 5），不占 navIndex（浮层式：额外 0.98→1 缩放）
                AnimatedPage {
                    anchors.fill: parent
                    z: win.effectivePage === 5 ? 4 : 1
                    active: win.effectivePage === 5
                    animationsEnabled: win.pageTransitions
                    scaleEnabled: true

                    AboutPage {
                        anchors.fill: parent
                        glassSource: win.glassSource
                    }
                }
            }

            // ---------- 全局搜索（窗口右上角常驻，所有页面可见） ----------
            Item {
                id: globalSearchLayer
                anchors.fill: parent
                z: 100

                // 有结果时点击空白处关闭
                MouseArea {
                    anchors.fill: parent
                    visible: win.globalSearchActive
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: win.clearGlobalSearch()
                }

                // 搜索框
                Item {
                    id: globalSearchBox
                    width: 236
                    height: 38
                    anchors.top: parent.top
                    anchors.topMargin: 18
                    anchors.right: parent.right
                    anchors.rightMargin: 24

                    Rectangle {
                        anchors.fill: parent
                        visible: !AppTheme.glass
                        radius: 19
                        color: AppTheme.cardBg
                        border.width: 1
                        border.color: globalSearchInput.activeFocus ? AppTheme.accent : AppTheme.cardBorder
                        Behavior on border.color { ColorAnimation { duration: 140 } }
                    }

                    LiquidGlass {
                        anchors.fill: parent
                        visible: AppTheme.glass
                        sourceItem: win.glassSource
                        radius: 19
                        depth: 0.6
                        frost: 0.02
                        aberration: 0.22
                        highlight: 0.75
                        whiten: 0.03
                        tintAlpha: 0.2
                        tint: AppTheme.glassTint
                        sheen: 0.35
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: AppTheme.glass
                        radius: 19
                        color: "transparent"
                        border.width: 1
                        border.color: globalSearchInput.activeFocus ? AppTheme.accent : "#33FFFFFF"
                    }

                    Glyph {
                        id: globalSearchGlyph
                        anchors.left: parent.left
                        anchors.leftMargin: 13
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "search"
                        size: 14
                        color: globalSearchInput.activeFocus ? AppTheme.accent : AppTheme.textTertiary
                    }

                    TextInput {
                        id: globalSearchInput
                        anchors.left: globalSearchGlyph.right
                        anchors.leftMargin: 8
                        anchors.right: globalSearchClear.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        color: AppTheme.textPrimary
                        selectionColor: AppTheme.accentSoft
                        selectedTextColor: "#FFFFFF"
                        font.pixelSize: 12
                        font.family: C.numFont
                        onTextChanged: {
                            win.globalSearchText = text
                            win.globalSearchOpen = true
                        }
                        Keys.onReturnPressed: win.activateFirstSearchResult()
                        Keys.onEnterPressed: win.activateFirstSearchResult()
                        Keys.onEscapePressed: win.clearGlobalSearch()
                    }

                    // 占位提示放在输入框外面：输入法组合期间不会和候选/正文重叠
                    Text {
                        anchors.left: globalSearchInput.left
                        anchors.right: globalSearchInput.right
                        anchors.verticalCenter: globalSearchInput.verticalCenter
                        visible: globalSearchInput.text.length === 0 && !globalSearchInput.activeFocus
                        text: qsTr("搜索空间 / 主题 / 插件")
                        color: AppTheme.textTertiary
                        font.pixelSize: 12
                        font.family: C.numFont
                        elide: Text.ElideRight
                    }

                    Item {
                        id: globalSearchClear
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        visible: globalSearchInput.text.length > 0

                        Glyph {
                            anchors.centerIn: parent
                            kind: "close"
                            size: 11
                            color: globalSearchClearArea.containsMouse ? AppTheme.textPrimary : AppTheme.textTertiary
                        }

                        MouseArea {
                            id: globalSearchClearArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.clearGlobalSearch()
                        }
                    }
                }

                // 搜索结果面板
                Item {
                    id: globalSearchPanel
                    objectName: "GlobalSearchPanel"
                    visible: win.globalSearchActive || opacity > 0.01
                    opacity: win.globalSearchActive ? 1 : 0
                    scale: win.globalSearchActive ? 1 : 0.96
                    Behavior on opacity {
                        enabled: win.pageTransitions
                        NumberAnimation {
                            duration: win.globalSearchActive ? 140 : 120
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on scale {
                        enabled: win.pageTransitions
                        NumberAnimation {
                            duration: win.globalSearchActive ? 140 : 120
                            easing.type: Easing.OutCubic
                        }
                    }
                    width: 344
                    height: win.globalSearchResults.length === 0
                            ? 54
                            : Math.min(372, win.globalSearchResults.length * 60 + 12)
                    x: globalSearchBox.x + globalSearchBox.width - width
                    y: globalSearchBox.y + globalSearchBox.height + 8

                    Rectangle {
                        anchors.fill: parent
                        visible: !AppTheme.glass
                        radius: 14
                        color: AppTheme.cardBg
                        border.width: 1
                        border.color: AppTheme.cardBorderStrong
                    }

                    LiquidGlass {
                        anchors.fill: parent
                        visible: AppTheme.glass
                        sourceItem: win.glassSource
                        radius: 14
                        depth: 0.85
                        frost: 0.03
                        aberration: 0.35
                        highlight: 0.9
                        whiten: 0.03
                        tintAlpha: 0.24
                        tint: AppTheme.glassTint
                        sheen: 0.4
                    }

                    Text {
                        visible: win.globalSearchResults.length === 0
                        anchors.centerIn: parent
                        text: qsTr("没有找到匹配结果")
                        color: AppTheme.textTertiary
                        font.pixelSize: 12
                        font.family: C.numFont
                    }

                    ListView {
                        id: globalResultsList
                        anchors.fill: parent
                        anchors.margins: 5
                        visible: win.globalSearchResults.length > 0
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: win.globalSearchResults
                        spacing: 3

                        delegate: Item {
                            id: resultDelegate
                            width: globalResultsList.width
                            height: Math.max(56, resultTextCol.implicitHeight + 18)
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                radius: 9
                                color: globalResultArea.containsMouse
                                       ? (AppTheme.glass ? "#1FFFFFFF" : AppTheme.cardBgAlt)
                                       : "transparent"
                                // 结果行 hover 只做底色 90ms 淡变，不位移
                                Behavior on color {
                                    enabled: win.pageTransitions
                                    ColorAnimation { duration: 90 }
                                }
                            }

                            Glyph {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.top: parent.top
                                anchors.topMargin: 13
                                kind: win.searchKindGlyph(String(modelData.kind))
                                size: 15
                                color: AppTheme.accent
                            }

                            Column {
                                id: resultTextCol
                                width: resultDelegate.width - 36 - 14
                                anchors.left: parent.left
                                anchors.leftMargin: 36
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Text {
                                    width: parent.width
                                    text: modelData.title !== undefined ? String(modelData.title) : ""
                                    color: AppTheme.textPrimary
                                    font.pixelSize: 13
                                    font.family: C.numFont
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.sub !== undefined ? String(modelData.sub) : ""
                                    color: AppTheme.textTertiary
                                    font.pixelSize: 11
                                    font.family: C.numFont
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    maximumLineCount: 1
                                }
                            }

                            MouseArea {
                                id: globalResultArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.applyGlobalSearchResult(modelData)
                            }
                        }
                    }
                }

                Shortcut {
                    sequences: ["Ctrl+K", "Ctrl+F"]
                    onActivated: win.focusGlobalSearch()
                }
            }

            // ---------- 浮层（白名单） ----------
            Item {
                id: overlayLayer
                objectName: "OverlayLayer"
                anchors.fill: parent
                z: 300
                // 关闭时要等 scrim / 内容淡出动画结束再真正隐藏
                visible: win.overlayMode !== "none" || scrim.opacity > 0.001
                focus: visible
                Keys.onEscapePressed: win.closeOverlay()

                Rectangle {
                    id: scrim
                    objectName: "OverlayScrim"
                    anchors.fill: parent
                    color: "#05070A"
                    opacity: win.overlayMode !== "none" ? C.scrimOpacity : 0
                    Behavior on opacity { enabled: win.pageTransitions; NumberAnimation { duration: 220 } }
                }

                // 拦截下层点击
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onClicked: {}
                }

                WhitelistPage {
                    anchors.fill: parent
                    anchors.margins: 16
                    glassSource: win.glassSource
                    spaceId: win.whitelistSpaceId
                    mode: win.whitelistMode
                    visible: win.overlayMode === "whitelist" || opacity > 0.01
                    opacity: win.overlayMode === "whitelist" ? 1 : 0
                    scale: win.overlayMode === "whitelist" ? 1 : 0.98
                    Behavior on opacity {
                        enabled: win.pageTransitions
                        NumberAnimation {
                            duration: win.overlayMode === "whitelist" ? 200 : 160
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on scale {
                        enabled: win.pageTransitions
                        NumberAnimation {
                            duration: win.overlayMode === "whitelist" ? 200 : 160
                            easing.type: Easing.OutCubic
                        }
                    }
                    transform: Translate {
                        y: win.overlayMode === "whitelist" ? 0 : 24
                        Behavior on y {
                            enabled: win.pageTransitions
                            NumberAnimation {
                                duration: win.overlayMode === "whitelist" ? 220 : 160
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                    onBackRequested: win.closeOverlay()
                }
            }
        }
    }

    // ---------- 新手引导（首次启动 / 设置页手动打开） ----------
    Onboarding {
        id: onboarding
        animationsEnabled: win.pageTransitions
    }

    // ---------- 进入专注前的 10 秒倒计时（水滴凝聚） ----------
    EnterCountdown {
        animationsEnabled: win.pageTransitions
    }

    // ---------- 专注结束「今日专注卡片」 ----------
    FocusSummary {
        id: focusSummary
        animationsEnabled: win.pageTransitions
    }

    // ---------- 重度锁机全屏遮罩 ----------
    LockOverlay {
        animationsEnabled: win.pageTransitions
    }

    Connections {
        target: (typeof App !== "undefined") ? App : null
        function onLockedChanged() { win.checkFocusSession() }
    }
}