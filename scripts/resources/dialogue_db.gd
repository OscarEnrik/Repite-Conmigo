class_name DialogueDB
extends RefCounted
## Base de datos de diálogos: carga y valida `assets/data/days.json`.
##
## Uso:
##     var days := DialogueDB.load_from()
##     if days.day_count() == 0:
##         push_error("no se pudo cargar el guion")
##
## El archivo define los 4 días de la semana. Cada día trae una intro de Richard y
## `EXPECTED_TURNS` turnos, y cada turno `EXPECTED_OPTIONS` opciones con la forma
## `{ "text": String, "kind": "choke" | "motivate" | "sound", "mood": int }`.
##
## Los accesos NUNCA devuelven null: si pedís un día, turno u opción que no
## existe, devuelven `{}` para que la UI no crashee. Los problemas de forma se
## reportan con `push_error` al cargar, nombrando el día y el turno exactos.
##
## Política de errores: si el archivo falta, no se abre o el JSON es ilegible, la
## base queda **vacía** (`day_count() == 0`) y el juego decide qué hacer. Si el
## JSON es legible pero tiene la forma mal (faltan campos, sobran opciones), se
## avisa con `push_error` y **igual se carga** lo que haya: en una jam conviene
## degradar y seguir, no negarse a arrancar.

## Ruta por defecto del guion.
const DATA_PATH := "res://assets/data/days.json"

## Forma esperada. Si el contenido no la cumple, `_validate()` avisa.
const EXPECTED_DAYS := 4
const EXPECTED_TURNS := 2
const EXPECTED_OPTIONS := 3

## Tipos de respuesta de Loretta. Cada turno debe tener exactamente uno de cada.
const VALID_KINDS: Array[StringName] = [&"choke", &"motivate", &"sound"]

## Lista cruda de días, tal como viene del JSON.
var _days: Array = []


## Carga el guion desde `path`. Es el único punto de entrada.
static func load_from(path: String = DATA_PATH) -> DialogueDB:
	var db := DialogueDB.new()
	db._load(path)
	return db


## Cantidad de días cargados (0 si el archivo no se pudo leer).
func day_count() -> int:
	return _days.size()


## Día completo: `{ day, title, start_mood, pass_threshold, richard_intro, turns }`.
func get_day(index: int) -> Dictionary:
	if index < 0 or index >= _days.size():
		return {}
	return _as_dictionary(_days[index])


## Turno: `{ prompt, options }`.
func get_turn(day: int, turn: int) -> Dictionary:
	var turns: Variant = get_day(day).get("turns")
	if typeof(turns) != TYPE_ARRAY:
		return {}
	var turn_list: Array = turns
	if turn < 0 or turn >= turn_list.size():
		return {}
	return _as_dictionary(turn_list[turn])


## Opción: `{ text, kind, mood }`.
func option_at(day: int, turn: int, option: int) -> Dictionary:
	var options: Variant = get_turn(day, turn).get("options")
	if typeof(options) != TYPE_ARRAY:
		return {}
	var option_list: Array = options
	if option < 0 or option >= option_list.size():
		return {}
	return _as_dictionary(option_list[option])


# --- Carga ------------------------------------------------------------------

func _load(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("DialogueDB: no existe '%s'." % path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DialogueDB: no se pudo abrir '%s' (%s)." % [path, error_string(FileAccess.get_open_error())])
		return false
	var text := file.get_as_text()
	file.close()

	# JSON.new() en vez de JSON.parse_string(): así tenemos mensaje y línea del
	# error, igual que hacemos con error_string() en el resto del proyecto.
	var json := JSON.new()
	if json.parse(text) != OK:
		# get_error_line() es 0-based: +1 para que el log diga la línea que ve el humano.
		push_error("DialogueDB: '%s' no es JSON válido (%s, línea %d)." % [path, json.get_error_message(), json.get_error_line() + 1])
		return false

	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("DialogueDB: la raíz de '%s' debería ser un objeto JSON." % path)
		return false
	var root: Dictionary = json.data

	var raw_days: Variant = root.get("days")
	if typeof(raw_days) != TYPE_ARRAY:
		push_error("DialogueDB: falta la lista 'days' en '%s'." % path)
		return false

	var parsed_days: Array = raw_days
	if parsed_days.is_empty():
		push_error("DialogueDB: la lista 'days' de '%s' está vacía." % path)
		return false

	_days = parsed_days
	_validate()
	return true


# --- Validación -------------------------------------------------------------

## Revisa la forma del guion y avisa por `push_error`. No borra datos: el juego
## sigue andando con lo que haya.
func _validate() -> void:
	if _days.size() != EXPECTED_DAYS:
		push_error("DialogueDB: se esperaban %d días, hay %d." % [EXPECTED_DAYS, _days.size()])

	for d in _days.size():
		var day := _as_dictionary(_days[d])
		var label := "el día %d" % (d + 1)
		if day.is_empty():
			push_error("DialogueDB: %s no es un objeto JSON." % label)
			continue

		for key in ["title", "richard_intro"]:
			if String(day.get(key, "")).strip_edges().is_empty():
				push_error("DialogueDB: a %s le falta '%s'." % [label, key])
		for key in ["start_mood", "pass_threshold"]:
			if not _is_number(day.get(key)):
				push_error("DialogueDB: %s no tiene '%s' numérico." % [label, key])

		var turns: Variant = day.get("turns")
		if typeof(turns) != TYPE_ARRAY:
			push_error("DialogueDB: %s no tiene la lista 'turns'." % label)
			continue
		var turn_list: Array = turns
		if turn_list.size() != EXPECTED_TURNS:
			push_error("DialogueDB: %s debería tener %d turnos, tiene %d." % [label, EXPECTED_TURNS, turn_list.size()])
		for t in turn_list.size():
			_validate_turn(d, t, turn_list[t])


func _validate_turn(day_index: int, turn_index: int, turn: Variant) -> void:
	var where := "día %d, turno %d" % [day_index + 1, turn_index + 1]
	var turn_dict := _as_dictionary(turn)
	if turn_dict.is_empty():
		push_error("DialogueDB: el %s no es un objeto JSON." % where)
		return

	if String(turn_dict.get("prompt", "")).strip_edges().is_empty():
		push_error("DialogueDB: al %s le falta 'prompt'." % where)

	var options: Variant = turn_dict.get("options")
	if typeof(options) != TYPE_ARRAY:
		push_error("DialogueDB: al %s le falta la lista 'options'." % where)
		return
	var option_list: Array = options
	if option_list.size() != EXPECTED_OPTIONS:
		push_error("DialogueDB: el %s debería tener %d opciones, tiene %d." % [where, EXPECTED_OPTIONS, option_list.size()])

	var seen: Array[StringName] = []
	for i in option_list.size():
		var option := _as_dictionary(option_list[i])
		var owhere := "%s, opción %d" % [where, i + 1]
		if option.is_empty():
			push_error("DialogueDB: la %s no es un objeto JSON." % owhere)
			continue

		if String(option.get("text", "")).strip_edges().is_empty():
			push_error("DialogueDB: la %s no tiene 'text'." % owhere)
		if not _is_number(option.get("mood")):
			push_error("DialogueDB: la %s no tiene 'mood' numérico." % owhere)

		var kind := StringName(option.get("kind", &""))
		if not VALID_KINDS.has(kind):
			push_error("DialogueDB: la %s tiene kind '%s' (válidos: %s)." % [owhere, kind, str(VALID_KINDS)])
		elif seen.has(kind):
			push_error("DialogueDB: el %s repite el kind '%s'." % [where, kind])
		else:
			seen.append(kind)

	for kind in VALID_KINDS:
		if not seen.has(kind):
			push_error("DialogueDB: al %s le falta la opción '%s'." % [where, kind])


# --- Utilidades -------------------------------------------------------------

## Devuelve el valor solo si es un Dictionary; si no, `{}`.
func _as_dictionary(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
