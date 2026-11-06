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
                        font.pixelSize: 30
                        font.weight: Font.Bold
                        font.family: C.numFont
                        font.letterSpacing: 1
                    }
                    Text {
                        text: qsTr("Patina · 看得见的专注，才守得住")
                        color: AppTheme.textSecondary
                        font.pixelSize: 13
                        font.family: C.numFont
                    }
                }

                Rectangle {
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
                        font.pixelSize: 12
                        font.family: C.numFont
                    }
                }
            }

            // ---------- 统计卡片横排 ----------
            Row {
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
                                    font.pixelSize: 12
                                    font.family: C.numFont
                                }
                            }

                            Row {
                                spacing: 5
                                Text {
                                    text: String(modelData.value)
                                    color: AppTheme.textPrimary
                                    font.pixelSize: 30
                                    font.weight: Font.DemiBold
                                    font.family: C.monoFont
                                }
                                Text {
                                    anchors.baseline: parent.children[0].baseline
                                    text: String(modelData.unit)
                                    color: AppTheme.textTertiary
                                    font.pixelSize: 12
                                    font.family: C.numFont
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
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            font.family: C.numFont
                        }
                        Item { width: parent.width - 200; height: 1 }
                        Text {
                            text: qsTr("合计 %1 分钟").arg(Math.round(page.weekTotal))
                            color: AppTheme.textTertiary
                            font.pixelSize: 12
                            font.family: C.numFont
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
                                        font.pixelSize: 10
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
                                        font.pixelSize: 11
                                        font.family: C.numFont
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- 最近会话 ----------
            GlassCard {
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
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            font.family: C.numFont
                        }
                        Item { width: parent.width - 200; height: 1 }
                        Text {
                            text: qsTr("今日 %1 次").arg(page.cardSessions)
                            color: AppTheme.textTertiary
                            font.pixelSize: 12
                            font.family: C.numFont
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
                                            font.pixelSize: 13
                                            font.family: C.numFont
                                        }
                                        Text {
                                            text: (modelData.spaceName !== undefined && String(modelData.spaceName) !== "")
                                                  ? String(modelData.spaceName) : qsTr("专注")
                                            color: AppTheme.textTertiary
                                            font.pixelSize: 11
                                            font.family: C.numFont
                                        }
                                    }
                                    Item { width: parent.width - 300; height: 1 }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: qsTr("%1 分钟").arg(Math.round(Number(modelData.minutes) || 0))
                                            + (modelData.completed === true ? " · " + qsTr("完成") : "")
                                        color: AppTheme.textSecondary
                                        font.pixelSize: 12
                                        font.family: C.numFont
                                    }
                                }
                            }
                        }

                        Text {
                            visible: page.recentRows.length === 0
                            width: parent.width
                            text: qsTr("还没有专注记录，开始一轮吧。")
                            color: AppTheme.textTertiary
                            font.pixelSize: 12
                            font.family: C.numFont
                        }
                    }

                    Text {
                        width: parent.width
                        text: qsTr("更早的会话明细将在后续版本提供。")
                        color: AppTheme.textTertiary
                        font.pixelSize: 11
                        font.family: C.numFont
                    }
                }
            }

            Text {
                width: parent.width
                text: qsTr("Patina · 统计卡片与图表结构已就绪，等待补充更多细节。")
                color: AppTheme.textTertiary
                font.pixelSize: 11
                font.family: C.numFont
                wrapMode: Text.WordWrap
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
