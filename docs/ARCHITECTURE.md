# Arquitectura — Repite Conmigo

> Documento para el equipo. Explica **cómo está armado** el juego y **dónde tocar cada cosa**.
> El recorrido va de lo conceptual (secciones 1-9) a lo quirúrgico (sección 11: recetario con
> archivo y línea exacta).

**Estado:** prototipo jugable completo. Los 13 pasos de `docs/IMPLEMENTATION_PLAN.md` están
cerrados. Motor: Godot **4.8-dev6**, 2D, renderer **GL Compatibility** (`d3d12`), lienzo
**1920×1080** (diseño original 640×360 escalado ×3).

## Índice

1. [Resumen en 30 segundos](#1-resumen-en-30-segundos)
2. [Los tres conceptos](#2-los-tres-conceptos)
3. [El arranque](#3-el-arranque-qué-pasa-al-apretar-f5)
4. [`Game`: el estado global](#4-game-el-estado-global)
5. [`Events`: el cableado](#5-events-el-cableado)
6. [El guion](#6-el-guion-daysjson--dialoguedb)
7. [Las escenas](#7-las-escenas-una-por-una)
8. [Un día completo, paso a paso](#8-un-día-completo-paso-a-paso)
9. [Pausa y guardado](#9-pausa-y-guardado)
10. [Cómo probar](#10-cómo-probar)
11. [Trampas que te van a morder](#11-trampas-que-te-van-a-morder)
12. [**Recetario: quiero cambiar X → toco Y**](#12-recetario-quiero-cambiar-x--toco-y)
13. [Verificación rápida por tipo de cambio](#13-verificación-rápida-por-tipo-de-cambio)
14. [Mapa de archivos](#14-mapa-de-archivos)

---

# 1. Resumen en 30 segundos

El texto vive en **`assets/data/days.json`**. **`Game`** es el único que sabe el estado (en qué
día vamos, cuánto ánimo hay) y el único que decide. **`Events`** es el cableado: escenas y
autoloads se hablan por señales, nunca por referencias directas. Las **escenas** solo pintan y
avisan. Y **`main.tscn`** mantiene vivos el HUD y la caja de diálogo mientras los días pasan por
`LevelHost`.

La regla de oro del proyecto: **una escena nunca llama a otra escena**. Le pide a `Game` o grita
por `Events`, y quien corresponda reacciona.

```
                    ┌──────────── AUTOLOADS (siempre vivos) ────────────┐
                    │  Events   Settings   Save   Audio  SceneLoader   │
                    │                    Game ─────────────────────────┐│
                    └──────────────────────────────────────────────────┘│
                              ▲   │              ▲     │                │
              emite señales   │   │  lee estado  │     │ cambia escena  │
                              │   ▼              │     ▼                │
   boot ──► main_menu ──► main.tscn (host persistente) ──► ending.tscn ◄┘
                              │
                              ├── LevelHost ──► day_01..day_07  (se tiran y recargan)
                              ├── HUD                (sobrevive)
                              ├── DialogueBox        (sobrevive)
                              └── PauseMenu          (sobrevive)
```

---

# 2. Los tres conceptos

| Capa | Qué es | Dónde vive |
|---|---|---|
| **Estado global** | Los 6 autoloads. Existen siempre, sobreviven a cualquier cambio de escena | `scripts/autoload/` |
| **Cables** | `Events`: señales. Nadie guarda referencias a nadie | `scripts/autoload/event_bus.gd` |
| **Vistas** | Escenas que se cargan y se tiran: pintan y avisan | `scenes/` |

Los 6 autoloads son (el orden de carga importa, `Audio` y `Game` dependen de los anteriores):

| Autoload | Script | Para qué |
|---|---|---|
| `Events` | `scripts/autoload/event_bus.gd` | Señales globales. **Solo declaraciones**, cero lógica |
| `Settings` | `scripts/autoload/settings_manager.gd` | Volúmenes y pantalla completa → `user://settings.cfg` |
| `Save` | `scripts/autoload/save_manager.gd` | Un slot JSON → `user://savegame.json` |
| `Audio` | `scripts/autoload/audio_manager.gd` | Pool de SFX + música; crea los buses `Music`/`SFX` |
| `SceneLoader` | `scripts/autoload/scene_loader.gd` | Cambio de escena con fundido |
| `Game` | `scripts/autoload/game_manager.gd` | Estado de la semana: ánimo, día, turno, pausa, finales |

> El proyecto tiene un autoload extra, `_mcp_game_helper`, que es del addon de IA. **No se toca.**

---

# 3. El arranque (qué pasa al apretar F5)

```
boot.tscn  (main scene del proyecto)
  _ready()
    ├─ Settings.apply()                 aplica volumen/pantalla del .cfg
    ├─ precarga main, main_menu, ending, day_01   (PRELOAD_SCENES)
    └─ espera 0.5s  ──►  SceneLoader.change_scene("res://scenes/ui/main_menu.tscn")

main_menu.tscn
  _ready()
    ├─ Game.state = MENU ; get_tree().paused = false
    └─ si Save.has_save() → habilita y enfoca "Continuar"; si no, "Nueva partida"

  "Nueva partida" ──► Save.delete_save()  +  Game.start_run()
  "Continuar"     ──► Game.continue_run()
  "Opciones"      ──► instancia settings_menu como HIJO, se oculta él
  "Salir"         ──► Game.quit_game()
```

`Game.start_run()` limpia todo (`mood = 50`, `current_day = 0`, `history = []`,
`days_passed = 0`), pone `state = INTRO` y cambia a `main.tscn`.

---

# 4. `Game`: el estado global

`scripts/autoload/game_manager.gd`. Es lo único que sabe "en qué día estamos" y "cuánto ánimo
hay". Todo lo demás le pregunta.

## 4.1 El enum de estados

```gdscript
enum State {
	BOOT,        ## arranque, antes de todo
	MENU,        ## en el menú principal
	INTRO,       ## se muestra la desgracia del día
	DIALOGUE,    ## Loretta elige entre las 3 opciones
	DAY_RESULT,  ## resumen del día (superado / se acumula la tristeza)
	PAUSED,
	ENDING,      ## pantalla de final de semana
}
```

## 4.2 Variables de estado

| Variable | Qué es |
|---|---|
| `days` | el guion ya cargado (`DialogueDB`) |
| `mood` | ánimo actual, 0..100 |
| `current_day` | 0 = Lunes … 6 = Domingo |
| `current_turn` | 0 o 1 |
| `history` | ánimo al cierre de cada día jugado. **Su promedio decide el final** |
| `days_passed` | cuántos días llegaron al umbral |
| `ending_id` | `ending_bright` / `ending_bittersweet` / `ending_gloomy` |
| `state` | el enum de arriba |
| `run_time` | segundos jugados (se guarda como `play_time_seconds`) |
| `_state_before_pause` | a qué estado volver al reanudar |

## 4.3 Constantes

```gdscript
const DAY_COUNT := 7
const TURNS_PER_DAY := 2
const MOOD_MIN := 0
const MOOD_MAX := 100
const MOOD_START := 50
const PENALTY_GROWTH := 0.12   # cuánto CRECE el daño por día jugado
const REWARD_DECAY := 0.06     # cuánto se DESGASTA lo bueno por día jugado
const ENDING_BRIGHT_MIN := 70.0
const ENDING_NEUTRAL_MIN := 40.0
```

## 4.4 La máquina de estados, en orden

```
start_run() ──► start_day(i) ──► begin_dialog() ──► choose_option(n) ──► apply_mood(delta)
                    ▲                  │                  │                    │
                    │                  │                  └── advance_turn() ───┘
                    │                  │                          │
                    │                  │                  (último turno)
                    │                  │                          ▼
                    │                  └──────────────────── finish_day()
                    │                                             │
                    └──────────── next_day() ◄────────────────────┘
                                      │
                              (después del domingo)
                                      ▼
                                finish_week() ──► ending.tscn
```

**Fórmulas clave:**

```gdscript
# La dificultad: más avanzada la semana, lo malo pega más y lo bueno rinde menos
func difficulty_scale(delta):
    if delta < 0: return roundi(delta * (1.0 + 0.12 * current_day))
    return roundi(delta * (1.0 - 0.06 * current_day))

# El final
func _evaluate_ending():
    var avg = average_mood()          # promedio de history; si está vacío, mood
    if avg >= 70.0: return &"ending_bright"
    if avg >= 40.0: return &"ending_bittersweet"
    return &"ending_gloomy"
```

`difficulty_scale` usa `current_day`, así que el Lunes no tiene castigo y el Domingo es el más
duro. Es la razón de que, con **las mismas buenas elecciones**, se cierre en ~69 el lunes y en
~60 el domingo.

---

# 5. `Events`: el cableado

`scripts/autoload/event_bus.gd`. Nadie conecta escenas entre sí; todos se cuelgan de acá. Esta
es la lista real y quién las usa:

| Señal | Quién la emite | Quién la escucha |
|---|---|---|
| `game_started` | `Game.start_run()` / `continue_run()` | (nadie hoy — **punto libre**) |
| `game_returned_to_menu` | `Game.go_to_menu()` | (nadie hoy — **punto libre**) |
| `game_paused` / `game_resumed` | `Game.pause_game()` / `resume_game()` | `Main` → muestra/oculta `PauseMenu` |
| `day_started(day_index, title)` | `Game.start_day()` | `Main` (carga la escena del día) y `HUD` (pinta el día) |
| `dialogue_turn_started(day, turn)` | `Game.begin_dialog()` / `advance_turn()` | `DialogueBox` (pinta el turno) y `DayScene` (esconde la IntroCard) |
| `option_chosen(i, kind, delta)` | `Game.choose_option()` | (nadie hoy — ideal para SFX/reacciones) |
| `mood_changed(new_mood, delta)` | `Game.apply_mood()` | `HUD` (mueve la barra) |
| `day_finished(day, passed)` | `Game.finish_day()` | `DialogueBox` (panel de resultado) |
| `week_finished(ending_id)` | `Game.finish_week()` | (nadie hoy — `finish_week()` ya cambia de escena) |
| `sfx_requested(sfx_id, position)` | cualquiera | `Audio` → `play_sfx()` |

Además, `Game` declara por su cuenta **`signal state_changed(new_state)`**
(`game_manager.gd:55`, emitida por el setter de `state` en la línea 62). Hoy nadie la escucha:
es un punto libre para reaccionar a cambios de estado.

**Para agregar una señal propia:** declarala en `event_bus.gd`, emitila desde donde corresponda,
y conectala en el consumidor. Las señales nunca llevan lógica, solo el dato.
`Events.clear_all()` desconecta todas automáticamente (recorre `get_script_signal_list()`), así
que no hay ninguna lista que mantener a mano.

---

# 6. El guion: `days.json` + `DialogueDB`

**Todo el texto vive en `assets/data/days.json`**: es la única fuente de verdad.

```json
{
  "version": 1,
  "days": [
    {
      "day": 1,
      "title": "Lunes",
      "start_mood": 50,
      "pass_threshold": 50,
      "richard_intro": "El colectivo se incendió. Richard llegó tarde y con olor a humo.",
      "turns": [
        {
          "prompt": "Richard vuelca el café sobre su camisa blanca.",
          "options": [
            { "text": "«¿Eso es café o una declaración de guerra?»", "kind": "choke",    "mood": -12 },
            { "text": "«Tranquilo, a todos nos pasa.»",             "kind": "motivate", "mood":  10 },
            { "text": "«...psssst.»",                              "kind": "sound",    "mood":  -2 }
          ]
        }
      ]
    }
  ]
}
```

| Clave | Qué es |
|---|---|
| `day` | Número 1..7 |
| `title` | Día de la semana ("Lunes"…) |
| `start_mood` | Ánimo al que arranca el día |
| `pass_threshold` | Ánimo mínimo al cierre para "Día superado" |
| `richard_intro` | La desgracia del día (la IntroCard) |
| `turns[]` | 2 turnos, cada uno con `prompt` y `options[]` |
| `options[]` | 3 opciones, cada una con `text`, `kind` (`choke`/`motivate`/`sound`) y `mood` |

El `mood` del JSON es el valor **base**: `Game.difficulty_scale()` lo reescala según el día
jugado.

## 6.1 `DialogueDB` (`scripts/resources/dialogue_db.gd`)

Carga y **valida** el archivo:

- `DATA_PATH = "res://assets/data/days.json"`
- `EXPECTED_DAYS = 7`, `EXPECTED_TURNS = 2`, `EXPECTED_OPTIONS = 3`
- `VALID_KINDS = [&"choke", &"motivate", &"sound"]` — cada turno debe tener **exactamente uno
  de cada**, sin repetir
- Los accesos **nunca devuelven `null`**: si pedís un día/turno/opción inexistente te da `{}`
- Si el archivo falta o el JSON está roto → base vacía + `push_error`. Si está legible pero mal
  formado → **avisa y sigue andando** (filosofía de jam: degradar, no reventar el arranque)

Se accede siempre por `Game.days`:

```gdscript
Game.days.day_count()          # 7
Game.days.get_day(0)           # { day, title, start_mood, pass_threshold, richard_intro, turns }
Game.days.get_turn(0, 1)       # { prompt, options }
Game.days.option_at(0, 1, 2)   # { text, kind, mood }
```

---

# 7. Las escenas, una por una

| Escena | `layer` | Rol | Nodos que el código toca (`%Nombre`) |
|---|---|---|---|
| `boot/boot.tscn` | — | splash + precarga + salto al menú | `%StatusLabel` |
| `ui/main_menu.tscn` | — | menú principal | `%NewGameButton`, `%ContinueButton`, `%SettingsButton`, `%QuitButton` |
| `main.tscn` | — | **host persistente** | `%LevelHost`, `%HUD`, `%DialogueBox`, `%PauseMenu` |
| `levels/day_01..07.tscn` | `UI` = 0 | la tarjeta de contexto del día | `%IntroCard`, `%DayTitleLabel`, `%IntroLabel`, `%ContinueButton` |
| `ui/dialogue_box.tscn` | **5** | prompt + 3 opciones + resultado | `%DialoguePanel`, `%PromptLabel`, `%OptionsContainer`, `%FeedbackLabel`, `%DayResultPanel`, `%ResultLabel`, `%ResultButton` |
| `ui/hud.tscn` | **1** (default) | día + barra de ánimo | `%DayLabel`, `%MoodValueLabel`, `%MoodBar` |
| `ui/pause_menu.tscn` | **10** | pausa | `%ResumeButton`, `%RestartButton`, `%MenuButton` |
| `ui/settings_menu.tscn` | **20** | opciones | `%MasterSlider`, `%MusicSlider`, `%SfxSlider`, `%FullscreenCheck`, `%ValuesLabel`, `%BackButton` |
| `ui/ending.tscn` | — | final de semana | `%TitleLabel`, `%DaysLabel`, `%AverageLabel`, `%RetryButton`, `%MenuButton` |

**El orden de capas importa:** HUD (1) ↦ DialogueBox (5) ↦ PauseMenu (10) ↦ Settings (20).

> **Nota sobre el `UI` CanvasLayer de los días:** en Godot, un `Control` colgado directamente de
> un `Node2D` se mide contra un rectángulo de 0×0 y queda invisible o mal centrado. Por eso los
> días son `Node2D` → `CanvasLayer` llamado `UI` → Controls. **Si agregás UI a un día, metela
> adentro de `UI`.**

---

# 8. Un día completo, paso a paso

El recorrido real, con quién llama a quién. Es la mejor referencia para saber dónde engancharte:

```
Game.start_day(2)
  ├─ lee days.get_day(2); si está vacío → push_error y no hace nada
  ├─ current_day = 2 ; current_turn = 0 ; mood = clamp(start_mood) ; state = INTRO
  └─ Events.day_started.emit(2, "Miércoles")
        ├─► Main.load_day(2)      →  carga res://scenes/levels/day_03.tscn dentro de LevelHost
        │                             (libera el día anterior, espera 1 frame)
        └─► HUD._on_day_started   →  "Día 3/7 · Miércoles" + repinta la barra

DayScene._ready()
  ├─ Game.days.get_day(day_index) → pinta título + richard_intro en %IntroCard
  ├─ %ContinueButton.pressed ──► Game.begin_dialog()
  └─ Events.dialogue_turn_started.connect(...)  →  esconde la IntroCard

Game.begin_dialog()   (solo si state == INTRO)
  ├─ state = DIALOGUE
  └─ Events.dialogue_turn_started.emit(2, 0)
        └─► DialogueBox._show_turn → prompt + 3 botones (texto de Game.option_at)

El jugador toca un botón
  └─► DialogueBox._on_option_pressed(i)
        ├─ deshabilita los botones   (evita el doble clic que se come 2 opciones)
        ├─ delta = Game.choose_option(i)
        │     ├─ delta = difficulty_scale(option.mood)
        │     ├─ apply_mood(delta) ──► Events.mood_changed ──► HUD mueve la barra
        │     └─ Events.option_chosen.emit(i, kind, delta)
        ├─ pinta %FeedbackLabel ("+9 🙂")
        └─ Game.advance_turn()   →  turno 1, o finish_day()

Game.finish_day()
  ├─ passed = mood >= pass_threshold del día
  ├─ history.append(mood) ; if passed: days_passed += 1
  ├─ state = DAY_RESULT ; save_progress()      ← ACÁ SE GUARDA
  └─ Events.day_finished.emit(current_day, passed)
        └─► DialogueBox._show_result → "Día superado" / "Se acumula la tristeza" + botón "Seguir"

"Seguir" ──► DialogueBox._on_result_pressed ──► Game.next_day()
                                                  ├─ día siguiente: start_day(current_day + 1)
                                                  └─ era domingo: finish_week() ──► ending.tscn
```

---

# 9. Pausa y guardado

## 9.1 Pausa

`Game` tiene `process_mode = ALWAYS` y es el **único** que lee la acción `pause`:

```gdscript
Game.toggle_pause()   # PAUSED ⇄ el estado anterior
Game.pause_game()     # guarda _state_before_pause, state = PAUSED, get_tree().paused = true
Game.resume_game()    # get_tree().paused = false, vuelve al estado anterior
```

Solo se puede pausar en `INTRO`, `DIALOGUE` o `DAY_RESULT` (lo decide `_can_pause()`).
`PauseMenu` y `SettingsMenu` se ponen `PROCESS_MODE_ALWAYS` **por código** para poder responder
con el árbol pausado.

## 9.2 Guardado

Un solo slot: `user://savegame.json`.

```gdscript
Game.save_progress()   # Game → GameData.to_dict() → Save.save_game()   (en finish_day y finish_week)
Game.load_progress()   # Save.load_game() → GameData.from_dict() → Game
Game.continue_run()    # load_progress() y saltar al día history.size()
```

`GameData.from_dict()` castea todo a mano, así que **un guardado viejo, incompleto o corrupto no
rompe el arranque**: cae en los valores por defecto.

> **Matiz importante:** al retomar, `Game.mood` queda en el `start_mood` del día (50), no en el
> ánimo guardado. Es **a propósito**: cada día arranca con la barra llena, y lo que realmente
> viaja entre días es `history`. Lo que se restaura es `current_day`, `history` y `days_passed`.

---

# 10. Cómo probar

```gdscript
// 1. Levantás el juego
project_run            →  tiene que decir  status: "live", ready: true

// 2. Inspeccionás desde adentro del proceso
editor_manage op="game_eval"  params={"code": "return Game.mood"}
   ⚠️ SIEMPRE con return, o te devuelve null y creés que falló
   ⚠️ Tiene presupuesto de ~8 s: una semana entera NO entra en un solo eval

// 3. Leés la consola del juego (no la del editor, que acumula basura vieja)
logs_read  source="game"
```

Estados útiles para mirar: `Game.state`, `Game.current_day`, `Game.current_turn`, `Game.mood`,
`Game.history`, `Game.days.day_count()`.

**Si el eval se cuelga:** un aborto puede dejar el juego congelado y el siguiente llamado falla
con `EVAL_GAME_NOT_READY`. Se recupera con `project_manage op="stop"` y después `project_run`.

---

# 11. Trampas que te van a morder

1. **Lienzo de 1920×1080, layout apretado.** Presupuesto real (medido en el juego): el HUD ocupa
   `0..262`, la tarjeta del día `288..732` (alto **fijo**) y el panel de diálogo `450..1080`.
   Tarjeta y panel se solapan a propósito y nunca se ven juntos (la tarjeta se esconde al empezar
   el diálogo). Si metés algo nuevo, respetá esas franjas o vas a superponer.
2. **`%Nombre` solo funciona si el nodo tiene `unique_name_in_owner`.** Si agregás un nodo que tu
   código necesita, marcalo en el editor o usá `$Path`.
3. **Nunca `class_name` que choque con un autoload** (`Game`, `Events`, `Audio`, `Save`,
   `Settings`, `SceneLoader`) ni con un miembro de `Game.State`. Ya rompió el arranque una vez con
   `State`.
4. **No renombres `.tscn` o `.gd` a mano:** las escenas referencian scripts por path y hay UIDs.
   Usá el editor.
5. **Controls dentro de un día, siempre adentro del `CanvasLayer` `UI`.**
6. **Autoloads y orden.** Si agregás uno, va en `project.godot` y el orden es orden de carga.
   **Los autoloads solo se registran al arrancar el editor** → si tocás eso, reiniciá el editor.
7. **`project.godot` tiene cosas intocables:** el autoload `_mcp_game_helper` y la sección
   `[editor_plugins]` (si los borrás, se muere el puente MCP con el asistente). Tampoco saques
   Jolt / `d3d12` / `gl_compatibility`.
8. **Renderer GL Compatibility:** nada de Forward+ ni features 3D-only.
9. **`get_tree().paused`:** cualquier nodo que tenga que funcionar en pausa necesita
   `process_mode = Node.PROCESS_MODE_ALWAYS`.
10. **Nada de `score` / `PLAYING` / `health_changed`:** eso era el prototipo de combate y se borró
    por completo. Si lo ves en un tutorial, no aplica a este proyecto.
11. **`DialogueDB` exige "uno de cada kind, sin repetir".** Si agregás opciones o tipos, leé la
    receta C2: hay que ajustar la validación o el log te va a llenar de errores.

---

# 12. Recetario: "quiero cambiar X" → toco Y

> **Cómo leer esto.** Los números de línea son los de hoy. Si movés algo arriba, cambian: por eso
> cada receta incluye el **ancla** (el texto exacto). Buscá el ancla con `Ctrl+F` (o `Ctrl+Shift+F`
> para buscar en todo el proyecto) y siempre caés en el lugar correcto.

## 12.0 Distinguí dos clases de constante

| Constante | Archivo:línea | ¿Hace qué? |
|---|---|---|
| `TURNS_PER_DAY` | `game_manager.gd:37` | **Comportamiento** (cuántos turnos se juegan) |
| `EXPECTED_TURNS` | `dialogue_db.gd:29` | Solo validación (si no coincide, te loguea error) |
| Botones dentro del contenedor | `dialogue_box.tscn:38-48` | **Comportamiento** (cuántas opciones ves) |
| `EXPECTED_OPTIONS` | `dialogue_db.gd:30` | Solo validación |
| `DAY_COUNT` | `game_manager.gd:35` | **Comportamiento** |
| `EXPECTED_DAYS` | `dialogue_db.gd:28` | Solo validación |

Tocar solo las de validación **no cambia el juego**: solo hace que el log te avise bien.

---

## A. Texto y contenido

### A1. Cambiar cualquier frase, prompt o intro → `assets/data/days.json`

**Cada día ocupa exactamente 25 líneas.** El día N empieza en la línea `5 + 25 × (N − 1)`:

| Día | Bloque (`{`) | `title` | `start_mood` | `pass_threshold` | `richard_intro` | `prompt` turno 1 | opciones turno 1 | `prompt` turno 2 | opciones turno 2 |
|---|---|---|---|---|---|---|---|---|---|
| 1 Lunes | 4 | 6 | 7 | 8 | 9 | 12 | **14-16** | 20 | **22-24** |
| 2 Martes | 29 | 31 | 32 | 33 | 34 | 37 | **39-41** | 45 | **47-49** |
| 3 Miércoles | 54 | 56 | 57 | 58 | 59 | 62 | **64-66** | 70 | **72-74** |
| 4 Jueves | 79 | 81 | 82 | 83 | 84 | 87 | **89-91** | 95 | **97-99** |
| 5 Viernes | 104 | 106 | 107 | 108 | 109 | 112 | **114-116** | 120 | **122-124** |
| 6 Sábado | 129 | 131 | 132 | 133 | 134 | 137 | **139-141** | 145 | **147-149** |
| 7 Domingo | 154 | 156 | 157 | 158 | 159 | 162 | **164-166** | 170 | **172-174** |

- **Cambiar una frase** → pisá la línea. La forma de una opción es
  `{ "text": "«Tu frase.»", "kind": "choke", "mood": -12 }`
- **Cambiar cuánto mueve el ánimo** → el número de `"mood"` (es el valor *base*; el juego lo
  reescala por día, ver B2)
- **Cambiar la intro del día** → `richard_intro`
- **Cambiar el umbral de "Día superado"** → `pass_threshold`
- **Cambiar con qué barra arranca el día** → `start_mood`
- **Cambiar el nombre del día** → `title` (solo texto; el día real lo manda `day_index` en la
  escena)

### A2. Textos de UI que no viven en el JSON

| Qué | Archivo:línea | Texto actual |
|---|---|---|
| Título del menú | `scenes/ui/main_menu.tscn:39` | `text = "Repite Conmigo"` |
| Subtítulo | `scenes/ui/main_menu.tscn:44` | `text = "Siete días para levantarle el ánimo."` |
| Botones del menú | `main_menu.tscn:56, 62, 68, 74` | Nueva partida / Continuar / Opciones / Salir |
| Botón de la intro de cada día | `scenes/levels/day_01.tscn:60` … `day_07.tscn` | `text = "Continuar"` |
| Resultado del día | `scenes/ui/dialogue_box.gd:97` | `"Día superado"` / `"Se acumula la tristeza"` |
| Botón del resultado | `scenes/ui/dialogue_box.tscn:83` | `text = "Seguir"` |
| Formato del feedback | `scenes/ui/dialogue_box.gd:87` | `"%s  %s" % [delta, emoji]` |
| Cómo se escribe el delta | `scenes/ui/dialogue_box.gd:118-123` | `_format_delta()` (`+10`, `−12`, `0`) |
| Emoji por tipo | `scenes/ui/dialogue_box.gd:13-17` | `FEEDBACK_EMOJI` |
| Título de cada final | `scenes/ui/ending.gd:11-15` | `const TITLES` |
| "Días superados / Ánimo promedio" | `scenes/ui/ending.gd:29-30` | los dos `text =` |
| HUD: día y ánimo | `scenes/ui/hud.gd:36` y `:41` | `"Día %d/%d · %s"`, `"Ánimo: %d/%d"` |
| Menú de pausa | `pause_menu.tscn:49, 55, 61` | Continuar / Reiniciar / Volver al menú |

> Los `text =` que ves en los `.tscn` del HUD y del final son **valores de diseño** (placeholder
> del editor): el código los pisa en `_ready()`. Cambiá el `.gd`, no el `.tscn`.

### A3. Cambiar el tamaño de **toda** la tipografía → `resources/themes/main_theme.tres:4`

```
default_font_size = 54
```

Esa línea es el tamaño base de **todos** los `Label` y `Button` que no tengan un
`theme_override_font_sizes/font_size` propio: es la palanca más rápida del proyecto. Bajala y todo
el juego achica el texto de una.

- Las fuentes **por escena** están en los `.tscn` como `theme_override_font_sizes/font_size = N`.
  Los que hoy tienen valor propio: título del menú y del final (`96`), título del día (`60`),
  "Pausa" y "Opciones" (`72`), resultado del día (`66`), línea de valores de Opciones (`42`) y el
  splash de arranque (`84`).
- **Ojo con la proporción:** el lienzo es 1920×1080 y se muestra escalado a la ventana
  (hoy 1280×720, o sea ×0,667). Un `54` se ve a ~36 px reales.

---

## B. Balance y reglas

### B1. Cuándo sale cada final → `scripts/autoload/game_manager.gd:48-49`

```gdscript
48: const ENDING_BRIGHT_MIN := 70.0
49: const ENDING_NEUTRAL_MIN := 40.0
```

Los usan las líneas **283** y **285** de `_evaluate_ending()` (281-287). El orden importa: se
evalúa primero el ≥70 y después el ≥40.

> ⚠️ No confundir con `pass_threshold` del JSON: eso es solo "Día superado" (el cartel del día).
> El final sale del **promedio de `history`**.

### B2. La curva de dificultad → `game_manager.gd:43` y `:45`

```gdscript
43: const PENALTY_GROWTH := 0.12
45: const REWARD_DECAY := 0.06
```

Se aplican en `difficulty_scale()`, líneas **263-268**:

```gdscript
263: func difficulty_scale(delta: int) -> int:
264: 	if delta < 0:
265: 		return roundi(delta * (1.0 + PENALTY_GROWTH * current_day))
266: 	if delta > 0:
267: 		return roundi(delta * (1.0 - REWARD_DECAY * current_day))
268: 	return 0
```

- Dificultad **plana** → dejá las dos en `0.0`
- Que lo bueno **también** crezca → `REWARD_DECAY` en negativo
- Curva no lineal → reescribí las líneas 265 y 267 (tenés `current_day` a mano)

### B3. Rango del ánimo → `game_manager.gd:38-40`

```gdscript
38: const MOOD_MIN := 0
39: const MOOD_MAX := 100
40: const MOOD_START := 50
```

- `MOOD_MIN/MAX` se usan en el `clampi()` de `apply_mood()` (línea **213**) y de `start_day()`
  (línea **169**)
- `MOOD_START` es además el *fallback* de `start_day()` (**169**) y de `finish_day()` (**230**)
- Si lo cambiás, actualizá el default del guardado: `scripts/resources/game_data.gd:17` →
  `@export var mood: int = 50`
- La barra toma su rango del `.tscn`: `scenes/ui/hud.tscn` (nodo `%MoodBar`, `max_value`)

### B4. Qué cuenta cada "Día superado" → `game_manager.gd:228-240`

```gdscript
230: 	var threshold := int(data.get("pass_threshold", MOOD_START))
231: 	var passed := mood >= threshold
```

Si querés rachas, bonus por días seguidos, etc., acá es donde se cambia la lógica.

---

## C. Estructura: turnos, opciones, días, tipos

### C1. Pasar de 2 a 3 turnos por día

**Tres lugares:**

1. `game_manager.gd:37` → `const TURNS_PER_DAY := 2` a `3` ← **esto es lo que cambia el juego**
   (lo usa `advance_turn()`, línea **219**)
2. `dialogue_db.gd:29` → `const EXPECTED_TURNS := 2` a `3` ← solo para que no loguee error
3. `days.json`: agregar un tercer `{ "prompt": ..., "options": [ ...3... ] }` dentro del array
   `turns` de cada día. Los arrays son las líneas **10-27**, **35-52**, **60-77**, **85-102**,
   **110-127**, **135-152** y **160-177**

**No hay que tocar la UI**: `advance_turn()` cierra el día solo cuando se acaban los turnos.

### C2. Pasar de 3 a 4 opciones — hay una regla dura

`DialogueDB` valida **"exactamente uno de cada `kind`, sin repetir"**:

```gdscript
189: 		elif seen.has(kind):
190: 			push_error("DialogueDB: el %s repite el kind '%s'." % [where, kind])
...
194: 	for kind in VALID_KINDS:
195: 		if not seen.has(kind):
196: 			push_error("DialogueDB: al %s le falta la opción '%s'." % [where, kind])
```

Hay **dos caminos**:

**(a) 4º tipo nuevo (recomendado).** Tocá:

1. `dialogue_db.gd:33` → agregá `&"tuTipo"` a
   `const VALID_KINDS: Array[StringName] = [&"choke", &"motivate", &"sound"]`
2. `dialogue_db.gd:30` → `EXPECTED_OPTIONS := 3` a `4`
3. `dialogue_box.gd:13-17` → `FEEDBACK_EMOJI`: agregá la carita del tipo nuevo
4. `dialogue_box.tscn`: agregá un 4º botón dentro de `%OptionsContainer` (el contenedor es el
   nodo de la **línea 33**; los 3 botones son las líneas **38-48**). Insertá después de la 48:

   ```
   [node name="Option4" type="Button" parent="DialoguePanel/VBoxContainer/OptionsContainer"]
   layout_mode = 2
   text = "Opción 4"
   ```

   **Sin `unique_name_in_owner`**: el script arma la lista leyendo los hijos del contenedor
   (`dialogue_box.gd:36-41`)
5. `days.json`: la 4ª opción en los **14 turnos** (uno de cada tipo en cada turno, o falla la
   validación)

**(b) Repetir un tipo existente** (p. ej. dos "choke" distintos). Además de los puntos 2, 4 y 5
de arriba, tenés que **aflojar la validación**: borrar las líneas **189-191** (el chequeo de
repetidos) y **194-196** (el de "falta un kind") de `dialogue_db.gd`.

> `apply_mood` y `choose_option` no necesitan cambios: trabajan por índice.

### C3. Agregar un día (semana de 8)

1. `days.json`: copiá el bloque de 25 líneas del Lunes (**4-28**) y pegalo antes del `]` de la
   línea **180**, cambiando `"day"` y el contenido
2. `game_manager.gd:35` → `const DAY_COUNT := 7` a `8`
3. `dialogue_db.gd:28` → `const EXPECTED_DAYS := 7` a `8`
4. `scenes/levels/day_08.tscn`: copiá `day_01.tscn`. Adentro, la línea **5** es
   `[node name="Day01" type="Node2D"]` → `Day08`, y la línea **7** `day_index = 0` → `7`
5. *(Opcional)* `scenes/boot/boot.gd:10-15` → `PRELOAD_SCENES`: agregá
   `"res://scenes/levels/day_08.tscn"`

**Lo demás se adapta solo:** `main.gd:31` arma el nombre con `%02d` (`day_%02d.tscn`), y el HUD
(`hud.gd:36`) y el final (`ending.gd:29`) usan `Game.DAY_COUNT`.

### C4. Quitar un día (semana de 6)

Al revés: `DAY_COUNT` a 6, `EXPECTED_DAYS` a 6, y **borrá el último bloque** del JSON (o el que
quieras, pero reordená `"day"`). El `day_07.tscn` podés dejarlo (nadie lo carga) o borrarlo.

### C5. Agregar un tipo de respuesta nuevo

1. `dialogue_db.gd:33` → `VALID_KINDS`
2. `dialogue_box.gd:13-17` → `FEEDBACK_EMOJI`
3. `days.json` → la opción con ese `kind` (recordá la regla de C2: si sumás un tipo, **todos** los
   turnos necesitan una opción de ese tipo)

Opcional: el `kind` viaja dentro de `option_chosen`, así que cualquier listener puede reaccionar
distinto según el tipo.

---

## D. Los finales

### D1. Cambiar los textos → `scenes/ui/ending.gd:11-15`

```gdscript
11: const TITLES := {
12: 	&"ending_bright": "Una semana distinta",
13: 	&"ending_bittersweet": "Se sostuvo, a duras penas",
14: 	&"ending_gloomy": "La tristeza se acumuló",
15: }
```

### D2. Agregar un 4º final

Cuatro puntos, todos con el mismo `id`:

1. `game_manager.gd:48-49` → agregá un corte nuevo, p. ej.
   `const ENDING_PERFECT_MIN := 90.0`
2. `game_manager.gd:281-287` → agregá la rama **arriba** de las otras (el orden de los `if`
   importa):

   ```gdscript
   if average >= ENDING_PERFECT_MIN:
       return &"ending_perfect"
   ```

3. `ending.gd:11-15` → agregá `&"ending_perfect": "Tu título"`
4. *(Opcional)* `ending.gd:28` ya usa `TITLES.get(Game.ending_id, "Fin de la semana")`, así que si
   te olvidás del punto 3 cae en el texto genérico en vez de crashear

Si querés **imagen, color o música distinta por final**: `ending.gd:24-34` (`_ready()`), donde ya
se leen `Game.ending_id`, `Game.days_passed` y `Game.average_mood()`.

---

## E. UI

### E1. Cambiar el HUD → `scenes/ui/hud.gd`

```gdscript
35: func _refresh_day(day_index: int, title: String) -> void:
36: 	_day_label.text = "Día %d/%d · %s" % [day_index + 1, Game.DAY_COUNT, title]
...
39: func _refresh_mood(new_mood: int) -> void:
40: 	_mood_bar.value = new_mood
41: 	_mood_label.text = "Ánimo: %d/%d" % [new_mood, Game.MOOD_MAX]
```

- Los nodos salen de `scenes/ui/hud.tscn` (`%DayLabel`, `%MoodValueLabel`, `%MoodBar`)
- Si agregás un dato nuevo al HUD, sumá la conexión en `hud.gd:17-18` (ahí se conectan
  `mood_changed` y `day_started`)
- **Trampa:** `_on_day_started` (líneas **27-32**) repinta el ánimo a mano porque `start_day()`
  cambia `mood` **sin** emitir `mood_changed`. No pierdas la línea **32** o la barra amanece con
  el valor de ayer

### E2. Cambiar el orden de las capas superpuestas

| Overlay | Archivo:línea |
|---|---|
| HUD | `scenes/ui/hud.tscn` — sin `layer` (default = 1) |
| Caja de diálogo | `scenes/ui/dialogue_box.tscn:7` → `layer = 5` |
| Menú de pausa | `scenes/ui/pause_menu.tscn:6` → `layer = 10` |
| Menú de opciones | `scenes/ui/settings_menu.tscn:6` → `layer = 20` |
| UI de un día | `scenes/levels/day_XX.tscn:10` → `layer = 0` (dentro del `CanvasLayer` `UI`) |

### E3. Mover/redimensionar el panel de diálogo

`scenes/ui/dialogue_box.tscn`, líneas **15-17** (offsets del `%DialoguePanel`, anclado abajo):

```
15: offset_left = 48.0
16: offset_top = -630.0    ← alto del panel (arranca en y = 450)
17: offset_right = -48.0
```

Panel de resultado: líneas **59-62** del mismo archivo (`180 / 216 / -180 / -216`).

### E4. Mover/redimensionar la tarjeta del día

`scenes/levels/day_XX.tscn` (los 7 archivos), líneas **29-32** del `%IntroCard`:

```
29: offset_left = 72.0
30: offset_top = 288.0       ← ojo: es alto FIJO, no "hug content"
31: offset_right = -72.0
32: offset_bottom = 732.0
```

> **Trampa real que ya nos mordió:** acá el alto es fijo **a propósito**. Si lo dejás crecer con el
> contenido, a 1920×1080 se come el panel de diálogo.

---

## F. Audio y ajustes

### F1. Música y SFX → `scripts/autoload/audio_manager.gd`

```gdscript
60: func register_sfx(id: StringName, stream: AudioStream) -> void:
64: func register_music(id: StringName, stream: AudioStream) -> void:
69: func play_sfx(id: StringName, world_position: Variant = null) -> void:
93: func play_music(id: StringName, fade_time: float = MUSIC_FADE_TIME) -> void:
```

**Dónde registrar:** `scenes/boot/boot.gd`, dentro de `_ready()` (líneas **23-35**) o en
`_preload_all()`:

```gdscript
Audio.register_music(&"tema", preload("res://assets/audio/music/tema.ogg"))
Audio.register_sfx(&"click", preload("res://assets/audio/sfx/click.ogg"))
```

**Dónde disparar:**

- directo: `Audio.play_music(&"tema")`, `Audio.play_sfx(&"click")`
- **desacoplado** (recomendado desde cualquier escena):
  `Events.sfx_requested.emit(&"click", Vector2.ZERO)`. El receptor ya existe:
  `audio_manager.gd:48` conecta → `_on_sfx_requested` (línea **131**)

**El volumen ya está cableado**: los sliders de Ajustes escriben en los buses `Music`/`SFX`
(`settings_manager.gd:53-55`), y los reproductores ya están en esos buses
(`audio_manager.gd:40` para SFX, **:45** para música). No hace falta tocar nada.

Pedir un id sin registrar avisa con `push_warning` en vez de quedarse en silencio.

### F2. Agregar una opción al menú de Ajustes

El propio archivo lo explica en `settings_manager.gd:6-7`. Son **cinco lugares**:

| Paso | Archivo:línea | Qué agregar |
|---|---|---|
| 1. Variable con default | `settings_manager.gd:16-20` | `var idioma: String = "es"` (ya existe, es el ejemplo) |
| 2. Cargar | `settings_manager.gd:32-36` | `idioma = str(config.get_value("game", "language", idioma))` |
| 3. Guardar | `settings_manager.gd:41-45` | `config.set_value("game", "language", idioma)` |
| 4. Aplicar | `settings_manager.gd:52-56` | solo si toca audio/pantalla |
| 5. Setter público | `settings_manager.gd:77-88` o `:91-94` | tu setter, terminando con `save_settings()` |

Después: el control en `scenes/ui/settings_menu.tscn` (con `unique_name_in_owner = true`), y
conectalo en `settings_menu.gd` — los `@onready` van en las líneas **13-18** y las conexiones en
**21-35**, siguiendo el patrón de `_on_master_changed` (línea **38**).

### F3. Ruta del guardado → `scripts/autoload/save_manager.gd:12`

```gdscript
12: const SAVE_PATH := "user://savegame.json"
```

**⚠️ Si agregás un dato a la partida tenés que tocar CUATRO lugares** o se pierde al recargar:

1. `scripts/resources/game_data.gd:17-22` → el `@export var`
2. `game_data.gd:25-32` → `to_dict()`
3. `game_data.gd:35-48` → `from_dict()`
4. `game_manager.gd:293-301` (`save_progress`) y `:306-315` (`load_progress`) → volcarlo desde/hacia `Game`

El guardado ocurre en `game_manager.gd:238` (al cerrar cada día) y `:255` (al cerrar la semana).

---

## G. Extender con código nuevo

### G1. Reaccionar a cada elección (sonido, partículas, temblor)

Hoy `option_chosen` **no lo escucha nadie**: es un punto libre.

- Declarada en `scripts/autoload/event_bus.gd:31`
- Emitida en `game_manager.gd:202` con `(índice, kind, delta)` — el delta **ya viene escalado**
- Conectar desde el `_ready()` de tu nodo:

  ```gdscript
  Events.option_chosen.connect(_on_option_chosen)
  ```

Con un solo listener podés, por ejemplo, hacer `Events.sfx_requested.emit(&"click")` según el
`kind`.

### G2. Agregar una señal nueva

1. Declarala en `scripts/autoload/event_bus.gd`, en la sección que le corresponda (**líneas 17-40**)
2. Emitila desde `Game` o desde donde tenga sentido
3. Conectala en el consumidor

`Events.clear_all()` (línea **46**) la incluye automáticamente: recorre
`get_script_signal_list()`, así que no hay lista que mantener.

### G3. Una pantalla nueva

1. `.tscn` + su `.gd` al lado (sin `class_name` que choque con los autoloads)
2. Constante de path junto a las otras: `game_manager.gd:51-53`
3. Entrar: `SceneLoader.change_scene("res://tu/escena.tscn")`; volver: `Game.go_to_menu()`
4. Si es **overlay**: `CanvasLayer` con `layer` arriba del que deba tapar (ver E2)
5. Si debe andar **en pausa**: `process_mode = Node.PROCESS_MODE_ALWAYS` (mirá `pause_menu.gd:13`)

### G4. Reaccionar a la pausa

`game_paused` / `game_resumed` los emite `Game` (líneas **338** y **346**) y los escucha `Main`
(`main.gd:20-21`) para mostrar el `PauseMenu`. Si querés que **vos** también reacciones, sumá tus
conexiones al lado de esas.

---

## H. Config del proyecto (`project.godot`)

| Qué | Línea | Valor actual |
|---|---|---|
| Nombre del juego | `13` | `config/name="Repite Conmigo"` |
| Escena inicial | `14` | `run/main_scene="res://scenes/boot/boot.tscn"` |
| Ancho del viewport | `30` | `window/size/viewport_width=1920` |
| Alto del viewport | `31` | `window/size/viewport_height=1080` |
| Modo de ventana | `32` | `window/size/mode=2` |
| Tamaño de ventana (override) | `33-34` | `1280` × `720` |
| Stretch | `35-36` | `canvas_items` / `expand` |
| Acción `pause`: Escape | `61` | `"keycode": 4194305` |
| Acción `pause`: tecla P | `78` | `"keycode": 80` |
| Acción `pause`: botón joystick | `89` | `"button_index": 6` |
| Capas de render con nombre | `102-105` | world / actors / fx / ui |

- **Si cambiás `pause` de nombre**, cambialo también en `game_manager.gd:104`
- **El lienzo es 1920×1080** y todos los offsets y fuentes están escalados ×3 respecto del diseño
  original de 640×360. Si volvés a cambiar el viewport, hay que reescalar E3/E4 otra vez
- **La ventana se abre a `window_width/height_override`** (1280×720), no maximizada: el override
  gana sobre `mode`. Poné los dos en `0` si querés que se aplique de verdad el modo de ventana
- **Intocables:** `project.godot:20` (`_mcp_game_helper`) y `:38-40` (`[editor_plugins]`). Si los
  sacás, se muere el puente MCP con el asistente. Tampoco toques `:109` (Jolt), `:113` (`d3d12`)
  ni `:114-115` (`gl_compatibility`)

---

# 13. Verificación rápida por tipo de cambio

| Cambio | Cómo lo confirmás en 10 segundos |
|---|---|
| Texto / opciones | `game_eval` → `return Game.days.option_at(0,0,1).text` |
| Umbrales del final | `return Game.ENDING_BRIGHT_MIN` |
| Dificultad | `Game.current_day = 6` y después `return Game.difficulty_scale(-12)` |
| N° de turnos | `return Game.TURNS_PER_DAY` y `Game.days.get_day(0)["turns"].size()` |
| N° de opciones | `return (get_node("/root/Main/DialogueBox").get_node("%OptionsContainer") as Node).get_child_count()` |
| Días de la semana | `return Game.DAY_COUNT` y `Game.days.day_count()` |
| JSON bien formado | `return Game.days.day_count()` → si da 0, el JSON está roto (mirá los logs) |
| Guardado | `return Save.load_game()` |
| Tu señal nueva | Conectala y disparala a mano desde un `game_eval` |

Siempre, después de tocar algo: `project_run` debe dar `status: "live"` / `ready: true`, y
`logs_read source="game"` debe quedar en **0 errores / 0 warnings**.

**Truco general:** en Godot, `Ctrl+Shift+F` busca en todo el proyecto. Buscá el **nombre** de la
constante o la función (no la línea) y siempre caés en el lugar correcto.

---

# 14. Mapa de archivos

```
assets/
  data/days.json            Guion de la semana (7 días × 2 turnos × 3 opciones) ← acá va el texto
  art/, audio/              Vacías por ahora (.gitkeep)
docs/
  ARCHITECTURE.md           Este documento
  IMPLEMENTATION_PLAN.md    Orden de construcción del prototipo (13 pasos, todos cerrados)
  GDD.md                    Diseño: pitch, loop, mecánicas, finales
  TODO.md                   Pendientes y deuda técnica
  CREDITS.md                Equipo y assets de terceros (completar antes de entregar)
resources/themes/           main_theme.tres (fuente 18, tema global)
scenes/
  boot/boot.tscn            Main scene: splash + precarga + salto al menú
  main.tscn                 Host persistente: LevelHost + HUD + DialogueBox + PauseMenu
  main.gd                   Carga el día que pide day_started; muestra/oculta la pausa
  levels/day_scene.gd       Script compartido por los 7 días
  levels/day_01..07.tscn    Un día cada uno (Node2D → CanvasLayer "UI")
  ui/main_menu.tscn|gd      Menú principal
  ui/hud.tscn|gd            Día + barra de ánimo
  ui/dialogue_box.tscn|gd   Prompt, 3 opciones, feedback y resultado del día
  ui/pause_menu.tscn|gd     Pausa (Continuar / Reiniciar / Volver al menú)
  ui/settings_menu.tscn|gd  Volumen y pantalla completa
  ui/ending.tscn|gd         Final de semana (3 finales)
scripts/
  autoload/event_bus.gd         Events — señales globales, cero lógica
  autoload/settings_manager.gd  Settings — user://settings.cfg
  autoload/save_manager.gd      Save — user://savegame.json
  autoload/audio_manager.gd     Audio — SFX + música, buses Music/SFX
  autoload/scene_loader.gd      SceneLoader — cambio de escena con fundido
  autoload/game_manager.gd      Game — el estado de la semana (el archivo más importante)
  resources/dialogue_db.gd      DialogueDB — carga y valida days.json
  resources/game_data.gd        GameData — DTO de la partida guardada
```

Cada `.tscn` vive **al lado** de su `.gd`. `addons/` es de terceros: **no se toca**.

---

## Regla de convivencia del equipo

1. **El texto no se escribe en código.** Va en `days.json`.
2. **La UI no decide reglas.** Pregunta a `Game` y escucha a `Events`.
3. **El texto de UI no se hardcodea en dos lados.** Si un texto vive en `days.json`, ahí se edita.
4. **Antes de agregar un autoload, preguntá.** El proyecto deliberadamente tiene 6; sumar uno
   cambia el orden de carga y obliga a reiniciar el editor.
5. **Nunca commitees con errores en consola.** `logs_read source="game"` en 0/0 es el estándar.
