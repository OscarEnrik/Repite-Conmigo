extends Node
## Escena raíz del juego (res://scenes/main.tscn).
## Mantiene vivos el HUD, la caja de diálogo y el reproductor de animatics
## mientras las escenas de día se cargan y se descargan dentro de `LevelHost`.
##
## Flujo: boot.tscn -> main_menu.tscn -> main.tscn -> ending.tscn
##
## Reparto de responsabilidades: `Game` decide qué día toca y avisa por
## `Events.day_started`; `Main` hace el fundido entre días, instancia la escena
## de ese día y dispara el animatic (`1.png`..`4.png`) si el día tiene carpeta
## en `res://assets/art/animatics/day%02d/`.

@onready var _level_host: Node2D = %LevelHost
@onready var _animatic_player: AnimaticPlayer = %AnimaticPlayer
@onready var _pause_menu: CanvasLayer = %PauseMenu

var _current_day: Node = null
var _load_token: int = 0


func _ready() -> void:
	_pause_menu.visible = false
	Events.game_paused.connect(_on_game_paused)
	Events.game_resumed.connect(_on_game_resumed)
	Events.day_started.connect(_on_day_started)

	# `start_day()` emite `day_started`, así que la primera escena del día la
	# carga el mismo camino que las demás (una sola ruta, sin caso especial).
	Game.start_day(Game.current_day)


## Carga la escena del día `index` (0 = Lunes) dentro de `LevelHost`.
## Si venimos de otro día, funde a negro antes de cambiar y levanta el telón
## con el animatic del nuevo día (o con el escenario si ese día no tiene viñetas).
func load_day(index: int) -> void:
	var path := "res://scenes/levels/day_%02d.tscn" % (index + 1)
	if not ResourceLoader.exists(path):
		push_warning("Main: no existe '%s'." % path)
		return

	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Main: '%s' no es una escena válida." % path)
		return

	_load_token += 1
	var token := _load_token
	var with_fade := _current_day != null and not SceneLoader.is_transitioning

	if with_fade:
		await SceneLoader.fade_out()
		if token != _load_token or not is_inside_tree():
			return

	if not _level_host.get_children().is_empty():
		for child in _level_host.get_children():
			child.queue_free()
		_current_day = null
		# Un frame de espera para que el día viejo termine de liberarse y no
		# queden dos días vivos al mismo tiempo (con sus conexiones a `Events`).
		await get_tree().process_frame
		if token != _load_token or not is_inside_tree():
			return

	_current_day = packed.instantiate()
	_level_host.add_child(_current_day)
	_animatic_player.play_for_day(index)

	if with_fade:
		await SceneLoader.fade_in()


func _on_day_started(index: int, _title: String) -> void:
	load_day(index)


func _on_game_paused() -> void:
	_pause_menu.visible = true


func _on_game_resumed() -> void:
	_pause_menu.visible = false
