import QtQuick

// 页面容器（v0.6 全局动画）
// - 进入：200ms 淡入 + 从下方 8px 上移（OutCubic）
// - 离开：160ms 淡出 + 下移 6px（OutCubic）
// - 浮层页（主题/关于）可开启 0.98→1 的轻微缩放（scaleEnabled）
// - animationsEnabled=false（对应 Main.pageTransitions=false）时全部瞬时完成
Item {
    id: root

    property bool active: false
    property bool animationsEnabled: true
    property bool scaleEnabled: false

    default property alias content: stage.data

    visible: stage.opacity > 0.001
    // 退出动画期间仍为 true，供外层保持 z 序（浮层页关闭时不被底层盖住）
    readonly property bool shown: stage.opacity > 0.001
    enabled: root.active

    function applyShown() {
        stage.opacity = 1
        stageShift.y = 0
        stage.scale = 1
    }

    function applyHidden() {
        stage.opacity = 0
        stageShift.y = 6
        stage.scale = root.scaleEnabled ? 0.98 : 1
    }

    onActiveChanged: {
        if (!stage) return
        enterAnim.stop()
        exitAnim.stop()
        if (root.active) {
            if (root.animationsEnabled)
                enterAnim.restart()
            else
                root.applyShown()
        } else {
            // 首次创建时 active=false 也会走到这里，直接落到隐藏态即可（过渡动画无目标变化）
            if (root.animationsEnabled && stage.opacity > 0.001)
                exitAnim.restart()
            else
                root.applyHidden()
        }
    }

    Component.onCompleted: {
        if (root.active)
            root.applyShown()
        else
            root.applyHidden()
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation {
            target: stage
            property: "opacity"
            from: 0
            to: 1
            duration: root.animationsEnabled ? 200 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: stageShift
            property: "y"
            from: 8
            to: 0
            duration: root.animationsEnabled ? 200 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: stage
            property: "scale"
            from: root.scaleEnabled ? 0.98 : 1
            to: 1
            duration: root.animationsEnabled && root.scaleEnabled ? 220 : 0
            easing.type: Easing.OutCubic
        }
    }

    ParallelAnimation {
        id: exitAnim
        NumberAnimation {
            target: stage
            property: "opacity"
            to: 0
            duration: root.animationsEnabled ? 160 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: stageShift
            property: "y"
            to: 6
            duration: root.animationsEnabled ? 160 : 0
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: stage
            property: "scale"
            to: root.scaleEnabled ? 0.98 : 1
            duration: root.animationsEnabled && root.scaleEnabled ? 160 : 0
            easing.type: Easing.OutCubic
        }
    }

    Item {
        id: stage
        objectName: "AnimatedStage"
        anchors.fill: parent
        opacity: 0
        scale: 1
        // 供测试/调试读取当前纵向位移
        property alias shiftY: stageShift.y

        // anchors.fill 会锁住 x/y，位移用 Translate 实现
        transform: Translate {
            id: stageShift
            y: 6
        }
    }
}
