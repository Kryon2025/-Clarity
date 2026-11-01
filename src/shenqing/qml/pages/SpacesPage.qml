import QtQuick
import "../components"
import "../components/Constants.js" as C

// 首页：主空间大卡 + 其他空间分组 + 新增空间
Item {
    id: page

    property Item glassSource: null

    signal editSpaceRequested(string id)
    signal newSpaceRequested()

    readonly property var superSpace: {
        var list = App.spaces || []
        for (var i = 0; i < list.length; i++) {
            if (list[i].super) return list[i]
        }
        return null
    }

    readonly property int lightCount: (App.spacesLight || []).length

    // 空状态：一张空间都没有（异常情况兜底）
    readonly property bool empty: (App.spaces || []).length === 0

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: pageColumn.height + 64
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
                        text: "深清"
                        color: C.textPrimary
                        font.pixelSize: 30
                        font.weight: Font.Bold
                        font.family: C.numFont
                        font.letterSpacing: 1
                    }

                    Text {
                        text: App.busy
                              ? qsTr("专注中 · %1 · 剩余 %2").arg(App.activeSpaceName).arg(App.remainingText)
                              : qsTr("把注意力收回来")
                        color: App.busy ? "#9FB6FF" : C.textSecondary
                        font.pixelSize: 13
                        font.family: C.numFont
                    }
                }

            }

            // ---------- 会话条（专注中才显示） ----------
            GlassCard {
                id: sessionCard
                width: parent.width
                height: 78
                radius: 20
                interactive: false
                visible: App.busy
                glassSource: page.glassSource

                // 左侧：呼吸点 + 文案
                Item {
                    id: sessionLeft
                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    height: 40
                    width: sessionText.width + 22

                    Rectangle {
                        id: pulseDot
                        width: 9
                        height: 9
                        radius: 4.5
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#6FE3B0"
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 1200; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
                        }
                    }

                    Column {
                        id: sessionText
                        anchors.left: pulseDot.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Text {
                            text: qsTr("专注中 · %1").arg(App.activeSpaceName)
                            color: C.textPrimary
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            font.family: C.numFont
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, sessionCard.width * 0.5)
                        }
                        Text {
                            text: App.state === "paused" ? qsTr("已暂停") : qsTr("剩余 %1").arg(App.remainingText)
                            color: C.textSecondary
                            font.pixelSize: 12
                            font.family: C.numFont
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    GlassButton {
                        text: App.state === "paused" ? qsTr("继续") : qsTr("暂停")
                        tone: "tinted"
                        fontSize: 13
                        padH: 16
                        minHeight: 34
                        visible: App.state === "paused" || App.canPause
                        onClicked: {
                            if (App.state === "paused") App.resumeSession()
                            else App.pauseSession()
                        }
                    }
                    GlassButton {
                        text: qsTr("结束")
                        tone: "ghost"
                        fontSize: 13
                        padH: 16
                        minHeight: 34
                        onClicked: App.stopSession()
                    }
                }

                // 底部进度
                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 12
                    anchors.bottomMargin: 12
                    width: Math.max(0, (sessionCard.width - 24) * Math.max(0, Math.min(1, App.progress)))
                    height: 3
                    radius: 2
                    color: "#6E93FF"
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                }
            }

            // ---------- 主空间大卡 ----------
            SpaceCard {
                width: parent.width
                height: page.superSpace ? 148 : 0
                visible: page.superSpace !== null
                superCard: true
                spaceName: page.superSpace ? String(page.superSpace.name) : ""
                minutes: page.superSpace ? Number(page.superSpace.minutes) : 0
                accentColor: page.superSpace && page.superSpace.atmosphereColor !== undefined
                             ? page.superSpace.atmosphereColor : C.accent
                onEditRequested: page.editSpaceRequested(String(page.superSpace.id))
                onStartRequested: App.startSpace(String(page.superSpace.id))
            }

            // ---------- 其他空间分组 ----------
            Item {
                width: parent.width
                height: 22
                visible: page.lightCount > 0
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("其他空间")
                    color: C.textSecondary
                    font.pixelSize: 13
                    font.family: C.numFont
                    font.letterSpacing: 1
                }
            }

            Repeater {
                model: App.spacesLight || []
                delegate: SpaceCard {
                    width: pageColumn.width
                    height: 108
                    glassSource: page.glassSource
                    spaceName: String(modelData.name)
                    minutes: Number(modelData.minutes)
                    accentColor: modelData.atmosphereColor !== undefined
                                 ? modelData.atmosphereColor : C.accent
                    onEditRequested: page.editSpaceRequested(String(modelData.id))
                    onStartRequested: App.startSpace(String(modelData.id))
                }
            }

            // ---------- 新增空间 ----------
            Item {
                width: parent.width
                height: 14
            }

            NewSpaceCard {
                width: parent.width
                glassSource: page.glassSource
                onClicked: page.newSpaceRequested()
            }
        }
    }

    // 纤细滚动指示
    Rectangle {
        id: scrollThumb
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