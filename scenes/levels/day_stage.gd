class_name DayStage
extends Control
## Escenario de espera de un día (res://scenes/levels/day_stage.tscn).
##
## Se instancia dentro del `CanvasLayer` `UI` de cada `day_XX.tscn`, delante del
## `Background` y detrás de la `IntroCard` (el orden de hermanos es el orden de
## dibujo). Reemplaza el arranque viejo, donde la tarjeta del día aparecía sola:
## ahora Richard deambula por el suelo verde despejado y hay que clickearlo para
## que la tarjeta aparezca. `day_scene.gd` escucha `clicked`.
##
## Deambular es 100% código: este script nunca lee input de movimiento.
## Las zonas transitables (`zone_left`, `zone_front`, `zone_right`) delimitan
## exclusivamente el suelo verde despejado, y `_build_path` bordea el sofá
## central usando esquinas bisagra para no atravesarlo ni tocar los muebles.
##
## `stop()` lo llama `day_scene.gd` cuando la tarjeta ya se reveló: congela a
## Richard donde está y saca la pista de la pantalla.

signal clicked

## Zonas transitables de suelo verde despejado (en coordenadas de lienzo 1920x1080).
## Ala izquierda: suelo verde al lado del sofá, debajo de los muebles.
@export var zone_left: Rect2 = Rect2(180.0, 540.0, 260.0, 300.0)
## Pasillo frontal: suelo verde y alfombra frente al sofá, arriba de la TV.
@export var zone_front: Rect2 = Rect2(440.0, 780.0, 1040.0, 70.0)
## Ala derecha: suelo verde a la derecha del sofá y de la lámpara.
@export var zone_right: Rect2 = Rect2(1480.0, 540.0, 260.0, 300.0)

## Puntos de paso bisagra para bordear el sofá sin atravesarlo.
@export var corner_left: Vector2 = Vector2(420.0, 810.0)
@export var corner_right: Vector2 = Vector2(1480.0, 810.0)

@export var speed: float = 220.0
## Pausa entre un destino y el siguiente (mínimo, máximo), en segundos.
@export var idle_time_range: Vector2 = Vector2(0.4, 1.2)
## Semilla fija: dos corridas deambulan igual (y la verificación es reproducible).
@export var rng_seed: int = 20261017
@export_group("Animations - Idle")
## Nombres de las animaciones de reposo para cada dirección:
@export var idle_front_animation: StringName = &"idle_front"
@export var idle_back_animation: StringName = &"idle_back"
@export var idle_side_animation: StringName = &"idle_side"
@export var idle_diagonal_front_animation: StringName = &"idle_diagonal_front"
@export var idle_diagonal_back_animation: StringName = &"idle_diagonal_back"
## Fallback para compatibilidad si solo existe una animación genérica de reposo.
@export var idle_animation: StringName = &"idle"

@export_group("Animations - Walk")
## Nombres de las animaciones de caminata para cada dirección:
@export var walk_front_animation: StringName = &"walk_front"
@export var walk_back_animation: StringName = &"walk_back"
@export var walk_side_animation: StringName = &"walk_side"
@export var walk_diagonal_front_animation: StringName = &"walk_diagonal_front"
@export var walk_diagonal_back_animation: StringName = &"walk_diagonal_back"
## Fallback para compatibilidad si solo existe una animación genérica de caminar.
@export var walk_animation: StringName = &"walk"

@export_group("Animations - Settings")
## Indica si el dibujo base del sprite sheet mira hacia la derecha.
@export var sprite_faces_right: bool = true

enum Phase { IDLE, WALK }

enum Direction8 {
	RIGHT = 0,
	DOWN_RIGHT = 1,
	DOWN = 2,
	DOWN_LEFT = 3,
	LEFT = 4,
	UP_LEFT = 5,
	UP = 6,
	UP_RIGHT = 7,
}

@onready var _walker: Node2D = %Walker
@onready var _animated_sprite: AnimatedSprite2D = %AnimatedSprite
@onready var _hit_area: Area2D = %HitArea
@onready var _hint_label: Label = %HintLabel

var _phase: Phase = Phase.IDLE
var _target: Vector2 = Vector2.ZERO
var _wait_left: float = 0.0
var _stopped: bool = false
var _rng := RandomNumberGenerator.new()
var _current_path: Array[Vector2] = []
var _last_sector: int = Direction8.DOWN


func _ready() -> void:
	_rng.seed = rng_seed

	# El picking de física (de donde sale Area2D.input_event) viene apagado por
	# defecto en el viewport.
	var viewport := get_viewport()
	if viewport != null:
		viewport.physics_object_picking = true

	_walker.position = _random_point()
	_update_directional_animation(Vector2.DOWN)
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
		if not _current_path.is_empty():
			_target = _current_path.pop_front()
			_update_directional_animation(_target - _walker.position)
		else:
			_go_idle()
		return

	_walker.position += offset.normalized() * step
	_update_directional_animation(offset)


## Congela a Richard donde está, lo deja en reposo y saca la pista de la pantalla.
func stop() -> void:
	if _stopped:
		return
	_stopped = true
	_phase = Phase.IDLE
	_current_path.clear()
	_play_idle()
	_hint_label.visible = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _go_idle() -> void:
	_phase = Phase.IDLE
	_wait_left = _rng.randf_range(
		minf(idle_time_range.x, idle_time_range.y),
		maxf(idle_time_range.x, idle_time_range.y),
	)
	_play_idle()


func _start_walk() -> void:
	_phase = Phase.WALK
	var dest := _random_point()
	_current_path = _build_path(_walker.position, dest)
	if _current_path.is_empty():
		_go_idle()
		return
	_target = _current_path.pop_front()
	_update_directional_animation(_target - _walker.position)


## Calcula el ángulo del vector de movimiento (usando angle()) y selecciona
## la animación adecuada de 8 direcciones en el AnimatedSprite2D junto con flip_h.
func _update_directional_animation(dir_vector: Vector2) -> void:
	if dir_vector.length_squared() < 0.25:
		return

	var angle := dir_vector.angle()
	# wrapf normaliza el ángulo al rango [0.0, TAU)
	var positive_angle := wrapf(angle, 0.0, TAU)
	# Divide en 8 sectores de 45° (TAU / 8), centrados en su dirección:
	# 0: Derecha, 1: Diagonal abajo-der, 2: Abajo, 3: Diagonal abajo-izq,
	# 4: Izquierda, 5: Diagonal arriba-izq, 6: Arriba, 7: Diagonal arriba-der.
	var sector := int(round(positive_angle / (TAU / 8.0))) % 8
	_last_sector = sector

	var anim_name := _resolve_walk_animation(sector)
	if not anim_name.is_empty():
		_play(anim_name)
		_update_flip(sector, anim_name)


## Compatibilidad hacia atrás: actualiza la orientación horizontal.
func _update_facing(dir_x: float) -> void:
	if absf(dir_x) > 0.5:
		_update_directional_animation(Vector2(dir_x, 0.0))


## Resuelve el nombre de la animación para el sector indicado consultando las animaciones
## disponibles en el SpriteFrames, aplicando fallbacks seguros para evitar errores si aún
## faltan animaciones por configurar en el editor.
func _resolve_walk_animation(sector: int) -> StringName:
	var frames := _animated_sprite.sprite_frames
	if frames == null:
		return &""

	var candidates: Array[StringName] = []
	match sector:
		Direction8.RIGHT:
			candidates = [walk_side_animation, &"walk_right", walk_animation, walk_front_animation]
		Direction8.DOWN_RIGHT:
			candidates = [
				walk_diagonal_front_animation,
				&"walk_down_right",
				&"walk_front_diagonal",
				&"walk_diagonal_down",
				walk_front_animation,
				walk_side_animation,
				walk_animation,
			]
		Direction8.DOWN:
			candidates = [walk_front_animation, &"walk_down", walk_side_animation, walk_animation]
		Direction8.DOWN_LEFT:
			candidates = [
				&"walk_down_left",
				walk_diagonal_front_animation,
				&"walk_front_diagonal",
				&"walk_diagonal_down",
				walk_front_animation,
				walk_side_animation,
				walk_animation,
			]
		Direction8.LEFT:
			candidates = [
				&"walk_left",
				walk_side_animation,
				&"walk_right",
				walk_animation,
				walk_front_animation,
			]
		Direction8.UP_LEFT:
			candidates = [
				&"walk_up_left",
				walk_diagonal_back_animation,
				&"walk_back_diagonal",
				&"walk_diagonal_up",
				walk_back_animation,
				walk_side_animation,
				walk_front_animation,
				walk_animation,
			]
		Direction8.UP:
			candidates = [
				walk_back_animation,
				&"walk_up",
				walk_front_animation,
				walk_side_animation,
				walk_animation,
			]
		Direction8.UP_RIGHT:
			candidates = [
				walk_diagonal_back_animation,
				&"walk_up_right",
				&"walk_back_diagonal",
				&"walk_diagonal_up",
				walk_back_animation,
				walk_side_animation,
				walk_front_animation,
				walk_animation,
			]

	for anim in candidates:
		if frames.has_animation(anim):
			return anim

	var anim_list := frames.get_animation_names()
	if not anim_list.is_empty():
		return anim_list[0]
	return &""


## Ajusta la propiedad flip_h del sprite según la dirección y la animación elegida.
func _update_flip(sector: int, anim_name: StringName) -> void:
	var name_str := String(anim_name).to_lower()

	# Las animaciones estrictamente verticales (frente o espalda) nunca se voltean horizontalmente
	if anim_name == walk_front_animation or anim_name == walk_back_animation \
			or anim_name == idle_front_animation or anim_name == idle_back_animation \
			or name_str == "walk_front" or name_str == "walk_down" \
			or name_str == "walk_back" or name_str == "walk_up" \
			or name_str == "idle_front" or name_str == "idle_down" \
			or name_str == "idle_back" or name_str == "idle_up":
		_animated_sprite.flip_h = false
		return

	var moving_left := (sector == Direction8.DOWN_LEFT or sector == Direction8.LEFT or sector == Direction8.UP_LEFT)
	var moving_right := (sector == Direction8.DOWN_RIGHT or sector == Direction8.RIGHT or sector == Direction8.UP_RIGHT)

	var needs_flip: bool = false
	if moving_left:
		# Si la animación tiene arte específico para la izquierda (ej. walk_left, walk_down_left),
		# ya está dibujada hacia la izquierda y no debe voltearse.
		# Si es una animación lateral/diagonal compartida (dibujada hacia la derecha), sí se voltea.
		if name_str.contains("left"):
			needs_flip = false
		else:
			needs_flip = true
	elif moving_right:
		if name_str.contains("left"):
			needs_flip = true
		else:
			needs_flip = false
	else:
		needs_flip = false

	_animated_sprite.flip_h = needs_flip if sprite_faces_right else not needs_flip


## Pone al personaje en reposo. Si hay animación idle (direccional o genérica),
## la reproduce; de lo contrario pausa el fotograma actual para no caminar en el lugar.
func _play_idle() -> void:
	var frames := _animated_sprite.sprite_frames
	if frames == null:
		return

	# 1. Probar animaciones idle direccionales según el último sector hacia el que miraba/caminaba
	var directional_idles := _get_directional_idle_candidates(_last_sector)
	for anim in directional_idles:
		if frames.has_animation(anim):
			_play(anim)
			_update_flip(_last_sector, anim)
			return

	# 2. Probar animación idle genérica configurada
	if frames.has_animation(idle_animation):
		_play(idle_animation)
		return

	# 3. Fallback: pausar el sprite para que se quede en pose estática en la última dirección
	if _animated_sprite.is_playing():
		_animated_sprite.pause()


func _get_directional_idle_candidates(sector: int) -> Array[StringName]:
	match sector:
		Direction8.DOWN:
			return [idle_front_animation, &"idle_front", &"idle_down"]
		Direction8.UP:
			return [idle_back_animation, &"idle_back", &"idle_up"]
		Direction8.DOWN_RIGHT:
			return [
				idle_diagonal_front_animation,
				&"idle_down_right",
				&"idle_front_diagonal",
				&"idle_diagonal_down",
				idle_front_animation,
				idle_side_animation,
			]
		Direction8.DOWN_LEFT:
			return [
				&"idle_down_left",
				idle_diagonal_front_animation,
				&"idle_front_diagonal",
				&"idle_diagonal_down",
				idle_front_animation,
				idle_side_animation,
			]
		Direction8.UP_RIGHT:
			return [
				idle_diagonal_back_animation,
				&"idle_up_right",
				&"idle_back_diagonal",
				&"idle_diagonal_up",
				idle_back_animation,
				idle_side_animation,
			]
		Direction8.UP_LEFT:
			return [
				&"idle_up_left",
				idle_diagonal_back_animation,
				&"idle_back_diagonal",
				&"idle_diagonal_up",
				idle_back_animation,
				idle_side_animation,
			]
		Direction8.RIGHT:
			return [idle_side_animation, &"idle_right", idle_animation]
		Direction8.LEFT:
			return [&"idle_left", idle_side_animation, &"idle_right", idle_animation]
	return []


## Elige un punto al azar dentro de alguna de las 3 zonas transitables de suelo verde.
func _random_point() -> Vector2:
	var zones := [zone_left, zone_front, zone_right]
	var zone: Rect2 = zones[_rng.randi_range(0, zones.size() - 1)]
	return Vector2(
		_rng.randf_range(zone.position.x, zone.end.x),
		_rng.randf_range(zone.position.y, zone.end.y),
	)


## Construye un camino seguro por el suelo verde bordeando el sofá central si es necesario.
func _build_path(from_pt: Vector2, to_pt: Vector2) -> Array[Vector2]:
	var path: Array[Vector2] = []
	var from_is_left_high := from_pt.x < 460.0 and from_pt.y < 760.0
	var from_is_right_high := from_pt.x > 1460.0 and from_pt.y < 760.0
	var to_is_left_high := to_pt.x < 460.0 and to_pt.y < 760.0
	var to_is_right_high := to_pt.x > 1460.0 and to_pt.y < 760.0

	# 1. Ambos dentro del ala izquierda: línea recta directa
	if from_pt.x < 460.0 and to_pt.x < 460.0:
		path.append(to_pt)
		return path

	# 2. Ambos dentro del ala derecha: línea recta directa
	if from_pt.x > 1460.0 and to_pt.x > 1460.0:
		path.append(to_pt)
		return path

	# 3. Ambos en el pasillo frontal: línea recta directa
	if from_pt.y >= 760.0 and to_pt.y >= 760.0:
		path.append(to_pt)
		return path

	# Transiciones que involucran zonas altas para no atravesar las esquinas del sofá
	if from_is_left_high:
		path.append(corner_left)
	if from_is_right_high:
		path.append(corner_right)

	# Cruce completo de un ala a la otra a través del frente
	if (from_pt.x < 460.0 and to_pt.x > 1460.0) or (from_pt.x > 1460.0 and to_pt.x < 460.0):
		if from_pt.x < 460.0:
			path.append(corner_right)
		else:
			path.append(corner_left)

	if to_is_left_high and (path.is_empty() or path.back() != corner_left):
		path.append(corner_left)
	if to_is_right_high and (path.is_empty() or path.back() != corner_right):
		path.append(corner_right)

	path.append(to_pt)
	return path


## Reproduce la animación pedida si existe; conserva el progreso de fotogramas
## entre cambios de dirección en caminata para una marcha más natural y fluida,
## y reinicia a fotograma 0 al cambiar entre caminata y reposo.
func _play(anim_name: StringName) -> void:
	var frames := _animated_sprite.sprite_frames
	if frames == null:
		return
	if not frames.has_animation(anim_name):
		if _animated_sprite.is_playing():
			_animated_sprite.pause()
		return
	if _animated_sprite.animation != anim_name:
		var prev_anim := String(_animated_sprite.animation)
		var new_anim := String(anim_name)
		var prev_frame := _animated_sprite.frame
		_animated_sprite.play(anim_name)
		if prev_anim.begins_with("walk") and new_anim.begins_with("walk"):
			var count := frames.get_frame_count(anim_name)
			if count > 0:
				_animated_sprite.frame = prev_frame % count
		else:
			_animated_sprite.frame = 0
	elif not _animated_sprite.is_playing():
		_animated_sprite.play(anim_name)


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
