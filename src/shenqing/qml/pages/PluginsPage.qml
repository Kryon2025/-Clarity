import QtQuick
import "../components"
import "../components/Constants.js" as C

// 插件页：插件列表 / 启停 / 重扫
Item {
    id: page

    property Item glassSource: null

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
                        text: qsTr("插件")
                        color: C.textPrimary
                        font.pixelSize: 30
                        font.weight: Font.Bold
                        font.family: C.numFont
                        font.letterSpacing: 1
                    }
                    Text {
                        text: qsTr("插件给深清加功能")
                        color: C.textSecondary
                        font.pixelSize: 13
                        font.family: C.numFont
                    }
                }
            }

            // ---------- 插件列表 ----------
            GlassCard {
                width: parent.width
                implicitHeight: pluginColumn.implicitHeight + 18
                height: implicitHeight
                radius: 20
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: pluginColumn
                    width: parent.width
                    anchors.top: parent.top
                    anchors.topMargin: 10

                    Item {
                        width: parent.width
                        height: 40

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("已安装插件")
                            color: C.textPrimary
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            font.family: C.numFont
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 96
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("（%1）").arg((App.plugins || []).length)
                            color: C.textTertiary
                            font.pixelSize: 12
                            font.family: C.numFont
                        }

                        GlassButton {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("重新扫描")
                            tone: "ghost"
                            fontSize: 12
                            padH: 14
                            minHeight: 30
                            onClicked: {
                                if (typeof App.restartPlugins === "function")
                                    App.restartPlugins()
                            }
                        }
                    }

                    Text {
                        width: parent.width - 32
                        x: 16
                        topPadding: 6
                        bottomPadding: 10
                        text: qsTr("还没有插件。把插件放到 %APPDATA%/ShenQing/plugins 后点「重新扫描」。")
                        color: C.textTertiary
                        font.pixelSize: 12
                        font.family: C.numFont
                        wrapMode: Text.WordWrap
                        visible: (App.plugins || []).length === 0
                    }

                    Repeater {
                        model: App.plugins || []
                        delegate: Item {
                            id: pluginRow
                            readonly property string pluginState: (modelData.state && modelData.state.summary)
                                ? String(modelData.state.summary) : ""
                            width: parent.width
                            height: pluginState.length > 0 ? 92 : 72

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                height: 1
                                color: "#0FFFFFFF"
                                visible: index > 0
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.right: pluginSwitch.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3

                                Row {
                                    spacing: 8
                                    Text {
                                        text: String(modelData.name !== undefined ? modelData.name : qsTr("插件"))
                                        color: C.textPrimary
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                        font.family: C.numFont
                                    }
                                    Text {
                                        anchors.baseline: parent.children[0].baseline
                                        text: "v" + String(modelData.version !== undefined ? modelData.version : "1.0")
                                        color: C.textTertiary
                                        font.pixelSize: 11
                                        font.family: C.numFont
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: {
                                        if (modelData.error !== undefined && String(modelData.error).length > 0)
                                            return qsTr("错误：%1").arg(String(modelData.error))
                                        return String(modelData.description !== undefined ? modelData.description : "")
                                    }
                                    color: (modelData.error !== undefined && String(modelData.error).length > 0)
                                           ? "#FF8898" : C.textTertiary
                                    font.pixelSize: 12
                                    font.family: C.numFont
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    visible: pluginRow.pluginState.length > 0
                                    text: pluginRow.pluginState
                                    color: C.accent
                                    font.pixelSize: 12
                                    font.family: C.numFont
                                    elide: Text.ElideRight
                                }
                            }

                            GlassSwitch {
                                id: pluginSwitch
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                checked: modelData.enabled === true
                                onClicked: {
                                    if (typeof App.setPluginEnabled === "function")
                                        App.setPluginEnabled(String(modelData.id), !(modelData.enabled === true))
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
