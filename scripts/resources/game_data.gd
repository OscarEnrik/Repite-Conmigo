class_name GameData
extends Resource
## Snapshot serializable de la semana jugada. Es lo que guarda y carga `Save`.
##
## Regla: solo datos planos (int, float, String, Array, Dictionary), para que la
## conversión a JSON no se queje.
##
## Uso:
##     Save.save_game(data.to_dict())
##     var data := GameData.from_dict(Save.load_game())
##
## `from_dict()` castea cada valor a mano: un guardado viejo, incompleto o con
## basura no rompe el arranque, cae en los valores por defecto. Un guardado con
## el formato anterior del proyecto (claves `score` / `current_level`) se ignora
## por completo: la semana arranca de cero.

@export var mood: int = 50
@export var current_day: int = 0
@export var days_passed: int = 0
@export var play_time_seconds: float = 0.0
## Ánimo al cierre de cada día jugado. Su promedio decide el final.
@export var history: Array[int] = []


func to_dict() -> Dictionary:
	return {
		"mood": mood,
		"current_day": current_day,
		"days_passed": days_passed,
		"play_time_seconds": play_time_seconds,
		"history": history.duplicate(),
	}


static func from_dict(data: Dictionary) -> GameData:
	var game_data := GameData.new()
	game_data.mood = _to_int(data.get("mood"), game_data.mood)
	game_data.current_day = _to_int(data.get("current_day"), game_data.current_day)
	game_data.days_passed = _to_int(data.get("days_passed"), game_data.days_passed)
	game_data.play_time_seconds = _to_float(data.get("play_time_seconds"), game_data.play_time_seconds)

	var raw_history: Variant = data.get("history")
	if typeof(raw_history) == TYPE_ARRAY:
		for value in raw_history:
			if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
				game_data.history.append(int(value))

	return game_data


# --- Conversión defensiva ---------------------------------------------------

## Int desde JSON. Acepta int/float/bool y String numérico; cualquier otra cosa
## (null, Dictionary, Array, texto) cae en `fallback`.
static func _to_int(value: Variant, fallback: int = 0) -> int:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return int(value)
		TYPE_STRING:
			return int(value) if String(value).is_valid_int() else fallback
		_:
			return fallback


## Float desde JSON, con la misma tolerancia que `_to_int`.
static func _to_float(value: Variant, fallback: float = 0.0) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return float(value)
		TYPE_STRING:
			return float(value) if String(value).is_valid_float() else fallback
		_:
			return fallback
