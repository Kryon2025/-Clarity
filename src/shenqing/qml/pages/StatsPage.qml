import QtQuick
import "../theme"
import "../components"
import "../components/Constants.js" as C

// 数据页：统计卡片 + 近 7 天柱状图
Item {
    id: page

    property Item glassSource: null

    function roundText(value) {
        var n = Number(value)
        if (!isFinite(n)) n = 0
        return String(Math.round(n))
    }

    readonly property var days: App.last7Days || []
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

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageColumn.height + 60
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: pageColumn
            width: Math.min(flick.width - 96, 780)
            x: (flick.width - width) / 2
            y: 26
            spacing: 16

            // ---------- 页头 ----------
            Item {
                width: parent.width
                height: 76

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
                        text: qsTr("看得见的专注，才守得住")
                        color: AppTheme.textSecondary
                        font.pixelSize: 13
                        font.family: C.numFont
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    spacing: 10

                    GlassButton {
                        text: qsTr("刷新")
                        tone: "ghost"
                        fontSize: 13
                        padH: 16
                        minHeight: 36
                        onClicked: App.refreshStats()
                    }
                    GlassButton {
                        text: qsTr("导出 CSV")
                        tone: "tinted"
                        fontSize: 13
                        padH: 16
                        minHeight: 36
                        onClicked: App.exportStats()
                    }
                }
            }

            // ---------- 统计卡片 ----------
            Row {
                width: parent.width
                spacing: 14

                Repeater {
                    model: [
                        { label: qsTr("今日专注"), value: page.roundText(App.todayMinutes), unit: qsTr("分钟") },
                        { label: qsTr("本周专注"), value: page.roundText(App.weekMinutes), unit: qsTr("分钟") },
                        { label: qsTr("连续天数"), value: page.roundText(App.streakDays), unit: qsTr("天") },
                        { label: qsTr("累计会话"), value: page.roundText(App.sessionCount), unit: qsTr("次") }
                    ]
                    delegate: GlassCard {
                        width: (pageColumn.width - 3 * 14) / 4
                        height: 116
                        radius: 20
                        interactive: false
                        glassSource: page.glassSource
                        accentTint: "#0CFFFFFF"

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                text: modelData.label
                                color: AppTheme.textSecondary
                                font.pixelSize: 12
                                font.family: C.numFont
                            }
                            Text {
                                text: modelData.value
                                      + "<span style='font-size:12px; color:" + AppTheme.textSecondary + "'> "
                                      + modelData.unit + "</span>"
                                textFormat: Text.StyledText
                                color: "#FFFFFF"
                                font.pixelSize: 30
                                font.weight: Font.Bold
                                font.family: C.numFont
                            }
                        }
                    }
                }
            }

            // ---------- 近 7 天 ----------
            GlassCard {
                width: parent.width
                height: 288
                radius: 22
                interactive: false
                glassSource: page.glassSource

                Item {
                    anchors.fill: parent
                    anchors.margins: 24

                    Item {
                        id: chartHeader
                        width: parent.width
                        height: 24

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("近 7 天")
                            color: AppTheme.textPrimary
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            font.family: C.numFont
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("共 %1 分钟").arg(page.roundText(page.weekTotal))
                            color: AppTheme.textSecondary
                            font.pixelSize: 12
                            font.family: C.numFont
                        }
                    }

                    Item {
                        id: chartArea
                        anchors.top: chartHeader.bottom
                        anchors.topMargin: 22
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom

                        // 基线
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 24
                            height: 1
                            color: "#1AFFFFFF"
                        }

                        Row {
                            id: barsRow
                            anchors.fill: parent
                            spacing: 14

                            Repeater {
                                model: page.days
                                delegate: Item {
                                    width: (barsRow.width - 6 * 14) / 7
                                    height: barsRow.height
                                    readonly property real ratio: page.dayMax > 0
                                                                    ? Math.min(1, (Number(modelData.minutes) || 0) / page.dayMax)
                                                                    : 0
                                    readonly property bool today: index === page.days.length - 1

                                    // 数值
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: bar.top
                                        anchors.bottomMargin: 6
                                        text: page.roundText(modelData.minutes)
                                        color: parent.today ? "#DCE7FF" : AppTheme.textTertiary
                                        font.pixelSize: 11
                                        font.family: C.numFont
                                    }

                                    Rectangle {
                                        id: bar
                                        width: Math.min(30, parent.width * 0.62)
                                        height: Math.max(4, parent.ratio * (parent.height - 70))
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: parent.height - 26 - height
                                        radius: Math.min(10, width / 2)
                                        gradient: Gradient {
                                            GradientStop {
                                                position: 0.0
                                                color: parent.today ? "#B7CBFF" : "#7EA3FF"
                                            }
                                            GradientStop {
                                                position: 1.0
                                                color: parent.today ? "#5C86FF" : "#2E56D6"
                                            }
                                        }
                                        opacity: parent.ratio > 0 ? 1.0 : 0.35
                                        Behavior on height {
                                            NumberAnimation { duration: 420; easing.type: Easing.OutCubic }
                                        }
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        text: {
                                            var d = String(modelData.date)
                                            return d.length >= 10 ? d.slice(5) : d
                                        }
                                        color: parent.today ? "#B7C3D9" : AppTheme.textTertiary
                                        font.pixelSize: 11
                                        font.family: C.numFont
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item { width: parent.width; height: 2 }
        }
    }

    Rectangle {
        visible: flick.contentHeight > flick.height + 4
        width: 4
        radius: 2
        color: "#26FFFFFF"
        x: flick.width - 14
        height: Math.max(48, flick.height * flick.height / Math.max(1, flick.contentHeight))
        y: 18 + Math.max(0, Math.min(1, flick.contentY / Math.max(1, flick.contentHeight - flick.height)))
           * Math.max(1, flick.height - 36 - height)
    }
}