import QtQuick
import "../theme"
import "Constants.js" as C

// 设置行：左标题 + 右值/自定义尾部 + 可选 chevron
Item {
    id: root
    default property alias trailing: trailingHost.data

    property string title: ""
    property string value: ""
    property bool showChevron: true
    property bool interactive: true
    property bool expandable: false
    property bool expanded: false
    property int titleSize: 15
    property string titleColor: AppTheme.textPrimary
    property int rowHeight: 62

    implicitHeight: rowHeight

    signal clicked()

    Rectangle {
        id: rowBg
        anchors.fill: parent
        radius: 14
        color: (root.interactive && pointer.containsMouse) ? "#0DFFFFFF" : "#00FFFFFF"
    }

    Text {
        id: titleText
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        color: root.titleColor
        font.pixelSize: root.titleSize
        font.weight: Font.DemiBold
        font.family: C.numFont
        elide: Text.ElideRight
        width: Math.min(implicitWidth, root.width - 190)
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.value
            visible: root.value !== ""
            color: AppTheme.textSecondary
            font.pixelSize: 14
            font.family: C.numFont
        }

        Item {
            id: trailingHost
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: 32
        }

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showChevron
            kind: root.expandable && root.expanded ? "chevronDown" : "chevron"
            size: 13
            color: AppTheme.textTertiary
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.interactive) root.clicked()
    }
}