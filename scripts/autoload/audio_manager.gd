extends Node
## Autoload: `Audio`
## Música y efectos de sonido sin tener que poner un AudioStreamPlayer
## en cada escena.
##
## Uso:
##     Audio.register_sfx(&"jump", preload("res://assets/audio/sfx/jump.ogg"))
##     Audio.play_sfx(&"jump")
##     Audio.play_sfx(&"hit", global_position)   # con atenuación por distancia
##     Audio.play_music(&"main_theme")
##     Audio.stop_music()
##
## Los callbacks devuelven push_warning si pedís un id que no registraste,
## así te enterás en vez de quedarte en silencio.

const SFX_VOICES := 12
const MUSIC_FADE_TIME := 0.8
const DISTANCE_FALLOFF_PX := 600.0

## Cargá los sonidos desde un script de arranque, o a mano en el inspector
## de un .tres. Ejemplo: en boot.gd, Audio.register_sfx(&"click", preload(...))
var sfx_library: Dictionary = {}
var music_library: Dictionary = {}

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_index: int = 0
var _music_player: AudioStreamPlayer
var _current_music: StringName = &""


func _ready() -> void:
	# Los buses "Music" y "SFX" no existen en un proyecto nuevo: los creamos.
	# Si preferís verlos en el editor, guardá un default_bus_layout.tres y
	# exportá los mismos nombres; esta función los detecta y no hace nada.
	_ensure_bus(&"Music")
	_ensure_bus(&"SFX")

	for i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_sfx_players.append(player)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	add_child(_music_player)

	Events.sfx_requested.connect(_on_sfx_requested)


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")


func register_sfx(id: StringName, stream: AudioStream) -> void:
	sfx_library[id] = stream


func register_music(id: StringName, stream: AudioStream) -> void:
	music_library[id] = stream


## Si pasás world_position, el volumen baja según la distancia a la cámara.
func play_sfx(id: StringName, world_position: Variant = null) -> void:
	if _sfx_players.is_empty():
		return
	var stream := sfx_library.get(id) as AudioStream
	if stream == null:
		push_warning("Audio: el sfx '%s' no está registrado." % id)
		return

	var player := _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % _sfx_players.size()

	player.stream = stream
	player.volume_db = 0.0
	if world_position is Vector2:
		var position_2d: Vector2 = world_position
		var distance := 0.0
		var camera := get_viewport().get_camera_2d()
		if camera != null:
			distance = camera.global_position.distance_to(position_2d)
		var falloff := clampf(1.0 - distance / DISTANCE_FALLOFF_PX, 0.0, 1.0)
		player.volume_db = linear_to_db(maxf(falloff, 0.001))
	player.play()


func play_music(id: StringName, fade_time: float = MUSIC_FADE_TIME) -> void:
	if _music_player == null:
		return
	if id == _current_music and _music_player.playing:
		return
	var stream := music_library.get(id) as AudioStream
	if stream == null:
		push_warning("Audio: la música '%s' no está registrada." % id)
		return
	_current_music = id

	var tween := create_tween()
	if _music_player.playing:
		tween.tween_property(_music_player, "volume_db", -60.0, fade_time * 0.5)
		tween.tween_callback(func() -> void:
			_music_player.stream = stream
			_music_player.play())
		tween.tween_property(_music_player, "volume_db", 0.0, fade_time * 0.5)
	else:
		_music_player.stream = stream
		_music_player.volume_db = -60.0
		_music_player.play()
		tween.tween_property(_music_player, "volume_db", 0.0, fade_time)


func stop_music(fade_time: float = MUSIC_FADE_TIME) -> void:
	if _music_player == null or not _music_player.playing:
		return
	_current_music = &""
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -60.0, fade_time)
	tween.tween_callback(_music_player.stop)


func is_music_playing(id: StringName) -> bool:
	return id == _current_music and _music_player != null and _music_player.playing


func _on_sfx_requested(sfx_id: StringName, position: Vector2) -> void:
	play_sfx(sfx_id, position)
