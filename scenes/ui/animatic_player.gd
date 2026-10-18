class_name AnimaticPlayer
extends CanvasLayer
## Reproductor de animatics al inicio de un día (`res://scenes/ui/animatic_player.tscn`).
##
## Muestra una pantalla en negro indicando el número y título del día (ej. "DÍA 1 · Lunes")
## y transiciona suavemente hacia los animatics del día si existen (viñetas `1.png` .. `4.png`
## en `res://assets/art/animatics/day%02d/`) o directamente al escenario si no hay animatics.
## El avance se realiza por temporizador o con clic izquierdo / `ui_accept` (Espacio / Enter).

signal finished

const ANIMATICS_DIR := "res://assets/art/animatics/day%02d"
const SLIDE_COUNT := 4
const TITLE_DISPLAY_TIME := 1.8
const CROSSFADE_TIME := 0.35
const FADE_OUT_TIME := 0.40

@onready var _click_catcher: Control = %ClickCatcher
@onready var _title_container: VBoxContainer = %TitleContainer
@onready var _day_title_label: Label = %DayTitleLabel
@onready var _day_subtitle_label: Label = %DaySubtitleLabel
@onready var _slide_texture: TextureRect = %SlideTexture
@onready var _fade_texture: TextureRect = %FadeTexture
@onready var _step_hint_label: Label = %StepHintLabel

var _slides: Array[Texture2D] = []
var _current_index: int = 0
var _is_transitioning: bool = false
var _is_title_card: bool = false
var _current_tween: Tween = null
var _auto_timer: SceneTreeTimer = null


func _ready() -> void:
	visible = false
	_click_catcher.gui_input.connect(_on_click_catcher_gui_input)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		advance()


## Devuelve las texturas encontradas (`1.png`..`4.png`) para `day_index` (0 = Día 1).
func load_slides_for_day(day_index: int) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var folder := ANIMATICS_DIR % (day_index + 1)
	for i in range(1, SLIDE_COUNT + 1):
		var path := "%s/%d.png" % [folder, i]
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex != null:
			result.append(tex)
	return result


## Prepara y muestra la pantalla en negro indicando el día ("DÍA X"), y luego
## transiciona suavemente a los animatics (o directo al escenario si no hay).
func play_for_day(day_index: int) -> bool:
	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()

	_slides = load_slides_for_day(day_index)
	_current_index = 0
	_is_transitioning = false
	_is_title_card = true

	var day_num := day_index + 1
	var weekday := ""
	if Game != null and Game.days != null:
		var data: Dictionary = Game.days.get_day(day_index)
		weekday = String(data.get("title", ""))

	_day_title_label.text = "DÍA %d" % day_num
	_day_subtitle_label.text = weekday
	_day_subtitle_label.visible = not weekday.is_empty()
	_title_container.modulate.a = 1.0
	_title_container.visible = true

	_click_catcher.modulate.a = 1.0
	_fade_texture.modulate.a = 0.0
	_fade_texture.texture = null
	_slide_texture.modulate.a = 0.0
	_slide_texture.texture = _slides[0] if not _slides.is_empty() else null
	_step_hint_label.text = "Clic para continuar"

	visible = true
	_click_catcher.grab_focus()

	# Temporizador para auto-avanzar después de TITLE_DISPLAY_TIME segundos
	_start_title_timer()
	return true


func _start_title_timer() -> void:
	_auto_timer = get_tree().create_timer(TITLE_DISPLAY_TIME)
	_auto_timer.timeout.connect(_on_title_timer_timeout)


func _on_title_timer_timeout() -> void:
	if visible and _is_title_card and not _is_transitioning:
		advance()


## Avanza a la siguiente viñeta con crossfade suave o disuelve el animatic si era la última.
func advance() -> void:
	if not visible:
		return

	# Si el jugador hace clic durante la animación, completa el tween inmediatamente
	if _is_transitioning:
		if _current_tween != null and _current_tween.is_valid():
			_current_tween.custom_step(999.0)
		return

	if _is_title_card:
		_transition_from_title_card()
		return

	if _current_index + 1 < _slides.size():
		_current_index += 1
		_crossfade_to_current_slide()
	else:
		_fade_out_and_finish()


func _transition_from_title_card() -> void:
	_is_transitioning = true

	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()

	if not _slides.is_empty():
		_slide_texture.texture = _slides[0]
		_slide_texture.modulate.a = 0.0
		_current_tween = create_tween().set_parallel(true)
		_current_tween.tween_property(_title_container, "modulate:a", 0.0, CROSSFADE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_current_tween.tween_property(_slide_texture, "modulate:a", 1.0, CROSSFADE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		await _current_tween.finished

		_title_container.visible = false
		_is_title_card = false
		_is_transitioning = false
	else:
		_current_tween = create_tween()
		_current_tween.tween_property(_click_catcher, "modulate:a", 0.0, FADE_OUT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		await _current_tween.finished

		_title_container.visible = false
		_is_title_card = false
		_is_transitioning = false
		visible = false
		_click_catcher.modulate.a = 1.0
		finished.emit()


func _crossfade_to_current_slide() -> void:
	_is_transitioning = true
	_fade_texture.texture = _slides[_current_index]
	_fade_texture.modulate.a = 0.0

	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()

	_current_tween = create_tween()
	_current_tween.tween_property(_fade_texture, "modulate:a", 1.0, CROSSFADE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await _current_tween.finished

	_slide_texture.texture = _slides[_current_index]
	_fade_texture.modulate.a = 0.0
	_fade_texture.texture = null
	_is_transitioning = false


func _fade_out_and_finish() -> void:
	_is_transitioning = true

	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()

	_current_tween = create_tween()
	_current_tween.tween_property(_click_catcher, "modulate:a", 0.0, FADE_OUT_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await _current_tween.finished

	_slides.clear()
	visible = false
	_is_title_card = false
	_is_transitioning = false
	_click_catcher.modulate.a = 1.0
	finished.emit()


func _on_click_catcher_gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_click_catcher.accept_event()
		advance()
	elif event.is_action_pressed(&"ui_accept"):
		_click_catcher.accept_event()
		advance()
