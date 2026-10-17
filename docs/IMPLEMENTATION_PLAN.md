# Plan de implementación — "Repite Conmigo" (MVP)

> **Documento de trabajo para el agente que construye.** Seguí los pasos **en orden**.
> Al terminar cada paso, marcá su checkbox. Si algo no coincide con lo que dice acá,
> **pará y preguntá** antes de improvisar.
>
> Estado: **pendiente de ejecución**. Ningún paso está hecho todavía.

---

## 0. Estado actual del repo (baseline real, verificado)

Esto es lo que hay hoy. Varias cosas contradicen la documentación vieja del repo.

| Cosa | Estado real |
|---|---|
| `scenes/levels/` | **Vacío** (0 entradas, ni un `.gitkeep`) |
| `README.md` | **0 bytes** (vacío) |
| `project.godot` → `config/name` | `"Game Jam"` |
| Juego actual | Esqueleto top-down con combate (player, enemigos, hurtbox/hitbox/health) |
| `main.tscn` | `Main` + `LevelHost` + `HUD` + `PauseMenu` |
| `scenes/main.gd` | Carga `res://scenes/levels/level_%02d.tscn` → **no existe ninguna** |
| `game_manager.gd` | `score`, `high_score`, `current_level`, `run_time`, `GRID`, `_on_player_died()` |
| `event_bus.gd` | Señales de combate (`player_died`, `health_changed`, `enemy_died`, …) |
| `hud.tscn` | `%ScoreLabel` + `%HealthLabel` |
| `scenes/ui/game_over.tscn` | Pantalla "Fin del juego" |
| Autoloads | 6, en orden: `Events`, `Settings`, `Save`, `Audio`, `SceneLoader`, `Game` |
| Addon | `addons/godot_ai` v4.3.0 — **no tocar** |
| `docs/ART.md` | Queda huérfano con este plan → se borra en el Paso 12 |

**Resultado esperado al terminar:** un prototipo jugable donde Loretta tiene 2 turnos de
3 opciones por día, durante 7 días (Lunes a Domingo), con una barra de ánimo de 0 a 100,
y 3 finales según el promedio semanal.

---

## 1. Contrato de ejecución (leer antes de escribir una línea)

### 1.1 Reglas duras del repo

1. **Serializá las llamadas MCP.** Nada de ráfagas en paralelo → `Port 8001 is occupied…`
   y `Timed out waiting for backend startup lock`. Una llamada, esperá, la siguiente.
2. **Si el juego está corriendo, no escribas escenas ni scripts** → falla con
   `EDITOR_NOT_READY`. Pará el juego primero.
3. **`game_eval` exige `return` explícito**, si no devuelve `null` y parece que falló.
4. **Leé siempre `logs_read source="game"`**. Nunca los logs del editor: guardan errores
   viejos para siempre y `logs_clear` no los limpia.
5. **No toques `addons/`** (es de terceros).
6. **Preservá en `project.godot`**: `_mcp_game_helper`, `[editor_plugins]`, Jolt,
   `d3d12`, `gl_compatibility`. **No agregues `stretch/scale_mode`** (`fractional` es el
   default; no falta, no lo "arregles").
7. **Convenciones**: cada `.tscn` junto a su `.gd`; los nodos que el código necesita van
   con `unique_name_in_owner` y se leen con `%Name` (nunca `$Path`); `snake_case` para
   archivos/carpetas; `class_name` en PascalCase; **ningún `class_name` que colisione con
   un autoload** (`Events`, `Settings`, `Save`, `Audio`, `SceneLoader`, `Game`) **ni con un
   miembro de `Game.State`**.
8. **Todo por `Events`** entre sistemas: el HUD y el diálogo tienen que sobrevivir a que
   el día se recargue. Nunca guardes referencias a nodos del nivel.
9. **No agregues autoloads nuevos.** Son 6 y el orden es orden de carga; agregar uno exige
   reiniciar el editor. `DialogueDB` se carga desde `Game._ready()`, no es autoload.
10. **`script_create` / `script_manage` puede tirar `Identifier not found: <Autoload>`
    falso** (validación en compilación aislada, sin globals de autoload). Ese mismo archivo
    corre bien en el juego. Confiá en ese diagnóstico **solo** para errores de sintaxis y
    resolución de `class_name`; no reescribas código que funciona.
11. **Entorno del shell (Windows/cmd)**: `powershell` **no está en el PATH** y el shell **no
    respeta comillas** en argumentos con espacios — `"C:\Users\LENOVO L560\..."` se rompe.
    Usá **rutas relativas sin espacios** (con `workdir`) o el nombre corto 8.3
    (`C:\Users\LENOVO~1\...`). `python` **sí** funciona (3.12) para validar JSON o scripts.

### 1.2 Contrato de interfaces (ambos lados deben cumplirlo)

**`Game` (autoload) — API pública que consumen los demás:**

```gdscript
var mood: int                # 0..100
var current_day: int         # 0..6
var current_turn: int        # 0..1
var history: Array[int]      # ánimo al cerrar cada día
var days_passed: int
var ending_id: StringName
var days: DialogueDB

func start_run() -> void
func restart_run() -> void
func go_to_menu() -> void
func start_day(index: int) -> void          # setea mood/turn, emite day_started
func begin_dialog() -> void                 # INTRO -> DIALOGUE, emite dialogue_turn_started(day, 0)
func current_turn_data() -> Dictionary
func option_at(i: int) -> Dictionary        # {text, kind, mood}
func choose_option(i: int) -> int           # aplica escala, emite option_chosen + mood_changed, devuelve delta efectivo
func advance_turn() -> void                 # turn++ o finish_day()
func finish_day() -> bool                   # registra history, emite day_finished, devuelve passed
func next_day() -> void                     # day++ -> start_day | finish_week
func finish_week() -> StringName            # promedio -> ending_id, emite week_finished, va a ending.tscn
func difficulty_scale(delta: int) -> int
```

**`Events` — señales nuevas:**

```gdscript
signal day_started(day_index: int, title: String)
signal dialogue_turn_started(day_index: int, turn_index: int)
signal option_chosen(option_index: int, kind: StringName, mood_delta: int)
signal mood_changed(new_mood: int, delta: int)
signal day_finished(day_index: int, passed: bool)
signal week_finished(ending_id: StringName)
```

**Flujo acordado:**

```
main_menu → Game.start_run() → change_scene(main.tscn)
main.gd._ready() → conecta Events → Game.start_day(Game.current_day)
   → Events.day_started → main.gd carga day_XX.tscn en LevelHost
day_XX.tscn: muestra la intro de Richard → confirmar → Game.begin_dialog()
   → Events.dialogue_turn_started → DialogueBox pinta 3 opciones
click → Game.choose_option(i) → Events.mood_changed (HUD actualiza la barra)
   → Game.advance_turn() → turno 2 → Game.finish_day() → Events.day_finished (panel de resultado)
confirmar → Game.next_day() → repite desde day_started
Domingo terminado → Game.finish_week() → Events.week_finished → ending.tscn
```

**Quién carga las escenas:** `main.gd` escucha `Events.day_started`. `Game` **nunca**
conoce escenas de día (solo dispara señales). `main.gd` conecta en `_ready()` **antes** de
llamar a `Game.start_day()` — si invertís el orden, se pierde la primera señal.

### 1.3 Puertas de calidad

- **Pasos 1-7 son aditivos**: al terminar cada uno, `project_run` debe seguir funcionando
  igual que antes. Si algo se rompió, no avances.
- **Paso 8**: el HUD pasa a barra de ánimo. Todavía no hay día cargado → es esperado que
  la barra se vea con el valor por defecto.
- **Paso 9 es atómico**: **no lo partas**. Al terminarlo el juego debe ser jugable de
  Lunes a Domingo.
- **Pasos 10-13**: refinamiento, limpieza y docs.

---

## 2. Pasos

### [x] Paso 1 — Datos de diálogo (aditivo)

**Hecho.** `assets/data/days.json` creado con los 7 días completos (42 opciones, bandas de
delta respetadas, `pass_threshold` 50→62). Validado con un script externo: 242/242 checks OK.
`project_run` → `status: "live"`, `ready: true`, sin errores nuevos (solo el warning previo
del nivel faltante).

**Objetivo:** crear la fuente de verdad del contenido.

**Crear `assets/data/days.json`** (la carpeta `assets/data/` ya existe, está vacía):

```json
{
  "version": 1,
  "days": [
    {
      "day": 1, "title": "Lunes", "start_mood": 50, "pass_threshold": 50,
      "richard_intro": "El colectivo se incendió. Richard llegó tarde y con olor a humo.",
      "turns": [
        { "prompt": "Richard vuelca el café sobre su camisa blanca.",
          "options": [
            {"text": "«¿Eso es café o una declaración de guerra?»", "kind": "choke",    "mood": -12},
            {"text": "«Tranquilo, a todos nos pasa.»",              "kind": "motivate", "mood": 10},
            {"text": "«...psssst.»",                                "kind": "sound",    "mood": -2}
          ] },
        { "prompt": "Su jefe le grita frente a todo el equipo.",
          "options": [
            {"text": "...", "kind": "choke",    "mood": -10},
            {"text": "...", "kind": "motivate", "mood": 9},
            {"text": "...", "kind": "sound",    "mood": 1}
          ] }
      ]
    }
  ]
}
```

**Contenido de los 7 días** (usá estas intros como semilla, `start_mood` 50 para todos):

| day | title | pass_threshold | richard_intro (semilla) |
|---|---|---|---|
| 1 | Lunes | 50 | El colectivo se incendió. Llegó tarde y con olor a humo. |
| 2 | Martes | 52 | Le llegó una multa por algo que no hizo. Y se le cayó el café al pagarla. |
| 3 | Miércoles | 54 | Su jefe le gritó por un mail que no mandó él. |
| 4 | Jueves | 56 | Le robaron la bici atada con tres candados. Llovía. |
| 5 | Viernes | 58 | Se le rompió el celular con la puerta del subte: perdió las fotos de su abuela. |
| 6 | Sábado | 60 | Su mejor amigo le canceló el plan por tercera vez. La pizza llegó fría y sin queso. |
| 7 | Domingo | 62 | Se despertó a las 4 AM con la sensación de que el lunes ya empezó. |

**Reglas del contenido:**
- 7 días × **exactamente 2 turnos** × **exactamente 3 opciones** = 42 opciones.
- Cada turno tiene siempre un `choke` (chiste/broma que no cae bien), un `motivate`
  (frase motivacional) y un `sound` (sonido random: "pssst", palmaditas, etc.).
- Deltas base: `choke` −8..−14 · `motivate` +7..+12 · `sound` −3..+3.
- **No compenses la dificultad en el JSON**: la escala la hace `Game.difficulty_scale()`.
  El texto se vuelve más hiriente/desesperado a medida que avanza la semana.

**Verificar:** `project_run` sigue igual (nada carga este archivo todavía).

---

### [x] Paso 2 — Cargador de datos (aditivo)

**Hecho.** `scripts/resources/dialogue_db.gd` creado (`class_name DialogueDB extends
RefCounted`), registrado en el editor (`.uid` generado y presente en
`.godot/global_script_class_cache.cfg`). Verificado con `game_eval` en el proceso del juego:
`day_count() == 7`, títulos `Lunes`→`Domingo`, 2 turnos en el día 0, kinds
`[choke, motivate, sound]`, `option_at(0,0,0)` → texto correcto y `mood = -12`, thresholds
`[50,52,54,56,58,60,62]`, y los accesos fuera de rango o con índice negativo devuelven `{}`.
Camino de fallo probado: archivo inexistente y archivo que no es JSON → `day_count() == 0`
sin crashear, con `push_error` legible.

**Detalle encontrado:** `JSON.get_error_line()` es **0-based**; se suma 1 para que el log diga
la línea real (`línea 3` para un error en la tercera línea). Verificado con un JSON roto en
`user://`.

**Objetivo original:** crear `scripts/resources/dialogue_db.gd`.

```gdscript
class_name DialogueDB
extends RefCounted
```

API:
- `static func load_from(path: String) -> DialogueDB`
- `func get_day(i: int) -> Dictionary`
- `func get_turn(day: int, turn: int) -> Dictionary`
- `func option_at(day: int, turn: int, i: int) -> Dictionary`
- `func day_count() -> int`

**Lectura:** `FileAccess.get_as_text()` + `JSON.parse_string()` (mismo patrón que
`scripts/autoload/save_manager.gd:38-49`). **No** uses `load()`: evita depender del
importador de `.json`.

**Validación defensiva** (mismo estilo que `scene_loader.gd:47-49`): si falla el parseo, si
`days` no tiene 7 entradas, si un día no tiene 2 turnos, o si un turno no tiene 3 opciones
→ `push_error` **nombrando día y turno exactos**. Nunca crashear: devolvé un diccionario
vacío y dejá que el juego avise.

**Verificar:** `project_run` sigue igual.

---

### [x] Paso 3 — DTO de guardado (aditivo)

**Hecho.** `scripts/resources/game_data.gd` reescrito como snapshot de la semana
(`mood`, `current_day`, `days_passed`, `play_time_seconds`, `history: Array[int]`) con
`_to_int()` / `_to_float()` defensivos dentro de `from_dict()`. Verificado con `game_eval` en
el proceso del juego: round-trip por `JSON.stringify` / `parse_string` idéntico; un guardado
con el formato viejo (`score` / `current_level`), uno con basura (`null`, `String`,
`Dictionary`, `Array`) y uno vacío `{}` caen en los valores por defecto sin crashear.

**Objetivo original:**

**Modificar `scripts/resources/game_data.gd`** — reutilizá la clase como snapshot de la
semana y actualizá `to_dict()` / `from_dict()`:

| Antes | Después |
|---|---|
| `score` | `mood: int` |
| `current_level` | `current_day: int` |
| `unlocked_levels` | `days_passed: int` |
| `collected_ids: Array[StringName]` | `history: Array[int]` |
| `play_time_seconds` | `play_time_seconds` (queda igual) |

`from_dict()` debe castear cada valor (`int(...)`) para que un JSON viejo no rompa.

**Verificar:** `project_run` sigue igual (nadie lo usa todavía).

---

### [x] Paso 4 — Estado global (aditivo)

**Hecho.** `scripts/autoload/game_manager.gd` reescrito con el contrato de la semana.
Verificado con `game_eval` en el proceso del juego, todo en verde:

- `days.day_count() == 7`; `start_day(0)` → `state = INTRO`, `mood = 50`, `current_turn = 0`.
- `begin_dialog()` → `state = DIALOGUE`; `current_turn_data()` trae el prompt real y 3 opciones.
- Día 1: `choose_option(0)` (choke −12) → `mood 38`; `advance_turn()` → turno 1;
  `choose_option(1)` (motivate +9) → `mood 47`; `advance_turn()` → `state = DAY_RESULT`,
  `history == [47]`, `days_passed == 0` (47 < umbral 50), `current_turn == 1`.
- `next_day()` → `current_day = 1`, `mood = 50` (el `start_mood` del Martes), turno reseteado.
- `difficulty_scale()`: día 1 → `[−13, +9]`; día 6 → `[−21, +6]`; `0` → `0`.
- Clamp: 95 + 10 → 100; 3 − 12 → 0; `apply_mood(0)` no emite nada.
- Accesos fuera de rango (`current_turn = 5`, `option_at(99)`, `get_day(99)`) → `{}`, sin
  crashear ni ensuciar el log.
- Finales: `[80,85,90]` → `ending_bright`, `[50,55,60]` → `ending_bittersweet`,
  `[20,30,39]` (29.67) → `ending_gloomy`; bordes exactos 70 → bright, 40 → bittersweet,
  39.5 → gloomy; `history` vacío → `average_mood()` = ánimo actual.
- `save_progress()` / `load_progress()`: round-trip exacto
  (`mood 63`, `current_day 3`, `days_passed 2`, `play_time 123.5`, `history [50,63,71]`),
  `Save.delete_save()` limpia.
- Pausa: en `PLAYING` pausa y **vuelve al estado anterior** (ya no clava `PLAYING`);
  en `MENU` no pausa.
- `next_day()` desde el domingo → `finish_week()`: `ending_id = ending_bright`,
  `state = ENDING`, guardado escrito.

**Errores esperados en el log** (solo dos, ninguna regresión): el warning previo de
`boot.gd:42` por `level_01.tscn`, y **un** `SceneLoader: no existe la escena
'res://scenes/ui/ending.tscn'` disparado a propósito por el test de `finish_week()` —
esa escena la crea el **Paso 10**.

**Extra pedido por el usuario ("borra lo viejo").** Se borró el andamiaje de combate
completo, que es el que nadie de afuera referenciaba:

- `scenes/actors/**` (player y enemies, con sus `.uid`)
- `scenes/dev/sandbox.tscn`
- `scripts/components/**` (`health_component`, `hitbox_component`, `hurtbox_component`,
  `interactable`, `state`, `state_machine`)
- `scripts/resources/stat_block.gd`, `scripts/resources/level_data.gd`

Comprobado por grep que **no queda ninguna referencia** en `res://` (solo el caché
`.godot/`, que se regenera, y docs que se limpian en los Pasos 11-12). También se sacó de
`game_manager.gd` lo que quedó huérfano: `GRID` y `_on_player_died()` con su conexión a
`Events.player_died`.

**Lo que sigue siendo andamio y por qué no se puede borrar todavía:** `main.gd` lee
`Game.State.PLAYING` / `Game.set_level()`, `hud.gd` lee `Game.score` y escucha
`score_changed` / `health_changed`, y `game_over.gd` lee `Game.score` / `high_score` /
`State.GAME_OVER`. Si los saco ahora, esos tres archivos no compilan y el proyecto deja de
arrancar. Están encerrados en un bloque marcado
`# --- DEPRECADO ... Se retira en el Paso 11` y los consumen los Pasos 8, 9 y 10.

**Objetivo original:**

**Modificar `scripts/autoload/game_manager.gd`.**

**Agregar** (sin borrar nada todavía):
- `enum State` → sumar `INTRO, DIALOGUE, DAY_RESULT, ENDING` (dejá `PLAYING`/`GAME_OVER`
  por ahora, los saca el Paso 11).
- `const DAY_COUNT := 7`, `const TURNS_PER_DAY := 2`.
- Las variables del contrato (§1.2) + `var days: DialogueDB`.
- `_ready()`: `days = DialogueDB.load_from("res://assets/data/days.json")`. Si `days` queda
  vacío, `push_error` claro y legible.
- Las funciones del contrato: `start_day()`, `begin_dialog()`, `current_turn_data()`,
  `option_at()`, `choose_option()`, `advance_turn()`, `finish_day()`, `next_day()`,
  `finish_week()`, `difficulty_scale()`.
- **`difficulty_scale(delta)`**: `delta < 0` → `roundi(delta * (1.0 + 0.12 * current_day))`;
  `delta > 0` → `roundi(delta * (1.0 - 0.06 * current_day))`.
  Escala real: el domingo (day 6) un chiste pega ×1.72 y una frase buena rinde ×0.64.
- **`finish_week()`**: `avg = average(history)` → `>= 70` → `&"ending_bright"`;
  `40..69` → `&"ending_bittersweet"`; `< 40` → `&"ending_gloomy"`.

**Clavar el ánimo:** `mood = clampi(mood + scaled, 0, 100)` y emitir `mood_changed`
**siempre**, incluso si el clamp dejó el valor igual (la UI necesita refrescar de todos
modos).

**No tocar todavía:** `start_run()`, `score`, `add_score()`, `PLAYING`, `_on_player_died()`.

**Verificar:** `project_run` sigue igual (el juego arranca como antes).

---

### [x] Paso 5 — Eventos (aditivo)

**Hecho.** `scripts/autoload/event_bus.gd` ahora declara las 6 señales de la semana en una
sección `# --- Día y diálogo ---`, cada una con su comentario de tipo y de quién la emite:
`day_started(day_index, title)`, `dialogue_turn_started(day_index, turn_index)`,
`option_chosen(option_index, kind, mood_delta)`, `mood_changed(new_mood, delta)`,
`day_finished(day_index, passed)` y `week_finished(ending_id)`. Hoy no las escucha nadie; el
Paso 8 (HUD) y el Paso 9 (`Main`) las consumen. El juego arranca igual (`live`, `ready`).

**Extra:** se borraron las 5 señales que quedaron sin emisor ni oyente al eliminar el
combate (`player_spawned`, `player_died`, `enemy_died`, `checkpoint_reached`,
`screen_shake_requested`). Verificado por grep en todo `res://`. Se conservan `score_changed`,
`level_started`, `level_completed` y `health_changed` porque `hud.gd`, `main.gd` y el bloque
viejo de `game_manager.gd` todavía las usan.

**Objetivo original:**

**Modificar `scripts/autoload/event_bus.gd`** — agregar las 6 señales del contrato (§1.2)
en una sección `# --- Diálogo y días ---`, con comentario de tipo a `StringName`.

**No borres** las de combate todavía (las retira el Paso 11) — salvo las que ya quedaron
sin emisor ni oyente tras borrar `scenes/actors/**` y `scripts/components/**`.

**Verificar:** `project_run` sigue igual.

---

### [x] Paso 6 — Escenas de día

**Hecho.** `scenes/levels/day_scene.gd` + `day_01.tscn` … `day_07.tscn` (7 archivos, mismo
árbol, solo cambia `day_index`, el color de fondo y el texto de preview). `scenes/levels/`
ya tenía un `.gitkeep`.

Verificado con `game_eval` en el proceso del juego, instanciando las 7 escenas: cada
`%DayTitleLabel` = `"Día N · <title>"` y cada `%IntroLabel` = el `richard_intro` exacto de
`days.json` (`Día 1 · Lunes` … `Día 7 · Domingo`), `%ContinueButton` = `"Continuar"`.

**Dos bugs de layout reales, encontrados y corregidos** (el tercero cae en el Paso 7; los
tres valen para el resto del proyecto):

1. **Un `Control` cuyo padre es un `Node2D` se mide contra un rect 0×0.** El
   `Background` daba `(0,0,0,0)` y la tarjeta quedaba en `(-85, -178)`, fuera de pantalla.
   `Rect2 Control::_get_parent_anchorable_rect()` cae al viewport solo si el padre no es un
   `CanvasItem`; con un `Node2D` usa su `get_anchorable_rect()`, que es vacío. **Solución:**
   la UI del día cuelga de un `CanvasLayer` (`UI`, `layer = 0`), como hacen `hud.tscn` y
   `dialogue_box.tscn`.

2. **No dejar que la tarjeta "abrace el contenido"** (altura 0 vía `offset_bottom ==
   offset_top`). Con altura 0 el `Label` con `autowrap` se formatea antes de que el
   contenedor le dé ancho, cachea su mínimo con **1 px de ancho** (`(1, 1563)` → 54 líneas)
   y el layout no se recupera nunca: la tarjeta quedaba de `592×1645`. Con **altura fija
   anclada** el contenedor reparte el ancho primero y todo cuadra. Medido después del
   arreglo: `IntroCard` `592×136`, `IntroLabel` `592×26` (1 línea), mínimo `(200,108)`.

**Reparto vertical a 640×360** (viewport real de `project.godot`): HUD `0..88`, tarjeta
`96..244`, caja de diálogo `150..360`. La tarjeta y el diálogo **nunca se ven juntos**: al
emitirse `dialogue_turn_started` la escena del día oculta `%IntroCard` (a 360 px de alto no
entran los dos; el contexto queda en el título del HUD y en el prompt de cada turno).

**Verificación headless de los 7 (independiente del bridge MCP).** Cuando el MCP quedó
inutilizable (ver Paso 7), corrí la comprobación con un Godot headless y una escena
temporal (`godot --headless --path <proyecto> res://__verify_days.tscn`). Ojo: **no sirve
`--script`**, porque en ese modo los autoloads no se registran y nada que use
`Game`/`Events`/`Save` compila. Resultado para los 7 días:

```
DIA 1 Lunes     card 592x148 @(24,96) | necesita 108 | lineas 1 | entra true
DIA 2 Martes    card 592x148 @(24,96) | necesita 137 | lineas 2 | entra true
DIA 3 Miércoles card 592x148 @(24,96) | necesita 108 | lineas 1 | entra true
DIA 4 Jueves    card 592x148 @(24,96) | necesita 108 | lineas 1 | entra true
DIA 5 Viernes   card 592x148 @(24,96) | necesita 137 | lineas 2 | entra true
DIA 6 Sábado    card 592x148 @(24,96) | necesita 137 | lineas 2 | entra true
DIA 7 Domingo   card 592x148 @(24,96) | necesita 108 | lineas 1 | entra true
```

Ningún `richard_intro` pasa de 2 líneas: el peor caso necesita 137 px y la tarjeta tiene
148. Los temporales se borraron después (el proyecto quedó sin archivos sueltos).

**Objetivo original:**

**Crear `scenes/levels/day_scene.gd`:**

```gdscript
extends Node2D
@export var day_index: int = 0
```

En `_ready()`: leé `Game.days.get_day(day_index)`, pintá `%IntroLabel` con `richard_intro` y
`%DayTitleLabel` con el título (`"Día 3 · Miércoles"`). Conectá `%ContinueButton`: al
presionarlo (o con `ui_accept`) → `Game.begin_dialog()`.

**Crear `scenes/levels/day_01.tscn` … `day_07.tscn`** (7 archivos, mismo árbol, solo cambia
`day_index` 0..6):

```
Day01 (Node2D, script day_scene.gd, day_index = 0)
├── Background (ColorRect, anclado full rect, color propio del día)
├── IntroCard (PanelContainer)
│   └── VBoxContainer
│       ├── %DayTitleLabel (Label)
│       ├── %IntroLabel (Label, autowrap)
│       └── %ContinueButton (Button, texto "Continuar")
```

`scenes/levels/` está vacío hoy: hay que crear la carpeta. `day_01` → `day_index = 0`,
`day_07` → `day_index = 6`.

**Verificar:** `project_run` sigue igual. Abrí `day_01.tscn` en el editor y confirmá que no
haya errores de script (en la salida del editor, no en los logs guardados).

---

### [x] Paso 7 — `DialogueBox`

**Hecho.** `scenes/ui/dialogue_box.gd` (`class_name DialogueBox extends CanvasLayer`,
`layer = 5`) + `scenes/ui/dialogue_box.tscn`, registrado en
`.godot/global_script_class_cache.cfg` como `DialogueBox` → `res://scenes/ui/dialogue_box.gd`.

Árbol: `DialoguePanel` (PanelContainer abajo) → `%PromptLabel`, `%OptionsContainer` (3
`Button`), `%FeedbackLabel`; y `%DayResultPanel` → `%ResultLabel` + `%ResultButton`.

Verificado en runtime, turno por turno: arranca `visible = false`; `dialogue_turn_started`
lo muestra con el prompt real y los 3 textos de `option_at(i)`; un clic llama
`Game.choose_option(i)`, **deshabilita los 3 botones antes de tocar `Game`** (un doble clic
no puede comerse un turno), pinta `%FeedbackLabel` y encadena `advance_turn()`; el turno 2
vuelve a habilitar los botones; el segundo clic cierra el día → `%DayResultPanel` visible,
`%DialoguePanel` oculto, `"Se acumula la tristeza"` (47 < umbral 50); `%ResultButton` →
`Game.next_day()` → Día 2 con `mood = 50` y la caja oculta.

Medido: `DialoguePanel` = `(16, 150) 608×210` con contenido real de 162 px (entra);
`%DayResultPanel` = `(60, 72) 520×216`. Captura `editor_screenshot source="game"`: los
emoji del feedback (`😖`) y el signo menos tipográfico (`−12`) **renderizan bien**, y las 3
opciones se leen en una línea.

**Ajuste sobre el plan (a propósito):** el plan decía limpiar `%FeedbackLabel` en cada
`_show_turn()`, pero como `advance_turn()` se llama en el acto, el feedback del turno 1 se
borraba antes de que nadie lo leyera. Ahora **se mantiene** el del turno anterior y solo se
limpia al empezar el día (turno 0): el jugador ve qué le costó su última frase mientras
elige la siguiente.

**Verificación headless (misma corrida que el Paso 6):** el flujo completo, con exit code 0
y `stderr` vacío.

```
tras Continuar -> state=3 card_visible=false caja_visible=true
prompt: Richard vuelca el café sobre su camisa blanca.
clic 1 -> feedback='−12  😖' animo=38 turno=1
clic 2 -> state=4 history=[47] result_visible=true texto='Se acumula la tristeza' dialogo_oculto=true
Seguir -> dia=1 animo=50 turno=0 caja_visible=false
save borrado: true
```

Con la caja ya visible, el layout resuelto es el previsto: `DialoguePanel` `608×210` con
contenido mínimo de 178 px, `%PromptLabel` de 1 línea y los 3 botones a `608×34`.

**Tercera lección de layout (vale para todo el proyecto):** **Godot no resuelve el layout de
un contenedor oculto.** Midiendo la caja en su estado inicial (`visible = false`) salía un
panel de `608×584` con el `%PromptLabel` de **1 px de ancho** repartido en 15 líneas; con
`visible = true` y otra medición, todo caía en su lugar. No hay nada que arreglar en la
escena (la caja se hace visible dentro de `_show_turn()`, y ahí sí se ordena), pero **no hay
que medir layouts de nodos ocultos** ni confundir ese artefacto con un problema real.

**Objetivo original:**

**Crear `scenes/ui/dialogue_box.gd` + `scenes/ui/dialogue_box.tscn`.**

- `class_name DialogueBox extends CanvasLayer`, **`layer = 5`** → encima del HUD (layer 1),
  debajo de `PauseMenu` (layer 10). Así la pausa tapa el diálogo.
- Nodos: `%PromptLabel` (Label autowrap), `%OptionsContainer` (VBoxContainer con 3
  `Button`), `%FeedbackLabel`, `%DayResultPanel` (PanelContainer con `%ResultLabel` +
  `%ResultButton`).
- `_ready()`: conectar `Events.dialogue_turn_started` → `_show_turn()` y
  `Events.day_finished` → `_show_result()`. Arrancar con `visible = false`.
- `_show_turn(day, turn)`: `Game.option_at(turn, i)["text"]` en cada botón; `visible = true`;
  limpiar feedback; habilitar los 3 botones; foco en el primero.
- Al presionar una opción: `var delta := Game.choose_option(i)` → **deshabilitar los 3
  botones** → `%FeedbackLabel` con el delta efectivo (`"−12 😖"` / `"+10 🙂"`) →
  `Game.advance_turn()`.
- `_show_result(day, passed)`: `%ResultLabel` = "Día superado" / "Se acumula la tristeza";
  `%ResultButton` → `Game.next_day()` y `visible = false`.
- **`process_mode` por defecto (hereda)**: así no responde mientras el juego está pausado.
- Sin `$Path`: solo `%Name` con `unique_name_in_owner`.

**Verificar:** `project_run` sigue igual (nadie lo instancia todavía).

---

### [x] Paso 8 — HUD: barra de ánimo

**Hecho.** `hud.tscn`: `ScoreLabel` + `HealthLabel` fuera, entran `%DayLabel`,
`%MoodValueLabel` y `%MoodBar` (ProgressBar 0..100, `show_percentage = false`,
`custom_minimum_size = (0, 10)` para fijar el alto). `hud.gd` ya no toca `score_changed`
ni `health_changed`: `_ready()` pinta desde `Game.mood` / `Game.current_day` y escucha
`mood_changed` + `day_started`.

Medido en runtime con `game_eval` sobre `/root/Main/HUD` (viewport 640×360):

```
inicial      -> day='Día 1/7 · Lunes'  mood='Ánimo: 50/100'  bar=50
mood_changed -> bar=37 'Ánimo: 37/100'   (clamp: +250 -> bar=100)
day_started  -> day='Día 3/7 · Miércoles'
```

Layout (trampa conocida): el `MarginContainer` mide 620×344 porque `MarginContainer`
**estira** a su hijo (`size_flags` no lo achica), pero lo pintado termina en el fondo de la
barra, `y = 74`. La tarjeta del día arranca en `y = 96` (`IntroCard` `(24, 96) 592×148`),
así que quedan **22 px de aire**: no hay solape. Captura `editor_screenshot source="game"`
con la tarjeta cargada: HUD arriba, tarjeta debajo, sin pisarse.

**Bug de integración encontrado y corregido (lo destapó este paso):** `Game.start_day()`
fija `mood` en el `start_mood` del día **sin pasar por `apply_mood()`**, así que no emite
`mood_changed` y el HUD amanecía con la barra del día anterior. Reproducido: con la barra en
90, `Game.start_day(2)` dejaba `Game.mood = 50` pero `bar = 90`. Arreglado en
`_on_day_started()`: además del `%DayLabel`, repinta el ánimo desde `Game.mood`. Verificado
después del arreglo: `bar = 50` y `'Ánimo: 50/100'` junto con `'Día 3/7 · Miércoles'`.

Los 3 errores / 2 warnings que escupe `project_run` son de `boot.gd` y `main.gd` por el
`level_01.tscn` borrado: son de los Pasos 10 y 9, no del HUD. Sin `user://savegame.json`
colgando.

**Objetivo original:**

**Modificar `scenes/ui/hud.tscn` y `scenes/ui/hud.gd`.**

Reemplazar `ScoreLabel` + `HealthLabel` (`hud.tscn:24-34`) por:

```
MarginContainer/VBoxContainer
├── %DayLabel        (Label)  → "Día 3/7 · Miércoles"
├── %MoodValueLabel  (Label)  → "Ánimo: 62/100"
└── %MoodBar         (ProgressBar, min_value = 0, max_value = 100, value = 50, show_percentage = false)
```

`hud.gd`: conectar `Events.mood_changed` → barra + valor; `Events.day_started` →
`%DayLabel`. **En `_ready()` leé `Game.mood` y `Game.current_day` para pintar el estado
inicial** — no esperes al primer evento: ese es exactamente el bug del HUD actual (se
conecta antes de que el actor exista y queda vacío).

**Verificar:** `project_run` sigue igual, con la barra visible.

---

### [x] Paso 9 — NÚCLEO ATÓMICO (⚠️ no lo partas)

**Hecho — y el juego es jugable de Lunes a Domingo.**

- `main.tscn`: instancia `DialogueBox` (`unique_name_in_owner`). Queda
  `LevelHost` + `HUD` + `DialogueBox` + `PauseMenu`; el orden de dibujo lo dan las capas
  (día 0, HUD 1, diálogo 5, pausa 10).
- `main.gd`: reescrito. Fuera `DEFAULT_LEVEL_SCENE`, `load_level()` y la conexión a
  `level_completed`. Entra `load_day(index)` (`day_%02d.tscn`), `Events.day_started` →
  `_on_day_started`, y `_ready()` termina en `Game.start_day(Game.current_day)` — así la
  primera escena del día entra por el mismo camino que las demás (`start_day()` emite
  `day_started`, un solo camino). Se conserva el `await get_tree().process_frame` entre
  liberar el día viejo e instanciar el nuevo.
- `game_manager.gd`: los guards de `_unhandled_input` pasan de `State.PLAYING` a
  `state in [INTRO, DIALOGUE, DAY_RESULT]` (igual que `_can_pause()`); `_process` acumula
  `run_time` en esos estados para que `play_time_seconds` no quede muerto. `start_run()` ya
  estaba (Paso 4).

**Verificación con clics reales** (evento `InputEventMouseButton` inyectado al viewport en
coordenadas de canvas: `game_manage input_mouse` / `input_action` no llegan al botón porque
la ventana va por la *Embedded Game View* y el mapeo de coordenadas no es 1:1):

```
tras Continuar -> state=3 (DIALOGUE) prompt='Richard vuelca el café sobre su camisa blanca.'
clic 1         -> animo 50 -> 38  feedback='−12  😖'  turno=1
clic 2         -> animo=27  history=[27]  result_visible=true 'Se acumula la tristeza' state=4
Seguir         -> dia=1 animo=50 Day02 cargado dlg_visible=false
```

**Semana completa, Sábado a Domingo incluidos** (7 días jugados con la misma vía, eligiendo
siempre la primera opción): `history = [27, 24, 18, 19, 13, 9, 7]`, `promedio = 16.71`,
`days_passed = 0`, `ending_id = ending_gloomy`, `state = ENDING`. No queda ningún día viejo
colgado: `LevelHost` termina con 1 hijo. `get_tree().paused == false`.

Único error nuevo: `SceneLoader: no existe la escena 'res://scenes/ui/ending.tscn'`. Es el
esperado: esa escena la crea el Paso 10.

**Flujo real desde el arranque:** `boot.tscn` → `MainMenu` → clic en "Nueva partida" →
`Main` con `Day01` cargado, `mood = 50`, `history = []` y el save borrado
(`Save.has_save() == false`).

**Guards de pausa del 9.3**, inyectando `InputEventAction`:

```
pausa (Esc)    -> paused=true   state=5 (PAUSED)  PauseMenu.visible=true
pausa otra vez -> paused=false  state=2 (INTRO)   PauseMenu.visible=false
restart        -> animo 30 -> 50  history=[]  Day01 recargado  paused=false
pausa en ENDING y en MENU -> ignorada (sigue paused=false y el mismo state)
```

**Camino de error de `load_day`:** pedir un día inexistente (`load_day(99)`) deja un solo
warning limpio — `Main: no existe 'res://scenes/levels/day_100.tscn'.` — y el día cargado
sigue en pie (no se libera el bueno). Sin errores crudos del motor.

**Desvío a propósito:** el plan pedía conectar también `Events.week_finished` en `Main`.
No se hizo: `Game.finish_week()` ya cambia de escena y `Main` se libera entero, así que el
handler sería código muerto. Si el Paso 10 necesita algo ahí (p. ej. un fade), se agrega.

**Objetivo original:**

Al terminar este paso el juego debe ser **jugable de Lunes a Domingo**. No lo dividas: a
mitad de camino los archivos se rompen entre sí.

**9.1 `scenes/main.tscn`** — agregar la instancia de `scenes/ui/dialogue_box.tscn` como hijo
de `Main`, con `unique_name_in_owner = true` y nombre `DialogueBox`. Queda:
`LevelHost` + `HUD` + `DialogueBox` + `PauseMenu`.

**9.2 `scenes/main.gd`**
- Borrar `DEFAULT_LEVEL_SCENE` (`:8`) y `load_level()` (`:27-50`).
- Agregar `load_day(index)` → `res://scenes/levels/day_%02d.tscn`, con `push_warning` si
  falta el archivo.
- `_ready()`: conectar `Events.day_started` → `_on_day_started(index)` (carga la escena en
  `LevelHost`) y `Events.week_finished`; borrar la conexión a `level_completed` (`:20`);
  reemplazar `:21` (`Game.state = PLAYING` + `load_level()`) por
  `Game.start_day(Game.current_day)`.
- `_on_day_started`: instanciar la escena nueva y liberar la anterior con **un
  `await get_tree().process_frame`** entre medio (mismo motivo que `:40-45`: si no, quedan
  dos días vivos al mismo tiempo).

**9.3 `scripts/autoload/game_manager.gd`**
- `start_run()`: resetear `mood` / `current_day` / `current_turn` / `history` /
  `days_passed` / `ending_id`, `state = INTRO`, `change_scene(main.tscn)`.
- `pause_game()` / `resume_game()` / `_unhandled_input`: cambiar el guard de `PLAYING` a
  `state in [INTRO, DIALOGUE, DAY_RESULT]`. No permitir pausa en `MENU` ni en `ENDING`.
- **Sacar** `_on_player_died()` y la conexión a `Events.player_died` — **ya hecho en el Paso 4.**

**9.4 Verificación dura** — con el juego corriendo, `editor_manage op="game_eval"`
(serializado, con `return` explícito):

```gdscript
var dlg = get_node("/root/Main/DialogueBox")
var opts = dlg.get_node("%OptionsContainer")
return {
  "opciones": opts.get_child_count(),                 # esperado: 3
  "dia": Game.current_day,                            # esperado: 0
  "animo": Game.mood,                                 # esperado: 50
  "turnos": Game.days.get_day(0)["turns"].size()      # esperado: 2
}
```

Después: 2 clics → `Game.mood != 50`; confirmar el resultado → `Game.current_day == 1`.

---

### [x] Paso 10 — Menús y pantalla de final

**Hecho.**

- **10.1** `game_over.tscn` + `game_over.gd` (+ su `.uid`) → `ending.tscn` + `ending.gd`, con
  el `.uid` preservado (`uid://dbqchs3wftag6`) para no romper referencias por UID.
- **10.2** `game_manager.gd`: fuera `GAME_OVER_SCENE` y `trigger_game_over()`;
  `ENDING_SCENE` ya existía (sin el comentario de "todavía no existe").
- **10.3** `main_menu.gd`: `_on_new_game_pressed` ya estaba (`Save.delete_save()` +
  `Game.start_run()`); `_on_continue_pressed` pasa a `Game.continue_run()`, que envuelve
  `Game.load_progress()` (el `GameData.from_dict(Save.load_game())` + volcado a `Game`) y
  el `change_scene`. Se va la lectura de `score` / `current_level` viejos y la constante
  `GAME_SCENE` local.
- **10.4** `boot.gd`: `PRELOAD_SCENES` = `main.tscn`, `main_menu.tscn`, `ending.tscn`,
  `day_01.tscn`. Se acabaron los warnings de precarga por `level_01.tscn`.
- `pause_menu.gd` y `settings_menu.*`: sin tocar.

**Renombrado con el editor abierto:** el `.tscn` se movió con `filesystem_manage rename`
(→ `ending.tscn`). El `.gd` **no** se pudo mover igual: el rename se niega porque el
`.tscn` lo referencia por path literal ("dependency path rewrites... unsupported"). Se
creó `ending.gd` nuevo + su `.uid` copiado, y se borró `game_over.gd` (sus `referenced_by`
quedaron vacíos al reapuntar `ending.tscn`).

**Verificación — partida completa por clics** (menú → 7 días → final, forzando
`Game.mood = 95` antes del turno que cierra cada día):

```
MainMenu -> "Nueva partida" -> Main/Day01
7 días jugados -> escena='Ending'  ending_id=ending_bright  days_passed=7
history=[84,80,78,79,77,76,73]  promedio=78.14
%TitleLabel='Una semana distinta'  %DaysLabel='Días superados: 7/7'
%AverageLabel='Ánimo promedio: 78/100'  state=ENDING
0 errores nuevos
```

**Los 3 finales** (forzando el promedio) y los botones:

```
history=[55 x7] -> ending_bittersweet  'Se sostuvo, a duras penas'  'Días superados: 3/7'  'Ánimo promedio: 55/100'
history=[20 x7] -> ending_gloomy       'La tristeza se acumuló'     'Días superados: 0/7'  'Ánimo promedio: 20/100'
"Volver al menú" -> MainMenu (Continuar habilitado)
```

**`Continuar` a mitad de semana**, con un guardado de prueba (`history=[70]`):

```
tras Continuar -> escena=Main  dia=1  dia_escena='Day02'  history=[70]  days_passed=1
```

O sea: retoma en el día siguiente al último cerrado y **no** repite ni duplica el Lunes.
"Jugar de nuevo" desde el final → `Main`/`Day01`, `mood=50`, `history=[]`.

**Desvíos a propósito:**
- Las labels `%ScoreLabel` / `%HighScoreLabel` se renombraron a `%DaysLabel` /
  `%AverageLabel`: mostraban días y promedio, no puntaje (un nombre que miente es una
  trampa de lectura). El árbol y el resto de los nodos son los mismos.
- Los botones se retitularon `"Reintentar"` → `"Jugar de nuevo"` (el final puede ser bueno)
  y se agregó `unique_name_in_owner` al `TitleLabel`, que antes no lo tenía.
- `Game.continue_run()` es nuevo: el plan pedía "restaurar y volcar a `Game` antes del
  `change_scene`", y meter eso en el menú dejaba la transición de escena fuera de `Game`
  (donde ya viven `start_run()` / `go_to_menu()`). Además corrige que el guardado se hace
  al **cerrar** un día, así que sin el ajuste "Continuar" repetía el último día jugado.

**Objetivo original:**

**10.1** Renombrar `scenes/ui/game_over.tscn` + `game_over.gd` → `scenes/ui/ending.tscn` +
`ending.gd` (incluido el `.uid` si existe). Mismo árbol; retitulá el `TitleLabel` según
`Game.ending_id` (3 textos distintos), `%ScoreLabel` → días superados y `%HighScoreLabel` →
promedio de `Game.history`.

**10.2 `scripts/autoload/game_manager.gd`** → `GAME_OVER_SCENE` pasa a
`ENDING_SCENE = "res://scenes/ui/ending.tscn"`; `trigger_game_over()` desaparece (su lugar
lo ocupa `finish_week()`).

**10.3 `scenes/ui/main_menu.gd`** (`:34-45`) → `_on_new_game_pressed`:
`Save.delete_save()` + `Game.start_run()`. `_on_continue_pressed`: restaurar con
`GameData.from_dict(Save.load_game())` y volcar a `Game` antes del `change_scene`.

**10.4 `scenes/boot/boot.gd`** (`:9-15`) → `PRELOAD_SCENES` =
`main.tscn`, `main_menu.tscn`, `ending.tscn`, `day_01.tscn`.

`pause_menu.gd` y `settings_menu.*`: **sin cambios**.

**Verificar:** partida completa: menú → 7 días → final. Probá los 3 finales forzando
`Game.mood`.

---

### [x] Paso 11 — Limpieza

**Hecho** (además de lo ya adelantado en el Paso 4).

- **`event_bus.gd`:** fuera `health_changed`, `level_started`, `level_completed`,
  `score_changed` y `game_over`. Los dos últimos no estaban en la lista del plan, pero al
  borrar `add_score()` y `trigger_game_over()` se quedaron **sin emisor y sin oyente** (la
  regla que el propio plan fija). Quedan `game_started`, `game_paused` / `game_resumed`,
  `game_returned_to_menu`, `week_finished` y compañía, `sfx_requested` (lo escucha
  `audio_manager`) y `clear_all()`.
- **`game_manager.gd`:** fuera `score`, `high_score`, `current_level`, `add_score()`,
  `reset_score()`, `set_level()`, `complete_level()` y del `enum State` los `PLAYING` /
  `GAME_OVER`. El `high_score` que se leía de `Save` en `_ready()` también se fue.
  **`run_time` se queda**: no era del todo viejo — `save_progress()` lo guarda como
  `play_time_seconds` y `_process()` lo acumula durante el día.
- **`project.godot`:** fuera las 8 acciones de combate (`move_left`, `move_right`,
  `move_up`, `move_down`, `jump`, `attack`, `interact`, `restart`) y las 7 capas
  `2d_physics/layer_1..7`. El archivo pasó de 412 a 117 líneas. Intactos
  `_mcp_game_helper`, `[editor_plugins]`, Jolt, `d3d12` y `gl_compatibility`, y el
  `config/name` ya estaba.
- **`save_manager.gd`:** el ejemplo del docstring decía `{"score": 120, "current_level": 3}`;
  ahora muestra el formato real (`{"mood": 62, "current_day": 3}`).

**Consecuencia que hay que tener presente:** borrar la acción `restart` obligó a sacar la
rama de `_unhandled_input` que la leía (`is_action_pressed(&"restart")` con una acción
inexistente loguea error). Reiniciar la semana sigue disponible desde el menú de pausa
("Reiniciar") y desde el final ("Jugar de nuevo"); lo que se pierde es el atajo de teclado.
`pause` queda (la necesita `_unhandled_input`), y `ui_accept` es una acción **built-in** de
Godot, así que no hace falta declararla.

**Verificación:**

```
project_run -> status=live ready=true
InputMap: pause=true  restart=false  move_left=false  ui_accept=true
layer_names/2d_physics/layer_1 -> "" (borrada)
escena -> MainMenu   errores=0   warnings=0
```

Partida completa otra vez, por clics, eligiendo siempre la opción "motivate":

```
día  hud                 animo_fin  barra  resultado
1    'Día 1/7 · Lunes'   69         69     'Día superado'
2    'Día 2/7 · Martes'  66         66     'Día superado'
3    'Día 3/7 · Miércoles' 65       65     'Día superado'
...
7    'Día 7/7 · Domingo' 60         60     'Se acumula la tristeza'
-> Ending · ending_bittersweet · days_passed=6 · promedio=64.43
   'Se sostuvo, a duras penas' / 'Días superados: 6/7' / 'Ánimo promedio: 64/100'
   pausa: paused=true state=PAUSED menu_visible=true -> reanudar: state=INTRO
   0 errores nuevos
```

Se ve la curva de dificultad: con las **mismas** buenas elecciones el ánimo cae de 69 a 60
a lo largo de la semana.

**Objetivo original:**

**Ya hecho en el Paso 4** (adelantado a pedido del usuario, "borra lo viejo"): el andamiaje
de combate completo —
- `scripts/components/*.gd` (los 6: `health_component`, `hitbox_component`,
  `hurtbox_component`, `interactable`, `state`, `state_machine`)
- `scenes/actors/**` (player y enemies, con sus `.uid`)
- `scenes/dev/sandbox.tscn`
- `scripts/resources/stat_block.gd`
- `scripts/resources/level_data.gd`

y de `event_bus.gd` las señales sin emisor ni oyente (`player_died`, `enemy_died`,
`player_spawned`, `checkpoint_reached`, `screen_shake_requested`), más `GRID` y
`_on_player_died()` en `game_manager.gd`.

**Falta acá** (depende de los Pasos 8, 9 y 10, que reescriben a los consumidores):
- `event_bus.gd` → quitar `health_changed` (la escucha `hud.gd`) y, si ya no se usa,
  `level_started` / `level_completed`.
  Conservar `game_started`, `game_paused`/`game_resumed`, `game_returned_to_menu`,
  `sfx_requested` (lo usa el `kind: "sound"`) y `clear_all()`.
- `game_manager.gd` → quitar el bloque `# --- DEPRECADO ---`: `score`, `add_score()`,
  `reset_score()`, `high_score`, `set_level()`, `complete_level()`, `trigger_game_over()`,
  `current_level`, y del `enum State` los `PLAYING` / `GAME_OVER` que ya no se usen.

**Modificar `project.godot`**
- `config/name` (`:13`) → `"Repite Conmigo"` — **ya está hecho** (verificado 2026-10-16).
- Borrar los inputs `move_left` / `move_right` / `move_up` / `move_down`, `jump`, `attack`,
  `interact`, `restart`. Opcional: agregar `choice_1` / `choice_2` / `choice_3`.
- Borrar las capas `2d_physics/layer_1..7` de combate.
- **No tocar** `_mcp_game_helper`, `[editor_plugins]`, Jolt, `d3d12`, `gl_compatibility`.

**Verificar:** `project_run` `live` / `ready`, `logs_read source="game"` sin errores, y
partida completa otra vez.

---

### [x] Paso 12 — Documentación

**`AGENTS.md`** (ajustes obligatorios, porque este plan borra `scripts/components/state.gd`):
1. El ejemplo de `game_eval` es inconsistente consigo mismo: dice
   `/root/Main/LevelHost/Day01/DialogueBox`, pero `DialogueBox` cuelga de `Main` → debe ser
   `/root/Main/DialogueBox`.
2. Re-agregar `PauseMenu` a la descripción del host de `main.tscn`.
3. La sección "Naming traps" cita `StateNode` / `state.gd` como motivo del nombre: hay que
   **reescribirla** (el FSM ya no existe), dejando solo la regla de no colisionar
   `class_name` con autoloads o con `Game.State`.
4. Borrar la nota de Anchorpoint: no hay `.git`, ni `.ap/`, ni `*.approj` en el repo.
5. Agregar el salto de línea final que falta.
6. Mover "Gameplay Mechanics Layers" a `docs/GDD.md` (por su propia regla, el diseño vive
   en `docs/`).

**`README.md`** (hoy 0 bytes): estructura + tabla de controles (`ui_accept` / clic, `pause`)
+ recetas de uso de los 6 autoloads.

**`docs/GDD.md`** y **`docs/TODO.md`**: reescribir para los 7 días / diálogo / barra de
ánimo / 3 finales. Hoy siguen describiendo el prototipo de combate.

**`docs/ART.md`**: **borrar**. Queda huérfano y contradice el foco del prototipo.

**Hecho.** Los 6 ajustes de `AGENTS.md`, y además:

1. El ejemplo de `game_eval` ahora apunta a `/root/Main/DialogueBox` y aclara que el día es
   el primer hijo de `LevelHost` (antes decía `/root/Main/LevelHost/Day01/DialogueBox`).
2. `main.tscn` ya describe sus cuatro piezas: `LevelHost` + `HUD` + `DialogueBox` + `PauseMenu`.
3. "Naming traps" reescrita: ya no cita `StateNode` / `state.gd` (borrados); queda la regla de
   no colisionar `class_name` con autoloads ni con `Game.State`, con la lista concreta.
4. La nota de Anchorpoint se reemplazó por la verdad verificada (no hay `.git`, ni `.ap/`, ni
   `*.approj`; `git` no está en el PATH de este shell). Se conservó ese último dato porque sí
   es cierto y útil.
5. Salto de línea final añadido.
6. "Gameplay Mechanics Layers" se movió a `docs/GDD.md` como "Capas de mecánicas"; en
   `AGENTS.md` queda un puntero corto a `docs/GDD.md` con las acciones de entrada.

Extra (misma clase de desactualización, no listado en el plan): en la tabla de autoloads
`Game` decía "score/mood bar": el `score` se borró en el Paso 11, así que quedó "mood bar,
day/turn progression, pause".

- **`README.md`** (0 bytes → ~200 líneas): pitch, cómo correrlo, tabla de controles
  (`ui_accept` / clic, `pause`), árbol de carpetas real, el bucle dibujado como diagrama, y
  recetas de los 6 autoloads con la API real (`Events.mood_changed`, `Settings.set_bus_volume`,
  `Save.save_game` / `has_save` / `delete_save`, `Audio.register_sfx` / `play_sfx` /
  `play_music`, `SceneLoader.change_scene`, `Game.start_run` / `continue_run` / `start_day` /
  `choose_option` / `next_day`). Cierra con cómo editar el contenido en `assets/data/days.json`
  (tabla clave por clave).
- **`docs/GDD.md`** reescrito: pitch, datos básicos, loop de 4 pasos, capas de mecánicas,
  tabla de números reales (`DAY_COUNT`, `PENALTY_GROWTH` 0.12, `REWARD_DECAY` 0.06,
  `ENDING_BRIGHT_MIN` 70, `ENDING_NEUTRAL_MIN` 40), fórmula de escalado, tabla de los 3
  finales con sus `ending_id` y sus títulos **reales** (sacados de `TITLES` en `ending.gd`,
  no inventados), mapa de dónde vive cada pieza, MVP/stretch/fuera de alcance y referencias.
- **`docs/TODO.md`** reescrito: "Listo" y "Siguiente" hablan de los 7 días / diálogo / ánimo /
  finales; fuera `player`, `enemy_base`, `level_01`, `sandbox`, los componentes de combate y
  `game_over`. La deuda técnica ahora es la real (sin tests, buses de `Audio` en runtime,
  `restart_run()` sin confirmación, sin arte, finales con plantilla compartida).
- **`docs/ART.md`** borrado (`docs/` quedó con 4 archivos: `CREDITS`, `GDD`,
  `IMPLEMENTATION_PLAN`, `TODO`).

**Verificación:** no quedan referencias muertas fuera del propio plan. `grep` de
`StateNode|state.gd|Anchorpoint|Day01|score/mood bar` en `AGENTS.md` solo devuelve la frase
nueva y verdadera sobre Anchorpoint; `grep` de `ART.md|game_over|HealthComponent|player.tscn|enemy_base|sandbox|move_left|jump|attack`
en `*.md` solo devuelve líneas de `IMPLEMENTATION_PLAN.md`, que es el registro histórico de la
construcción (ahí es correcto que aparezcan).

---

### [x] Paso 13 — Verificación final

Con el juego detenido antes de cada escritura, y MCP serializado:

1. `project_run` → `status: "live"`, `ready: true`.
2. `game_eval` con `return` → los 3 checks del Paso 9.4.
3. Partida completa Lunes→Domingo, forzando `Game.mood` para ejercitar los 3 finales.
4. `logs_read source="game"` → cero errores y cero warnings.
5. "Continuar": cerrar a mitad de semana, reabrir, y verificar que restaure
   `current_day` y `mood`.

**Hecho — 5/5 en verde.**

```
1. project_run              -> status=live  ready=true
2. checks del 9.4           -> opciones=3  dia=0  animo=50  turnos=2
                               (y la escena cargada: Day01)
3. semana completa por clics, forzando Game.mood=95 antes del turno de cierre:
                               -> Ending · ending_bright · 7/7 · promedio 99.86
                                  'Una semana distinta'
   semana forzada a cierres de 58  -> ending_bittersweet · 5/7 · promedio 58
                                  'Se sostuvo, a duras penas'
   semana forzada a cierres de 12  -> ending_gloomy     · 0/7 · promedio 12
                                  'La tristeza se acumuló'
   -> los 3 finales ejercitados
4. logs_read source="game"  -> 0 errores, 0 warnings
5. Continuar:
   dia 1 por clics cierra en 69 -> guardado en disco
       { current_day: 0, mood: 69, history: [69], days_passed: 1 }
   stop + project_run (arranque limpio) -> el menu habilita y enfoca "Continuar"
   tras el clic -> Main · Day02 · HUD 'Día 2/7 · Martes'
       current_day=1  history=[69]  days_passed=1
```

**Matiz del punto 5, para que no confunda:** `Game.mood` queda en **50**, no en 69. Es
correcto: `Main._ready()` llama a `Game.start_day()`, que reinicia la barra al `start_mood` del
día (50 en toda la semana) *por diseño* — cada día se juega con la barra llena. Lo que
realmente se restaura es `current_day`, `history` y `days_passed`; el 69 sobrevive ahí, no en
`mood`.

**Nota de método:** una semana entera no entra en un solo `game_eval` (presupuesto duro de
~8 s). Hubo un `EVAL_HUNG` + `EVAL_GAME_NOT_READY` al intentar dos semanas juntas; se resolvió
partiendo cada final en su propia llamada. Quedó documentado en `AGENTS.md`.

Al terminar se borró el guardado de prueba (`Save.delete_save()`) para no dejar la partida a
mitad de semana.

---

## 3. Mapa de dependencias (para que nadie se adelante)

| Paso | Depende de | Qué rompe si se adelanta |
|---|---|---|
| 1-7 | nada | no rompe (todos aditivos) |
| 8 | Paso 5 (`mood_changed`) | HUD sin señal → barra congelada |
| 9 | Pasos 1-8 | **todo lo visual se rompe a mitad de camino** |
| 10 | Paso 9 | `ENDING_SCENE` apunta a un archivo inexistente |
| 11 | Pasos 8-10 | borrar `score` / `PLAYING` / `health_changed` antes de reescribir a sus consumidores (`main.gd`, `hud.gd`, `game_over.gd`) → no compilan y el proyecto no arranca |
| 12-13 | Paso 11 | docs describiendo código que ya cambió |

**Adelantado a pedido del usuario:** el Paso 4 también borró el andamiaje de combate (ver
Paso 11). Se comprobó que nada fuera del propio andamiaje lo referenciaba, así que no movió
el mapa de dependencias: el Paso 11 sigue dependiendo de los Pasos 8-10.

---

## 4. Riesgos conocidos

| Riesgo | Mitigación |
|---|---|
| JSON mal formado rompe el arranque | `DialogueDB.parse()` valida y hace `push_error` con día y turno; nunca crashea |
| Falta un `day_XX.tscn` | `main.gd` loguea y cae al día 1, igual que hacía `load_level()` |
| `class_name` nuevo colisiona | Verificado: `DialogueDB`, `DialogueBox` y `day_scene.gd` (sin `class_name`) no colisionan |
| Escribir con el juego corriendo | `EDITOR_NOT_READY` → pará el juego primero |
| `Identifier not found: <Autoload>` falso | Ignoralo (ver §1.1, regla 10) |
| Ráfagas de MCP | Una llamada a la vez (ver §1.1, regla 1) |
