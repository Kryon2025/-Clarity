import QtQuick
import "../theme"
import "../components"
import "../glass"
import "../components/Constants.js" as C

// v0.10 独立更新页：当前版本 / 检查更新 / 新版本说明 / 下载安装 / 自动检查 / 最近更新日志
Item {
    id: page

    property Item glassSource: null
    property bool animationsEnabled: true

    readonly property string updateState: (typeof App !== "undefined" && App.updateState !== undefined)
                                         ? String(App.updateState) : "idle"
    readonly property bool updateAvailable: (typeof App !== "undefined" && App.updateAvailable === true)
    readonly property string latestVersion: (typeof App !== "undefined" && App.updateLatestVersion !== undefined)
                                            ? String(App.updateLatestVersion) : ""
    readonly property string updateNotes: (typeof App !== "undefined" && App.updateNotes !== undefined)
                                          ? String(App.updateNotes) : ""
    readonly property int updateProgress: (typeof App !== "undefined" && App.updateProgress !== undefined)
                                          ? Math.max(0, Math.min(100, Number(App.updateProgress))) : 0
    readonly property string updateError: (typeof App !== "undefined" && App.updateError !== undefined)
                                          ? String(App.updateError) : ""
    readonly property bool autoUpdateEnabled: (typeof App !== "undefined" && App.autoUpdate === true)

    readonly property string statusText: {
        if (page.updateState === "checking") return qsTr("正在检查更新…")
        if (page.updateState === "available") return qsTr("发现新版本 v%1").arg(page.latestVersion)
        if (page.updateState === "downloading") return qsTr("正在下载更新 %1%").arg(Math.round(page.updateProgress))
        if (page.updateState === "ready") return qsTr("更新已就绪，安装并重启即可")
        if (page.updateState === "error") return page.updateError !== "" ? page.updateError : qsTr("检查更新失败")
        return qsTr("已是最新版本")
    }

    function checkUpdate() {
        if (typeof App !== "undefined" && typeof App.checkUpdate === "function")
            App.checkUpdate()
    }
    function downloadUpdate() {
        if (typeof App !== "undefined" && typeof App.downloadUpdate === "function")
            App.downloadUpdate()
    }
    function cancelDownload() {
        if (typeof App !== "undefined" && typeof App.cancelUpdateDownload === "function")
            App.cancelUpdateDownload()
    }
    function installUpdate() {
        if (typeof App !== "undefined" && typeof App.installUpdate === "function")
            App.installUpdate()
    }
    function openReleasePage() {
        if (typeof App !== "undefined" && typeof App.openReleasePage === "function")
            App.openReleasePage()
        else
            Qt.openUrlExternally("https://github.com/Kryon2025/Clarity/releases")
    }
    function setAutoUpdate(enabled) {
        if (typeof App !== "undefined" && typeof App.setAutoUpdate === "function")
            App.setAutoUpdate(!!enabled)
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

            Item {
                width: parent.width
                height: 78
                Column {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 6
                    Text {
                        text: qsTr("更新")
                        color: AppTheme.textPrimary
                        font.pixelSize: 30
                        font.weight: Font.Bold
                        font.family: C.numFont
                        font.letterSpacing: 1
                    }
                    Text {
                        text: qsTr("深清当前版本 v%1 · 数据保存在本机").arg(String(App.version))
                        color: AppTheme.textSecondary
                        font.pixelSize: 13
                        font.family: C.numFont
                    }
                }
            }

            GlassCard {
                width: parent.width
                implicitHeight: updateColumn.implicitHeight + 36
                height: implicitHeight
                radius: 22
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: updateColumn
                    x: 22
                    y: 18
                    width: parent.width - 44
                    spacing: 14

                    Item {
                        width: parent.width
                        height: 52

                        Rectangle {
                            width: 42
                            height: 42
                            radius: 13
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#7FE7DA" }
                                GradientStop { position: 1.0; color: "#2B86FF" }
                            }
                            Glyph { anchors.centerIn: parent; kind: "download"; size: 20; color: "#04222B" }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 54
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 300
                            spacing: 3
                            Text {
                                text: qsTr("当前版本 v%1").arg(String(App.version))
                                color: AppTheme.textPrimary
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                font.family: C.numFont
                            }
                            Text {
                                width: parent.width
                                text: page.statusText
                                color: page.updateState === "error" ? AppTheme.danger
                                      : (page.updateState === "available" ? AppTheme.accent : AppTheme.textSecondary)
                                font.pixelSize: 12
                                font.family: C.numFont
                                wrapMode: Text.WordWrap
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10
                            GlassButton {
                                text: page.updateState === "checking" ? qsTr("检查中…") : qsTr("检查更新")
                                tone: "tinted"
                                fontSize: 13
                                padH: 18
                                minHeight: 36
                                enabled: page.updateState !== "checking" && page.updateState !== "downloading"
                                onClicked: page.checkUpdate()
                            }
                            GlassButton {
                                visible: page.updateState === "available" || page.updateState === "ready"
                                text: qsTr("前往发布页")
                                tone: "ghost"
                                fontSize: 12
                                padH: 14
                                minHeight: 34
                                onClicked: page.openReleasePage()
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: AppTheme.divider }

                    // 新版本说明
                    Column {
                        width: parent.width
                        spacing: 8
                        visible: page.updateState === "available" || page.updateState === "downloading"
                                 || page.updateState === "ready"

                        Text {
                            text: page.latestVersion !== ""
                                  ? qsTr("新版本 v%1").arg(page.latestVersion) : qsTr("新版本")
                            color: AppTheme.textPrimary
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            font.family: C.numFont
                        }
                        Text {
                            width: parent.width
                            text: page.updateNotes !== "" ? page.updateNotes : qsTr("暂无更新说明")
                            color: AppTheme.textSecondary
                            font.pixelSize: 12
                            font.family: C.numFont
                            wrapMode: Text.WordWrap
                            lineHeight: 1.45
                        }
                    }

                    // 下载进度
                    Column {
                        width: parent.width
                        spacing: 8
                        visible: page.updateState === "downloading"

                        Item {
                            width: parent.width
                            height: 10
                            Rectangle {
                                anchors.fill: parent
                                radius: 5
                                color: AppTheme.glass ? "#1AFFFFFF" : AppTheme.divider
                            }
                            Rectangle {
                                width: parent.width * page.updateProgress / 100
                                height: parent.height
                                radius: 5
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#2B86FF" }
                                    GradientStop { position: 1.0; color: "#2ED3C6" }
                                }
                                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            }
                        }
                        Row {
                            width: parent.width
                            Text {
                                text: qsTr("已下载 %1%").arg(Math.round(page.updateProgress))
                                color: AppTheme.textSecondary
                                font.pixelSize: 12
                                font.family: C.numFont
                            }
                            Item { width: parent.width - 200; height: 1 }
                            GlassButton {
                                text: qsTr("取消下载")
                                tone: "ghost"
                                fontSize: 12
                                padH: 14
                                minHeight: 32
                                onClicked: page.cancelDownload()
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 10
                        visible: page.updateState === "available" || page.updateState === "ready"
                        GlassButton {
                            visible: page.updateState === "available"
                            text: qsTr("下载更新")
                            tone: "light"
                            fontSize: 13
                            padH: 20
                            minHeight: 38
                            onClicked: page.downloadUpdate()
                        }
                        GlassButton {
                            visible: page.updateState === "ready"
                            text: qsTr("安装并重启")
                            tone: "light"
                            fontSize: 13
                            padH: 20
                            minHeight: 38
                            onClicked: page.installUpdate()
                        }
                    }

                    Text {
                        visible: page.updateState === "error" && page.updateError !== ""
                        width: parent.width
                        text: page.updateError
                        color: AppTheme.danger
                        font.pixelSize: 12
                        font.family: C.numFont
                        wrapMode: Text.WordWrap
                    }

                    Rectangle { width: parent.width; height: 1; color: AppTheme.divider }

                    Row {
                        width: parent.width
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("启动时自动检查更新")
                            color: AppTheme.textPrimary
                            font.pixelSize: 13
                            font.family: C.numFont
                        }
                        Item { width: parent.width - 220; height: 1 }
                        GlassSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: page.autoUpdateEnabled
                            onClicked: page.setAutoUpdate(!page.autoUpdateEnabled)
                        }
                    }
                }
            }

            // 最近更新日志
            GlassCard {
                width: parent.width
                implicitHeight: changelogColumn.implicitHeight + 36
                height: implicitHeight
                radius: 22
                interactive: false
                glassSource: page.glassSource

                Column {
                    id: changelogColumn
                    x: 22
                    y: 18
                    width: parent.width - 44
                    spacing: 10

                    Row {
                        width: parent.width
                        Text {
                            text: qsTr("最近更新日志")
                            color: AppTheme.textPrimary
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            font.family: C.numFont
                        }
                        Item { width: parent.width - 200; height: 1 }
                        Text {
                            text: qsTr("共 %1 个版本").arg((typeof App !== "undefined" && App.changelog !== undefined)
                                                          ? App.changelog.length : 0)
                            color: AppTheme.textTertiary
                            font.pixelSize: 11
                            font.family: C.numFont
                        }
                    }

                    Repeater {
                        model: (typeof App !== "undefined" && App.changelog !== undefined) ? App.changelog : []
                        delegate: Item {
                            width: parent.width
                            height: 42
                            visible: index < 4
                            Row {
                                anchors.fill: parent
                                spacing: 10
                                Rectangle {
                                    width: 42
                                    height: 22
                                    radius: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: index === 0 ? AppTheme.accentSoft : AppTheme.cardBgAlt
                                    Text {
                                        anchors.centerIn: parent
                                        text: "v" + String(modelData.version)
                                        color: index === 0 ? AppTheme.accent : AppTheme.textSecondary
                                        font.pixelSize: 11
                                        font.family: C.monoFont
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 180
                                    text: (modelData.items !== undefined && modelData.items.length > 0)
                                          ? String(modelData.items[0]) : qsTr("更新内容")
                                    color: AppTheme.textSecondary
                                    font.pixelSize: 11
                                    font.family: C.numFont
                                    elide: Text.ElideRight
                                }
                                Item { width: parent.width - 470; height: 1 }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (modelData.date !== undefined) ? String(modelData.date) : ""
                                    color: AppTheme.textTertiary
                                    font.pixelSize: 10
                                    font.family: C.numFont
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: qsTr("更新会从 GitHub Releases 获取安装包，下载完成后可一键安装并重启。")
                color: AppTheme.textTertiary
                font.pixelSize: 11
                font.family: C.numFont
                wrapMode: Text.WordWrap
            }
        }
    }

    Rectangle {
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
