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
        // Fallback robusto: si explicit falló o vacío, intentar focused/0 para no bloquear apertura
        // Se mantiene warn arriba para no ocultar bug de propagation, pero garantiza apertura
        const focusedName = AxctlService.focusedMonitor?.name || "";
        if (focusedName) {
            const fs = screenByName(focusedName);
            if (fs) {
                if (explicit) console.warn("SettingsWindow resolveTargetScreen: fallback a focused", focusedName, "tras fail explicit", explicit);
                return fs;
            }
        }
        if (Quickshell.screens.length > 0) {
            if (explicit) console.warn("SettingsWindow resolveTargetScreen: fallback a screens[0]", Quickshell.screens[0].name, "tras fail explicit", explicit);
            return Quickshell.screens[0];
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
        // Loader se activa con GlobalStates.settingsWindowVisible true: el signal ya se emitió
        // antes de que este componente existiera, por lo que Connections no lo recibe.
        // Asegurar screen ANTES de visible para evitar flash en monitor 1 (per-screen N dinámico).
        if (GlobalStates.settingsWindowVisible) {
            preparePlacement();
            // Qt.callLater garantiza que screen ya está asignado antes de que el compositor mapee
            Qt.callLater(() => {
                if (GlobalStates.settingsWindowVisible) settingsWindow.visible = true;
            });
        }
    }

    // Close on visibility change from outside
    onVisibleChanged: {
        if (visible) {
            // Re-validar por si hotplug cambió entre preparePlacement y mapeo (race)
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
    // Incluye hotplug: re-resolver si cambia targetScreenName mientras está visible
    Connections {
        target: GlobalStates
        function onSettingsWindowVisibleChanged() {
            if (GlobalStates.settingsWindowVisible) {
                // 1. Asignar screen antes de hacer visible (evita flash en monitor 1)
                settingsWindow.preparePlacement();
                // 2. Recién después hacer visible en siguiente tick (screen ya asignado)
                Qt.callLater(() => {
                    settingsWindow.visible = GlobalStates.settingsWindowVisible;
                });
            } else {
                // Cierre inmediato
                settingsWindow.visible = false;
            }
        }
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
