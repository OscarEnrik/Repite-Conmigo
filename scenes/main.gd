extends Node
## Escena raíz del juego (res://scenes/main.tscn).
## Mantiene vivos el HUD y la caja de diálogo mientras las escenas de día se
## cargan y se descargan dentro de `LevelHost`.
##
## Flujo: boot.tscn -> main_menu.tscn -> main.tscn -> ending.tscn
##
## Reparto de responsabilidades: `Game` decide qué día toca y avisa por
## `Events.day_started`; `Main` solo instancia la escena de ese día. Quién pide el
## día siguiente es `DialogueBox` (`Game.next_day()`), no este script.

@onready var _level_host: Node2D = %LevelHost
@onready var _pause_menu: CanvasLayer = %PauseMenu

var _current_day: Node = null


func _ready() -> void:
	_pause_menu.visible = false
	Events.game_paused.connect(_on_game_paused)
	Events.game_resumed.connect(_on_game_resumed)
	Events.day_started.connect(_on_day_started)

	# `start_day()` emite `day_started`, así que la primera escena del día la
	# carga el mismo camino que las demás (una sola ruta, sin caso especial).
	Game.start_day(Game.current_day)


## Carga la escena del día `index` (0 = Lunes) dentro de `LevelHost`.
func load_day(index: int) -> void:
	var path := "res://scenes/levels/day_%02d.tscn" % (index + 1)
	if not ResourceLoader.exists(path):
		push_warning("Main: no existe '%s'." % path)
		return

	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Main: '%s' no es una escena válida." % path)
		return

	if _current_day != null:
		_current_day.queue_free()
		_current_day = null
		# Un frame de espera para que el día viejo termine de liberarse y no
		# queden dos días vivos al mismo tiempo (con sus conexiones a `Events`).
		await get_tree().process_frame

	_current_day = packed.instantiate()
	_level_host.add_child(_current_day)


func _on_day_started(index: int, _title: String) -> void:
	load_day(index)


func _on_game_paused() -> void:
	_pause_menu.visible = true


func _on_game_resumed() -> void:
	_pause_menu.visible = false
