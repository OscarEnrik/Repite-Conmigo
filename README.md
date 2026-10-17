# Repite Conmigo

Prototipo jugable para la Woman Game Jam 2026.

Richard tiene un mal día tras otro. Loretta se sienta al lado y, en cada momento, elige
**una de 3 frases**: un chiste que lo choca, una frase que lo motiva o un ruido sin
sentido. Lo que salga de su boca mueve la **barra de ánimo**; el promedio de la semana
decide cuál de los **3 finales** le toca.

Godot **4.8 (dev `4.8-dev6`)**, 2D, renderer **GL Compatibility** con driver `d3d12`
(nada de Forward+/3D). Viewport 640×360, ventana 1280×720, stretch `canvas_items` + `expand`.

## Cómo correrlo

1. Abrí `project.godot` con Godot 4.8-dev6.
2. `F5`. La main scene es `scenes/boot/boot.tscn`: aplica preferencias, precarga lo pesado
   y salta al menú principal.

Con el addon MCP (`godot-ai`) desde el editor: `project_run` levanta el juego y `game_eval`
permite inspeccionarlo o manejarlo en vivo. Detalles y trampas en `AGENTS.md`.

## Controles

| Acción | Entrada |
|---|---|
| Elegir una frase | clic en el botón, o `ui_accept` (Enter / Espacio) sobre el botón enfocado |
| Confirmar la intro / cerrar el día | clic en "Continuar" / "Seguir" |
| Pausa | `Esc` o `P` (acción `pause`) |

`ui_accept` es una acción **built-in** de Godot, por eso no está declarada en
`project.godot`. El mapa de entrada propio del proyecto es una sola acción: `pause`.

## Estructura

```
assets/
  data/days.json         Guion de la semana: 7 días × 2 turnos × 3 opciones
  art/, audio/           Vacías por ahora (.gitkeep)
docs/
  ARCHITECTURE.md        Cómo funciona todo + recetario "quiero cambiar X" (para el equipo)
  IMPLEMENTATION_PLAN.md Orden de construcción del prototipo (paso a paso)
  GDD.md                 Diseño: pitch, loop, mecánicas, finales
  TODO.md                Pendientes y deuda técnica
  CREDITS.md             Equipo y assets de terceros (completar antes de entregar)
resources/themes/        main_theme.tres (fuente 18, tema global)
scenes/
  boot/boot.tscn         Main scene: splash + precarga + salto al menú
  main.tscn              Host persistente: LevelHost + HUD + DialogueBox + PauseMenu
  levels/day_scene.gd    Script compartido por los 7 días
  levels/day_01..07.tscn Un día cada uno
  ui/                    main_menu, hud, dialogue_box, pause_menu, settings_menu, ending
scripts/
  autoload/              Los 6 autoloads (ver recetas)
  resources/dialogue_db.gd  Lee y valida assets/data/days.json
  resources/game_data.gd    DTO de la semana guardada (savegame)
```

Cada `.tscn` vive **al lado** de su `.gd`. `addons/` es de terceros: no se toca.

## El bucle, en una pasada

```
boot.tscn ──► main_menu.tscn ──(Nueva partida)──► Game.start_run()
                                                      │
                              main.tscn ◄─────────────┘
                                 │
   LevelHost carga day_01..day_07 (uno por vez)
                                 │
   IntroCard ──"Continuar"──► Game.begin_dialog()
                                 │
   DialogueBox: 2 turnos, 3 opciones cada uno  ──► Events.mood_changed ──► HUD
                                 │
   "Día superado" / "Se acumula la tristeza" ──"Seguir"──► Game.next_day()
                                 │
                        (domingo) Game.finish_week() ──► ending.tscn
```

Quién decide qué día toca es `Game`; `Main` solo instancia la escena que le pide la señal
`Events.day_started`. Quién pasa al día siguiente es `DialogueBox` (`Game.next_day()`).

## Recetas: los 6 autoloads

El orden de carga importa (`Audio` y `Game` dependen de los anteriores).

| Autoload | Script | Para qué |
|---|---|---|
| `Events` | `scripts/autoload/event_bus.gd` | Señales globales. **Solo declaraciones**, cero lógica |
| `Settings` | `scripts/autoload/settings_manager.gd` | Volúmenes y pantalla completa → `user://settings.cfg` |
| `Save` | `scripts/autoload/save_manager.gd` | Un slot JSON → `user://savegame.json` |
| `Audio` | `scripts/autoload/audio_manager.gd` | Pool de SFX + música; crea los buses `Music`/`SFX` |
| `SceneLoader` | `scripts/autoload/scene_loader.gd` | Cambio de escena con fundido |
| `Game` | `scripts/autoload/game_manager.gd` | Estado de la semana: ánimo, día, turno, pausa, finales |

### Events — comunicarse sin acoplarse

```gdscript
Events.mood_changed.connect(_on_mood_changed)   # escuchar
Events.mood_changed.emit(62, -12)               # emitir
```

Señales: `game_started`, `game_returned_to_menu`, `game_paused`, `game_resumed`,
`day_started(day_index, title)`, `dialogue_turn_started(day_index, turn_index)`,
`option_chosen(option_index, kind, mood_delta)`, `mood_changed(new_mood, delta)`,
`day_finished(day_index, passed)`, `week_finished(ending_id)`,
`sfx_requested(sfx_id, position)`.

HUD, menús y días se hablan **solo** por acá, nunca por referencias directas: así
sobreviven a que se recargue el día. Si ves callbacks duplicados, `Events.clear_all()`.

### Settings — preferencias

```gdscript
Settings.set_audio_volume(&"music", 0.6)   # "master" | "music" | "sfx": aplica y guarda
Settings.set_fullscreen(true)              # aplica y guarda
Settings.apply()                           # vuelca el .cfg a audio/pantalla (lo llama boot)
```

`set_bus_volume()` y `apply_fullscreen()` son las mitades que solo aplican, sin guardar; el
menú de opciones usa las de arriba.

### Save — guardado

```gdscript
if Save.has_save():
    var data := Save.load_game()          # {} si no hay partida o el archivo está corrupto
Save.save_game({"mood": 62, "current_day": 3})
Save.set_value("muted", true)             # claves sueltas, sin tocar el resto del JSON
Save.delete_save()
```

`Game.save_progress()` / `Game.load_progress()` son el guardado real de la semana.

### Audio — música y SFX

```gdscript
Audio.register_sfx(&"click", preload("res://assets/audio/sfx/click.ogg"))
Audio.play_sfx(&"click")
Audio.play_sfx(&"hit", global_position)   # con atenuación por distancia
Audio.play_music(&"main_theme")
Audio.stop_music()
```

Pedir un id sin registrar avisa con `push_warning` en vez de quedarse en silencio.

### SceneLoader — cambiar de pantalla

```gdscript
await SceneLoader.change_scene("res://scenes/main.tscn")   # con fundido
SceneLoader.reload_scene()                                 # reinicia la escena actual
```

### Game — el estado de la semana

```gdscript
Game.start_run()             # semana nueva desde el lunes
Game.continue_run()          # retoma el guardado (sigue en history.size())
Game.start_day(0)            # fija ánimo/turno del día y emite day_started
Game.begin_dialog()          # la intro terminó: empiezan los turnos
Game.choose_option(1)        # aplica la opción y devuelve el delta ya escalado
Game.advance_turn()          # turno siguiente, o cierra el día
Game.next_day()              # día siguiente, o cierra la semana
Game.finish_week()           # el promedio de history decide el final
```

Constantes útiles: `DAY_COUNT`, `TURNS_PER_DAY`, `MOOD_MIN`/`MOOD_MAX`/`MOOD_START`,
`ENDING_BRIGHT_MIN` (70) y `ENDING_NEUTRAL_MIN` (40).

También es el único que lee `pause`: no dupliques esa lectura en las escenas.

## Editar el contenido

Todo el texto vive en **`assets/data/days.json`** (una sola fuente de verdad). Por día:

| Clave | Qué es |
|---|---|
| `day` | Número 1..7 |
| `title` | Día de la semana ("Lunes"…) |
| `start_mood` | Ánimo al que arranca el día |
| `pass_threshold` | Ánimo mínimo al cierre para "Día superado" |
| `richard_intro` | La desgracia del día (la IntroCard) |
| `turns[]` | 2 turnos, cada uno con `prompt` y `options[]` |
| `options[]` | 3 opciones, cada una con `text`, `kind` (`choke`/`motivate`/`sound`) y `mood` |

El `mood` del JSON es el valor **base**: `Game.difficulty_scale()` lo ajusta según el día
jugado (lo hiriente pega más fuerte y lo bueno rinde menos a medida que avanza la semana).
`DialogueDB.parse()` valida el archivo y hace `push_error` con día y turno si algo está mal,
así que un JSON roto avisa en consola en vez de crashear.

Los textos de los 3 finales viven en `scenes/ui/ending.gd` (`TITLES`).
