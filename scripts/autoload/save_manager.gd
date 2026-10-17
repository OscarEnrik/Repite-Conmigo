extends Node
## Autoload: `Save`
## Guardado en un único archivo JSON: user://savegame.json
##
## Para una jam alcanza con un slot. Si necesitás varios, convertí
## SAVE_PATH en un array y agregá un slot_index.
##
## Uso:
##     Save.save_game({"mood": 62, "current_day": 3})
##     var data := Save.load_game()

const SAVE_PATH := "user://savegame.json"

signal saved
signal loaded(data: Dictionary)
signal save_deleted


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(data: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Save: no se pudo abrir %s para escritura." % SAVE_PATH)
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	saved.emit()
	return true


## Devuelve {} si no hay partida o si el archivo está corrupto.
func load_game() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Save: no se pudo abrir %s para lectura." % SAVE_PATH)
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save: %s está corrupto o vacío, se ignora." % SAVE_PATH)
		return {}
	var data: Dictionary = parsed
	loaded.emit(data)
	return data


## Escribe una clave puntual sin tener que cargar y reescribir todo a mano.
func set_value(key: String, value: Variant) -> void:
	var data := load_game()
	data[key] = value
	save_game(data)


func get_value(key: String, default_value: Variant = null) -> Variant:
	var data := load_game()
	return data.get(key, default_value)


func delete_save() -> void:
	if not has_save():
		return
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if error != OK:
		push_warning("Save: no se pudo borrar %s (%s)." % [SAVE_PATH, error_string(error)])
		return
	save_deleted.emit()
