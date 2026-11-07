import QtQuick
import "../theme"
import "../components"
import "../glass"
import "../components/Constants.js" as C

// 数据页（v0.8 Patina 风格骨架）
// - 顶部统计卡片横排：今日专注次数 / 今日时长 / 连续打卡 / 今日会话
// - 最近 7 天柱状图
// - 最近会话列表（后端 session 明细接口未就绪时显示今日汇总占位）
Item {
    id: page

    property Item glassSource: null

    // v0.9 应用使用时长：截图 harness 可注入演示数据；正式运行取后端接口
    property var demoUsageToday: null
    property var demoUsageWeek: null
    property var demoCategories: null
    property int usageRange: 0   // 0=今日，1=本周
    readonly property var appUsageColors: ["#2ED3C6", "#7FB6FF", "#F2C879", "#C9A7FF",
                                           "#F27E7E", "#8FD1A8", "#E8B86B", "#7ED7E8"]
    function itemName(item) {
        if (item === null || item === undefined) return ""
        if (item.name !== undefined) return String(item.name)
        if (item.app !== undefined) return String(item.app)
        if (item.title !== undefined) return String(item.title)
        return String(item)
    }
    function itemMinutes(item) {
        if (item === null || item === undefined) return 0
        if (item.minutes !== undefined) return Math.max(0, Number(item.minutes) || 0)
        if (item.duration !== undefined) return Math.max(0, Number(item.duration) || 0)
        return 0
    }
    function itemColor(item, index) {
        if (item !== null && item !== undefined && item.color !== undefined && String(item.color) !== "")
            return String(item.color)
        return page.appUsageColors[index % page.appUsageColors.length]
    }
    readonly property var rawAppUsage: {
        if (page.usageRange === 0) {
            if (page.demoUsageToday !== null) return page.demoUsageToday
            return (typeof App !== "undefined" && App.appUsageToday !== undefined && App.appUsageToday !== null)
                   ? App.appUsageToday : []
        }
        if (page.demoUsageWeek !== null) return page.demoUsageWeek
        return (typeof App !== "undefined" && App.appUsageWeek !== undefined && App.appUsageWeek !== null)
               ? App.appUsageWeek : []
    }
    readonly property var appUsage: {
        var out = []
        for (var i = 0; i < page.rawAppUsage.length; i++)
            out.push(page.rawAppUsage[i])
        out.sort(function (a, b) { return page.itemMinutes(b) - page.itemMinutes(a) })
        return out
    }
    readonly property real appUsageMax: {
        var maxValue = 1
        for (var i = 0; i < page.appUsage.length; i++)
            maxValue = Math.max(maxValue, page.itemMinutes(page.appUsage[i]))
        return maxValue
    }
    readonly property var rawCategories: {
        if (page.demoCategories !== null) return page.demoCategories
        return (typeof App !== "undefined" && App.appCategories !== undefined && App.appCategories !== null)
               ? App.appCategories : []
    }
    readonly property var appCategories: {
        var out = []
        for (var i = 0; i < page.rawCategories.length; i++)
            out.push(page.rawCategories[i])
        out.sort(function (a, b) { return page.itemMinutes(b) - page.itemMinutes(a) })
        return out
    }
    readonly property real categoryTotal: {
        var total = 0
        for (var i = 0; i < page.appCategories.length; i++)
            total += page.itemMinutes(page.appCategories[i])
        return total
    }
    function usageMinutesText(minutes) {
        var m = Math.round(Number(minutes) || 0)
        if (m >= 60) return qsTr("%1 小时 %2 分钟").arg(Math.floor(m / 60)).arg(m % 60)
        return qsTr("%1 分钟").arg(m)
    }

    readonly property var days: (typeof App !== "undefined" && App.last7Days !== undefined) ? App.last7Days : []
    readonly property int todaySessions: (typeof App !== "undefined" && App.todaySessions !== undefined)
                                         ? Number(App.todaySessions) : 0
    readonly property real todayMinutes: (typeof App !== "undefined" && App.todayMinutes !== undefined)
                                         ? Number(App.todayMinutes) : 0
    readonly property int streakDays: (typeof App !== "undefined" && App.streakDays !== undefined)
                                      ? Number(App.streakDays) : 0
    readonly property var focusCard: (typeof App !== "undefined" && App.todayFocusCard !== undefined
                                      && App.todayFocusCard !== null) ? App.todayFocusCard : ({})
    readonly property var recentSessions: (typeof App !== "undefined" && App.recentSessions !== undefined
                                           && App.recentSessions !== null) ? App.recentSessions : []
    readonly property var recentRows: {
        var out = []
        for (var i = 0; i < page.recentSessions.length && i < 6; i++)
            out.push(page.recentSessions[i])
        return out
    }
    function timeOf(ms) {
        if (ms === undefined || ms === null || Number(ms) <= 0) return ""
        var d = new Date(Number(ms))
        function two(n) { return n < 10 ? "0" + n : String(n) }
        return two(d.getHours()) + ":" + two(d.getMinutes())
    }
    readonly property int cardSessions: (focusCard.sessions !== undefined) ? Number(focusCard.sessions) : 0

    readonly property real dayMax: {
        var maxValue = 60
        for (var i = 0; i < page.days.length; i++) {
            var m = Number(page.days[i].minutes) || 0
            if (m > maxValue) maxValue = m
        }
        return maxValue
    }
    readonly property real weekTotal: {
        var total = 0
        for (var i = 0; i < page.days.length; i++) total += Number(page.days[i].minutes) || 0
        return total
    }

    readonly property var statCards: [
        { label: qsTr("今日专注"), value: page.todaySessions, unit: qsTr("次"), accent: "#2ED3C6" },
        { label: qsTr("今日时长"), value: Math.round(page.todayMinutes), unit: qsTr("分钟"), accent: "#7FB6FF" },
        { label: qsTr("连续打卡"), value: page.streakDays, unit: qsTr("天"), accent: "#F2C879" },
        { label: qsTr("今日会话"), value: page.cardSessions, unit: qsTr("次"), accent: "#C9A7FF" }
    ]

    // ---------- v0.13：横向分类 ----------
    property int section: 0
    property var demoUsageApps: null
    property var demoCategoryOptions: null
    property var demoHeatmap: null
    property var demoHourly: null
    property int categoryMenuRow: -1
    property real categoryMenuX: 0
    property real categoryMenuY: 0
    property real categoryMenuW: 120

    readonly property var usageApps: page.demoUsageApps !== null ? page.demoUsageApps
                                    : ((typeof App !== "undefined" && App.appUsageApps !== undefined
                                        && App.appUsageApps !== null) ? App.appUsageApps : [])
    readonly property var categoryOptions: page.demoCategoryOptions !== null ? page.demoCategoryOptions
                                    : ((typeof App !== "undefined" && App.appCategoryOptions !== undefined
                                        && App.appCategoryOptions !== null) ? App.appCategoryOptions
                                       : [{ value: "dev", label: qsTr("开发") },
                                          { value: "browser", label: qsTr("浏览") },
                                          { value: "social", label: qsTr("沟通") },
                                          { value: "other", label: qsTr("其他") }])
    function appExe(item) {
        if (item !== null && item.exe !== undefined) return String(item.exe)
        return ""
    }
    function appCategory(item) {
        if (item !== null && item.category !== undefined) return String(item.category)
        return ""
    }
    function optionLabel(value) {
        for (var i = 0; i < page.categoryOptions.length; i++)
            if (String(page.categoryOptions[i].value) === String(value))
                return String(page.categoryOptions[i].label)
        return String(value)
    }
    function openCategoryMenu(rowItem, index) {
        var point = rowItem.mapToItem(page, 0, rowItem.height + 4)
        page.categoryMenuRow = index
        page.categoryMenuW = 120
        page.categoryMenuX = Math.max(8, Math.min(page.width - 128, point.x))
        page.categoryMenuY = Math.max(8, Math.min(page.height - 220, point.y))
    }
    function selectCategory(item, value) {
        var exe = page.appExe(item)
        page.categoryMenuRow = -1
        if (typeof App !== "undefined" && typeof App.setAppCategory === "function" && exe !== "")
            App.setAppCategory(exe, String(value))
    }
    function resetCategory(item) {
        var exe = page.appExe(item)
        if (typeof App !== "undefined" && typeof App.resetAppCategory === "function" && exe !== "")
            App.resetAppCategory(exe)
    }

    // 90 天热力图（列=周、行=星期，GitHub 风格）
    readonly property var heatmapCells: {
        var values = page.demoHeatmap
        if (values === null && typeof App !== "undefined" && App.appUsageHeatmap !== undefined)
            values = App.appUsageHeatmap
        var map = ({})
        if (values !== null && values !== undefined) {
            if (values.length !== undefined) {
                for (var i = 0; i < values.length; i++) {
                    var item = values[i]
                    if (item !== null && item.date !== undefined)
                        map[String(item.date)] = Number(item.minutes) || 0
                }
            } else {
                for (var key in values) map[String(key)] = Number(values[key]) || 0
            }
        }
        var today = new Date()
        today.setHours(0, 0, 0, 0)
        var cells = []
        for (var w = 12; w >= 0; w--) {
            for (var d = 0; d < 7; d++) {
                var dt = new Date(today.getTime())
                dt.setDate(today.getDate() - (w * 7 + (6 - d)))
                var fs = function (n) { return n < 10 ? "0" + n : String(n) }
                var dateText = dt.getFullYear() + "-" + fs(dt.getMonth() + 1) + "-" + fs(dt.getDate())
                cells.push({ date: dateText, minutes: Number(map[dateText] || 0) })
            }
        }
        return cells
    }
    readonly property real heatmapMax: {
        var maxValue = 1
        for (var i = 0; i < page.heatmapCells.length; i++)
            maxValue = Math.max(maxValue, Number(page.heatmapCells[i].minutes) || 0)
        return maxValue
    }
    readonly property bool heatmapEmpty: page.heatmapMax <= 1
    function heatColor(minutes) {
        if (Number(minutes) <= 0) return AppTheme.glass ? "#12FFFFFF" : AppTheme.divider
        var ratio = Number(minutes) / Math.max(1, page.heatmapMax)
        if (ratio > 0.75) return "#2ED3C6"
        if (ratio > 0.5) return "#2ED3C6"
        if (ratio > 0.25) return "#1E9E95"
        return "#176B68"
    }
    readonly property var hourlyValues: {
        var values = page.demoHourly
        if (values === null && typeof App !== "undefined" && App.appUsageHourly !== undefined)
            values = App.appUsageHourly
        var out = []
        for (var h = 0; h < 24; h++) {
            var v = 0
            if (values !== null && values !== undefined) {
                if (values.length !== undefined && values.length >= 24) {
                    var item = values[h]
                    v = (item !== null && item !== undefined && item.minutes !== undefined)
                        ? Number(item.minutes) : Number(item)
                } else if (values.length === undefined) {
                    v = Number(values[String(h)] || values[h] || 0)
                }
            }
            out.push(isFinite(v) ? v : 0)
        }
        return out
    }
    readonly property real hourlyMax: {
        var maxValue = 1
        for (var i = 0; i < page.hourlyValues.length; i++)
            maxValue = Math.max(maxValue, Number(page.hourlyValues[i]) || 0)
        return maxValue
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageColumn.height + 64
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: pageColumn
            width: Math.min(flick.width - 96, 860)
            x: (flick.width - width) / 2
            y: 24
            spacing: 16

            // ---------- 页头 ----------
            Item {
                width: parent.width
                height: 78

                Column {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 6

                    Text {
                        text: qsTr("数据")
                        color: AppTheme.textPrimary
                        font.pixelSize: AppTheme.fs(30)
                        font.weight: Font.Bold
                        font.family: AppTheme.fontFamily
                        font.letterSpacing: 1
                    }
                    Text {
                        text: qsTr("Patina · 看得见的专注，才守得住")
                        color: AppTheme.textSecondary
                        font.pixelSize: AppTheme.fs(13)
                        font.family: AppTheme.fontFamily
                    }
                }

                Rectangle {
                    visible: page.section === 0
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    width: weekBadgeText.implicitWidth + 26
                    height: 30
                    radius: 15
                    color: AppTheme.glass ? "#1AFFFFFF" : AppTheme.cardBgAlt
                    border.width: 1
                    border.color: AppTheme.cardBorder
                    Text {
                        id: weekBadgeText
                        anchors.centerIn: parent
                        text: qsTr("近 7 天 · %1 分钟").arg(Math.round(page.weekTotal))
                        color: AppTheme.textSecondary
                        font.pixelSize: AppTheme.fs(12)
                        font.family: AppTheme.fontFamily
                    }
                }
            }

            // ---------- v0.13 横向分类 ----------
            Row {
                width: parent.width
                spacing: 8

                Repeater {
                    model: [
                        { key: "overview", label: qsTr("概览") },
                        { key: "apps", label: qsTr("应用") },
                        { key: "category", label: qsTr("分类") },
                        { key: "heatmap", label: qsTr("热力图") },
                        { key: "sessions", label: qsTr("会话") }
                    ]
                    delegate: Item {
                        width: chipLabel.implicitWidth + 30
                        height: 34
                        readonly property bool selected: page.section === index
                        Rectangle {
                            anchors.fill: parent
                            radius: 17
                            color: selected ? AppTheme.accentSoft : AppTheme.cardBg
                            border.width: 1
                            border.color: selected ? AppTheme.accent : AppTheme.cardBorder
                        }
                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: String(modelData.label)
                            color: selected ? AppTheme.textPrimary : AppTheme.textSecondary
                            font.pixelSize: AppTheme.fs(12)
                            font.weight: selected ? Font.DemiBold : Font.Normal
                            font.family: AppTheme.fontFamily
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.section = index
                        }
                    }
                }
            }

            // ---------- 统计卡片横排 ----------
            Row {
                visible: page.section === 0
                width: parent.width
                spacing: 12

                Repeater {
                    model: page.statCards

                    delegate: GlassCard {
                        width: (pageColumn.width - 36) / 4
                        height: 112
                        radius: 20
                        interactive: false
                        glassSource: page.glassSource

                        Column {
                            x: 16
                            y: 14
                            width: parent.width - 32
                            spacing: 6

                            Row {
                                spacing: 7
                                Rectangle {
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: String(modelData.accent)
                                }
                                Text {
                                    text: String(modelData.label)
                                    color: AppTheme.textSecondary
                                    font.pixelSize: AppTheme.fs(12)
                                    font.family: AppTheme.fontFamily
                                }
                            }

                            Row {
                                spacing: 5
                                Text {
                                    text: String(modelData.value)
                                    color: AppTheme.textPrimary
                                    font.pixelSize: AppTheme.fs(30)
                                    font.weight: Font.DemiBold
                                    font.family: C.monoFont
                                }
                                Text {
                                    anchors.baseline: parent.children[0].baseline
                                    text: String(modelData.unit)
                                    color: AppTheme.textTertiary
                                    font.pixelSize: AppTheme.fs(12)
                                    font.family: AppTheme.fontFamily
                                }
                            }

                            Rectangle {
                                width: parent.width * (0.35 + 0.15 * (index % 3))
                                height: 3
                                radius: 1.5
                                color: String(modelData.accent)
                                opacity: 0.75
                            }
                        }
                    }
                }
            }

            // ---------- 最近 7 天柱状图 ----------
            GlassCard {
                visible: page.section === 0
                width: parent.width
                height: 236
                radius: 22
                interactive: false
                glassSource: page.glassSource

                Column {
                    x: 22
                    y: 18
                    width: parent.width - 44
                    spacing: 14

                    Row {
                        width: parent.width
                        Text {
                            text: qsTr("最近 7 天")
                            color: AppTheme.textPrimary
                            font.pixelSize: AppTheme.fs(16)
                            font.weight: Font.DemiBold
                            font.family: AppTheme.fontFamily
                        }
                        Item { width: parent.width - 200; height: 1 }
                        Text {
                            text: qsTr("合计 %1 分钟").arg(Math.round(page.weekTotal))
                            color: AppTheme.textTertiary
                            font.pixelSize: AppTheme.fs(12)
                            font.family: AppTheme.fontFamily
                        }
                    }

                    Item {
                        width: parent.width
                        height: 150

                        Row {
                            anchors.fill: parent
                            spacing: 10

                            Repeater {
                                model: page.days

                                delegate: Item {
                                    width: (parent.width - 60) / Math.max(1, page.days.length)
                                    height: parent.height

                                    Rectangle {
                                        anchors.bottom: barLabel.top
                                        anchors.bottomMargin: 6
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.max(18, parent.width * 0.48)
                                        height: Math.max(4, (parent.height - 46)
                                                              * (Number(modelData.minutes) || 0) / page.dayMax)
                                        radius: 8
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: "#7FE7DA" }
                                            GradientStop { position: 1.0; color: "#2B86FF" }
                                        }
                                        opacity: 0.9
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: barLabel.top
                                        anchors.bottomMargin: 6 + Math.max(4, (parent.height - 46)
                                                            * (Number(modelData.minutes) || 0) / page.dayMax) + 2
                                        text: Math.round(Number(modelData.minutes) || 0)
                                        color: AppTheme.textTertiary
                                        font.pixelSize: AppTheme.fs(10)
                                        font.family: C.monoFont
                                        visible: (Number(modelData.minutes) || 0) > 0
                                    }

                                    Text {
                                        id: barLabel
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        text: (modelData.label !== undefined) ? String(modelData.label)
                                                                              : String(modelData.date || "")
                                        color: AppTheme.textTertiary
                                        font.pixelSize: AppTheme.fs(11)
                                        font.family: AppTheme.fontFamily
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- v0.9 应用使用时长 ----------
            GlassCard {
                visible: page.section === 1
                width: parent.width
                implicitHeight: usageColumn.implicitHeight + 36
                height: implicitHeight
                radius: 22
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: usageColumn
                    x: 22
                    y: 18
                    width: parent.width - 44
                    spacing: 12

                    Row {
                        width: parent.width
                        spacing: 12

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("应用使用时长")
                            color: AppTheme.textPrimary
                            font.pixelSize: AppTheme.fs(16)
                            font.weight: Font.DemiBold
                            font.family: AppTheme.fontFamily
                        }

                        Item { width: parent.width - 320; height: 1 }

                        // 今日 / 本周切换
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Repeater {
                                model: [qsTr("今日"), qsTr("本周")]
                                delegate: Item {
                                    width: 62
                                    height: 28
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 14
                                        color: page.usageRange === index ? AppTheme.accent
                                              : (tabArea.containsMouse ? AppTheme.cardBgAlt : AppTheme.cardBg)
                                        border.width: 1
                                        border.color: page.usageRange === index ? AppTheme.accent : AppTheme.cardBorder
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: String(modelData)
                                        color: page.usageRange === index ? "#FFFFFF" : AppTheme.textSecondary
                                        font.pixelSize: AppTheme.fs(12)
                                        font.family: AppTheme.fontFamily
                                    }
                                    MouseArea {
                                        id: tabArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: page.usageRange = index
                                    }
                                }
                            }
                        }
                    }

                    // 类别横排名称（一行可多个）
                    Flow {
                        width: parent.width
                        spacing: 8
                        visible: page.appCategories.length > 0

                        Repeater {
                            model: page.appCategories
                            delegate: Item {
                                width: categoryName.implicitWidth + 46
                                height: 26
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 13
                                    color: AppTheme.cardBgAlt
                                    border.width: 1
                                    border.color: AppTheme.cardBorder
                                }
                                Rectangle {
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: page.itemColor(modelData, index)
                                }
                                Text {
                                    id: categoryName
                                    anchors.left: parent.left
                                    anchors.leftMargin: 23
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.itemName(modelData) + " · " + page.usageMinutesText(page.itemMinutes(modelData))
                                    color: AppTheme.textSecondary
                                    font.pixelSize: AppTheme.fs(11)
                                    font.family: AppTheme.fontFamily
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // 类别堆叠条
                    Item {
                        width: parent.width
                        height: 12
                        visible: page.categoryTotal > 0

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: AppTheme.glass ? "#1AFFFFFF" : AppTheme.divider
                        }

                        Row {
                            anchors.fill: parent
                            spacing: 2

                            Repeater {
                                model: page.appCategories
                                delegate: Rectangle {
                                    width: Math.max(3, (parent.width - (page.appCategories.length - 1) * 2)
                                                    * page.itemMinutes(modelData) / Math.max(1, page.categoryTotal))
                                    height: parent.height
                                    radius: 5
                                    color: page.itemColor(modelData, index)
                                }
                            }
                        }
                    }

                    // 应用列表
                    Column {
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: page.appUsage

                            delegate: Item {
                                width: parent.width
                                height: 34

                                Row {
                                    anchors.fill: parent
                                    spacing: 10

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 9
                                        height: 9
                                        radius: 4.5
                                        color: page.itemColor(modelData, index)
                                    }

                                    Text {
                                        width: 150
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: page.itemName(modelData)
                                        color: AppTheme.textPrimary
                                        font.pixelSize: AppTheme.fs(13)
                                        font.family: AppTheme.fontFamily
                                        elide: Text.ElideRight
                                    }

                                    Item {
                                        width: parent.width - 150 - 9 - 90 - 30
                                        height: 8
                                        anchors.verticalCenter: parent.verticalCenter

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 4
                                            color: AppTheme.glass ? "#14FFFFFF" : AppTheme.divider
                                        }
                                        Rectangle {
                                            width: parent.width * page.itemMinutes(modelData) / page.appUsageMax
                                            height: parent.height
                                            radius: 4
                                            color: page.itemColor(modelData, index)
                                        }
                                    }

                                    Text {
                                        width: 90
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: page.usageMinutesText(page.itemMinutes(modelData))
                                        color: AppTheme.textSecondary
                                        font.pixelSize: AppTheme.fs(11)
                                        font.family: AppTheme.fontFamily
                                    }
                                }
                            }
                        }

                        Text {
                            visible: page.appUsage.length === 0
                            width: parent.width
                            text: qsTr("还没有应用使用记录，开始一轮专注吧")
                            color: AppTheme.textTertiary
                            font.pixelSize: AppTheme.fs(12)
                            font.family: AppTheme.fontFamily
                        }
                    }
                }
            }

            // ---------- v0.13 分类管理 ----------
            GlassCard {
                visible: page.section === 2
                width: parent.width
                implicitHeight: categoryColumn.implicitHeight + 36
                height: implicitHeight
                radius: 22
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: categoryColumn
                    x: 22
                    y: 18
                    width: parent.width - 44
                    spacing: 12

                    Row {
                        width: parent.width
                        Text {
                            text: qsTr("应用分类")
                            color: AppTheme.textPrimary
                            font.pixelSize: AppTheme.fs(16)
                            font.weight: Font.DemiBold
                            font.family: AppTheme.fontFamily
                        }
                        Item { width: parent.width - 300; height: 1 }
                        Text {
                            text: qsTr("选中分类会立即保存；可恢复自动分类")
                            color: AppTheme.textTertiary
                            font.pixelSize: AppTheme.fs(10)
                            font.family: AppTheme.fontFamily
                        }
                    }

                    // 类别汇总 chips
                    Flow {
                        width: parent.width
                        spacing: 8
                        visible: page.appCategories.length > 0
                        Repeater {
                            model: page.appCategories
                            delegate: Item {
                                width: categoryChipLabel.implicitWidth + 40
                                height: 26
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 13
                                    color: AppTheme.cardBgAlt
                                    border.width: 1
                                    border.color: AppTheme.cardBorder
                                }
                                Rectangle {
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: page.itemColor(modelData, index)
                                }
                                Text {
                                    id: categoryChipLabel
                                    anchors.left: parent.left
                                    anchors.leftMargin: 23
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.itemName(modelData) + " · " + page.usageMinutesText(page.itemMinutes(modelData))
                                    color: AppTheme.textSecondary
                                    font.pixelSize: AppTheme.fs(10)
                                    font.family: AppTheme.fontFamily
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: AppTheme.divider }

                    Column {
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: page.usageApps
                            delegate: Item {
                                id: categoryRow
                                width: parent.width
                                height: 38
                                Row {
                                    anchors.fill: parent
                                    spacing: 8
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 9
                                        height: 9
                                        radius: 4.5
                                        color: page.itemColor(modelData, index)
                                    }
                                    Text {
                                        width: 150
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: page.itemName(modelData)
                                        color: AppTheme.textPrimary
                                        font.pixelSize: AppTheme.fs(12)
                                        font.family: AppTheme.fontFamily
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: 160
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: page.appExe(modelData)
                                        color: AppTheme.textTertiary
                                        font.pixelSize: AppTheme.fs(9)
                                        font.family: AppTheme.fontFamily
                                        elide: Text.ElideRight
                                    }
                                    Item { width: parent.width - 560; height: 1 }
                                    Item {
                                        width: 112
                                        height: 28
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 9
                                            color: categoryButtonArea.containsMouse ? AppTheme.cardBgAlt : AppTheme.cardBg
                                            border.width: 1
                                            border.color: page.categoryMenuRow === index ? AppTheme.accent : AppTheme.cardBorder
                                        }
                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: page.optionLabel(page.appCategory(modelData))
                                            color: AppTheme.textSecondary
                                            font.pixelSize: AppTheme.fs(10)
                                            font.family: AppTheme.fontFamily
                                        }
                                        Text {
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "▾"
                                            color: AppTheme.textTertiary
                                            font.pixelSize: AppTheme.fs(10)
                                            font.family: AppTheme.fontFamily
                                        }
                                        MouseArea {
                                            id: categoryButtonArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: page.openCategoryMenu(categoryRow, index)
                                        }
                                    }
                                    Item {
                                        width: 62
                                        height: 28
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: typeof App !== "undefined" && typeof App.resetAppCategory === "function"
                                        Text {
                                            anchors.centerIn: parent
                                            text: qsTr("恢复自动")
                                            color: resetArea.containsMouse ? AppTheme.accent : AppTheme.textTertiary
                                            font.pixelSize: AppTheme.fs(9)
                                            font.family: AppTheme.fontFamily
                                        }
                                        MouseArea {
                                            id: resetArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: page.resetCategory(modelData)
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: page.usageApps.length === 0
                            width: parent.width
                            text: qsTr("还没有应用记录，开始一轮专注吧")
                            color: AppTheme.textTertiary
                            font.pixelSize: AppTheme.fs(11)
                            font.family: AppTheme.fontFamily
                        }
                    }
                }
            }

            // ---------- v0.13 热力图 ----------
            GlassCard {
                visible: page.section === 3
                width: parent.width
                implicitHeight: heatColumn.implicitHeight + 36
                height: implicitHeight
                radius: 22
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: heatColumn
                    x: 22
                    y: 18
                    width: parent.width - 44
                    spacing: 12

                    Row {
                        width: parent.width
                        Text {
                            text: qsTr("热力图")
                            color: AppTheme.textPrimary
                            font.pixelSize: AppTheme.fs(16)
                            font.weight: Font.DemiBold
                            font.family: AppTheme.fontFamily
                        }
                        Item { width: parent.width - 260; height: 1 }
                        Text {
                            text: qsTr("最近 90 天 · 按分钟色阶")
                            color: AppTheme.textTertiary
                            font.pixelSize: AppTheme.fs(10)
                            font.family: AppTheme.fontFamily
                        }
                    }

                    Grid {
                        columns: 13
                        rows: 7
                        flow: Grid.TopToBottom
                        spacing: 3
                        Repeater {
                            model: page.heatmapCells
                            delegate: Rectangle {
                                width: 14
                                height: 14
                                radius: 3
                                color: page.heatColor(modelData.minutes)
                                border.width: 1
                                border.color: AppTheme.glass ? "#10FFFFFF" : "#0A000000"
                            }
                        }
                    }

                    Row {
                        spacing: 4
                        Text {
                            text: qsTr("少")
                            color: AppTheme.textTertiary
                            font.pixelSize: AppTheme.fs(9)
                            font.family: AppTheme.fontFamily
                        }
                        Repeater {
                            model: ["#176B68", "#1E9E95", "#2ED3C6"]
                            delegate: Rectangle {
                                width: 11
                                height: 11
                                radius: 2
                                color: String(modelData)
                            }
                        }
                        Text {
                            text: qsTr("多")
                            color: AppTheme.textTertiary
                            font.pixelSize: AppTheme.fs(9)
                            font.family: AppTheme.fontFamily
                        }
                    }

                    Text {
                        visible: page.heatmapEmpty
                        text: qsTr("最近 90 天还没有应用使用记录")
                        color: AppTheme.textTertiary
                        font.pixelSize: AppTheme.fs(10)
                        font.family: AppTheme.fontFamily
                    }

                    Rectangle { width: parent.width; height: 1; color: AppTheme.divider }

                    Text {
                        text: qsTr("24 小时分布")
                        color: AppTheme.textSecondary
                        font.pixelSize: AppTheme.fs(12)
                        font.weight: Font.DemiBold
                        font.family: AppTheme.fontFamily
                    }

                    Item {
                        width: parent.width
                        height: 76
                        Row {
                            anchors.fill: parent
                            spacing: 4
                            Repeater {
                                model: page.hourlyValues
                                delegate: Item {
                                    width: (parent.width - 23 * 4) / 24
                                    height: parent.height
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: Math.max(2, (parent.height - 2) * Number(modelData) / page.hourlyMax)
                                        radius: 2
                                        color: Number(modelData) > 0 ? AppTheme.accent : (AppTheme.glass ? "#14FFFFFF" : AppTheme.divider)
                                        opacity: 0.85
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 0
                        Repeater {
                            model: ["00", "06", "12", "18", "23"]
                            delegate: Text {
                                width: parent.width / 5
                                text: String(modelData)
                                color: AppTheme.textTertiary
                                font.pixelSize: AppTheme.fs(9)
                                font.family: AppTheme.fontFamily
                            }
                        }
                    }
                }
            }

            // ---------- 最近会话 ----------
            GlassCard {
                visible: page.section === 4
                width: parent.width
                height: sessionColumn.implicitHeight + 36
                radius: 22
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: sessionColumn
                    x: 22
                    y: 18
                    width: parent.width - 44
                    spacing: 12

                    Row {
                        width: parent.width
                        Text {
                            text: qsTr("最近会话")
                            color: AppTheme.textPrimary
                            font.pixelSize: AppTheme.fs(16)
                            font.weight: Font.DemiBold
                            font.family: AppTheme.fontFamily
                        }
                        Item { width: parent.width - 200; height: 1 }
                        Text {
                            text: qsTr("今日 %1 次").arg(page.cardSessions)
                            color: AppTheme.textTertiary
                            font.pixelSize: AppTheme.fs(12)
                            font.family: AppTheme.fontFamily
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: AppTheme.divider }

                    Column {
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: page.recentRows

                            delegate: Item {
                                width: parent.width
                                height: 42

                                Row {
                                    anchors.fill: parent
                                    spacing: 12

                                    Rectangle {
                                        width: 4
                                        height: 28
                                        radius: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: modelData.completed === true ? "#2ED3C6" : "#7FB6FF"
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2
                                        Text {
                                            text: (page.timeOf(modelData.startMs) !== ""
                                                   ? page.timeOf(modelData.startMs)
                                                   : String(modelData.date || ""))
                                            color: AppTheme.textPrimary
                                            font.pixelSize: AppTheme.fs(13)
                                            font.family: AppTheme.fontFamily
                                        }
                                        Text {
                                            text: (modelData.spaceName !== undefined && String(modelData.spaceName) !== "")
                                                  ? String(modelData.spaceName) : qsTr("专注")
                                            color: AppTheme.textTertiary
                                            font.pixelSize: AppTheme.fs(11)
                                            font.family: AppTheme.fontFamily
                                        }
                                    }
                                    Item { width: parent.width - 300; height: 1 }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: qsTr("%1 分钟").arg(Math.round(Number(modelData.minutes) || 0))
                                            + (modelData.completed === true ? " · " + qsTr("完成") : "")
                                        color: AppTheme.textSecondary
                                        font.pixelSize: AppTheme.fs(12)
                                        font.family: AppTheme.fontFamily
                                    }
                                }
                            }
                        }

                        Text {
                            visible: page.recentRows.length === 0
                            width: parent.width
                            text: qsTr("还没有专注记录，开始一轮吧。")
                            color: AppTheme.textTertiary
                            font.pixelSize: AppTheme.fs(12)
                            font.family: AppTheme.fontFamily
                        }
                    }

                    Text {
                        width: parent.width
                        text: qsTr("更早的会话明细将在后续版本提供。")
                        color: AppTheme.textTertiary
                        font.pixelSize: AppTheme.fs(11)
                        font.family: AppTheme.fontFamily
                    }
                }
            }

            Text {
                width: parent.width
                text: qsTr("Patina · 统计卡片与图表结构已就绪，等待补充更多细节。")
                color: AppTheme.textTertiary
                font.pixelSize: AppTheme.fs(11)
                font.family: AppTheme.fontFamily
                wrapMode: Text.WordWrap
            }
        }
    }

    // ---------- 分类下拉菜单 ----------
    Item {
        visible: page.categoryMenuRow >= 0
        z: 70
        x: page.categoryMenuX
        y: page.categoryMenuY
        width: page.categoryMenuW
        height: categoryMenuColumn.height + 8
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: AppTheme.cardBg
            border.width: 1
            border.color: AppTheme.cardBorderStrong
        }
        Column {
            id: categoryMenuColumn
            x: 4
            y: 4
            width: parent.width - 8
            spacing: 2
            Repeater {
                model: page.categoryOptions
                delegate: Item {
                    width: parent.width
                    height: 28
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(modelData.label)
                        color: String(modelData.value) === page.appCategory(page.usageApps[page.categoryMenuRow] || ({}))
                               ? AppTheme.accent : AppTheme.textSecondary
                        font.pixelSize: AppTheme.fs(10)
                        font.family: AppTheme.fontFamily
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.selectCategory(page.usageApps[page.categoryMenuRow], modelData.value)
                    }
                }
            }
        }
    }

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
