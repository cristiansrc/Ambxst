---
increment: 004-multi-monitor-workspaces-wallpaper-rotation-mixer-toggles
title: "Multi-monitor Workspaces, Wallpaper Auto-rotation and Mixer Bar Toggles"
status: planning
created: 2026-08-25
project: Ambxst
target_version: 1.2.0
author: planner-agent
related_bugfixes:
  - 001-wifi-bt-gate-fix
  - 002-settingswindow-per-monitor
  - 003-ia-defaults
---

# Shared SDD Context — Increment 004

> **Single active shared context for this increment.**
> Este archivo es la única fuente de verdad para la fase de planificación.
> Otros shared contexts deben marcarse `superseded` antes de crear uno nuevo.

## Current status

`planning` — El Planner está diseñando los contratos de configuración, los mock QML snippets y los criterios de aceptación para las 3 features. No se ha iniciado todavía la validación por Spec Validator ni la descomposición en tareas.

**Próximo gate obligatorio:** Spec Validator review → Human Plan Approval → Task Decomposer.

## Canonical artifacts

| Tipo | Ruta absoluta | Rol |
|------|---------------|-----|
| Project root | `/mnt/storage/Lugares/Proyectos/ambxst-workspace/projects/Ambxst` | Raíz del repositorio activo |
| Delta spec | `docs/specs/increments/004-multi-monitor-workspaces-wallpaper-rotation-mixer-toggles.md` | Especificación incremental (este incremento) |
| Master spec | N/A | Proyecto STANDALONE — no aplica `master_spec.md` global |
| Config singleton | `config/Config.qml` | `FileView` + `JsonAdapter` reactivo, >3500 líneas |
| Workspaces defaults | `config/defaults/workspaces.js` | Blueprint para `workspaces.json` (extender con `perMonitor`) |
| Theme defaults | `config/defaults/theme.js` | Blueprint para `theme.json` (NO se modifica aquí; wallpaper rotation se almacena en otro lado) |
| Bar defaults | `config/defaults/bar.js` | Blueprint para `bar.json` (extender con `mixerToggles`) |
| Audio mixer defaults | `config/defaults/desktop.js` o nuevo `audio.js` | Blueprint para nuevo toggle de audio (ver Decomposition Contract) |
| Workspaces UI | `modules/widgets/dashboard/controls/ShellPanel.qml` (líneas 1138-1208) | Sección `Workspaces` (extender con `ToggleRow perMonitor`) |
| Wallpaper pipeline | `modules/widgets/dashboard/wallpapers/Wallpaper.qml` | `nextWallpaper()`, `setWallpaper()`, `runMatugenForCurrentWallpaper()` |
| Wallpaper config JSON | `~/.cache/ambxst/wallpapers.json` | Estado runtime del wallpaper (extension propuesta) |
| Colors JSON | `~/.cache/ambxst/colors.json` | Salida de matugen; consumido por `Colors.qml` |
| Audio service | `modules/services/Audio.qml` | `toggleMicMute()`, `setDefaultSink(node)`, `outputDevices`, `inputDevices` |
| Compositor abstraction | `modules/services/AxctlService.qml` | `dispatch("movetoworkspacesilent ws,address")` ya implementado |
| Workspaces widget | `modules/bar/workspaces/Workspaces.qml` | Renderiza botones de workspace; consume `Config.workspaces.*` |
| Bar content | `modules/bar/BarContent.qml` (líneas 502-507) | Punto de inserción de toggles junto a `PresetsButton` |
| Mixer UI | `modules/widgets/dashboard/controls/AudioMixerPanel.qml` | Panel de audio (extender con sección de toggles + selectors) |
| ToggleButton component | `modules/components/ToggleButton.qml` | Primitive para icon buttons en bar |
| Colors singleton | `modules/theme/Colors.qml` | Watches `~/.cache/ambxst/colors.json` reactivamente |
| Theme panel UI | `modules/widgets/dashboard/controls/ThemePanel.qml` (líneas 285-334) | Punto de inserción `Theme → General` debajo de `wallpaper location` |

> **Nota workspace-coordination:** Este proyecto es STANDALONE (no está bajo carpeta `projects/` padre de un Solution Workspace superior — está dentro de `ambxst-workspace/projects/Ambxst`, pero la jerarquía de Solution Workspace aplica cuando el padre es `projects/` y existe una Master Spec global. Como no existe `docs/specs/master_spec.md` ni en el proyecto ni en la raíz del workspace, este incremento no requiere `enterprise-spec-validator` ni `Workspace Aligned` gate.

## Artifact evidence

| Artefacto | Campo / endpoint / flow | Resultado observado | Estado |
|-----------|-------------------------|---------------------|--------|
| `config/defaults/workspaces.js` | `dynamic` (línea 8) | Existe `dynamic: false`; se añadirá `perMonitor: false` debajo | `pass` |
| `config/Config.qml` línea 589-595 | `workspacesLoader.adapter` | Existe adapter con `shown, showAppIcons, alwaysShowNumbers, showNumbers, dynamic`; se añadirá `perMonitor` | `pass` |
| `config/Config.qml` línea 530-552 | `barLoader.adapter` | Existe adapter con propiedades actuales; se añadirán `mixerMicToggle`, `mixerOutputToggle` | `pass` |
| `config/defaults/bar.js` | `keepBarBorder` (línea 23) | Última key actual; se añadirán las keys de mixer toggles debajo | `pass` |
| `modules/widgets/dashboard/controls/ShellPanel.qml` líneas 1198-1207 | `ToggleRow { label: "Dynamic" ... }` | Existe el `Dynamic` toggle; se insertará `perMonitor` ToggleRow justo debajo, dentro del bloque `workspaces` | `pass` |
| `modules/bar/BarContent.qml` líneas 502-507 | `PresetsButton` | Existe el botón; se insertarán dos `ToggleButton` (mic + output) entre `PresetsButton` y `ToolsButton` (horizontal) y entre `ToolsButton` y `PresetsButton` (vertical) | `pass` |
| `modules/widgets/dashboard/controls/ThemePanel.qml` líneas 285-334 | `Wallpapers` `TextInput` con `wallpaperConfig.adapter.wallPath` | El "wallpaper location" es `wallPath` en `~/.cache/ambxst/wallpapers.json`; se insertará `Toggle changeEveryTime` + `NumberInputRow` debajo | `pass` |
| `modules/widgets/dashboard/wallpapers/Wallpaper.qml` línea 340-354 | `function nextWallpaper()` | Existe función para avanzar al siguiente wallpaper; se reutilizará para la rotación automática | `pass` |
| `modules/services/Audio.qml` líneas 156-160, 201-207, 111-112 | `toggleMicMute()`, `setDefaultSink(node)`, `outputDevices/inputDevices` | API existente; sin necesidad de extender el servicio | `pass` |
| `modules/services/AxctlService.qml` líneas 53-58 | `movetoworkspacesilent` dispatch | Comando ya soportado via `axctl window move-to-workspace-silent`; se documentará para per-monitor | `pass` |
| `modules/components/ToggleButton.qml` | `buttonIcon`, `tooltipText`, `onToggle` | Primitive listo para usar con iconos mic/speaker/headphone | `pass` |
| `modules/theme/Icons.qml` líneas 133-140, 222 | `mic`, `micSlash`, `speakerHigh`, `headphones` | Iconos disponibles; se confirma que NO existe `speakerSlash` directo (se usará `speakerX` para toggle apagado) | `pass` |
| `modules/widgets/dashboard/controls/AudioMixerPanel.qml` línea 21 | `property bool showOutput` | Existe estado local; se extenderá con `mixerConfigVisible` para mostrar/ocultar cada botón | `pass` |
| `config/Config.qml` línea 11 | `import "defaults/workspaces.js" as WorkspacesDefaults` | Patrón de import ya establecido; se usará el mismo patrón para los nuevos defaults | `pass` |
| `config/Config.qml` líneas 1-15 | imports actuales | Existe `import "defaults/bar.js" as BarDefaults`; NO existe `audio.js`; se creará `config/defaults/audio.js` + nuevo `audioLoader` | `blocked` → acción: crear nuevo FileView para `audio.json` |

## Spec Validator Approval

```yaml
verdict: pending
reviewed_at: null
validator_agent: spec-validator
artifact_set_reviewed: null
summary: null
invalidated_by_changes_since: none
```

> El veredicto será `ready` solo cuando Spec Validator complete la revisión exitosa. Mientras tanto, el estado es `planning` y NO se autoriza descomposición ni ejecución.

## Decisions locked

1. **Persistencia de wallpaper rotation**: NO se almacena en `Config.theme` (que es para estado del tema, no rotación). Se almacena en `~/.cache/ambxst/wallpapers.json` (extender el `JsonAdapter` existente con `rotationEnabled`, `rotationIntervalMinutes`). Justificación: wallpaper config ya vive en ese archivo, evita crear un cuarto JSON solo para un par de campos.
2. **Persistencia de mixer bar toggles**: Sí se almacena en `Config.bar` (junto a `keepBarBorder`). Justificación: es configuración persistente de UI shell.
3. **Persistencia de mixer device selection**: Se almacena en **nuevo** `Config.audio` con un FileView propio. Justificación: los nombres de sinks de PipeWire son estado del sistema, no del shell; pero la elección del usuario (headphones vs speakers) es decisión de shell y debe persistir.
4. **`perMonitor` workspaces**: Habilitado condicionalmente por `Quickshell.screens.length >= 2`. Si se desactiva, workspaces vuelven al comportamiento global. Si se desactiva el monitor, las workspaces se consolidan.
5. **Wallpaper rotation timer**: Implementado como `Timer` dentro de `Wallpaper.qml` (la propiedad `currentIndex` se incrementa automáticamente cada N minutos llamando a `nextWallpaper()`). El timer se activa/desactiva reactivamente según `wallpaperConfig.adapter.rotationEnabled`.
6. **Mic mute toggle visual**: Color accent (`Styling.srItem("overprimary")`) cuando NO está muteado, color normal cuando SÍ está muteado. Icono: `Icons.mic` cuando activo, `Icons.micSlash` cuando muteado.
7. **Output toggle (speakers/headphones)**: Estado de toggle binario. Icono: `Icons.speakerHigh` o `Icons.headphones` según el sink activo. Click cicla entre los dos sinks pre-configurados.
8. **Multi-monitor workspaces: dispatch decision**: Se usará `movetoworkspacesilent` (no `movetoworkspace`) porque al cambiar el set de workspaces por monitor, no queremos que Hyprland haga focus follow; el foco lo manejaremos por separado con `focusmonitor`.

## Validator findings

> Vacío hasta que Spec Validator ejecute la revisión.

## Resolved findings

> Vacío hasta que se resuelvan hallazgos.

## Open questions

| # | Pregunta | Bloqueante | Owner | Estado |
|---|----------|-----------|-------|--------|
| 1 | ¿El usuario quiere que el timer de rotación respete el "pausa al ver video" (MPRIS active)? | No | Usuario | `pending` — Planner propone default: NO pausar (rotar siempre); dejar nota como follow-up futuro |
| 2 | ¿Para `perMonitor`, cuál es la asignación inicial workspace-monitor? | No | Spec Validator | `pending` — Planner propone: monitor 0 → ws 1..N, monitor 1 → ws N+1..2N, etc. (lineal por índice) |
| 3 | ¿El toggle de output debe ciclar entre 2 dispositivos fijos o permitir más de 2? | No | Usuario | `pending` — Planner propone: 2 dispositivos seleccionables en settings, click cicla entre los 2 |

> Las preguntas 1-3 NO bloquean el handoff. Se documentan para que Spec Validator las revise y proponga defaults si el usuario no responde antes de `ready`.

## Stale terms guard

Términos prohibidos en el código de este incremento (alertas inmediatas si aparecen):

- `handle properly`, `optimize`, `use best practices` — reemplazados por criterios concretos en la spec.
- `mixerMicToggle` debe ser el nombre canónico (NO `micToggle`, NO `barMicMute`).
- `mixerOutputToggle` debe ser el nombre canónico (NO `outputToggle`, NO `sinkToggle`).
- `perMonitor` debe ser el nombre canónico de la key de workspaces (NO `per_monitor`, NO `permonitor`).
- `rotationEnabled` / `rotationIntervalMinutes` deben ser los nombres canónicos de wallpaper rotation (NO `changeEveryTime`, NO `interval` a secas — esos son nombres de UI labels).
- `Config.audio.speakersNode` y `Config.audio.headphonesNode` son los nombres canónicos de selección de sinks (NO `outputSink1/2`).
- `WorkspaceManager` / `WallpaperRotationService` NO se crean nuevos singletons; se reutilizan los existentes (`Wallpaper.qml` es el manager, `AxctlService` ya dispatcha).
- `~/.cache/ambxst/wallpapers.json` es la ruta canónica del JSON de wallpaper (NO `~/.config/ambxst/wallpapers.json`).

## Next action

1. Crear el archivo de delta spec en `docs/specs/increments/004-multi-monitor-workspaces-wallpaper-rotation-mixer-toggles.md` con todas las secciones obligatorias (contratos, modelo de datos, lógica, integraciones, seguridad, operación, estrategia de test, criterios de aceptación).
2. Presentar el spec a Spec Validator para veredicto.
3. Si Spec Validator emite `ready`: solicitar `## Human Plan Approval: approved_by_user` antes de enrutar a Task Decomposer.
4. **Bloqueado** hasta que: (a) Spec Validator apruebe, (b) usuario apruebe el plan, (c) `audio.js` default + `audioLoader` FileView sean creados y validados.

---

## Human Plan Approval

```yaml
approved_by_user: false
approved_at: null
notes: null
```

> El Planner NO debe enrutar a Task Decomposer ni Executor sin este encabezado marcado `approved_by_user: true`.
