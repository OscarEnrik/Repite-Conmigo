extends Control
## Pantalla de arranque (es la main scene del proyecto).
## Aplica las preferencias, precarga lo pesado y salta al menú principal.
##
## Reemplazá el label por tu logo o splash cuando exista arte.

const NEXT_SCENE := "res://scenes/ui/main_menu.tscn"

## Escenas que conviene tener en caché antes del primer cambio de escena.
const PRELOAD_SCENES := [
	"res://scenes/main.tscn",
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/ending.tscn",
	"res://scenes/levels/day_01.tscn",
]

## Tiempo mínimo en pantalla para que el splash no parpadee.
const MINIMUM_SPLASH_TIME := 0.5

@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	Settings.apply()
	var started_at := Time.get_ticks_msec()

	_status_label.text = "Cargando..."
	await _preload_all()

	var elapsed := (Time.get_ticks_msec() - started_at) / 1000.0
	var remaining := MINIMUM_SPLASH_TIME - elapsed
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout

	SceneLoader.change_scene(NEXT_SCENE)


func _preload_all() -> void:
	for entry in PRELOAD_SCENES:
		var path := String(entry)
		if not ResourceLoader.exists(path):
			push_warning("Boot: no existe '%s', se omite del precargado." % path)
			continue
		ResourceLoader.load_threaded_request(path)
		var status := ResourceLoader.load_threaded_get_status(path)
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			status = ResourceLoader.load_threaded_get_status(path)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			push_warning("Boot: falló la carga de '%s'." % path)
