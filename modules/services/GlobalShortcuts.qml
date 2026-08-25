pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.globals
import qs.modules.services
import qs.config

import Quickshell.Io

QtObject {
    id: root

    readonly property string appId: "ambxst"
    readonly property string ipcPipe: "/tmp/ambxst_ipc.pipe"

    // High-performance Pipe Listener (Daemon mode)
    property Process pipeListener: Process {
        command: ["bash", "-c", "rm -f " + root.ipcPipe + "; mkfifo " + root.ipcPipe + "; tail -f " + root.ipcPipe]
        running: true
        
        stdout: SplitParser {
            onRead: data => {
                const cmd = data.trim();
                if (cmd !== "") {
                    root.run(cmd);
                }
            }
        }
    }

    function run(command) {
        console.log("IPC run command received:", command);
        // Soporte dinámico N monitores: "config DP-2", "dashboard-controls HDMI-A-1"
        const parts = command.split(" ");
        const baseCmd = parts[0];
        const argScreen = parts.length > 1 ? parts.slice(1).join(" ").trim() : "";
        switch (baseCmd) {
            // Launcher (Standalone Notch Module)
            case "launcher": toggleLauncher(); break;
            case "clipboard": toggleLauncherWithPrefix(1, Config.prefix.clipboard + " "); break;
            case "emoji": toggleLauncherWithPrefix(2, Config.prefix.emoji + " "); break;
            case "tmux": toggleLauncherWithPrefix(3, Config.prefix.tmux + " "); break;
            case "notes": toggleLauncherWithPrefix(4, Config.prefix.notes + " "); break;

            // Dashboard
            case "dashboard": toggleDashboardTab(0); break;
            case "wallpapers": toggleDashboardTab(1); break;
            case "assistant": toggleAssistant(); break;
            case "dashboard-widgets": toggleDashboardTab(0); break;
            case "dashboard-wallpapers": toggleDashboardTab(1); break;
            case "dashboard-kanban": toggleDashboardTab(2); break;
            case "dashboard-assistant": toggleAssistant(); break;
            case "dashboard-controls": toggleSettings(argScreen); break;

            // System
            case "overview": toggleSimpleModule("overview"); break;
            case "powermenu": toggleSimpleModule("powermenu"); break;
            case "tools": toggleSimpleModule("tools"); break;
            case "config": toggleSettings(argScreen); break;
            case "screenshot": Screenshot.initialize(); GlobalStates.screenshotToolVisible = true; break;
            case "screenrecord":
                ScreenRecorder.initialize();
                if (ScreenRecorder.isRecording) {
                    ScreenRecorder.toggleRecording();
                } else {
                    GlobalStates.screenRecordToolVisible = true;
                }
                break;
            case "lens": 
                Screenshot.initialize();
                Screenshot.captureMode = "lens";
                GlobalStates.screenshotToolVisible = true;
                break;
            case "lockscreen": GlobalStates.lockscreenVisible = true; break;
            
            // Media
            case "media-seek-backward": seekActivePlayer(-mediaSeekStepMs); break;
            case "media-seek-forward": seekActivePlayer(mediaSeekStepMs); break;
            case "media-play-pause": 
                if (MprisController.canTogglePlaying) MprisController.togglePlaying();
                break;
            case "media-next": MprisController.next(); break;
            case "media-prev": MprisController.previous(); break;
                
            default: console.warn("Unknown IPC command:", command);
        }
    }

    property IpcHandler ipcHandler: IpcHandler {
        target: "ambxst"

        function run(command: string) {
            root.run(command);
        }
    }

    // Helper dinámico N monitores: busca screen en Quickshell.screens (fuente de verdad para FloatingWindow.screen) dinámico
    function resolveScreenByName(name) {
        const n = (name || "").trim();
        if (!n) return null;
        // Quickshell.screens es dinámico N (hotplug) — iterar cada vez, no cachear
        const screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; i++) {
            if (screens[i] && screens[i].name === n) return screens[i];
        }
        return null;
    }

    function toggleSettings(screenName) {
        const willOpen = !GlobalStates.settingsWindowVisible;
        if (willOpen) {
            const trimmed = (screenName || "").trim();
            if (!trimmed) console.warn("toggleSettings: screenName vacío, verificar DashboardView screenName propagation sin shadowing");
            else console.log("toggleSettings request screenName:", trimmed, "screens:", (Quickshell.screens||[]).map(s=>s.name).join(","));

            // Resolver estrictamente vía Quickshell.screens cuando screenName válido — NO fallback a focusedMonitor si válido
            let targetScreen = trimmed ? resolveScreenByName(trimmed) : null;
            let targetMonitor = trimmed ? AxctlService.monitorFor(trimmed) : null;

            // Si hay screen válido pero Axctl aún no reporta monitor (race), intentar mapear via screen name
            if (targetScreen && !targetMonitor) {
                const monForScreen = AxctlService.monitorFor(targetScreen.name);
                if (monForScreen) targetMonitor = monForScreen;
            }
            // Si hay monitor válido pero no screen (ej. hyprland name vs Quickshell name difiere), resolver screen por monitor.name
            if (targetMonitor && !targetScreen) {
                targetScreen = resolveScreenByName(targetMonitor.name);
            }

            let canonicalName = "";
            let targetWorkspaceId = 0;
            if (trimmed) {
                // screenName válido: canonical es el nombre resuelto dinámicamente, no focusedMonitor
                if (targetScreen) canonicalName = targetScreen.name;
                else if (targetMonitor) canonicalName = targetMonitor.name;
                else {
                    console.warn("toggleSettings: screenName válido pero no resuelto en Quickshell.screens/AxctlService, usando trimmed como canonical:", trimmed);
                    canonicalName = trimmed; // preserva intención del monitor clickeado, evita caer a focusedMonitor
                }
                // WorkspaceId por monitor: preferir activeWorkspace del targetMonitor, no del focused
                targetWorkspaceId = targetMonitor?.activeWorkspace?.id || 0;
                // Si no hay monitor pero sí screen, intentar obtener workspace via screen->monitor mapping
                if (!targetWorkspaceId && targetScreen) {
                    const m2 = AxctlService.monitorFor(targetScreen.name);
                    targetWorkspaceId = m2?.activeWorkspace?.id || 0;
                }
            } else {
                // Sin screenName (fallback legacy): usar focusedMonitor dinámico
                targetMonitor = AxctlService.focusedMonitor;
                targetScreen = targetMonitor ? resolveScreenByName(targetMonitor.name) : null;
                if (!targetScreen && Quickshell.screens.length > 0) targetScreen = Quickshell.screens[0];
                canonicalName = targetMonitor?.name || targetScreen?.name || (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
                targetWorkspaceId = targetMonitor?.activeWorkspace?.id || AxctlService.focusedWorkspace?.id || 0;
            }
            // Fallback final para canonical si aún vacío y no había trimmed
            if (!canonicalName) {
                canonicalName = AxctlService.focusedMonitor?.name || (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
            }
            // Fallback workspaceId
            if (!targetWorkspaceId) targetWorkspaceId = AxctlService.focusedMonitor?.activeWorkspace?.id || AxctlService.focusedWorkspace?.id || 0;

            GlobalStates.settingsTargetWorkspaceId = targetWorkspaceId;
            GlobalStates.settingsTargetScreenName = canonicalName;
            console.log("toggleSettings screenName:", trimmed, "-> canonical:", canonicalName, "targetMonitor:", targetMonitor?.name, "targetScreen:", targetScreen?.name, "ws:", targetWorkspaceId, "screens:", (Quickshell.screens||[]).map(s=>s.name).join(","));

            // Focus dinámico N: solo si target difiere de focused, usando id correcto por monitor
            if (targetMonitor && AxctlService.focusedMonitor && targetMonitor.id !== AxctlService.focusedMonitor.id) {
                AxctlService.dispatch(`focusmonitor ${targetMonitor.id}`);
            } else if (targetScreen && AxctlService.focusedMonitor && targetScreen.name !== AxctlService.focusedMonitor.name) {
                const fallbackMon = AxctlService.monitorFor(targetScreen.name);
                if (fallbackMon && AxctlService.focusedMonitor && fallbackMon.id !== AxctlService.focusedMonitor.id) {
                    AxctlService.dispatch(`focusmonitor ${fallbackMon.id}`);
                } else if (!fallbackMon) {
                    // Si aún no hay mapeo, intentar dispatch por nombre (axctl lo resuelve)
                    AxctlService.dispatch(`focusmonitor ${targetScreen.name}`);
                }
            }
            Qt.callLater(() => Visibilities.setActiveModule(""));
        }
        GlobalStates.settingsWindowVisible = willOpen;
    }

    function toggleSimpleModule(moduleName) {
        if (Visibilities.currentActiveModule === moduleName) {
            Visibilities.setActiveModule("");
        } else {
            Visibilities.setActiveModule(moduleName);
        }
    }

    function toggleLauncher() {
        const isActive = Visibilities.currentActiveModule === "launcher";
        if (isActive && GlobalStates.widgetsTabCurrentIndex === 0 && GlobalStates.launcherSearchText === "") {
            Visibilities.setActiveModule("");
        } else {
            GlobalStates.widgetsTabCurrentIndex = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("launcher");
            }
        }
    }

    function toggleLauncherWithPrefix(tabIndex, prefix) {
        const isActive = Visibilities.currentActiveModule === "launcher";
        const currentTab = GlobalStates.widgetsTabCurrentIndex;
        const currentText = GlobalStates.launcherSearchText;

        if (isActive && currentTab === tabIndex && (currentText === prefix || currentText === "")) {
            Visibilities.setActiveModule("");
            GlobalStates.clearLauncherState();
            return;
        }

        GlobalStates.widgetsTabCurrentIndex = tabIndex;
        GlobalStates.launcherSearchText = prefix;
        
        if (!isActive) {
            Visibilities.setActiveModule("launcher");
        }
    }

    function toggleDashboardTab(tabIndex) {
        const isActive = Visibilities.currentActiveModule === "dashboard";
        
        // Special handling for widgets tab (launcher)
        if (tabIndex === 0) {
            if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === "") {
                // Only toggle off if we're already in launcher without prefix
                Visibilities.setActiveModule("");
                return;
            }
            
            // Otherwise, always go to launcher (clear any prefix and ensure tab 0)
            GlobalStates.dashboardCurrentTab = 0;
            GlobalStates.launcherSearchText = "";
            GlobalStates.launcherSelectedIndex = -1;
            if (!isActive) {
                Visibilities.setActiveModule("dashboard");
            }
            return;
        }
        
        // For other tabs, normal toggle behavior
        if (isActive && GlobalStates.dashboardCurrentTab === tabIndex) {
            Visibilities.setActiveModule("");
            return;
        }

        GlobalStates.dashboardCurrentTab = tabIndex;
        if (!isActive) {
            Visibilities.setActiveModule("dashboard");
        }
    }

    function toggleDashboardWithPrefix(prefix) {
        const isActive = Visibilities.currentActiveModule === "dashboard";
        
        if (isActive && GlobalStates.dashboardCurrentTab === 0 && GlobalStates.launcherSearchText === prefix) {
            Visibilities.setActiveModule("");
            GlobalStates.clearLauncherState();
            return;
        }

        GlobalStates.dashboardCurrentTab = 0;
        
        if (!isActive) {
            Visibilities.setActiveModule("dashboard");
            Qt.callLater(() => {
                GlobalStates.launcherSearchText = prefix;
            });
        } else {
            GlobalStates.launcherSearchText = prefix;
        }
    }

    function toggleAssistant() {
        GlobalStates.toggleAssistant();
    }
    function seekActivePlayer(offset) {
        const player = MprisController.activePlayer;
        if (!player || !player.canSeek) {
            return;
        }

        const maxLength = typeof player.length === "number" && !isNaN(player.length)
                ? player.length
                : Number.MAX_SAFE_INTEGER;
        const clamped = Math.max(0, Math.min(maxLength, player.position + offset));
        player.position = clamped;
    }
}
