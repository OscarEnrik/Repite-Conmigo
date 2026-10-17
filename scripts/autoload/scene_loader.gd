extends Node
## Autoload: `SceneLoader`
## Cambio de escena con fundido, para no cortar en seco entre pantallas.
##
## Uso:
##     SceneLoader.change_scene("res://scenes/main.tscn")
##     SceneLoader.reload_scene()
##     await SceneLoader.fade_out()
##
## El overlay se construye por código: no depende de ninguna escena, así que
## funciona incluso antes de cargar el menú.

const FADE_TIME := 0.3
const FADE_LAYER := 128
const FADE_COLOR := Color(0.05, 0.04, 0.08, 1.0)

var _overlay: ColorRect
var is_transitioning: bool = false


func _ready() -> void:
	# PROCESS_MODE_ALWAYS para que el fundido funcione aunque el juego esté en pausa.
	process_mode = Node.PROCESS_MODE_ALWAYS

	var layer := CanvasLayer.new()
	layer.layer = FADE_LAYER
	add_child(layer)

	_overlay = ColorRect.new()
	_overlay.color = FADE_COLOR
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.offset_right = 0.0
	_overlay.offset_bottom = 0.0
	_overlay.modulate.a = 0.0
	_overlay.visible = false
	layer.add_child(_overlay)


## Cambia de escena con fundido. Es una corrutina: si querés esperar a que
## termine, usá `await SceneLoader.change_scene(...)`.
func change_scene(scene_path: String, fade_time: float = FADE_TIME) -> void:
	if is_transitioning:
		push_warning("SceneLoader: ya hay una transición en curso, se ignora '%s'." % scene_path)
		return
	if not ResourceLoader.exists(scene_path):
		push_error("SceneLoader: no existe la escena '%s'." % scene_path)
		return

	is_transitioning = true
	get_tree().paused = false
	await fade_out(fade_time)

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("SceneLoader: falló el cambio a '%s' (%s)." % [scene_path, error_string(error)])

	await get_tree().process_frame
	await fade_in(fade_time)
	is_transitioning = false


## Recarga la escena actual. Ideal para reiniciar un nivel.
func reload_scene(fade_time: float = FADE_TIME) -> void:
	var current := get_tree().current_scene
	if current == null:
		push_warning("SceneLoader: no hay escena actual para recargar.")
		return
	change_scene(current.scene_file_path, fade_time)


func fade_out(duration: float = FADE_TIME) -> void:
	if _overlay == null:
		return
	_overlay.visible = true
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 1.0, duration)
	await tween.finished


func fade_in(duration: float = FADE_TIME) -> void:
	if _overlay == null:
		return
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 0.0, duration)
	await tween.finished
	_overlay.visible = false
