---
increment: 004-multi-monitor-workspaces-wallpaper-rotation-mixer-toggles
status: planning
project: Ambxst
target_version: 1.2.0
created: 2026-08-25
updated: 2026-08-25
author: planner-agent
related_bugfixes:
  - 001-wifi-bt-gate-fix
  - 002-settingswindow-per-monitor
  - 003-ia-defaults
---

# Increment 004 — Multi-monitor Workspaces, Wallpaper Auto-rotation, Mixer Bar Toggles

## 0. Lifecycle Status

**Status: `planning`**

Este incremento está en fase de diseño. Contiene tres features nuevas que amplían Ambxst sin romper contratos existentes:

| ID | Feature | Dominio de config | Archivos UI principales |
|----|---------|-------------------|-------------------------|
| F1 | Workspaces independientes por monitor | `Config.workspaces` | `ShellPanel.qml` + `Workspaces.qml` + `AxctlService.qml` (sin cambios) |
| F2 | Wallpaper auto-rotation | `~/.cache/ambxst/wallpapers.json` (extensión) | `ThemePanel.qml` + `Wallpaper.qml` (timer) |
| F3 | Mixer bar toggles (mic + output) | `Config.bar` (nuevas keys) + `Config.audio` (nuevo módulo) | `BarContent.qml` (icon buttons) + `AudioMixerPanel.qml` (settings) |

## 1. Contexto y Relación con Specs Anteriores

### 1.1 Bugfixes previos (Fase 1-3)
- **001-wifi-bt-gate-fix**: Corrige visibilidad condicional de NetworkService y BluetoothService.
- **002-settingswindow-per-monitor**: SettingsWindow ahora se abre en el monitor correcto.
- **003-ia-defaults**: Ajusta defaults de AI provider.

### 1.2 Estado del sistema Ambxst
- Wayland shell sobre Quickshell con Hyprland como compositor (vía `axctl`).
- Config reactivo basado en `FileView` + `JsonAdapter` con archivos por dominio en `~/.config/ambxst/config/`.
- Estado runtime del wallpaper en `~/.cache/ambxst/wallpapers.json` (gestionado por `Wallpaper.qml`).
- Paleta de colores derivada por `matugen` en `~/.cache/ambxst/colors.json` (consumida reactivamente por `Colors.qml`).
- Multi-monitor soportado con `Variants { model: Quickshell.screens }`.

### 1.3 Por qué este incremento
El usuario observa que el comportamiento actual de workspaces es **lineal** (ws1..N compartidos entre todos los monitores) y no aprovecha el layout físico. La rotación de wallpaper es **manual** (click en `nextWallpaper()`). Los toggles de audio (mute mic, switch speakers↔headphones) están **solo en el dashboard**, no son accesibles en 1-click desde la bar.

## 2. Contexto Previo de Decisiones (No Negociables)

| Decisión | Razón | Bloqueante |
|----------|-------|-----------|
| Nuevas keys de config SIEMPRE en `defaults/*.js` + `Config.qml` | Regla de `config/AGENTS.md` | Sí |
| UI con `StyledRect` + `Styling.*` + `Colors.*` (no `Rectangle` ni hex) | Regla de `modules/components/AGENTS.md` | Sí |
| Multi-monitor con `Variants { model: Quickshell.screens }` | Regla del AGENTS.md raíz | Sí |
| Nuevos archivos en `docs/specs/increments/` (no modificar specs históricas) | Regla de `spec-driven-development` §2 | Sí |
| Si se introducen cambios en contratos existentes, **incremento nuevo** | Regla de `spec-driven-development` §3 | Sí |
| `JsonAdapter` con tipos explícitos para cada key | `config/AGENTS.md` (atomic defaults) | Sí |
| `pauseAutoSave` para cambios masivos en Config | `config/AGENTS.md` | Recomendado |
| `Quickshell.screens.length >= 2` como guard condicional | AGENTS.md raíz multi-monitor pattern | Sí (para F1) |
| `Qt.callLater` para init de servicios críticos | AGENTS.md raíz | Sí |
| `null-check` en todas las propiedades anidadas | AGENTS.md raíz | Sí |
| `IconImage` + `Tinted` para iconos en bar, no `Image` crudo | Patrón de `ToggleButton.qml` | Recomendado |

## 3. Feature F1 — Workspaces Independientes por Monitor

### 3.1 Descripción funcional

Cuando el usuario tiene **2 o más monitores** y activa la opción **Per Monitor** en la configuración, cada monitor tiene su **propio set independiente de workspaces** en lugar de compartir el set lineal global.

**Comportamiento actual (referencia):**
- `Config.workspaces.shown = 10` → 10 workspaces compartidos (ws 1..10)
- Los workspaces se renderizan idénticos en todos los monitores en `Workspaces.qml`
- `workspaceGroup = floor((activeWorkspaceId - 1) / shown)` agrupa para scroll

**Comportamiento nuevo:**
- `Config.workspaces.perMonitor = true` y `Quickshell.screens.length >= 2`
- Cada monitor N muestra **únicamente** sus workspaces asignados: `ws[N*shown+1 .. (N+1)*shown]`
- Total de workspaces en Hyprland = `shown * screenCount` (se crean automáticamente vía `axctl`)
- Click en un botón de workspace del monitor N hace `movetoworkspacesilent` con `ws = N*shown + localIndex + 1`
- Si el monitor se desconecta, las workspaces de ese monitor se reasignan al monitor restante (o se eliminan vía `axctl workspace destroy`)

### 3.2 API Config

#### Default file: `config/defaults/workspaces.js`

```javascript
.pragma library

var data = {
    "shown": 10,
    "showAppIcons": true,
    "alwaysShowNumbers": false,
    "showNumbers": false,
    "dynamic": false,
    "perMonitor": false   // ← NUEVO. Ubicación: debajo de "dynamic"
}
```

#### Config.qml — Extensión del adapter (líneas 589-595)

```qml
adapter: JsonAdapter {
    property int shown: 10
    property bool showAppIcons: true
    property bool alwaysShowNumbers: false
    property bool showNumbers: false
    property bool dynamic: false
    property bool perMonitor: false   // ← NUEVO
}
```

**Validación:** `ConfigValidator.js` ya hace deep-merge con `WorkspacesDefaults.data`, no requiere cambios. La nueva key se propaga automáticamente.

#### Property expuesta (línea 3437, sin cambios)

```qml
property QtObject workspaces: workspacesLoader.adapter
```

### 3.3 Lógica de dominio

#### Workspaces.qml — Renderizado por monitor

Cambios en `modules/bar/workspaces/Workspaces.qml`:

1. Nueva computed property al inicio del componente (después de `monitor` línea 18):
   ```qml
   readonly property bool perMonitorMode: Config.workspaces.perMonitor && Quickshell.screens.length >= 2
   readonly property int monitorOffset: {
       if (!perMonitorMode) return 0;
       const monitors = AxctlService.monitors.values || [];
       const idx = monitors.findIndex(m => m.name === (monitor && monitor.name));
       return idx < 0 ? 0 : idx;
   }
   readonly property int perMonitorShown: perMonitorMode ? Math.max(1, Config.workspaces.shown) : Config.workspaces.shown
   ```

2. Modificar `workspaceGroup` (línea 21) — cuando `perMonitorMode`, el group siempre es 0:
   ```qml
   readonly property int workspaceGroup: perMonitorMode
       ? 0
       : Math.floor(((monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) - 1 || 0) / Config.workspaces.shown)
   ```

3. Modificar `getWorkspaceId(index)` (línea 108) — añadir offset:
   ```qml
   function getWorkspaceId(index) {
       const baseId = Config.workspaces.dynamic
           ? (dynamicWorkspaceIds[index] || 1)
           : workspaceGroup * Config.workspaces.shown + index + 1;
       if (perMonitorMode) {
           return monitorOffset * perMonitorShown + index + 1;
       }
       return baseId;
   }
   ```

4. Modificar el handler de click de cada botón (líneas 418 y 555) — preferir silent dispatch + focus:
   ```qml
   onPressed: {
       if (Config.workspaces.perMonitor && Quickshell.screens.length >= 2) {
           AxctlService.dispatch(`movetoworkspacesilent ${button.workspaceValue}`);
           AxctlService.dispatch(`focusmonitor ${monitor.name}`);
       } else {
           AxctlService.dispatch(`workspace ${button.workspaceValue}`);
       }
   }
   ```

#### Creación dinámica de workspaces

**En `Wallpaper.qml` o nuevo `CompositorWorkspaces.qml`** (recomendado: `Workspaces.qml` para mantener cohesión), cuando `perMonitor` se activa por primera vez, ejecutar:

```qml
Component.onCompleted: {
    if (Config.workspaces.perMonitor && Quickshell.screens.length >= 2) {
        ensurePerMonitorWorkspaces();
    }
}

function ensurePerMonitorWorkspaces() {
    const totalNeeded = Config.workspaces.shown * Quickshell.screens.length;
    const existing = AxctlService.workspaces.values.map(w => w.id);
    for (let i = 1; i <= totalNeeded; i++) {
        if (!existing.includes(i)) {
            // No-op: Hyprland auto-crea workspaces al hacer movetoworkspace
            // Solo los pre-creamos si estamos seguros
        }
    }
}
```

**Decisión de implementación:** NO pre-crear workspaces. Hyprland los crea automáticamente al primer `movetoworkspace` a un ID nuevo. Esto evita race conditions.

#### Mapping monitor → workspaces (display)

Cada `Workspaces.qml` instance se crea vía `Variants { model: Quickshell.screens }` (línea 632 de `BarContent.qml`), por lo que `monitor` ya está disponible. La asignación lineal (monitor 0 → 1..N, monitor 1 → N+1..2N) es estable mientras el orden de `Quickshell.screens` no cambie.

### 3.4 UI: ShellPanel.qml

**Archivo:** `modules/widgets/dashboard/controls/ShellPanel.qml`

**Ubicación:** Dentro del bloque `// WORKSPACES SECTION` (líneas 1138-1208), justo después del `ToggleRow { label: "Dynamic" }` (línea 1198-1207), antes del cierre del `ColumnLayout`.

```qml
// Justo después de la línea 1207
ToggleRow {
    label: "Per Monitor"
    checked: Config.workspaces.perMonitor ?? false
    enabled: Quickshell.screens.length >= 2
    opacity: enabled ? 1.0 : 0.5
    onToggled: value => {
        if (Quickshell.screens.length < 2) return;
        if (value !== Config.workspaces.perMonitor) {
            GlobalStates.markShellChanged();
            Config.workspaces.perMonitor = value;
        }
    }
}
```

**Nota:** El componente `ToggleRow` actual no soporta `enabled`/`opacity`. Se debe extender inline o crear un nuevo `ToggleRowDisabled` local. **Recomendación:** extender el inline `ToggleRow` (líneas 149-222) con:

```qml
component ToggleRow: RowLayout {
    id: toggleRowRoot
    property string label: ""
    property bool checked: false
    property bool enabled: true          // ← NUEVO
    signal toggled(bool value)

    property bool _updating: false

    onCheckedChanged: {
        if (!_updating && toggleSwitch.checked !== checked) {
            _updating = true;
            toggleSwitch.checked = checked;
            _updating = false;
        }
    }

    Layout.fillWidth: true
    spacing: 8

    Text {
        text: toggleRowRoot.label
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(0)
        color: toggleRowRoot.enabled ? Colors.overBackground : Colors.outline  // ← CAMBIO
        Layout.fillWidth: true
        opacity: toggleRowRoot.enabled ? 1.0 : 0.5  // ← CAMBIO
    }

    Switch {
        id: toggleSwitch
        checked: toggleRowRoot.checked
        enabled: toggleRowRoot.enabled  // ← NUEVO

        onCheckedChanged: {
            if (!toggleRowRoot._updating && checked !== toggleRowRoot.checked) {
                toggleRowRoot.toggled(checked);
            }
        }
        // ... resto del indicator igual
    }
}
```

### 3.5 Acceptance Criteria F1

| # | Criterio | Verificación |
|---|----------|--------------|
| AC-F1-1 | El toggle "Per Monitor" aparece en `ShellPanel → Workspaces` debajo de "Dynamic" | Visual: `qs -p shell.qml`, abrir Settings → Shell → Workspaces |
| AC-F1-2 | El toggle está deshabilitado (opacity 0.5) si `Quickshell.screens.length < 2` | Conectar/desconectar monitor y observar cambio de estado |
| AC-F1-3 | Cuando está activo, cada monitor muestra sus propios botones de workspace (1..N en monitor 0, N+1..2N en monitor 1) | Visual con 2+ monitores |
| AC-F1-4 | Click en workspace N+1 del monitor 1 cambia al workspace N+1 via `axctl window move-to-workspace-silent N+1` | Logs: `axctl subscribe` muestra evento `workspace` |
| AC-F1-5 | El foco sigue al workspace cambiado (no se queda en el monitor anterior) | Mover foco a una ventana del monitor 0, click en workspace del monitor 1, foco cambia |
| AC-F1-6 | Al desactivar, workspaces vuelven al modo global lineal | Sin perder datos de workspaces existentes |
| AC-F1-7 | `Config.workspaces.perMonitor = false` por default; usuarios existentes no rompen | Verificar que `workspaces.json` sin la key la recibe como `false` tras `validateModule` |
| AC-F1-8 | Funciona con `Config.workspaces.dynamic = true` simultáneamente | El `dynamic` mode sigue funcionando, simplemente los IDs mostrados son los del subset del monitor |

## 4. Feature F2 — Wallpaper Auto-rotation

### 4.1 Descripción funcional

Un **timer** rotativo cambia el wallpaper automáticamente cada N minutos (configurable, 1..1440) cuando está activo. El wallpaper se elige secuencialmente de la lista `wallpaperPaths` (rotación circular, igual que `nextWallpaper()` actual). El pipeline `matugen` se ejecuta después de cada cambio, regenerando `~/.cache/ambxst/colors.json` que `Colors.qml` watches reactivamente.

### 4.2 API Config

**Storage location:** `~/.cache/ambxst/wallpapers.json` (extensión del `JsonAdapter` existente en `ThemePanel.qml` líneas 99-104 y `Wallpaper.qml` líneas 711-718).

**Razón de no usar `Config.theme`:** La rotación es estado **runtime/efímero** del wallpaper, no del tema. Mantener wallpaper state en su propio archivo es coherente con la separación actual.

**Cambio en `Wallpaper.qml` líneas 711-718:**

```qml
JsonAdapter {
    id: wallpaperAdapter
    property string currentWall: ""
    property string wallPath: ""
    property string matugenScheme: "scheme-tonal-spot"
    property string activeColorPreset: ""
    property bool tintEnabled: false
    property var perScreenWallpapers: ({})

    // ── NUEVO F2: rotación automática ──
    property bool rotationEnabled: false
    property int rotationIntervalMinutes: 30  // default 30 min, rango 1..1440
    // ──────────────────────────────────────
}
```

**Mismo cambio en `ThemePanel.qml` líneas 99-104** (es el mismo FileView, así que ambos archivos ven la misma estructura).

**No se necesita** archivo de defaults separado. Los defaults del adapter están en el propio QML.

### 4.3 Lógica de dominio

**Archivo:** `modules/widgets/dashboard/wallpapers/Wallpaper.qml`

Añadir un `Timer` cerca del final del componente (antes de la línea 1099 o donde haya espacio):

```qml
// ── NUEVO F2: Auto-rotation timer ──
Timer {
    id: rotationTimer
    interval: Math.max(1, wallpaperConfig.adapter.rotationIntervalMinutes || 30) * 60 * 1000
    repeat: true
    running: wallpaperConfig.adapter.rotationEnabled === true
            && initialLoadCompleted
            && wallpaperPaths.length > 1
    triggeredOnStart: false

    onTriggered: {
        console.log("Auto-rotation: switching to next wallpaper");
        nextWallpaper();
    }
}

Connections {
    target: wallpaperConfig.adapter
    function onRotationIntervalMinutesChanged() {
        rotationTimer.interval = Math.max(1, wallpaperConfig.adapter.rotationIntervalMinutes || 30) * 60 * 1000;
    }
    function onRotationEnabledChanged() {
        rotationTimer.running = wallpaperConfig.adapter.rotationEnabled === true
            && initialLoadCompleted
            && wallpaperPaths.length > 1;
    }
}
// ───────────────────────────────────────
```

**Comportamiento del timer:**
- `running` es `true` solo si: rotación habilitada AND carga inicial completa AND hay >1 wallpaper.
- Cuando `rotationIntervalMinutes` cambia, el `interval` se actualiza sin reiniciar.
- Cada tick llama a `nextWallpaper()` que ya existe (línea 340) y que internamente llama a `runMatugenForCurrentWallpaper()` → regenera `~/.cache/ambxst/colors.json` → `Colors.qml` recarga reactivamente.

### 4.4 UI: ThemePanel.qml

**Archivo:** `modules/widgets/dashboard/controls/ThemePanel.qml`

**Ubicación:** Dentro del bloque `generalContent` (línea 269+), **justo después** del `RowLayout` que define el "Wallpapers" path (líneas 285-334). Este RowLayout termina en la línea 334 con `}`.

```qml
// Insertar después de la línea 334 (después del cierre del RowLayout Wallpapers)

// Auto-rotation toggle
ToggleRow {
    label: "Auto-rotate"
    checked: wallpaperConfig.adapter.rotationEnabled ?? false
    onToggled: value => {
        if (value !== wallpaperConfig.adapter.rotationEnabled) {
            wallpaperConfig.adapter.rotationEnabled = value;
            wallpaperConfig.writeAdapter();
        }
    }
}

// Auto-rotation interval
NumberInputRow {
    label: "Rotation interval"
    value: wallpaperConfig.adapter.rotationIntervalMinutes ?? 30
    minValue: 1
    maxValue: 1440
    suffix: "min"
    visible: wallpaperConfig.adapter.rotationEnabled === true
    onValueEdited: newValue => {
        if (newValue !== wallpaperConfig.adapter.rotationIntervalMinutes) {
            wallpaperConfig.adapter.rotationIntervalMinutes = newValue;
            wallpaperConfig.writeAdapter();
        }
    }
}
```

**Nota:** `ToggleRow` está definido localmente en `ThemePanel.qml` o importado. Verificar que `ThemePanel.qml` tenga acceso al componente `ToggleRow`. Si no, **importar** desde `ShellPanel.qml` o duplicar inline (más simple, menos acoplamiento).

**Verificación realizada:** El grep muestra que `ToggleRow` está definido en `ShellPanel.qml`, `SystemPanel.qml` y `CompositorPanel.qml` como componente inline. `ThemePanel.qml` actualmente **no** tiene `ToggleRow` local. **Acción:** duplicar el componente `ToggleRow` en `ThemePanel.qml` siguiendo el patrón de `ShellPanel.qml` líneas 149-222 (es la regla del proyecto: inline components en cada panel para no acoplar).

### 4.5 Acceptance Criteria F2

| # | Criterio | Verificación |
|---|----------|--------------|
| AC-F2-1 | El toggle "Auto-rotate" aparece en `ThemePanel → General` debajo del input de "Wallpapers" path | Visual |
| AC-F2-2 | El input "Rotation interval" (min) aparece solo cuando el toggle está activo | Visual con toggle off → invisible, on → visible |
| AC-F2-3 | El intervalo es un número entero entre 1 y 1440 (validación con `IntValidator`) | Intentar escribir 0 o 1500 → no acepta |
| AC-F2-4 | Cuando está activo, el wallpaper cambia automáticamente cada N minutos | Configurar 1 min, observar cambio |
| AC-F2-5 | Cada cambio ejecuta `matugen` y actualiza `~/.cache/ambxst/colors.json` | Después del cambio, `cat ~/.cache/ambxst/colors.json | jq .primary` muestra color nuevo |
| AC-F2-6 | Si solo hay 1 wallpaper en el directorio, el timer no inicia | Verificar logs: `Auto-rotation timer not started: < 2 wallpapers` |
| AC-F2-7 | Al desactivar el toggle, el timer se detiene inmediatamente | Verificar: tras desactivar, no hay más cambios automáticos |
| AC-F2-8 | El cambio de intervalo se aplica sin reiniciar el shell | Cambiar de 30 a 5 min, ver que el próximo tick ocurre a los 5 min desde el último cambio, no desde el inicio |
| AC-F2-9 | La rotación sobrevive a `Config.theme.lightMode` change | Si cambia light/dark, el timer sigue corriendo; matugen se re-ejecuta con el wallpaper actual |

## 5. Feature F3 — Mixer Bar Toggles + Mixer Settings

### 5.1 Descripción funcional

Dos icon buttons en la **bar** (junto a `PresetsButton`):
1. **Mic mute toggle**: Click cicla mute/unmute del micrófono. Color accent cuando NO está muteado, color neutro cuando SÍ.
2. **Output toggle (speakers ↔ headphones)**: Click cicla entre dos sinks PipeWire pre-seleccionados. Icono cambia según el sink activo.

Nueva sección en **AudioMixerPanel** (settings) para:
- Mostrar/ocultar cada botón independientemente.
- Seleccionar cuál nodo de `Audio.outputDevices` es el "speakers node" y cuál es el "headphones node".

### 5.2 API Config

#### Default file: `config/defaults/bar.js`

```javascript
.pragma library

var data = {
    "position": "top",
    "launcherIcon": "",
    "launcherIconTint": true,
    "launcherIconFullTint": true,
    "launcherIconSize": 24,
    "pillStyle": "default",
    "screenList": [],
    "enableFirefoxPlayer": false,
    "barColor": [["surface", 0.0]],
    "frameEnabled": false,
    "frameThickness": 6,
    "pinnedOnStartup": true,
    "hoverToReveal": true,
    "hoverRegionHeight": 8,
    "showPinButton": true,
    "availableOnFullscreen": false,
    "use12hFormat": false,
    "containBar": false,
    "keepBarShadow": false,
    "keepBarBorder": false,

    // ── NUEVO F3: Mixer bar toggles ──
    "mixerMicToggle": true,        // mostrar/ocultar botón mic en bar
    "mixerOutputToggle": true      // mostrar/ocultar botón output en bar
    // ──────────────────────────────────
}
```

#### Default file: `config/defaults/audio.js` (NUEVO)

```javascript
.pragma library

var data = {
    "speakersNode": "",   // nombre exacto del sink (Audio.sink.nickname o description)
    "headphonesNode": ""  // nombre exacto del sink
}
```

#### Config.qml — barLoader adapter (líneas 530-552)

```qml
adapter: JsonAdapter {
    property string position: "top"
    property string launcherIcon: ""
    property bool launcherIconTint: true
    property bool launcherIconFullTint: true
    property int launcherIconSize: 24
    property string pillStyle: "default"
    property list<string> screenList: []
    property bool enableFirefoxPlayer: false
    property list<var> barColor: [["surface", 0.0]]
    property bool frameEnabled: false
    property int frameThickness: 6
    property bool pinnedOnStartup: true
    property bool hoverToReveal: true
    property int hoverRegionHeight: 8
    property bool showPinButton: true
    property bool availableOnFullscreen: false
    property bool use12hFormat: false
    property bool containBar: false
    property bool keepBarShadow: false
    property bool keepBarBorder: false

    // ── NUEVO F3 ──
    property bool mixerMicToggle: true
    property bool mixerOutputToggle: true
    // ───────────────
}
```

#### Config.qml — Nuevo audioLoader (insertar después de workspacesLoader, línea 596)

```qml
// ============================================
// AUDIO MODULE (F3)
// ============================================
FileView {
    id: audioLoader
    path: root.configDir + "/audio.json"
    atomicWrites: true
    watchChanges: true
    onLoaded: {
        if (!root.audioReady) {
            validateModule("audio", audioLoader, AudioDefaults.data, () => {
                root.audioReady = true;
            });
        }
    }
    onLoadFailed: {
        if (error.toString().includes("FileNotFound") && !root.audioReady) {
            handleMissingConfig("audio", audioLoader, AudioDefaults.data, () => {
                root.audioReady = true;
            });
        }
    }
    onFileChanged: {
        root.pauseAutoSave = true;
        reload();
        root.pauseAutoSave = false;
    }
    onPathChanged: reload()
    onAdapterUpdated: {
        if (root.audioReady && !root.pauseAutoSave) {
            audioLoader.writeAdapter();
        }
    }

    adapter: JsonAdapter {
        property string speakersNode: ""
        property string headphonesNode: ""
    }
}
```

#### Config.qml — Imports (después de línea 11)

```qml
import "defaults/audio.js" as AudioDefaults
```

#### Config.qml — Exposed property (después de línea 3437, junto a `workspaces`)

```qml
property QtObject audio: audioLoader.adapter
```

#### Config.qml — Audio ready flag (buscar patrón `*Ready` y añadir)

Buscar dónde se declaran los `*Ready` flags (probablemente en un `QtObject` interno) y añadir `property bool audioReady: false` siguiendo el mismo patrón.

#### Config.qml — writeAdapter en el shutdown bulk save (línea 3520)

Añadir `audioLoader.writeAdapter();` siguiendo el patrón de los otros loaders.

### 5.3 Lógica de dominio

#### Audio.qml — Extensión de API

**Archivo:** `modules/services/Audio.qml`

Añadir al final del singleton (antes de `volumeIcon`, línea 209):

```qml
// ── NUEVO F3: device selection helpers ──

// Buscar un nodo por nombre (nickname o description)
function findDeviceByName(name: string, isSink: bool) {
    if (!name) return null;
    const list = isSink ? root.outputDevices : root.inputDevices;
    for (let i = 0; i < list.length; i++) {
        const n = list[i];
        if (n && (n.nickname === name || n.description === name)) return n;
    }
    return null;
}

// Set speakers as default sink
function setSpeakersAsDefault() {
    const node = root.findDeviceByName(Config.audio.speakersNode, true);
    if (node) {
        root.setDefaultSink(node);
    } else {
        console.warn("Audio.setSpeakersAsDefault: speakers node not found:", Config.audio.speakersNode);
    }
}

// Set headphones as default sink
function setHeadphonesAsDefault() {
    const node = root.findDeviceByName(Config.audio.headphonesNode, true);
    if (node) {
        root.setDefaultSink(node);
    } else {
        console.warn("Audio.setHeadphonesAsDefault: headphones node not found:", Config.audio.headphonesNode);
    }
}

// Determine which of the two configured nodes is currently the default sink
function currentOutputType(): string {
    const currentName = root.sink?.nickname || root.sink?.description || "";
    if (currentName === Config.audio.speakersNode) return "speakers";
    if (currentName === Config.audio.headphonesNode) return "headphones";
    return "unknown";
}

// Toggle between speakers and headphones
function toggleOutput() {
    if (root.currentOutputType() === "speakers") {
        root.setHeadphonesAsDefault();
    } else {
        root.setSpeakersAsDefault();
    }
}

// ──────────────────────────────────────────
```

**Nota:** `Config.audio` es accesible desde `Audio.qml` con `import qs.config` (ya importado en línea 7).

#### MicToggleButton.qml (NUEVO) — en `modules/bar/`

**Crear nuevo archivo:** `modules/bar/MicToggleButton.qml`

```qml
import QtQuick
import Quickshell
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.config

ToggleButton {
    required property var bar

    // Determine mute state
    readonly property bool micMuted: Audio.source?.audio?.muted ?? false

    buttonIcon: micMuted ? Icons.micSlash : Icons.mic
    tooltipText: micMuted ? "Unmute microphone" : "Mute microphone"
    iconTint: !micMuted
    iconFullTint: !micMuted

    onToggle: function () {
        Audio.toggleMicMute();
    }
}
```

#### OutputToggleButton.qml (NUEVO) — en `modules/bar/`

**Crear nuevo archivo:** `modules/bar/OutputToggleButton.qml`

```qml
import QtQuick
import Quickshell
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.config

ToggleButton {
    required property var bar

    // Determine current output type
    readonly property string currentOutput: Audio.currentOutputType()

    buttonIcon: currentOutput === "headphones" ? Icons.headphones : Icons.speakerHigh
    tooltipText: currentOutput === "headphones" ? "Switch to speakers" : "Switch to headphones"
    iconTint: currentOutput === "headphones"
    iconFullTint: currentOutput === "headphones"

    onToggle: function () {
        Audio.toggleOutput();
    }
}
```

#### BarContent.qml — Inserción de toggles (F3)

**Archivo:** `modules/bar/BarContent.qml`

**Inserción horizontal (después del `PresetsButton` línea 502, antes de `ToolsButton` línea 509):**

```qml
// Después de línea 507 (cierre de PresetsButton)

// Mixer Mic Toggle (F3)
MicToggleButton {
    id: micToggleButton
    visible: Config.bar.mixerMicToggle ?? true
    Layout.preferredWidth: visible ? 36 : 0
    startRadius: root.innerRadius
    endRadius: root.innerRadius
    enableShadow: root.shadowsEnabled
}

// Mixer Output Toggle (F3)
OutputToggleButton {
    id: outputToggleButton
    visible: Config.bar.mixerOutputToggle ?? true
    Layout.preferredWidth: visible ? 36 : 0
    startRadius: root.innerRadius
    endRadius: root.dockAtStart ? root.innerRadius : root.outerRadius
    enableShadow: root.shadowsEnabled
}
```

**Inserción vertical (después del `ToolsButtonVert` línea 579, antes del `PresetsButtonVert` línea 587):**

```qml
// Después de línea 585 (cierre de ToolsButtonVert vertical)

// Mixer Mic Toggle (F3) vertical
MicToggleButton {
    id: micToggleButtonVert
    visible: Config.bar.mixerMicToggle ?? true
    Layout.preferredHeight: visible ? 36 : 0
    startRadius: root.innerRadius
    endRadius: root.innerRadius
    vertical: true
    enableShadow: root.shadowsEnabled
}

// Mixer Output Toggle (F3) vertical
OutputToggleButton {
    id: outputToggleButtonVert
    visible: Config.bar.mixerOutputToggle ?? true
    Layout.preferredHeight: visible ? 36 : 0
    startRadius: root.innerRadius
    endRadius: root.innerRadius
    vertical: true
    enableShadow: root.shadowsEnabled
}
```

### 5.4 UI: AudioMixerPanel.qml

**Archivo:** `modules/widgets/dashboard/controls/AudioMixerPanel.qml`

**Insertar nueva sección** entre el `ColumnLayout` de devices (línea 193) y el `Separator` (línea 197). Es decir, **antes del `Separator`** que separa "Devices" de "Volume Mixer":

```qml
// Insertar antes de la línea 197 (antes del Separator)

// ── NUEVO F3: Mixer Toggles Settings ──
Text {
    text: "Bar Toggles"
    font.family: Config.theme.font
    font.pixelSize: Styling.fontSize(-1)
    font.weight: Font.Medium
    color: Colors.overSurfaceVariant
    Layout.topMargin: 8
}

ToggleRow {
    label: "Show Mic Mute in bar"
    checked: Config.bar.mixerMicToggle ?? true
    onToggled: value => {
        if (value !== Config.bar.mixerMicToggle) {
            Config.bar.mixerMicToggle = value;
        }
    }
}

ToggleRow {
    label: "Show Output Toggle in bar"
    checked: Config.bar.mixerOutputToggle ?? true
    onToggled: value => {
        if (value !== Config.bar.mixerOutputToggle) {
            Config.bar.mixerOutputToggle = value;
        }
    }
}

// ── Speakers / Headphones selection ──
Text {
    text: "Output Devices"
    font.family: Config.theme.font
    font.pixelSize: Styling.fontSize(-1)
    font.weight: Font.Medium
    color: Colors.overSurfaceVariant
    Layout.topMargin: 8
}

RowLayout {
    Layout.fillWidth: true
    spacing: 8
    Text {
        text: "Speakers"
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(0)
        color: Colors.overBackground
        Layout.preferredWidth: 80
    }
    StyledRect {
        variant: "common"
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: Styling.radius(-2)
        visible: Config.bar.mixerOutputToggle ?? true
        enabled: Config.audio.speakersNode !== "" || Audio.outputDevices.length > 0
        TextInput {
            anchors.fill: parent
            anchors.margins: 8
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            color: Colors.overBackground
            selectByMouse: true
            text: Config.audio.speakersNode
            placeholderText: Audio.outputDevices.length > 0
                ? "Available: " + Audio.outputDevices.map(d => d.nickname || d.description).join(", ")
                : "No output devices detected"
            onEditingFinished: {
                if (text !== Config.audio.speakersNode) {
                    Config.audio.speakersNode = text.trim();
                }
            }
        }
    }
}

RowLayout {
    Layout.fillWidth: true
    spacing: 8
    Text {
        text: "Headphones"
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(0)
        color: Colors.overBackground
        Layout.preferredWidth: 80
    }
    StyledRect {
        variant: "common"
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: Styling.radius(-2)
        visible: Config.bar.mixerOutputToggle ?? true
        enabled: Config.bar.mixerOutputToggle ?? true
        TextInput {
            anchors.fill: parent
            anchors.margins: 8
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            color: Colors.overBackground
            selectByMouse: true
            text: Config.audio.headphonesNode
            placeholderText: Audio.outputDevices.length > 0
                ? "Available: " + Audio.outputDevices.map(d => d.nickname || d.description).join(", ")
                : "No output devices detected"
            onEditingFinished: {
                if (text !== Config.audio.headphonesNode) {
                    Config.audio.headphonesNode = text.trim();
                }
            }
        }
    }
}

// ──────────────────────────────────────────
```

**Nota:** `ToggleRow` debe existir localmente en `AudioMixerPanel.qml`. Si no existe, **duplicar inline** siguiendo el patrón de `ShellPanel.qml` líneas 149-222.

### 5.5 Acceptance Criteria F3

| # | Criterio | Verificación |
|---|----------|--------------|
| AC-F3-1 | El botón mic toggle aparece en la bar (horizontal y vertical) si `Config.bar.mixerMicToggle = true` | Visual con toggle ON |
| AC-F3-2 | El botón mic toggle está oculto si `Config.bar.mixerMicToggle = false` | Visual con toggle OFF |
| AC-F3-3 | Click en mic toggle llama a `Audio.toggleMicMute()` y cambia el estado de `Audio.source.audio.muted` | Verificar: `wpctl get-mute @DEFAULT_SOURCE@` antes/después |
| AC-F3-4 | El icono cambia entre `Icons.mic` (no mute) y `Icons.micSlash` (mute) | Visual |
| AC-F3-5 | El icono mic está tintado con color accent cuando NO está muteado | Visual |
| AC-F3-6 | El botón output toggle aparece en la bar si `Config.bar.mixerOutputToggle = true` | Visual |
| AC-F3-7 | Click en output toggle cicla entre speakers y headphones | Configurar speakers="alsa_output.pci-0000_00_1f.3.analog-stereo" y headphones="alsa_output.usb-...", click observa cambio en `wpctl status` |
| AC-F3-8 | El icono del output toggle es `Icons.speakerHigh` cuando speakers activo, `Icons.headphones` cuando headphones activo | Visual |
| AC-F3-9 | En settings, los inputs "Speakers" y "Headphones" están deshabilitados si `mixerOutputToggle = false` | Visual: input gris, no editable |
| AC-F3-10 | Los inputs aceptan el nombre exacto (nickname o description) del sink PipeWire | `wpctl inspect <node>` para obtener el nombre, pegar en input |
| AC-F3-11 | Si el nombre no existe, `Audio.toggleOutput()` logea warning y no cambia el sink | Verificar logs al usar un nombre inválido |
| AC-F3-12 | `Config.audio.speakersNode` y `Config.audio.headphonesNode` persisten entre sesiones | Cerrar y abrir shell, los valores se mantienen |

## 6. Modelo de Datos (Resumen)

### 6.1 Cambios en archivos de config

| Archivo | Cambios |
|---------|---------|
| `config/defaults/workspaces.js` | +1 key: `perMonitor: false` |
| `config/defaults/bar.js` | +2 keys: `mixerMicToggle: true`, `mixerOutputToggle: true` |
| `config/defaults/audio.js` | **NUEVO**: `speakersNode: ""`, `headphonesNode: ""` |
| `config/Config.qml` | +1 import (`AudioDefaults`), +2 properties en `workspacesLoader.adapter`, +2 en `barLoader.adapter`, **+1 nuevo FileView** `audioLoader`, +1 property `audio: audioLoader.adapter` |
| `modules/widgets/dashboard/wallpapers/Wallpaper.qml` | +2 properties en `wallpaperAdapter`: `rotationEnabled`, `rotationIntervalMinutes` |
| `modules/widgets/dashboard/controls/ThemePanel.qml` | +2 properties en `wallpaperConfig.adapter` (mismo FileView) |

### 6.2 Nuevos archivos QML

| Archivo | Rol |
|---------|-----|
| `modules/bar/MicToggleButton.qml` | Botón mic mute (ToggleButton wrapper) |
| `modules/bar/OutputToggleButton.qml` | Botón output cycle (ToggleButton wrapper) |

### 6.3 Estado en disco

| Path | Cambio |
|------|--------|
| `~/.config/ambxst/config/workspaces.json` | +`perMonitor: false` (auto via validator) |
| `~/.config/ambxst/config/bar.json` | +`mixerMicToggle`, `mixerOutputToggle` (auto via validator) |
| `~/.config/ambxst/config/audio.json` | **NUEVO**, creado con `AudioDefaults.data` |
| `~/.cache/ambxst/wallpapers.json` | +`rotationEnabled`, `rotationIntervalMinutes` (auto via JsonAdapter default) |

## 7. Integraciones

### 7.1 PipeWire (vía Quickshell.Services.Pipewire)
- **Trigger:** Click en mic toggle, click en output toggle.
- **Operación:** `Audio.toggleMicMute()` y `Audio.setDefaultSink(node)`.
- **Idempotencia:** PipeWire maneja internamente (mute toggle es flip, setDefaultSink es set).
- **Retry policy:** N/A (operación síncrona local).
- **Failure handling:** Si el nodo no existe, warning log + no-op.
- **Observability:** Logs en `~/.local/share/quickshell/qml.log` y `wpctl status` en consola.

### 7.2 Hyprland (vía axctl)
- **Trigger:** Click en workspace button (F1 perMonitor), ya gestionado por `Workspaces.qml` actual.
- **Operación:** `axctl window move-to-workspace-silent <id>` + `axctl monitor focus <name>`.
- **Idempotencia:** N/A (cada click es un dispatch explícito).
- **Retry policy:** N/A.
- **Failure handling:** Si el comando axctl falla, no hay cambio visual; el usuario puede reintentar.
- **Observability:** `axctl subscribe` events ya se logean en `AxctlService.rawEvent`.

### 7.3 matugen
- **Trigger:** Wallpaper change (F2 rotation tick o F2 manual via `nextWallpaper`).
- **Operación:** `matugen image <wallpaper> --source-color-index 0 -t <scheme>` → regenera `~/.cache/ambxst/colors.json`.
- **Idempotencia:** Sí (es determinístico por imagen).
- **Retry policy:** No retry; si falla, el colors.json anterior permanece.
- **Failure handling:** Error log en `Wallpaper.qml` matugen process.
- **Observability:** `Colors.qml.onFileChanged` se dispara → todos los consumidores actualizan.

## 8. Seguridad y Permisos

| Aspecto | Estado | Justificación |
|---------|--------|--------------|
| AuthN/AuthZ | N/A | El shell se ejecuta en el contexto del usuario; no hay API externa que requiera auth. |
| Tenant boundary | N/A | Single-user shell. |
| Datos sensibles | Bajo | Los nombres de sinks PipeWire pueden incluir HW info (PCI paths), pero no es secreto. |
| Rate limits | N/A | No hay endpoints externos. |
| Auditoría | Bajo | Cambios de wallpaper/sink se reflejan en `~/.cache/ambxst/colors.json` (trazable). |

## 9. Operación

### 9.1 Logs
- `Quickshell.Io` process logs (matugen, axctl) van a `~/.local/share/quickshell/qml.log`.
- `console.log/warn/error` en QML van a `journalctl --user -u quickshell` o al stderr del proceso.

### 9.2 Métricas
No aplica (no hay backend que recolecte métricas).

### 9.3 Health checks
- `Audio.ready` (línea 18): si Pipewire no está disponible, los toggles en bar mostrarán estado neutro.
- `Quickshell.screens.length`: si 0, F1 toggle se deshabilita.

### 9.4 Configuración
Toda la config es por usuario en `~/.config/ambxst/config/`. Multi-usuario no es objetivo.

### 9.5 Despliegue local
- No requiere migraciones.
- `Config.qml` se recompila on the fly (Quickshell recarga con `qs -p shell.qml`).
- No afecta a `nix/packages/*` (todo es QML).

## 10. Estrategia de Test

### 10.1 Entorno de validación

**Comando principal:**
```bash
qs -p shell.qml
```

**Comandos auxiliares:**
```bash
# Ver logs de QML
journalctl --user -u quickshell -f

# Estado de audio
wpctl status
wpctl get-mute @DEFAULT_SOURCE@

# Estado de workspaces
hyprctl workspaces
axctl workspace list  # si axctl lo soporta

# Estado de wallpaper/colors
cat ~/.cache/ambxst/colors.json | jq '.primary'
ls ~/.cache/ambxst/wallpapers.json
cat ~/.cache/ambxst/wallpapers.json | jq .

# Verificar defaults aplicados
cat ~/.config/ambxst/config/workspaces.json
cat ~/.config/ambxst/config/bar.json
cat ~/.config/ambxst/config/audio.json  # nuevo
```

### 10.2 Plan de validación visual

| Feature | Pasos | Resultado esperado |
|---------|-------|-------------------|
| F1 | 1. Conectar 2do monitor 2. `qs -p shell.qml` 3. Settings → Shell → Workspaces → Per Monitor ON | Toggle habilitado, opacity 1.0 |
| F1 | Click en workspace 6 del monitor derecho | Logs: `axctl window move-to-workspace-silent 16` (offset 10*1 + 6) |
| F2 | 1. Theme → General → Auto-rotate ON, interval 1 min 2. Esperar 60s | Wallpaper cambia, matugen se ejecuta, colors.json se actualiza |
| F2 | Input interval 1500 | IntValidator rechaza, valor se mantiene en 1440 o anterior |
| F3 | 1. wpctl status para obtener nombres de sinks 2. Audio settings → Speakers y Headphones inputs 3. Click en output toggle de la bar | Sink default cambia, icono cambia |
| F3 | Click en mic toggle de la bar | `wpctl get-mute @DEFAULT_SOURCE@` cambia entre "Mute" y "[unmuted]" |

### 10.3 Checklist pre-flight (de `pre-flight-check`)

- [ ] `config/defaults/workspaces.js` contiene `perMonitor: false`
- [ ] `config/defaults/bar.js` contiene `mixerMicToggle: true` y `mixerOutputToggle: true`
- [ ] `config/defaults/audio.js` existe con `speakersNode: ""` y `headphonesNode: ""`
- [ ] `config/Config.qml` importa `AudioDefaults`
- [ ] `Config.qml` tiene `audioLoader` FileView con path y adapter correctos
- [ ] `Config.qml` expone `property QtObject audio: audioLoader.adapter`
- [ ] `barLoader.adapter` tiene las dos nuevas properties
- [ ] `workspacesLoader.adapter` tiene `perMonitor`
- [ ] `Wallpaper.qml` y `ThemePanel.qml` wallpaperAdapter tiene `rotationEnabled` y `rotationIntervalMinutes`
- [ ] `ShellPanel.qml` línea ~1208 tiene el nuevo `ToggleRow` "Per Monitor"
- [ ] `ThemePanel.qml` después de la línea 334 tiene `ToggleRow` "Auto-rotate" + `NumberInputRow` "Rotation interval"
- [ ] `AudioMixerPanel.qml` antes de línea 197 tiene sección "Bar Toggles" + "Output Devices"
- [ ] `modules/bar/MicToggleButton.qml` existe
- [ ] `modules/bar/OutputToggleButton.qml` existe
- [ ] `BarContent.qml` líneas ~507 y ~585 incluye los dos toggles
- [ ] `Audio.qml` tiene `findDeviceByName`, `setSpeakersAsDefault`, `setHeadphonesAsDefault`, `currentOutputType`, `toggleOutput`
- [ ] `Workspaces.qml` líneas 18, 21, 108, 418, 555 modificadas para perMonitor
- [ ] `ToggleRow` en `ThemePanel.qml` y `AudioMixerPanel.qml` está duplicado inline (no importado)

### 10.4 Criterios de no-regresión

- [ ] Workspaces con `perMonitor = false` se comportan idénticamente a la versión 1.1.5
- [ ] Wallpaper rotation desactivado por default; el shell se comporta idéntico sin tocar F2
- [ ] `Config.bar.mixerMicToggle = true` y `mixerOutputToggle = true` por default; si F3 falla, la bar no se rompe
- [ ] Si `Config.audio` no existe (usuario nuevo), el validador lo crea con defaults vacíos
- [ ] `Colors.qml` recarga reactivamente cuando matugen regenera `colors.json`
- [ ] `Wallpaper.qml` `nextWallpaper()` manual sigue funcionando idéntico a 1.1.5

## 11. Decomposition Contract (para Task Decomposer)

Esta sección es la **fuente de verdad** que `task-decomposer` usará para atomizar el trabajo. Contiene los nombres canónicos que NO deben cambiar.

### 11.1 Endpoints canónicos
- `Config.workspaces.perMonitor: bool`
- `Config.workspaces.shown: int` (sin cambios)
- `Config.bar.mixerMicToggle: bool`
- `Config.bar.mixerOutputToggle: bool`
- `Config.audio.speakersNode: string`
- `Config.audio.headphonesNode: string`
- `wallpaperConfig.adapter.rotationEnabled: bool`
- `wallpaperConfig.adapter.rotationIntervalMinutes: int`

### 11.2 Schemas / DTOs canónicos
- `MicToggleButton` (QML component) en `modules/bar/MicToggleButton.qml`
- `OutputToggleButton` (QML component) en `modules/bar/OutputToggleButton.qml`

### 11.3 Funciones / APIs canónicas
- `Audio.toggleMicMute()` (existente)
- `Audio.setDefaultSink(node)` (existente)
- `Audio.outputDevices` (existente)
- `Audio.findDeviceByName(name, isSink)` (NUEVO)
- `Audio.setSpeakersAsDefault()` (NUEVO)
- `Audio.setHeadphonesAsDefault()` (NUEVO)
- `Audio.currentOutputType(): string` (NUEVO)
- `Audio.toggleOutput()` (NUEVO)
- `Wallpaper.nextWallpaper()` (existente)
- `AxctlService.dispatch("movetoworkspacesilent <id>")` (existente)
- `AxctlService.dispatch("focusmonitor <name>")` (existente)

### 11.4 Allowed task order (orden de implementación recomendado)

1. **T1**: `config/defaults/audio.js` (nuevo archivo, contenido definido en §5.2)
2. **T2**: `config/Config.qml` — import AudioDefaults + nuevo audioLoader + property audio
3. **T3**: `config/defaults/workspaces.js` — añadir `perMonitor`
4. **T4**: `config/Config.qml` — añadir `perMonitor` a workspacesLoader.adapter
5. **T5**: `config/defaults/bar.js` — añadir `mixerMicToggle` y `mixerOutputToggle`
6. **T6**: `config/Config.qml` — añadir las dos keys a barLoader.adapter
7. **T7**: `Wallpaper.qml` — añadir `rotationEnabled` y `rotationIntervalMinutes` a wallpaperAdapter
8. **T8**: `ThemePanel.qml` — añadir las dos keys a wallpaperConfig.adapter (mismo JsonAdapter, asegurar consistencia)
9. **T9**: `Audio.qml` — añadir las 5 funciones nuevas
10. **T10**: `modules/bar/MicToggleButton.qml` (nuevo)
11. **T11**: `modules/bar/OutputToggleButton.qml` (nuevo)
12. **T12**: `BarContent.qml` — insertar toggles horizontal + vertical
13. **T13**: `Workspaces.qml` — implementar perMonitor (modificar 5 puntos)
14. **T14**: `ThemePanel.qml` — añadir ToggleRow "Auto-rotate" + NumberInputRow "Rotation interval"
15. **T15**: `ShellPanel.qml` — extender ToggleRow con `enabled` + añadir "Per Monitor"
16. **T16**: `AudioMixerPanel.qml` — añadir sección "Bar Toggles" + "Output Devices"
17. **T17**: Verificación final con `qs -p shell.qml` y checklist de §10.3

> **Regla de ordering:** T1-T8 son prerequisitos de config (pueden ir en cualquier orden entre sí, pero todas antes de T9-T16). T9-T13 son código de dominio. T14-T16 son UI. T17 es validación.

### 11.5 Forbidden stale terms
- ❌ "PerMonitor" (debe ser `perMonitor`)
- ❌ "rotationEveryTime" o "changeEveryTime" en código (label UI sí, pero key NO)
- ❌ "speakersSink" / "headphonesSink" (debe ser `speakersNode` / `headphonesNode`)
- ❌ "MicButton" (debe ser `MicToggleButton`)
- ❌ "OutputButton" (debe ser `OutputToggleButton`)
- ❌ "WallpaperService" nuevo singleton (reusar `Wallpaper.qml`)
- ❌ "micMute" o "isMicMuted" en Config (no aplica; el estado es runtime de Pipewire)

### 11.6 Archivos autoritativos (no se pueden crear variantes)

| Path | Tipo |
|------|------|
| `config/defaults/audio.js` | Default module |
| `modules/bar/MicToggleButton.qml` | Bar component |
| `modules/bar/OutputToggleButton.qml` | Bar component |
| `config/Config.qml` | Singleton |
| `modules/services/Audio.qml` | Singleton |
| `modules/bar/workspaces/Workspaces.qml` | Widget |
| `modules/widgets/dashboard/wallpapers/Wallpaper.qml` | Wallpaper pipeline |
| `modules/widgets/dashboard/controls/ThemePanel.qml` | Settings UI |
| `modules/widgets/dashboard/controls/ShellPanel.qml` | Settings UI |
| `modules/widgets/dashboard/controls/AudioMixerPanel.qml` | Settings UI |
| `modules/bar/BarContent.qml` | Bar layout |

## 12. Riesgos y Mitigaciones

| # | Riesgo | Probabilidad | Impacto | Mitigación |
|---|--------|--------------|---------|-----------|
| R1 | El nuevo `audioLoader` FileView causa doble-save en cascada | Baja | Medio | Usar `pauseAutoSave` y validar que no hay loops |
| R2 | `Workspaces.qml` con perMonitor rompe Hyprland si no hay suficientes workspaces | Media | Alto | Pre-validar `Config.workspaces.shown * Quickshell.screens.length <= 20` (límite razonable) y avisar al usuario si excede |
| R3 | `matugen` no está instalado → rotación falla silenciosa | Baja | Bajo | Log warning + mantener wallpaper pero no actualizar colors |
| R4 | `axctl` no soporta `move-to-workspace-silent` en versión vieja | Baja | Alto | Verificar versión de axctl; fallback a `workspace <id>` (no-silent) con focus follow |
| R5 | `Config.audio.speakersNode` y `Config.audio.headphonesNode` tienen el mismo valor | Baja | Bajo | `toggleOutput` log warning + no-op |
| R6 | El timer de rotación sigue corriendo cuando el usuario está en screensaver | Baja | Bajo | Aceptar; matugen es rápido |
| R7 | UI shows `ToggleRow` en `ThemePanel` con el componente sin `enabled` (oversight) | Media | Bajo | Duplicar el `ToggleRow` con extensión `enabled` (igual que en F1) en ThemePanel |
| R8 | Conflicto entre output toggle y sink por defecto del sistema | Media | Medio | Documentar en el tooltip que sobrescribe el default del sistema |

## 13. Criterios de Aceptación Globales

| # | Criterio |
|---|----------|
| CA-1 | Las 3 features pasan el checklist de §10.3 |
| CA-2 | No hay regresión: workspaces sin perMonitor, wallpaper sin rotation, mixer sin toggles se comportan idénticos a 1.1.5 |
| CA-3 | `qs -p shell.qml` inicia sin errores ni warnings nuevos en `journalctl` |
| CA-4 | Los archivos JSON de config persisten cambios y sobreviven reinicio del shell |
| CA-5 | `matugen` se ejecuta tras cada rotación (verificar `colors.json` updated) |
| CA-6 | `Config.audio.speakersNode` vacío no rompe la bar; el botón output muestra estado neutral (icono `speakerHigh` siempre, sin tint) |
| CA-7 | Documentación: el changelog del sitio web (`/home/adriano/Repos/Axenide/web/`) se actualiza con las 3 features (a criterio del usuario, NO parte de este incremento) |

## 14. Out of Scope

- F1: Asignación manual de workspaces por monitor (siempre lineal por índice).
- F2: Shuffle mode (aleatorio), pause-when-video, smart rotation basado en hora.
- F3: Más de 2 outputs configurables, perfiles de audio por aplicación, ecualizador.
- Cualquier cambio en `nix/packages/*`, `install.sh`, dependencias de compilación.
- Migración de datos de usuarios existentes (no hay schema change breaking — todas las keys nuevas tienen default).

## 15. References

- [Hyprland Workspace docs](https://wiki.hyprland.org/Configuring/Workspaces/)
- [Quickshell.Io.FileView](https://quickshell.org/docs/types/Quickshell/Io/FileView/)
- [Quickshell.Services.Pipewire](https://quickshell.org/docs/types/Quickshell/Services/Pipewire/)
- [matugen](https://github.com/InioX/matugen)
- [Phosphor Icons Bold](https://phosphoricons.com/)
- `AGENTS.md` (raíz del proyecto)
- `config/AGENTS.md`
- `modules/services/AGENTS.md`
- `modules/components/AGENTS.md`
- `modules/bar/AGENTS.md`
- `modules/theme/AGENTS.md`
- `modules/widgets/dashboard/AGENTS.md`
