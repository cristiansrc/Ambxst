import QtQuick
import Quickshell
import qs.modules.widgets.dashboard.controls
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.theme
import qs.config

FloatingWindow {
    id: settingsWindow

    // Window properties
    implicitWidth: 900
    implicitHeight: 650
    title: "Ambxst Settings"
    // Visible gestionado vía Connections para asegurar screen asignado ANTES de visible (evita flash en monitor 1)
    visible: false
    // Center on screen — screen asignado dinámicamente en preparePlacement via Quickshell.screens mapping
    color: "transparent"

    function screenByName(name) {
        const n = (name || "").trim();
        if (!n) return null;
        const screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; i++) {
            if (screens[i] && screens[i].name === n) return screens[i];
        }
        return null;
    }

    // Resolve dinámico N monitores usando Quickshell.screens (fuente de verdad para FloatingWindow.screen) — no cachear
    function resolveTargetScreen() {
        const explicit = (GlobalStates.settingsTargetScreenName || "").trim();
        if (explicit) {
            const s = screenByName(explicit);
            if (s) return s;
            // Si nombre no está en Quickshell.screens pero sí en AxctlService, intentar mapear (ej. diferencia de naming)
            const mon = AxctlService.monitorFor(explicit);
            if (mon && mon.name) {
                const mapped = screenByName(mon.name);
                if (mapped) return mapped;
                // Si aún no mapeado, log para debug per-screen
                console.warn("SettingsWindow resolveTargetScreen: explicit", explicit, "mon.name", mon.name, "no está en Quickshell.screens", (Quickshell.screens||[]).map(x=>x.name).join(","));
            } else {
                console.warn("SettingsWindow resolveTargetScreen: explicit", explicit, "no resuelto en Quickshell.screens ni AxctlService");
            }
        } else {
            console.warn("SettingsWindow resolveTargetScreen: settingsTargetScreenName vacío, revisar GlobalShortcuts toggleSettings propagation");
        }
        // Solo fallback a focused/0 si no hay explicit válido — no ocultar bug de screenName vacío
        if (!explicit) {
            const focusedName = AxctlService.focusedMonitor?.name || "";
            if (focusedName) {
                const fs = screenByName(focusedName);
                if (fs) return fs;
            }
            if (Quickshell.screens.length > 0) return Quickshell.screens[0];
        }
        return null;
    }

    function preparePlacement() {
        const targetScreen = resolveTargetScreen();
        if (targetScreen) {
            // Asignar screen ANTES de que el compositor mapee la ventana (evita que FloatingWindow aparezca en DP-1 flash en monitor 1)
            // Quickshell.screens mapping dinámico N: screen debe ser objeto ShellScreen de Quickshell.screens, no string
            settingsWindow.screen = targetScreen;
            console.log("SettingsWindow preparePlacement target:", GlobalStates.settingsTargetScreenName, "-> screen:", targetScreen.name, "screens:", (Quickshell.screens||[]).map(s=>s.name).join(","));
        } else {
            console.warn("SettingsWindow preparePlacement: no targetScreen found for", GlobalStates.settingsTargetScreenName, "screens:", (Quickshell.screens||[]).map(s=>s.name).join(","));
        }
        placementTimer.attempts = 0;
        placementTimer.restart();
    }

    // WorkspaceId correcto por monitor: particionado monitorOffset*perMonitorCount+1.. cuando perMonitor activo, dinámico N
    function resolveTargetWorkspaceId() {
        let ws = GlobalStates.settingsTargetWorkspaceId || 0;
        // Validar que ws pertenece al monitor target cuando perMonitorMode activo; si no, recalcular
        const perMon = (Config.workspaces.perMonitor ?? false) && Quickshell.screens.length >= 2;
        if (perMon) {
            const targetName = (GlobalStates.settingsTargetScreenName || "").trim();
            let targetMonitor = targetName ? AxctlService.monitorFor(targetName) : null;
            if (!targetMonitor && targetName) targetMonitor = AxctlService.monitorFor(resolveTargetScreen()?.name || "");
            if (targetMonitor) {
                // Si ws no existe o no está en rango del monitor, usar activeWorkspace del monitor como canonical
                const perCount = Math.max(1, Math.min(20, Config.workspaces.perMonitorCount ?? 5));
                // Calcular monitorOffset dinámico igual que Workspaces.qml
                const axMons = AxctlService.monitors.values || [];
                let idx = axMons.findIndex(m => m && m.name === targetMonitor.name);
                if (idx < 0) {
                    const screens = Quickshell.screens || [];
                    idx = screens.findIndex(s => s && s.name === targetMonitor.name);
                }
                if (idx < 0) idx = 0;
                const startId = idx * perCount + 1;
                const endId = startId + perCount - 1;
                if (!ws || ws < startId || ws > endId) {
                    // ws fuera de rango particionado → usar activeWorkspace del monitor si está en rango, sino startId
                    const activeWs = targetMonitor.activeWorkspace?.id || 0;
                    if (activeWs >= startId && activeWs <= endId) ws = activeWs;
                    else ws = startId;
                    console.log("SettingsWindow resolveTargetWorkspaceId: ws fuera de rango perMonitor, recalculado monitor", targetMonitor.name, "offset", idx, "-> ws", ws);
                }
            }
        }
        if (!ws) ws = AxctlService.focusedMonitor?.activeWorkspace?.id || AxctlService.focusedWorkspace?.id || 0;
        return ws;
    }

    function placeOnTargetWorkspace() {
        const targetWorkspace = resolveTargetWorkspaceId();
        if (!targetWorkspace) return false;

        const clients = AxctlService.clients.values || [];
        for (let i = 0; i < clients.length; i++) {
            const client = clients[i];
            if (client.title === settingsWindow.title) {
                if (client.workspace?.id !== targetWorkspace) {
                    AxctlService.dispatch(`movetoworkspacesilent ${targetWorkspace}, address:${client.address}`);
                    console.log("SettingsWindow placeOnTargetWorkspace movetoworkspacesilent", targetWorkspace, "addr", client.address, "screen", GlobalStates.settingsTargetScreenName);
                }
                AxctlService.dispatch(`focuswindow address:${client.address}`);
                return true;
            }
        }

        return false;
    }

    Timer {
        id: placementTimer
        interval: 100
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts++;
            if (!settingsWindow.visible || settingsWindow.placeOnTargetWorkspace() || attempts >= 20) {
                stop();
            }
        }
    }

    // Use a StyledRect for the background and styling
    StyledRect {
        anchors.fill: parent
        variant: "bg"
        radius: 0

        // Settings Tab Content
        SettingsTab {
            anchors.fill: parent
            anchors.margins: 16
        }
    }

    Component.onCompleted: {
        // Si el Loader nos crea ya con visible=true (race), asegurar screen asignado antes de mapear
        if (GlobalStates.settingsWindowVisible) preparePlacement();
    }

    // Close on visibility change from outside
    onVisibleChanged: {
        if (visible) {
            // screen ya asignado en onSettingsWindowVisibleChanged antes de visible=true; re-validar por si hotplug cambió
            const cur = resolveTargetScreen();
            if (cur && settingsWindow.screen !== cur) {
                console.log("SettingsWindow onVisibleChanged: corrigiendo screen a", cur.name);
                settingsWindow.screen = cur;
            }
        }

        if (!visible && GlobalStates.settingsWindowVisible) {
            GlobalStates.settingsWindowVisible = false;
        }
    }

    // Sync visibilidad desde GlobalStates — asigna screen ANTES de visible para N dinámico
    Connections {
        target: GlobalStates
        function onSettingsWindowVisibleChanged() {
            if (GlobalStates.settingsWindowVisible) {
                // 1. Asignar screen antes de hacer visible (evita flash en monitor 1)
                settingsWindow.preparePlacement();
            }
            // 2. Recién después hacer visible
            settingsWindow.visible = GlobalStates.settingsWindowVisible;
        }
    }
    // Hotplug N dinámico: re-resolver si cambia targetScreenName mientras está visible
    Connections {
        target: GlobalStates
        function onSettingsTargetScreenNameChanged() {
            if (settingsWindow.visible) {
                const cur = settingsWindow.resolveTargetScreen();
                if (cur && settingsWindow.screen !== cur) {
                    console.log("SettingsWindow settingsTargetScreenNameChanged -> reasignando screen", cur.name);
                    settingsWindow.screen = cur;
                }
            }
        }
    }
}
