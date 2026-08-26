import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.config

Item {
    id: workspacesWidget
    required property var bar
    required property string orientation
    readonly property var monitor: AxctlService.monitorFor(bar.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    // === perMonitor N dinámico — reimplementación spec-driven ===
    // perMonitorMode true solo si config flag + al menos 2 pantallas físicas
    readonly property bool perMonitorMode: (Config.workspaces.perMonitor ?? false) && Quickshell.screens.length >= 2
    // perMonitorCount 10 clamp 1..20 — cada monitor muestra exactamente este número de dots
    readonly property int perMonitorShown: Math.max(1, Math.min(20, Config.workspaces.perMonitorCount ?? 10))
    // monitorOffset determinístico ordenado por x (AxctlService.monitors metadata.x y Quickshell.screens.x) luego y, id, nombre
    // N dinámico: 2 monitores => 1-10,11-20 ; 3 monitores => 1-10,11-20,21-30 ; 4 monitores => 1-10,11-20,21-30,31-40
    readonly property int monitorOffset: {
        if (!perMonitorMode) return 0
        const mName = monitor && monitor.name ? monitor.name : ""
        if (!mName) return 0
        const axMonitors = AxctlService.monitors.values || []
        if (axMonitors.length > 0) {
            const ordered = axMonitors.slice().sort((a, b) => {
                const ax = (a && a.x !== undefined) ? a.x : (a && a.id !== undefined ? a.id * 10000 : 99999)
                const bx = (b && b.x !== undefined) ? b.x : (b && b.id !== undefined ? b.id * 10000 : 99999)
                if (ax !== bx) return ax - bx
                const ay = (a && a.y !== undefined) ? a.y : 0
                const by = (b && b.y !== undefined) ? b.y : 0
                if (ay !== by) return ay - by
                const aid = (a && a.id !== undefined) ? a.id : 999
                const bid = (b && b.id !== undefined) ? b.id : 999
                if (aid !== bid) return aid - bid
                return String(a ? a.name : "").localeCompare(String(b ? b.name : ""))
            })
            const idx = ordered.findIndex(m => m && m.name === mName)
            if (idx >= 0) return idx
            const rawIdx = axMonitors.findIndex(m => m && m.name === mName)
            if (rawIdx >= 0) return rawIdx
        }
        const screens = Quickshell.screens || []
        if (screens.length > 0) {
            const orderedScreens = screens.slice().sort((a, b) => {
                if (a && b && a.x !== undefined && b.x !== undefined && a.x !== b.x) return a.x - b.x
                if (a && b && a.y !== undefined && b.y !== undefined && a.y !== b.y) return a.y - b.y
                return String(a ? a.name : "").localeCompare(String(b ? b.name : ""))
            })
            const sIdx = orderedScreens.findIndex(s => s && s.name === mName)
            if (sIdx >= 0) return sIdx
            const rawSIdx = screens.findIndex(s => s && s.name === mName)
            if (rawSIdx >= 0) return rawSIdx
        }
        return 0
    }

    // workspaceGroup deshabilitado en perMonitor (0) — cada monitor partición independiente
    // global: mantiene comportamiento original (grupo basado en activeWorkspace del monitor)
    readonly property int workspaceGroup: perMonitorMode ? 0 : Math.floor(((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) - 1 || 0) / (Config.workspaces.shown ?? 10))
    property var workspaceOccupied: []
    property var dynamicWorkspaceIds: []
    // effectiveWorkspaceCount: perMonitor => perMonitorShown ; global => shown o dynamic
    property int effectiveWorkspaceCount: perMonitorMode ? perMonitorShown : (Config.workspaces.dynamic ? dynamicWorkspaceIds.length : (Config.workspaces.shown ?? 10))
    property int widgetPadding: 4
    property real radius: Styling.radius(0)
    property real startRadius: radius
    property real endRadius: radius

    property int baseSize: 36
    property int workspaceButtonSize: baseSize - widgetPadding * 2
    property int workspaceButtonWidth: workspaceButtonSize
    property real workspaceIconSize: Math.round(workspaceButtonWidth * 0.6)
    property real workspaceIconSizeShrinked: Math.round(workspaceButtonWidth * 0.5)
    property real workspaceIconOpacityShrinked: 1
    property real workspaceIconMarginShrinked: -4
    // workspaceIndexInGroup filtrado por monitor cuando perMonitor true
    property int workspaceIndexInGroup: {
        const curMon = AxctlService.monitorFor(bar.screen)
        const activeId = (curMon && curMon.activeWorkspace ? curMon.activeWorkspace.id : (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined)) || 1
        if (perMonitorMode) {
            const minId = monitorOffset * perMonitorShown + 1
            const idx = activeId - minId
            if (idx >= 0 && idx < perMonitorShown) return idx
            // active fuera de partición (ej hard restart o workspace aún no asignado) => mostrar primero sin highlight cruzado
            return 0
        }
        if (Config.workspaces.dynamic) return dynamicWorkspaceIds.indexOf(activeId)
        return ((activeId - 1 || 0) % (Config.workspaces.shown ?? 10))
    }
    property var occupiedRanges: []

    // updateWorkspaceOccupied filtrado por monitor en perMonitor: solo workspaces del rango offset*count+1 .. (offset+1)*count
    function updateWorkspaceOccupied() {
        if (perMonitorMode) {
            const occ = []
            const base = monitorOffset * perMonitorShown
            for (let i = 0; i < perMonitorShown; i++) {
                const wsId = base + i + 1
                occ.push(!!CompositorData.workspaceOccupationMap[wsId])
            }
            workspaceOccupied = occ
            // compat: mantener dynamicWorkspaceIds sincronizado pero no usado en perMonitor
            // no sobreescribir lógica global
        } else {
            if (Config.workspaces.dynamic) {
                const shownVal = Math.max(1, Math.min(20, Config.workspaces.shown ?? 10))
                const occupiedIds = (AxctlService.workspaces.values || []).filter(ws => CompositorData.workspaceOccupationMap[ws.id]).map(ws => ws.id).sort((a, b) => a - b).slice(0, shownVal)
                const activeId = (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) || 1
                if (!occupiedIds.includes(activeId)) {
                    occupiedIds.push(activeId)
                    occupiedIds.sort((a, b) => a - b)
                    if (occupiedIds.length > shownVal) occupiedIds.pop()
                }
                dynamicWorkspaceIds = occupiedIds
                workspaceOccupied = Array.from({ length: dynamicWorkspaceIds.length }, (_, i) => !!CompositorData.workspaceOccupationMap[dynamicWorkspaceIds[i]])
            } else {
                const shownVal = Math.max(1, Math.min(20, Config.workspaces.shown ?? 10))
                workspaceOccupied = Array.from({ length: shownVal }, (_, i) => {
                    const wsId = workspaceGroup * shownVal + i + 1
                    return !!CompositorData.workspaceOccupationMap[wsId]
                })
            }
        }
        updateOccupiedRanges()
    }

    function updateOccupiedRanges() {
        const ranges = []
        let rangeStart = -1
        for (let i = 0; i < effectiveWorkspaceCount; i++) {
            const isOccupied = workspaceOccupied[i]
            if (isOccupied) {
                if (rangeStart === -1) rangeStart = i
            } else {
                if (rangeStart !== -1) {
                    ranges.push({ start: rangeStart, end: i - 1 })
                    rangeStart = -1
                }
            }
        }
        if (rangeStart !== -1) ranges.push({ start: rangeStart, end: effectiveWorkspaceCount - 1 })
        occupiedRanges = ranges
    }

    function workspaceLabelFontSize(value) {
        const label = String(value)
        const shrink = label.length > 1 && label !== "10" ? (label.length - 1) * 2 : 0
        return Math.round(Math.max(1, Config.theme.fontSize - shrink))
    }

    // IDs particionados monitorOffset*perMonitorCount+index+1 en perMonitor; global igual que original
    function getWorkspaceId(index) {
        if (perMonitorMode) return monitorOffset * perMonitorShown + index + 1
        if (Config.workspaces.dynamic) return dynamicWorkspaceIds[index] || 1
        return workspaceGroup * (Config.workspaces.shown ?? 10) + index + 1
    }

    Timer {
        id: updateTimer
        interval: 100
        repeat: false
        onTriggered: workspacesWidget.updateWorkspaceOccupied()
    }

    Component.onCompleted: updateTimer.restart()

    Connections {
        target: AxctlService.workspaces
        function onValuesChanged() { updateTimer.restart() }
    }
    Connections {
        target: AxctlService.monitors
        function onValuesChanged() { updateTimer.restart() }
    }
    Connections {
        target: activeWindow
        function onActivatedChanged() { updateTimer.restart() }
    }
    Connections {
        target: CompositorData
        function onWindowListChanged() { updateTimer.restart() }
    }
    Connections {
        target: CompositorData
        function onWorkspaceOccupationMapChanged() { updateTimer.restart() }
    }

    onWorkspaceGroupChanged: updateTimer.restart()
    onPerMonitorModeChanged: updateTimer.restart()
    onMonitorOffsetChanged: updateTimer.restart()
    onPerMonitorShownChanged: updateTimer.restart()
    onEffectiveWorkspaceCountChanged: updateTimer.restart()

    implicitWidth: orientation === "vertical" ? baseSize : workspaceButtonSize * effectiveWorkspaceCount + widgetPadding * 2
    implicitHeight: orientation === "vertical" ? workspaceButtonSize * effectiveWorkspaceCount + widgetPadding * 2 : baseSize

    readonly property bool effectiveContainBar: Config.bar.containBar && ((Config.bar.frameEnabled !== undefined ? Config.bar.frameEnabled : false))

    StyledRect {
        id: bgRect
        variant: "bg"
        anchors.fill: parent
        enableShadow: Config.showBackground && (!effectiveContainBar || Config.bar.keepBarShadow)
        topLeftRadius: orientation === "vertical" ? workspacesWidget.startRadius : workspacesWidget.startRadius
        topRightRadius: orientation === "vertical" ? workspacesWidget.startRadius : workspacesWidget.endRadius
        bottomLeftRadius: orientation === "vertical" ? workspacesWidget.endRadius : workspacesWidget.startRadius
        bottomRightRadius: orientation === "vertical" ? workspacesWidget.endRadius : workspacesWidget.endRadius
    }

    // Navegación solo dentro del monitor en perMonitor (clamp); global usa r+1/r-1
    WheelHandler {
        onWheel: event => {
            if (perMonitorMode) {
                const curMon = AxctlService.monitorFor(bar.screen)
                const curId = (curMon && curMon.activeWorkspace ? curMon.activeWorkspace.id : (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 1)) || 1
                const minId = monitorOffset * perMonitorShown + 1
                const maxId = minId + perMonitorShown - 1
                if (event.angleDelta.y < 0) {
                    const tgt = Math.min(maxId, curId + 1)
                    if (tgt !== curId) AxctlService.dispatch(`workspace ${tgt}`)
                } else if (event.angleDelta.y > 0) {
                    const tgt = Math.max(minId, curId - 1)
                    if (tgt !== curId) AxctlService.dispatch(`workspace ${tgt}`)
                }
            } else {
                if (event.angleDelta.y < 0) AxctlService.dispatch(`workspace r+1`)
                else if (event.angleDelta.y > 0) AxctlService.dispatch(`workspace r-1`)
            }
        }
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onPressed: event => {
            if (event.button === Qt.BackButton) AxctlService.dispatch(`togglespecialworkspace`)
        }
    }

    Item {
        id: rowLayout
        visible: orientation === "horizontal"
        z: 1
        anchors.fill: parent
        anchors.margins: widgetPadding
        Repeater {
            model: occupiedRanges
            StyledRect {
                variant: "focus"
                required property int index
                required property var modelData
                z: 1
                width: (modelData.end - modelData.start + 1) * workspaceButtonWidth
                height: workspaceButtonWidth
                radius: workspacesWidget.startRadius > 0 ? Math.max(workspacesWidget.startRadius - widgetPadding, 0) : 0
                opacity: Config.theme.srFocus.opacity
                x: modelData.start * workspaceButtonWidth
                y: 0
                Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Math.max(0, Config.animDuration - 100); easing.type: Easing.OutQuad } }
                Behavior on x { enabled: Config.animDuration > 0; NumberAnimation { duration: Math.max(0, Config.animDuration - 100); easing.type: Easing.OutQuad } }
                Behavior on width { enabled: Config.animDuration > 0; NumberAnimation { duration: Math.max(0, Config.animDuration - 100); easing.type: Easing.OutQuad } }
            }
        }
    }

    Item {
        id: columnLayout
        visible: orientation === "vertical"
        z: 1
        anchors.fill: parent
        anchors.margins: widgetPadding
        Repeater {
            model: occupiedRanges
            StyledRect {
                variant: "focus"
                required property int index
                required property var modelData
                z: 1
                width: workspaceButtonWidth
                height: (modelData.end - modelData.start + 1) * workspaceButtonWidth
                radius: workspacesWidget.startRadius > 0 ? Math.max(workspacesWidget.startRadius - widgetPadding, 0) : 0
                opacity: Config.theme.srFocus.opacity
                x: 0
                y: modelData.start * workspaceButtonWidth
                Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: Math.max(0, Config.animDuration - 100); easing.type: Easing.OutQuad } }
                Behavior on y { enabled: Config.animDuration > 0; NumberAnimation { duration: Math.max(0, Config.animDuration - 100); easing.type: Easing.OutQuad } }
                Behavior on height { enabled: Config.animDuration > 0; NumberAnimation { duration: Math.max(0, Config.animDuration - 100); easing.type: Easing.OutQuad } }
            }
        }
    }

    StyledRect {
        id: activeHighlightH
        variant: "primary"
        visible: orientation === "horizontal"
        z: 2
        property real activeWorkspaceMargin: 4
        property real idx1: workspaceIndexInGroup
        property real idx2: workspaceIndexInGroup
        implicitWidth: Math.abs(idx1 - idx2) * workspaceButtonWidth + workspaceButtonWidth - activeWorkspaceMargin * 2
        implicitHeight: workspaceButtonWidth - activeWorkspaceMargin * 2
        radius: {
            const activeWorkspaceId = (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) || 1
            const currentWorkspaceHasWindows = CompositorData.workspaceOccupationMap[activeWorkspaceId]
            if (workspacesWidget.radius === 0) return 0
            return currentWorkspaceHasWindows ? workspacesWidget.radius > 0 ? Math.max(workspacesWidget.radius - parent.widgetPadding - activeWorkspaceMargin, 0) : 0 : implicitHeight / 2
        }
        anchors.verticalCenter: parent.verticalCenter
        x: Math.min(idx1, idx2) * workspaceButtonWidth + activeWorkspaceMargin + widgetPadding
        y: parent.height / 2 - implicitHeight / 2
        Behavior on activeWorkspaceMargin { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration / 2; easing.type: Easing.OutQuad } }
        Behavior on idx1 { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration / 3; easing.type: Easing.OutSine } }
        Behavior on idx2 { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutSine } }
    }

    StyledRect {
        id: activeHighlightV
        variant: "primary"
        visible: orientation === "vertical"
        z: 2
        property real activeWorkspaceMargin: 4
        property real idx1: workspaceIndexInGroup
        property real idx2: workspaceIndexInGroup
        implicitWidth: workspaceButtonWidth - activeWorkspaceMargin * 2
        implicitHeight: Math.abs(idx1 - idx2) * workspaceButtonWidth + workspaceButtonWidth - activeWorkspaceMargin * 2
        radius: {
            const activeWorkspaceId = (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) || 1
            const currentWorkspaceHasWindows = CompositorData.workspaceOccupationMap[activeWorkspaceId]
            if (workspacesWidget.radius === 0) return 0
            return currentWorkspaceHasWindows ? workspacesWidget.radius > 0 ? Math.max(workspacesWidget.radius - parent.widgetPadding - activeWorkspaceMargin, 0) : 0 : implicitWidth / 2
        }
        anchors.horizontalCenter: parent.horizontalCenter
        x: parent.width / 2 - implicitWidth / 2
        y: Math.min(idx1, idx2) * workspaceButtonWidth + activeWorkspaceMargin + widgetPadding
        Behavior on activeWorkspaceMargin { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration / 2; easing.type: Easing.OutQuad } }
        Behavior on idx1 { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration / 3; easing.type: Easing.OutSine } }
        Behavior on idx2 { enabled: Config.animDuration > 0; NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutSine } }
    }

    RowLayout {
        id: rowLayoutNumbers
        visible: orientation === "horizontal"
        z: 3
        spacing: 0
        anchors.fill: parent
        anchors.margins: widgetPadding
        implicitHeight: workspaceButtonWidth
        Repeater {
            model: effectiveWorkspaceCount
            Button {
                id: button
                property int workspaceValue: getWorkspaceId(index)
                Layout.fillHeight: true
                onPressed: AxctlService.dispatch(`workspace ${workspaceValue}`)
                width: workspaceButtonWidth
                background: Item {
                    id: workspaceButtonBackground
                    implicitWidth: workspaceButtonWidth
                    implicitHeight: workspaceButtonWidth
                    property var focusedWindow: {
                        const windowsInThisWorkspace = CompositorData.workspaceWindowsMap[button.workspaceValue] || []
                        if (windowsInThisWorkspace.length === 0) return null
                        return windowsInThisWorkspace.reduce((best, win) => {
                            const bestFocus = (best && best.focusHistoryID !== undefined ? best.focusHistoryID : Infinity)
                            const winFocus = (win && win.focusHistoryID !== undefined ? win.focusHistoryID : Infinity)
                            return winFocus < bestFocus ? win : best
                        }, null)
                    }
                    readonly property var focusedDesktopEntry: focusedWindow ? DesktopEntries.heuristicLookup(focusedWindow.class) : null
                    property var mainAppIconSource: {
                        if (focusedDesktopEntry && focusedDesktopEntry.icon) return Quickshell.iconPath(focusedDesktopEntry.icon, "image-missing")
                        return Quickshell.iconPath(AppSearch.getCachedIcon(focusedWindow ? focusedWindow.class : undefined), "image-missing")
                    }
                    Text {
                        opacity: Config.workspaces.alwaysShowNumbers || ((Config.workspaces.showNumbers && (!Config.workspaces.showAppIcons || !workspaceButtonBackground.focusedWindow || Config.workspaces.alwaysShowNumbers)) || (Config.workspaces.alwaysShowNumbers && !Config.workspaces.showAppIcons)) ? 1 : 0
                        z: 3
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: Config.theme.font
                        font.pixelSize: workspaceLabelFontSize(text)
                        text: `${button.workspaceValue}`
                        elide: Text.ElideRight
                        color: ((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) == button.workspaceValue) ? Styling.srItem("primary") : (workspaceOccupied[index] ? Colors.overBackground : Colors.overSecondaryFixedVariant)
                        Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    }
                    Rectangle {
                        opacity: (Config.workspaces.showNumbers || Config.workspaces.alwaysShowNumbers || (Config.workspaces.showAppIcons && workspaceButtonBackground.focusedWindow)) ? 0 : (((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) == button.workspaceValue) || workspaceOccupied[index] ? 1 : 0.5)
                        visible: opacity > 0
                        anchors.centerIn: parent
                        width: workspaceButtonWidth * 0.2
                        height: width
                        radius: width / 2
                        color: ((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) == button.workspaceValue) ? Styling.srItem("primary") : Colors.overBackground
                        Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    }
                    Item {
                        anchors.centerIn: parent
                        width: workspaceButtonWidth
                        height: workspaceButtonWidth
                        opacity: !Config.workspaces.showAppIcons ? 0 : (workspaceButtonBackground.focusedWindow && !Config.workspaces.alwaysShowNumbers && Config.workspaces.showAppIcons) ? 1 : workspaceButtonBackground.focusedWindow ? workspaceIconOpacityShrinked : 0
                        visible: opacity > 0
                        IconImage {
                            id: mainAppIcon
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.bottomMargin: (!Config.workspaces.alwaysShowNumbers && Config.workspaces.showAppIcons) ? Math.round((workspaceButtonWidth - workspaceIconSize) / 2) : workspaceIconMarginShrinked
                            anchors.rightMargin: (!Config.workspaces.alwaysShowNumbers && Config.workspaces.showAppIcons) ? Math.round((workspaceButtonWidth - workspaceIconSize) / 2) : workspaceIconMarginShrinked
                            source: workspaceButtonBackground.mainAppIconSource
                            implicitSize: (!Config.workspaces.alwaysShowNumbers && Config.workspaces.showAppIcons) ? workspaceIconSize : workspaceIconSizeShrinked
                            Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            Behavior on anchors.bottomMargin { enabled: Config.animDuration > 0; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            Behavior on anchors.rightMargin { enabled: Config.animDuration > 0; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            Behavior on implicitSize { enabled: Config.animDuration > 0; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                        }
                        Tinted { sourceItem: mainAppIcon; anchors.fill: mainAppIcon }
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: columnLayoutNumbers
        visible: orientation === "vertical"
        z: 3
        spacing: 0
        anchors.fill: parent
        anchors.margins: widgetPadding
        implicitWidth: workspaceButtonWidth
        Repeater {
            model: effectiveWorkspaceCount
            Button {
                id: buttonVert
                property int workspaceValue: getWorkspaceId(index)
                Layout.fillWidth: true
                onPressed: AxctlService.dispatch(`workspace ${workspaceValue}`)
                height: workspaceButtonWidth
                background: Item {
                    id: workspaceButtonBackgroundVert
                    implicitWidth: workspaceButtonWidth
                    implicitHeight: workspaceButtonWidth
                    property var focusedWindow: {
                        const windowsInThisWorkspace = CompositorData.workspaceWindowsMap[buttonVert.workspaceValue] || []
                        if (windowsInThisWorkspace.length === 0) return null
                        return windowsInThisWorkspace.reduce((best, win) => {
                            const bestFocus = (best && best.focusHistoryID !== undefined ? best.focusHistoryID : Infinity)
                            const winFocus = (win && win.focusHistoryID !== undefined ? win.focusHistoryID : Infinity)
                            return winFocus < bestFocus ? win : best
                        }, null)
                    }
                    readonly property var focusedDesktopEntry: focusedWindow ? DesktopEntries.heuristicLookup(focusedWindow.class) : null
                    property var mainAppIconSource: {
                        if (focusedDesktopEntry && focusedDesktopEntry.icon) return Quickshell.iconPath(focusedDesktopEntry.icon, "image-missing")
                        return Quickshell.iconPath(AppSearch.getCachedIcon(focusedWindow ? focusedWindow.class : undefined), "image-missing")
                    }
                    Text {
                        opacity: Config.workspaces.alwaysShowNumbers || ((Config.workspaces.showNumbers && (!Config.workspaces.showAppIcons || !workspaceButtonBackgroundVert.focusedWindow || Config.workspaces.alwaysShowNumbers)) || (Config.workspaces.alwaysShowNumbers && !Config.workspaces.showAppIcons)) ? 1 : 0
                        z: 3
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: Config.theme.font
                        font.pixelSize: workspaceLabelFontSize(text)
                        text: `${buttonVert.workspaceValue}`
                        elide: Text.ElideRight
                        color: ((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) == buttonVert.workspaceValue) ? Styling.srItem("primary") : (workspaceOccupied[index] ? Colors.overBackground : Colors.overSecondaryFixedVariant)
                        Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    }
                    Rectangle {
                        opacity: (Config.workspaces.showNumbers || Config.workspaces.alwaysShowNumbers || (Config.workspaces.showAppIcons && workspaceButtonBackgroundVert.focusedWindow)) ? 0 : (((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) == buttonVert.workspaceValue) || workspaceOccupied[index] ? 1 : 0.5)
                        visible: opacity > 0
                        anchors.centerIn: parent
                        width: workspaceButtonWidth * 0.2
                        height: width
                        radius: width / 2
                        color: ((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) == buttonVert.workspaceValue) ? Styling.srItem("primary") : Colors.overBackground
                        Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    }
                    Item {
                        anchors.centerIn: parent
                        width: workspaceButtonWidth
                        height: workspaceButtonWidth
                        opacity: !Config.workspaces.showAppIcons ? 0 : (workspaceButtonBackgroundVert.focusedWindow && !Config.workspaces.alwaysShowNumbers && Config.workspaces.showAppIcons) ? 1 : workspaceButtonBackgroundVert.focusedWindow ? workspaceIconOpacityShrinked : 0
                        visible: opacity > 0
                        IconImage {
                            id: mainAppIconVert
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.bottomMargin: (!Config.workspaces.alwaysShowNumbers && Config.workspaces.showAppIcons) ? Math.round((workspaceButtonWidth - workspaceIconSize) / 2) : workspaceIconMarginShrinked
                            anchors.rightMargin: (!Config.workspaces.alwaysShowNumbers && Config.workspaces.showAppIcons) ? Math.round((workspaceButtonWidth - workspaceIconSize) / 2) : workspaceIconMarginShrinked
                            source: workspaceButtonBackgroundVert.mainAppIconSource
                            implicitSize: (!Config.workspaces.alwaysShowNumbers && Config.workspaces.showAppIcons) ? workspaceIconSize : workspaceIconSizeShrinked
                            Behavior on opacity { enabled: Config.animDuration > 0; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            Behavior on anchors.bottomMargin { enabled: Config.animDuration > 0; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            Behavior on anchors.rightMargin { enabled: Config.animDuration > 0; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            Behavior on implicitSize { enabled: Config.animDuration > 0; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                        }
                        Tinted { sourceItem: mainAppIconVert; anchors.fill: mainAppIconVert }
                    }
                }
            }
        }
    }
}
