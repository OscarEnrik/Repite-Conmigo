extends Node
## Autoload: `Settings`
## Preferencias del jugador, persistidas en user://settings.cfg
##
## Aplica el volumen sobre los buses de audio y el modo de pantalla.
## Si agregás una opción nueva (idioma, escala de UI, vibración), sumala
## a las cuatro funciones: load, save, apply y el setter público.

const CONFIG_PATH := "user://settings.cfg"

const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"

## Valores por defecto si todavía no existe el archivo de config.
var master_volume: float = 0.8
var music_volume: float = 0.7
var sfx_volume: float = 0.9
var fullscreen: bool = false
var language: String = "es"


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return  # Primera ejecución: quedan los valores por defecto.
	master_volume = float(config.get_value("audio", "master_volume", master_volume))
	music_volume = float(config.get_value("audio", "music_volume", music_volume))
	sfx_volume = float(config.get_value("audio", "sfx_volume", sfx_volume))
	fullscreen = bool(config.get_value("video", "fullscreen", fullscreen))
	language = str(config.get_value("game", "language", language))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("game", "language", language)
	var error := config.save(CONFIG_PATH)
	if error != OK:
		push_warning("Settings: no se pudo guardar %s (%s)." % [CONFIG_PATH, error_string(error)])


## Vuelca todos los valores a los sistemas reales (audio, pantalla).
func apply() -> void:
	set_bus_volume(BUS_MASTER, master_volume)
	set_bus_volume(BUS_MUSIC, music_volume)
	set_bus_volume(BUS_SFX, sfx_volume)
	apply_fullscreen(fullscreen)


func set_bus_volume(bus_name: StringName, linear_volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	linear_volume = clampf(linear_volume, 0.0, 1.0)
	AudioServer.set_bus_mute(index, linear_volume <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear_volume, 0.001)))


func apply_fullscreen(enabled: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


## kind acepta "master", "music" o "sfx". Guarda el archivo al instante.
func set_audio_volume(kind: StringName, value: float) -> void:
	match kind:
		&"music":
			music_volume = clampf(value, 0.0, 1.0)
			set_bus_volume(BUS_MUSIC, music_volume)
		&"sfx":
			sfx_volume = clampf(value, 0.0, 1.0)
			set_bus_volume(BUS_SFX, sfx_volume)
		_:
			master_volume = clampf(value, 0.0, 1.0)
			set_bus_volume(BUS_MASTER, master_volume)
	save_settings()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	apply_fullscreen(enabled)
	save_settings()
