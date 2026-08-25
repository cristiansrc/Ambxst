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

    // perMonitor dinámico: requiere flag + al menos 2 pantallas físicas (Quickshell.screens) o 2 monitores reportados por axctl
    readonly property bool perMonitorMode: (Config.workspaces.perMonitor ?? false) && Quickshell.screens.length >= 2
    // monitorOffset determinístico ordenado por x/id (no por findIndex desordenado de Quickshell.screens/Axctl)
    // N dinámico: 3 monitores x0,x1920,x4480 => offsets 0,1,2 => IDs 1-10,11-20,21-30 cuando perMonitorCount=10
    readonly property int monitorOffset: {
        if (!perMonitorMode) return 0;
        const mName = monitor && monitor.name ? monitor.name : "";
        if (!mName) return 0;
        // Preferir AxctlService.monitors ordenado determinísticamente por x luego id luego nombre
        const axMonitors = AxctlService.monitors.values || [];
        if (axMonitors.length > 0) {
            const ordered = axMonitors.slice().sort((a, b) => {
                const ax = (a && a.x !== undefined) ? a.x : (a && a.id !== undefined ? a.id * 10000 : 99999);
                const bx = (b && b.x !== undefined) ? b.x : (b && b.id !== undefined ? b.id * 10000 : 99999);
                if (ax !== bx) return ax - bx;
                const aid = (a && a.id !== undefined) ? a.id : 999;
                const bid = (b && b.id !== undefined) ? b.id : 999;
                if (aid !== bid) return aid - bid;
                return String(a ? a.name : "").localeCompare(String(b ? b.name : ""));
            });
            const idx = ordered.findIndex(m => m && m.name === mName);
            if (idx >= 0) return idx;
            // fallback sin ordenar (por si orden no resuelve)
            const rawIdx = axMonitors.findIndex(m => m && m.name === mName);
            if (rawIdx >= 0) return rawIdx;
        }
        // Fallback a Quickshell.screens ordenado por x luego nombre (determinístico)
        const screens = Quickshell.screens || [];
        if (screens.length > 0) {
            const orderedScreens = screens.slice().sort((a, b) => {
                if (a && b && a.x !== undefined && b.x !== undefined && a.x !== b.x) return a.x - b.x;
                return String(a ? a.name : "").localeCompare(String(b ? b.name : ""));
            });
            const sIdx = orderedScreens.findIndex(s => s && s.name === mName);
            if (sIdx >= 0) return sIdx;
            const rawSIdx = screens.findIndex(s => s && s.name === mName);
            if (rawSIdx >= 0) return rawSIdx;
        }
        return 0;
    }
    // perMonitorCount dinámico por monitor (default 5), clamp 1..20 — cada monitor muestra exactamente perMonitorShown dots
    // Total workspaces sistema = perMonitorShown * Quickshell.screens.length (2→10, 3→15)
    readonly property int perMonitorShown: perMonitorMode ? Math.max(1, Math.min(20, Config.workspaces.perMonitorCount ?? 5)) : (Config.workspaces.shown ?? 10)

    // Lista real por monitor: filtra AxctlService.workspaces.values donde ws.monitor == bar.screen.name, ordena por id,
    // toma hasta perMonitorCount, incluye activeWorkspace.id si no está. Prioritaria sobre offset virtual.
    // Fallback a offset*count si no hay workspaces reales (boot temprano). Reactiva a workspaces, monitors y screens.
    readonly property var perMonitorRealIds: {
        if (!perMonitorMode) return [];
        const cnt = perMonitorShown;
        // dependencias reactivas explícitas para hard-restart-free: screens, workspaces, monitors
        const _scrLen = Quickshell.screens.length;
        const wsVals = AxctlService.workspaces.values;
        const _monVals = AxctlService.monitors.values;
        const curMon = AxctlService.monitorFor(bar.screen);
        const mName = curMon && curMon.name ? curMon.name : (monitor && monitor.name ? monitor.name : (bar.screen && bar.screen.name ? bar.screen.name : ""));
        const curMonId = curMon && curMon.id !== undefined ? curMon.id : (monitor && monitor.id !== undefined ? monitor.id : undefined);
        if (!mName) {
            const off = monitorOffset;
            let arr = [];
            for (let i = 0; i < cnt; i++) arr.push(off * cnt + i + 1);
            return arr;
        }
        let filtered = [];
        for (let i = 0; i < (wsVals || []).length; i++) {
            const w = wsVals[i];
            if (!w || w.id === undefined || w.id === null) continue;
            const wMon = w.monitor;
            if (wMon === undefined || wMon === null || String(wMon) === "") continue;
            if (String(wMon) === String(mName) || (curMonId !== undefined && String(wMon) === String(curMonId))) {
                filtered.push(w);
            }
        }
        filtered.sort((a, b) => (a.id || 0) - (b.id || 0));
        let ids = filtered.map(w => w.id);
        if (ids.length === 0) {
            const off = monitorOffset;
            let arr = [];
            for (let i = 0; i < cnt; i++) arr.push(off * cnt + i + 1);
            const activeId = curMon && curMon.activeWorkspace ? curMon.activeWorkspace.id : (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined);
            if (activeId !== undefined && activeId !== null && !arr.includes(activeId)) {
                // Si active pertenece a este monitor pero no está en rango virtual, forzar inclusión manteniendo cnt
                arr[cnt - 1] = activeId;
                arr.sort((a, b) => a - b);
            }
            return arr;
        }
        let sliced = ids.slice(0, cnt);
        const activeId2 = curMon && curMon.activeWorkspace ? curMon.activeWorkspace.id : (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined);
        if (activeId2 !== undefined && activeId2 !== null && !sliced.includes(activeId2)) {
            let belongs = false;
            let found = false;
            for (let k = 0; k < (wsVals || []).length; k++) {
                if (wsVals[k] && wsVals[k].id === activeId2) {
                    found = true;
                    const wm = wsVals[k].monitor;
                    if (String(wm) === String(mName) || (curMonId !== undefined && String(wm) === String(curMonId))) belongs = true;
                    break;
                }
            }
            if (!found) belongs = true; // workspace aún no en lista pero active del monitor => asumir pertenece
            if (belongs) {
                sliced.push(activeId2);
                sliced.sort((a, b) => a - b);
                if (sliced.length > cnt) {
                    // mantener cnt, remover el más lejano que no sea active
                    let rmIdx = sliced.length - 1;
                    if (sliced[rmIdx] === activeId2) rmIdx = sliced.length - 2;
                    // si active está en medio, remover último (no active)
                    if (rmIdx >= 0) sliced.splice(rmIdx, 1);
                    if (!sliced.includes(activeId2)) {
                        // edge: active fue removido, reinsertar forzado
                        sliced[cnt - 1] = activeId2;
                        sliced.sort((a, b) => a - b);
                    }
                    if (sliced.length > cnt) sliced = sliced.slice(0, cnt);
                }
            }
        }
        return sliced;
    }

    // workspaceGroup deshabilitado en perMonitor: cada monitor tiene grupo 0 independiente, rango calculado por lista real
    // perMonitor false => global: todos comparten 1..shown (grupo global basado en focusedWorkspace global, no per-monitor)
    readonly property int workspaceGroup: {
        if (perMonitorMode) return 0;
        const shownVal = Math.max(1, Math.min(20, Config.workspaces.shown ?? 10));
        // Preferir focusedWorkspace global para consistencia entre monitores cuando perMonitor false
        let gid = (AxctlService.focusedWorkspace && AxctlService.focusedWorkspace.id !== undefined ? AxctlService.focusedWorkspace.id : undefined);
        if (gid === undefined) gid = (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined);
        if (gid === undefined || gid === null) gid = 1;
        return Math.floor((gid - 1) / shownVal);
    }
    property var workspaceOccupied: []
    property var dynamicWorkspaceIds: []
    // effectiveWorkspaceCount: perMonitor usa perMonitorRealIds.length (dinámico hasta perMonitorCount), fallback perMonitorShown
    // global: shown (10) o dynamic length, compartido por todos los monitores
    property int effectiveWorkspaceCount: perMonitorMode ? (perMonitorRealIds.length > 0 ? perMonitorRealIds.length : perMonitorShown) : (Config.workspaces.dynamic ? dynamicWorkspaceIds.length : (Config.workspaces.shown ?? 10))
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
    property int workspaceIndexInGroup: {
        // dependencias reactivas: monitors, workspaces y perMonitorRealIds
        const _monVals2 = AxctlService.monitors.values;
        const curMon2 = AxctlService.monitorFor(bar.screen);
        const activeId = (curMon2 && curMon2.activeWorkspace ? curMon2.activeWorkspace.id : (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined)) || 1;
        if (perMonitorMode) {
            const idx = perMonitorRealIds.indexOf(activeId);
            if (idx >= 0) return idx;
            // active no está en lista real (p.ej. workspace de otro monitor) => 0
            return 0;
        }
        if (Config.workspaces.dynamic) return dynamicWorkspaceIds.indexOf(activeId);
        return ((activeId - 1 || 0) % (Config.workspaces.shown ?? 10));
    }
    property var occupiedRanges: []

    // Helper: ocupación filtrada por monitor asignado (no solo ID). Usa CompositorData si existe o Axctl workspace monitor_id.
    // En perMonitorMode el ID ya está particionado, pero filtramos además por workspace.monitor == bar.screen.name para evitar
    // que workspaces globales (1,2,3) se muestren como ocupados en monitores equivocados tras hard restart.
    function workspaceBelongsToCurrentMonitor(wsId) {
        const mName = (bar && bar.screen && bar.screen.name) ? bar.screen.name : (monitor && monitor.name ? monitor.name : "");
        if (!mName) return true; // null-safety: si no hay nombre, no filtrar
        const wsVals = AxctlService.workspaces.values || [];
        for (let k = 0; k < wsVals.length; k++) {
            const w = wsVals[k];
            if (w && w.id === wsId) {
                const wMon = w.monitor;
                if (wMon === undefined || wMon === null || wMon === "") return true;
                // wMon puede ser nombre (HDMI-A-1) o id numérico
                if (String(wMon) === String(mName)) return true;
                if (monitor && monitor.id !== undefined && String(wMon) === String(monitor.id)) return true;
                return false;
            }
        }
        // Si workspace aún no existe en AxctlService, considerar no-ocupado para este monitor (evita false positivos cross-monitor)
        // La ocupación real se basa en CompositorData.workspaceOccupationMap, pero si no hay objeto workspace, no pertenece
        return false;
    }

    // Lógica corregida: perMonitor true => IDs reales por monitor (filtrado ws.monitor == bar.screen.name)
    // perMonitor false => pool global 1..shown sin filtro monitor, ocupación global
    function updateWorkspaceOccupied() {
        if (perMonitorMode) {
            const ids = perMonitorRealIds;
            // Ocupación filtrada por monitor ya que ids son reales del monitor; map directo
            workspaceOccupied = ids.map(id => CompositorData.workspaceOccupationMap[id] || false);
            // Mantener dynamicWorkspaceIds sincronizado para compatibilidad (no usado en perMonitor pero útil para highlight)
            dynamicWorkspaceIds = ids.slice();
        } else {
            if (Config.workspaces.dynamic) {
                const shownVal = Math.max(1, Math.min(20, Config.workspaces.shown ?? 10));
                let occupiedIds = (AxctlService.workspaces.values || []).filter(ws => {
                    if (!ws || ws.id === undefined) return false;
                    if (!CompositorData.workspaceOccupationMap[ws.id]) return false;
                    return true;
                }).map(ws => ws.id).sort((a, b) => a - b);
                occupiedIds = occupiedIds.slice(0, shownVal);
                const activeId = (AxctlService.focusedWorkspace && AxctlService.focusedWorkspace.id !== undefined ? AxctlService.focusedWorkspace.id : (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined)) || 1;
                if (!occupiedIds.includes(activeId)) {
                    occupiedIds.push(activeId);
                    occupiedIds.sort((a, b) => a - b);
                    if (occupiedIds.length > shownVal) occupiedIds.pop();
                }
                dynamicWorkspaceIds = occupiedIds;
                workspaceOccupied = Array.from({
                    length: dynamicWorkspaceIds.length
                }, (_, i) => CompositorData.workspaceOccupationMap[dynamicWorkspaceIds[i]] || false);
            } else {
                // Global compartido: todos los monitores muestran mismos IDs 1..shown (workspaceGroup basado en focusedWorkspace global)
                const shownVal = Math.max(1, Math.min(20, Config.workspaces.shown ?? 10));
                workspaceOccupied = Array.from({
                    length: shownVal
                }, (_, i) => {
                    const wsId = workspaceGroup * shownVal + i + 1;
                    return CompositorData.workspaceOccupationMap[wsId] || false;
                });
            }
        }
        updateOccupiedRanges();
    }

    function updateOccupiedRanges() {
        const ranges = [];
        let rangeStart = -1;

        for (let i = 0; i < effectiveWorkspaceCount; i++) {
            const isOccupied = workspaceOccupied[i];

            if (isOccupied) {
                if (rangeStart === -1) {
                    rangeStart = i;
                }
            } else {
                if (rangeStart !== -1) {
                    ranges.push({
                        start: rangeStart,
                        end: i - 1
                    });
                    rangeStart = -1;
                }
            }
        }

        if (rangeStart !== -1) {
            ranges.push({
                start: rangeStart,
                end: effectiveWorkspaceCount - 1
            });
        }

        occupiedRanges = ranges;
    }

    function workspaceLabelFontSize(value) {
        const label = String(value);
        const shrink = label.length > 1 && label !== "10" ? (label.length - 1) * 2 : 0;
        return Math.round(Math.max(1, Config.theme.fontSize - shrink));
    }

    // ID por monitor: perMonitor true => IDs reales filtrados (perMonitorRealIds), fallback offset*count
    // perMonitor false => global compartido: grupo * shown + index, todos los monitores idénticos
    function getWorkspaceId(index) {
        if (perMonitorMode) {
            if (perMonitorRealIds && index >= 0 && index < perMonitorRealIds.length) return perMonitorRealIds[index];
            return monitorOffset * perMonitorShown + index + 1;
        }
        if (Config.workspaces.dynamic) {
            return dynamicWorkspaceIds[index] || 1;
        }
        return workspaceGroup * (Config.workspaces.shown ?? 10) + index + 1;
    }

    Timer {
        id: updateTimer
        interval: 100
        repeat: false
        onTriggered: workspacesWidget.updateWorkspaceOccupied()
    }

    // Initial update
    Component.onCompleted: updateTimer.restart()

    Connections {
        target: AxctlService.workspaces
        function onValuesChanged() {
            updateTimer.restart();
        }
    }

    Connections {
        target: activeWindow
        function onActivatedChanged() {
            updateTimer.restart();
        }
    }

    Connections {
        target: CompositorData
        function onWindowListChanged() {
            updateTimer.restart();
        }
    }

    Connections {
        target: CompositorData
        function onWorkspaceOccupationMapChanged() {
            updateTimer.restart();
        }
    }

    Connections {
        target: CompositorData
        function onWorkspaceWindowsMapChanged() {
            updateTimer.restart();
        }
    }

    // Reactivo a cambios de monitores conectados (hotplug) — Quickshell.screens.length y AxctlService.monitors
    Connections {
        target: AxctlService.monitors
        function onValuesChanged() {
            updateTimer.restart();
        }
    }

    onWorkspaceGroupChanged: {
        updateTimer.restart();
    }
    onPerMonitorModeChanged: updateTimer.restart()
    onMonitorOffsetChanged: updateTimer.restart()
    onPerMonitorShownChanged: updateTimer.restart()
    onPerMonitorRealIdsChanged: updateTimer.restart()

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

    WheelHandler {
        onWheel: event => {
            if (event.angleDelta.y < 0)
                AxctlService.dispatch(`workspace r+1`);
            else if (event.angleDelta.y > 0)
                AxctlService.dispatch(`workspace r-1`);
        }
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onPressed: event => {
            if (event.button === Qt.BackButton) {
                AxctlService.dispatch(`togglespecialworkspace`);
            }
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

                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Math.max(0, Config.animDuration - 100)
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on x {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Math.max(0, Config.animDuration - 100)
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on width {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Math.max(0, Config.animDuration - 100)
                        easing.type: Easing.OutQuad
                    }
                }
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

                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Math.max(0, Config.animDuration - 100)
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on y {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Math.max(0, Config.animDuration - 100)
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Math.max(0, Config.animDuration - 100)
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }

    // Horizontal active workspace highlight
    StyledRect {
        id: activeHighlightH
        variant: "primary"
        visible: orientation === "horizontal"
        z: 2
        property real activeWorkspaceMargin: 4
        // Two animated indices to create a stretchy transition effect
        property real idx1: workspaceIndexInGroup
        property real idx2: workspaceIndexInGroup

        implicitWidth: Math.abs(idx1 - idx2) * workspaceButtonWidth + workspaceButtonWidth - activeWorkspaceMargin * 2
        implicitHeight: workspaceButtonWidth - activeWorkspaceMargin * 2

        radius: {
            const activeWorkspaceId = (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) || 1;
            const currentWorkspaceHasWindows = CompositorData.workspaceOccupationMap[activeWorkspaceId];
            if (workspacesWidget.radius === 0)
                return 0;
            return currentWorkspaceHasWindows ? workspacesWidget.radius > 0 ? Math.max(workspacesWidget.radius - parent.widgetPadding - activeWorkspaceMargin, 0) : 0 : implicitHeight / 2;
        }

        anchors.verticalCenter: parent.verticalCenter

        x: Math.min(idx1, idx2) * workspaceButtonWidth + activeWorkspaceMargin + widgetPadding
        y: parent.height / 2 - implicitHeight / 2

        Behavior on activeWorkspaceMargin {

            enabled: Config.animDuration > 0

            NumberAnimation {
                duration: Config.animDuration / 2
                easing.type: Easing.OutQuad
            }
        }
        Behavior on idx1 {

            enabled: Config.animDuration > 0

            NumberAnimation {
                duration: Config.animDuration / 3
                easing.type: Easing.OutSine
            }
        }
        Behavior on idx2 {

            enabled: Config.animDuration > 0

            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutSine
            }
        }
    }

    // Vertical active workspace highlight
    StyledRect {
        id: activeHighlightV
        variant: "primary"
        visible: orientation === "vertical"
        z: 2
        property real activeWorkspaceMargin: 4
        // Two animated indices to create a stretchy transition effect
        property real idx1: workspaceIndexInGroup
        property real idx2: workspaceIndexInGroup

        implicitWidth: workspaceButtonWidth - activeWorkspaceMargin * 2
        implicitHeight: Math.abs(idx1 - idx2) * workspaceButtonWidth + workspaceButtonWidth - activeWorkspaceMargin * 2

        radius: {
            const activeWorkspaceId = (monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) || 1;
            const currentWorkspaceHasWindows = CompositorData.workspaceOccupationMap[activeWorkspaceId];
            if (workspacesWidget.radius === 0)
                return 0;
            return currentWorkspaceHasWindows ? workspacesWidget.radius > 0 ? Math.max(workspacesWidget.radius - parent.widgetPadding - activeWorkspaceMargin, 0) : 0 : implicitWidth / 2;
        }

        anchors.horizontalCenter: parent.horizontalCenter

        x: parent.width / 2 - implicitWidth / 2
        y: Math.min(idx1, idx2) * workspaceButtonWidth + activeWorkspaceMargin + widgetPadding

        Behavior on activeWorkspaceMargin {

            enabled: Config.animDuration > 0

            NumberAnimation {
                duration: Config.animDuration / 2
                easing.type: Easing.OutQuad
            }
        }
        Behavior on idx1 {

            enabled: Config.animDuration > 0

            NumberAnimation {
                duration: Config.animDuration / 3
                easing.type: Easing.OutSine
            }
        }
        Behavior on idx2 {

            enabled: Config.animDuration > 0

            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutSine
            }
        }
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
                onPressed: {
                    if (perMonitorMode) {
                        AxctlService.dispatch(`movetoworkspacesilent ${workspaceValue}`);
                        const mName = monitor && monitor.name ? monitor.name : "";
                        if (mName) AxctlService.dispatch(`focusmonitor ${mName}`);
                    } else {
                        AxctlService.dispatch(`workspace ${workspaceValue}`);
                    }
                }
                width: workspaceButtonWidth

                background: Item {
                    id: workspaceButtonBackground
                    implicitWidth: workspaceButtonWidth
                    implicitHeight: workspaceButtonWidth
                    property var focusedWindow: {
                        const windowsInThisWorkspace = CompositorData.workspaceWindowsMap[button.workspaceValue] || [];
                        if (windowsInThisWorkspace.length === 0)
                            return null;
                        // Get the window with the lowest focusHistoryID (most recently focused)
                        return windowsInThisWorkspace.reduce((best, win) => {
                            const bestFocus = (best && best.focusHistoryID !== undefined ? best.focusHistoryID : Infinity);
                            const winFocus = (win && win.focusHistoryID !== undefined ? win.focusHistoryID : Infinity);
                            return winFocus < bestFocus ? win : best;
                        }, null);
                    }
                    readonly property var focusedDesktopEntry: focusedWindow ? DesktopEntries.heuristicLookup(focusedWindow.class) : null
                    property var mainAppIconSource: {
                        if (focusedDesktopEntry && focusedDesktopEntry.icon) {
                            return Quickshell.iconPath(focusedDesktopEntry.icon, "image-missing");
                        }
                        return Quickshell.iconPath(AppSearch.getCachedIcon(focusedWindow ? focusedWindow.class : undefined), "image-missing");
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

                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                    Rectangle {
                        opacity: (Config.workspaces.showNumbers || Config.workspaces.alwaysShowNumbers || (Config.workspaces.showAppIcons && workspaceButtonBackground.focusedWindow)) ? 0 : (((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) == button.workspaceValue) || workspaceOccupied[index] ? 1 : 0.5)
                        visible: opacity > 0
                        anchors.centerIn: parent
                        width: workspaceButtonWidth * 0.2
                        height: width
                        radius: width / 2
                        color: ((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) == button.workspaceValue) ? Styling.srItem("primary") : Colors.overBackground

                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }
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

                            Behavior on opacity {
                                enabled: Config.animDuration > 0
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }
                            }
                            Behavior on anchors.bottomMargin {
                                enabled: Config.animDuration > 0
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }
                            }
                            Behavior on anchors.rightMargin {
                                enabled: Config.animDuration > 0
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }
                            }
                            Behavior on implicitSize {
                                enabled: Config.animDuration > 0
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }

                        Tinted {
                            sourceItem: mainAppIcon
                            anchors.fill: mainAppIcon
                        }
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
                onPressed: {
                    if (perMonitorMode) {
                        AxctlService.dispatch(`movetoworkspacesilent ${workspaceValue}`);
                        const mName = monitor && monitor.name ? monitor.name : "";
                        if (mName) AxctlService.dispatch(`focusmonitor ${mName}`);
                    } else {
                        AxctlService.dispatch(`workspace ${workspaceValue}`);
                    }
                }
                height: workspaceButtonWidth

                background: Item {
                    id: workspaceButtonBackgroundVert
                    implicitWidth: workspaceButtonWidth
                    implicitHeight: workspaceButtonWidth
                    property var focusedWindow: {
                        const windowsInThisWorkspace = CompositorData.workspaceWindowsMap[buttonVert.workspaceValue] || [];
                        if (windowsInThisWorkspace.length === 0)
                            return null;
                        // Get the window with the lowest focusHistoryID (most recently focused)
                        return windowsInThisWorkspace.reduce((best, win) => {
                            const bestFocus = (best && best.focusHistoryID !== undefined ? best.focusHistoryID : Infinity);
                            const winFocus = (win && win.focusHistoryID !== undefined ? win.focusHistoryID : Infinity);
                            return winFocus < bestFocus ? win : best;
                        }, null);
                    }
                    readonly property var focusedDesktopEntry: focusedWindow ? DesktopEntries.heuristicLookup(focusedWindow.class) : null
                    property var mainAppIconSource: {
                        if (focusedDesktopEntry && focusedDesktopEntry.icon) {
                            return Quickshell.iconPath(focusedDesktopEntry.icon, "image-missing");
                        }
                        return Quickshell.iconPath(AppSearch.getCachedIcon(focusedWindow ? focusedWindow.class : undefined), "image-missing");
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

                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                    Rectangle {
                        opacity: (Config.workspaces.showNumbers || Config.workspaces.alwaysShowNumbers || (Config.workspaces.showAppIcons && workspaceButtonBackgroundVert.focusedWindow)) ? 0 : (((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) == buttonVert.workspaceValue) || workspaceOccupied[index] ? 1 : 0.5)
                        visible: opacity > 0
                        anchors.centerIn: parent
                        width: workspaceButtonWidth * 0.2
                        height: width
                        radius: width / 2
                        color: ((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) == buttonVert.workspaceValue) ? Styling.srItem("primary") : Colors.overBackground

                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutQuad
                            }
                        }
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

                            Behavior on opacity {
                                enabled: Config.animDuration > 0
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }
                            }
                            Behavior on anchors.bottomMargin {
                                enabled: Config.animDuration > 0
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }
                            }
                            Behavior on anchors.rightMargin {
                                enabled: Config.animDuration > 0
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }
                            }
                            Behavior on implicitSize {
                                enabled: Config.animDuration > 0
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }

                        Tinted {
                            sourceItem: mainAppIconVert
                            anchors.fill: mainAppIconVert
                        }
                    }
                }
            }
        }
    }
}
