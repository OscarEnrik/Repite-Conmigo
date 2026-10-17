class_name DayStage
extends Control
## Escenario de espera de un día (res://scenes/levels/day_stage.tscn).
##
## Se instancia dentro del `CanvasLayer` `UI` de cada `day_XX.tscn`, delante del
## `Background` y detrás de la `IntroCard` (el orden de hermanos es el orden de
## dibujo). Reemplaza el arranque viejo, donde la tarjeta del día aparecía sola:
## ahora Richard deambula por el escenario y hay que clickearlo para que la tarjeta
## aparezca. `day_scene.gd` escucha `clicked`.
##
## Deambular es 100% código: este script nunca lee input de movimiento. `_process`
## manda `%Walker` a un destino al azar dentro de `roam_rect`, espera un rato y
## elige otro. Va en `_process` heredado, así que pausar el juego lo congela solo.
##
## El dibujo lo pone `%AnimatedSprite` (los SpriteFrames se cargan aparte: el
## proyecto todavía no tiene arte). Mientras no haya frames se ve el
## `PlaceholderVisual`, que se puede borrar sin tocar código. Un
## `AnimatedSprite2D` sin frames que recibe `play()` tira error, por eso `_play()`
## chequea antes.
##
## `stop()` lo llama `day_scene.gd` cuando la tarjeta ya se reveló: congela a
## Richard donde está (queda detrás de la tarjeta) y saca la pista de la pantalla.

## El jugador clickeó al personaje. Lo escucha `day_scene.gd`.
signal clicked

## Banda por la que deambula, en coordenadas de lienzo (1920x1080).
@export var roam_rect: Rect2 = Rect2(160.0, 140.0, 1600.0, 480.0)
## Mitad del ancho y del alto del personaje: lo mantiene entero dentro de la banda.
@export var half_extents: Vector2 = Vector2(90.0, 180.0)
@export var speed: float = 220.0
## Pausa entre un destino y el siguiente (mínimo, máximo), en segundos.
@export var idle_time_range: Vector2 = Vector2(0.4, 1.2)
## Semilla fija: dos corridas deambulan igual (y la verificación es reproducible).
@export var rng_seed: int = 20261017
## Nombres de las animaciones del personaje: si los cambiás, no hace falta tocar código.
@export var idle_animation: StringName = &"idle"
@export var walk_animation: StringName = &"walk"

enum Phase { IDLE, WALK }

@onready var _walker: Node2D = %Walker
@onready var _animated_sprite: AnimatedSprite2D = %AnimatedSprite
@onready var _hit_area: Area2D = %HitArea
@onready var _hint_label: Label = %HintLabel

var _phase: Phase = Phase.IDLE
var _target: Vector2 = Vector2.ZERO
var _wait_left: float = 0.0
var _stopped: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = rng_seed

	# El picking de física (de donde sale Area2D.input_event) viene apagado por
	# defecto en el viewport.
	var viewport := get_viewport()
	if viewport != null:
		viewport.physics_object_picking = true

	_walker.position = _random_point()
	_hit_area.input_event.connect(_on_hit_area_input_event)
	_hit_area.mouse_entered.connect(_on_hit_area_mouse_entered)
	_hit_area.mouse_exited.connect(_on_hit_area_mouse_exited)
	_go_idle()


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _process(delta: float) -> void:
	if _stopped:
		return

	if _phase == Phase.IDLE:
		_wait_left -= delta
		if _wait_left <= 0.0:
			_start_walk()
		return

	var offset := _target - _walker.position
	var step := speed * delta
	if offset.length() <= step:
		_walker.position = _target
		_go_idle()
		return

	_walker.position += offset.normalized() * step
	if absf(offset.x) > 1.0:
		_animated_sprite.flip_h = offset.x < 0.0


## Congela a Richard donde está, lo deja en reposo y saca la pista de la pantalla.
func stop() -> void:
	if _stopped:
		return
	_stopped = true
	_phase = Phase.IDLE
	_play(idle_animation)
	_hint_label.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _go_idle() -> void:
	_phase = Phase.IDLE
	_wait_left = _rng.randf_range(
		minf(idle_time_range.x, idle_time_range.y),
		maxf(idle_time_range.x, idle_time_range.y),
	)
	_play(idle_animation)


func _start_walk() -> void:
	_phase = Phase.WALK
	_target = _random_point()
	_play(walk_animation)


## Punto al azar de la banda, ya descontada la mitad del personaje para que no se
## salga de ella.
func _random_point() -> Vector2:
	var x_min := roam_rect.position.x + half_extents.x
	var x_max := roam_rect.end.x - half_extents.x
	var y_min := roam_rect.position.y + half_extents.y
	var y_max := roam_rect.end.y - half_extents.y
	return Vector2(
		_rng.randf_range(minf(x_min, x_max), maxf(x_min, x_max)),
		_rng.randf_range(minf(y_min, y_max), maxf(y_min, y_max)),
	)


## Solo llama a `play()` si la animación existe: con los SpriteFrames vacíos, un
## `AnimatedSprite2D` que recibe `play()` escribe un error en consola.
func _play(animation: StringName) -> void:
	var frames := _animated_sprite.sprite_frames
	if frames == null or not frames.has_animation(animation):
		return
	if _animated_sprite.animation != animation or not _animated_sprite.is_playing():
		_animated_sprite.play(animation)


func _on_hit_area_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if _stopped:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()


func _on_hit_area_mouse_entered() -> void:
	if not _stopped:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


func _on_hit_area_mouse_exited() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
