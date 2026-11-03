import QtQuick
import "../theme"
import "../glass"
import "Constants.js" as C

// 浮层面板外壳：「取消 / 标题 / 完成」顶栏 + 内容区 + 可选删除行。
// glass 主题：近不透明深色玻璃（浮层要压住背后内容，不做背景折射）；
// solid / light 主题：实底卡片 + 细描边，去掉光泽/顶部亮线。
Item {
    id: sheet
    default property alias content: contentHost.data

    property string title: qsTr("空间设置")
    property string cancelText: qsTr("取消")
    property string doneText: qsTr("完成")
    property bool doneEnabled: true
    property string deleteText: ""
    property bool deleteArmed: false
    property Item glassSource: null
    property int contentSpacing: 12

    signal cancelRequested()
    signal doneRequested()
    signal deleteRequested()

    implicitWidth: 600
    implicitHeight: 20 + header.height + 16 + contentHost.height
                    + (deleteVisible ? 18 + deleteRow.height : 0) + 20

    readonly property bool deleteVisible: deleteText !== ""

    // 实底：浮层需要压住背景内容，保持可读性
    Rectangle {
        id: panelBase
        anchors.fill: parent
        radius: C.radiusPanel
        color: AppTheme.glass ? "#E8070B13" : AppTheme.cardBg
        border.width: 1
        border.color: AppTheme.glass ? "#3AFFFFFF" : AppTheme.cardBorder
        Behavior on color { ColorAnimation { duration: 160 } }
    }

    // 玻璃光泽（仅玻璃主题）
    Rectangle {
        id: panel
        anchors.fill: parent
        visible: AppTheme.glass
        radius: C.radiusPanel
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#14FFFFFF" }
            GradientStop { position: 0.45; color: "#0AFFFFFF" }
            GradientStop { position: 1.0; color: "#05FFFFFF" }
        }
    }

    Rectangle {
        visible: AppTheme.glass
        x: C.radiusPanel * 1.1
        y: 1.2
        width: Math.max(0, parent.width * 0.5)
        height: 1.4
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#00FFFFFF" }
            GradientStop { position: 0.2; color: "#8CFFFFFF" }
            GradientStop { position: 0.7; color: "#26FFFFFF" }
            GradientStop { position: 1.0; color: "#00FFFFFF" }
        }
    }

    Item {
        id: header
        anchors.top: parent.top
        anchors.topMargin: 20
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        height: 54

        GlassButton {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: sheet.cancelText
            tone: "tinted"
            fontSize: 14
            padH: 20
            minHeight: 40
            onClicked: sheet.cancelRequested()
        }

        Text {
            anchors.centerIn: parent
            text: sheet.title
            color: AppTheme.textPrimary
            font.pixelSize: 20
            font.weight: Font.Bold
            font.family: C.numFont
        }

        GlassButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: sheet.doneText
            tone: "light"
            fontSize: 14
            padH: 22
            minHeight: 40
            enabled: sheet.doneEnabled
            onClicked: sheet.doneRequested()
        }
    }

    Item {
        id: contentHost
        anchors.top: header.bottom
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        height: childrenRect.height
    }

    Item {
        id: deleteRow
        visible: sheet.deleteVisible
        anchors.top: contentHost.bottom
        anchors.topMargin: 18
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        height: 56

        // 删除行：红色警示底。玻璃主题用半透明红玻璃质感；纯色/浅色用实底红。
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: {
                if (AppTheme.glass) {
                    return sheet.deleteArmed
                           ? (deletePointer.containsMouse ? "#38FF6B7A" : "#2EFF6B7A")
                           : (deletePointer.containsMouse ? "#26FF6B7A" : "#18FF6B7A")
                }
                if (AppTheme.light) {
                    return sheet.deleteArmed
                           ? (deletePointer.containsMouse ? "#FFD9DE" : "#FFE3E7")
                           : (deletePointer.containsMouse ? "#FDECEE" : "#FFF3F4")
                }
                return sheet.deleteArmed
                       ? (deletePointer.containsMouse ? "#471B23" : "#3D161E")
                       : (deletePointer.containsMouse ? "#33141B" : "#291016")
            }
            Behavior on color {
                ColorAnimation { duration: 160 }
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: AppTheme.glass
            radius: 18
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#14FFFFFF" }
                GradientStop { position: 0.45; color: "#00FFFFFF" }
                GradientStop { position: 1.0; color: "#1A000000" }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: "transparent"
            border.width: 1
            border.color: AppTheme.light
                          ? (sheet.deleteArmed ? "#B3E2555F" : "#66E2555F")
                          : (sheet.deleteArmed ? "#8CFF6B7A"
                                               : (deletePointer.containsMouse ? "#59FF6B7A" : "#33FF6B7A"))
            Behavior on border.color { ColorAnimation { duration: 160 } }
        }

        Text {
            anchors.centerIn: parent
            text: sheet.deleteArmed ? qsTr("再次点击，确认删除") : sheet.deleteText
            color: AppTheme.light ? AppTheme.danger
                                  : (sheet.deleteArmed ? "#FF98A6" : "#FF8092")
            font.pixelSize: 15
            font.weight: Font.DemiBold
            font.family: C.numFont
        }

        MouseArea {
            id: deletePointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sheet.deleteRequested()
        }
    }
}
