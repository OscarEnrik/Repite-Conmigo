extends Node
## Autoload: `Game`
## Estado global de la semana: en qué pantalla está el juego, el ánimo de Richard,
## en qué día vamos y cómo se cierra la semana.
##
## Uso:
##     Game.start_run()          # semana nueva, arranca en el Lunes
##     Game.start_day(0)         # fija ánimo/turno del día y emite day_started
##     Game.begin_dialog()       # la intro terminó, empiezan los turnos
##     Game.choose_option(1)     # aplica la opción y devuelve el delta real
##     Game.advance_turn()       # turno siguiente, o cierra el día
##     Game.next_day()           # día siguiente, o cierra la semana
##
## También es el único lugar que lee las teclas de pausa y reinicio, así que no
## las dupliques en las escenas.
##
## El guion viene de `assets/data/days.json` y lo carga `DialogueDB`. Si el
## archivo no se pudo leer, `days.day_count()` es 0 y cada `start_day()` avisa.
##
## Reglas del día: `TURNS_PER_DAY` turnos, cada uno con 3 opciones. El ánimo es
## 0..100 y arranca en el `start_mood` del día. Al cerrar el día se guarda en
## `history`; el promedio de `history` decide el final de la semana.

enum State {
	BOOT,
	MENU,
	INTRO,       ## se muestra la desgracia del día
	DIALOGUE,    ## Loretta elige entre las 3 opciones
	DAY_RESULT,  ## resumen del día (superado / se acumula la tristeza)
	PAUSED,
	ENDING,      ## pantalla de final de semana
}

## Días de la semana (Lunes a Jueves).
const DAY_COUNT := 4
## Oportunidades de Loretta por día.
const TURNS_PER_DAY := 2
const MOOD_MIN := 0
const MOOD_MAX := 100
const MOOD_START := 50

## Cuánto crece el daño de una frase mala por día jugado.
const PENALTY_GROWTH := 0.12
## Cuánto se desgasta una frase buena por día jugado.
const REWARD_DECAY := 0.06

## Cortes del final de semana, sobre el promedio de `history`.
const ENDING_BRIGHT_MIN := 70.0
const ENDING_NEUTRAL_MIN := 40.0

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const ENDING_SCENE := "res://scenes/ui/ending.tscn"

signal state_changed(new_state: State)

var state: State = State.BOOT:
	set(value):
		if state == value:
			return
		state = value
		state_changed.emit(state)

# --- Semana ---
## Guion cargado desde `assets/data/days.json`.
var days: DialogueDB
## Ánimo de Richard, 0..100.
var mood: int = MOOD_START
## Día actual, 0 = Lunes.
var current_day: int = 0
## Turno actual dentro del día, 0..TURNS_PER_DAY - 1.
var current_turn: int = 0
## Ánimo al cierre de cada día jugado. Su promedio decide el final.
var history: Array[int] = []
## Días que se superaron (ánimo >= pass_threshold al cierre).
var days_passed: int = 0
## `ending_bright` | `ending_bittersweet` | `ending_gloomy`.
var ending_id: StringName = &""

## Estado al que volver cuando se reanuda la pausa.
var _state_before_pause: State = State.INTRO

## Segundos jugados en la semana. `save_progress()` lo guarda como
## `play_time_seconds`; `_process()` lo acumula mientras se juega un día.
var run_time: float = 0.0


func _ready() -> void:
	# La pausa y el final tienen que seguir funcionando con el árbol pausado.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false

	days = DialogueDB.load_from()
	if days.day_count() == 0:
		push_error("Game: no se pudo cargar el guion de '%s'; la semana se queda sin contenido." % DialogueDB.DATA_PATH)


func _process(delta: float) -> void:
	if state in [State.INTRO, State.DIALOGUE, State.DAY_RESULT]:
		run_time += delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if state == State.PAUSED or _can_pause():
			toggle_pause()
			get_viewport().set_input_as_handled()


# --- Flujo de la semana -----------------------------------------------------

## Arranca una semana nueva desde cero y carga la escena de juego.
func start_run() -> void:
	mood = MOOD_START
	current_day = 0
	current_turn = 0
	history.clear()
	days_passed = 0
	ending_id = &""
	run_time = 0.0

	state = State.INTRO
	Events.game_started.emit()
	SceneLoader.change_scene(GAME_SCENE)


func restart_run() -> void:
	get_tree().paused = false
	start_run()


## Retoma la semana guardada.
##
## El guardado se hace al cerrar un día, así que `history` ya incluye el último
## jugado: se retoma en el **siguiente** (`history.size()`), no se repite.
func continue_run() -> void:
	get_tree().paused = false
	load_progress()

	if history.size() >= DAY_COUNT:
		# La semana ya estaba completa: directo al final.
		finish_week()
		return

	current_day = history.size()
	current_turn = 0
	state = State.INTRO
	Events.game_started.emit()
	SceneLoader.change_scene(GAME_SCENE)


func go_to_menu() -> void:
	get_tree().paused = false
	state = State.MENU
	Events.game_returned_to_menu.emit()
	SceneLoader.change_scene(MAIN_MENU_SCENE)


## Fija ánimo y turno del día `index` y avisa por `day_started`. `main.gd`
## escucha esa señal para cargar la escena del día dentro de `LevelHost`.
func start_day(index: int) -> void:
	var data: Dictionary = days.get_day(index)
	if data.is_empty():
		push_error("Game: no hay datos para el día %d (¿falló la carga de '%s'?)." % [index + 1, DialogueDB.DATA_PATH])
		return

	current_day = index
	current_turn = 0
	mood = clampi(int(data.get("start_mood", MOOD_START)), MOOD_MIN, MOOD_MAX)
	state = State.INTRO
	Events.day_started.emit(current_day, String(data.get("title", "")))


## La intro del día terminó: empiezan los turnos de diálogo.
func begin_dialog() -> void:
	if state != State.INTRO:
		return
	state = State.DIALOGUE
	Events.dialogue_turn_started.emit(current_day, current_turn)


## Turno actual: `{ prompt, options }`.
func current_turn_data() -> Dictionary:
	return days.get_turn(current_day, current_turn)


## Opción `i` del turno actual: `{ text, kind, mood }`.
func option_at(i: int) -> Dictionary:
	return days.option_at(current_day, current_turn, i)


## Aplica la opción elegida y devuelve el delta YA escalado por el día.
func choose_option(i: int) -> int:
	var option: Dictionary = option_at(i)
	if option.is_empty():
		push_error("Game: no existe la opción %d del día %d, turno %d." % [i, current_day + 1, current_turn + 1])
		return 0

	var kind := StringName(option.get("kind", &""))
	var delta := difficulty_scale(int(option.get("mood", 0)))
	apply_mood(delta)
	Events.option_chosen.emit(i, kind, delta)
	return delta


## Suma (o resta) ánimo y avisa siempre, incluso si el clamp dejó el valor
## igual: la UI necesita refrescar de todos modos.
## Ojo: `delta` es el cambio pedido. Si el ánimo ya estaba en 0 o en 100, el
## clamp absorbe parte y `mood` se mueve menos que `delta`.
func apply_mood(delta: int) -> void:
	if delta == 0:
		return
	mood = clampi(mood + delta, MOOD_MIN, MOOD_MAX)
	Events.mood_changed.emit(mood, delta)


## Pasa al turno siguiente, o cierra el día si ya no quedan.
func advance_turn() -> void:
	if current_turn + 1 < TURNS_PER_DAY:
		current_turn += 1
		Events.dialogue_turn_started.emit(current_day, current_turn)
	else:
		finish_day()


## Cierra el día: registra el ánimo, lo compara con el umbral y avisa.
## Devuelve true si el día se superó.
func finish_day() -> bool:
	var data: Dictionary = days.get_day(current_day)
	var threshold := int(data.get("pass_threshold", MOOD_START))
	var passed := mood >= threshold

	history.append(mood)
	if passed:
		days_passed += 1

	state = State.DAY_RESULT
	save_progress()
	Events.day_finished.emit(current_day, passed)
	return passed


## Avanza al día siguiente, o cierra la semana si era el último (el jueves).
func next_day() -> void:
	if current_day + 1 >= DAY_COUNT:
		finish_week()
		return
	start_day(current_day + 1)


## Cierra la semana: el promedio de `history` decide el final.
func finish_week() -> StringName:
	ending_id = _evaluate_ending()
	state = State.ENDING
	save_progress()
	Events.week_finished.emit(ending_id)
	SceneLoader.change_scene(ENDING_SCENE)
	return ending_id


## Escala un delta del guion según el día: más avanzada la semana, lo hiriente
## pega más fuerte y lo bueno rinde menos.
func difficulty_scale(delta: int) -> int:
	if delta < 0:
		return roundi(delta * (1.0 + PENALTY_GROWTH * current_day))
	if delta > 0:
		return roundi(delta * (1.0 - REWARD_DECAY * current_day))
	return 0


## Promedio del ánimo al cierre de cada día. Sin días jugados, el ánimo actual.
func average_mood() -> float:
	if history.is_empty():
		return float(mood)
	var total := 0
	for value in history:
		total += value
	return float(total) / float(history.size())


func _evaluate_ending() -> StringName:
	var average := average_mood()
	if average >= ENDING_BRIGHT_MIN:
		return &"ending_bright"
	if average >= ENDING_NEUTRAL_MIN:
		return &"ending_bittersweet"
	return &"ending_gloomy"


# --- Guardado ---------------------------------------------------------------

## Guarda la semana en un solo write (ver `GameData`).
func save_progress() -> void:
	var data := GameData.new()
	data.mood = mood
	data.current_day = current_day
	data.days_passed = days_passed
	data.play_time_seconds = run_time
	var stored: Array[int] = history.duplicate()
	data.history = stored
	Save.save_game(data.to_dict())


## Restaura la semana guardada. No decide si hay partida: eso lo hace
## `Save.has_save()` desde el menú.
func load_progress() -> void:
	var data := GameData.from_dict(Save.load_game())
	mood = data.mood
	current_day = data.current_day
	days_passed = data.days_passed
	run_time = data.play_time_seconds
	var stored: Array[int] = data.history.duplicate()
	history = stored
	current_turn = 0
	ending_id = &""


func quit_game() -> void:
	Settings.save_settings()
	get_tree().quit()


# --- Pausa ------------------------------------------------------------------

func toggle_pause() -> void:
	if state == State.PAUSED:
		resume_game()
	elif _can_pause():
		pause_game()


func pause_game() -> void:
	if not _can_pause():
		return
	_state_before_pause = state
	get_tree().paused = true
	state = State.PAUSED
	Events.game_paused.emit()


func resume_game() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	state = _state_before_pause
	Events.game_resumed.emit()


## Se puede pausar mientras se juega un día, no en el menú ni en el final.
func _can_pause() -> bool:
	match state:
		State.INTRO, State.DIALOGUE, State.DAY_RESULT:
			return true
		_:
			return false

