extends CanvasLayer
## HUD del juego: el día de la semana y la barra de ánimo de Richard.
##
## Escucha al EventBus en vez de a los actores: así sobrevive a que la escena del
## día se recargue o cambie dentro de `LevelHost`.
##
## Pinta el estado inicial en `_ready()` leyendo `Game`. Si esperara al primer
## `mood_changed`, el HUD arrancaría vacío hasta la primera elección: ese es el
## bug del HUD viejo (se conectaba antes de que existiera el actor).

@onready var _day_label: Label = %DayLabel
@onready var _mood_label: Label = %MoodValueLabel
@onready var _mood_bar: TextureProgressBar = %MoodBar
@onready var _delta_label: Label = %DeltaLabel

var _delta_tween: Tween


func _ready() -> void:
	_delta_label.modulate.a = 0.0
	Events.mood_changed.connect(_on_mood_changed)
	Events.day_started.connect(_on_day_started)
	_refresh_day(Game.current_day, _day_title(Game.current_day))
	_refresh_mood(Game.mood)


func _on_mood_changed(new_mood: int, delta: int) -> void:
	_refresh_mood(new_mood)
	if delta != 0:
		_animate_delta(delta)


func _on_day_started(day_index: int, title: String) -> void:
	_refresh_day(day_index, title)
	# `Game.start_day()` fija el ánimo en el `start_mood` del día sin pasar por
	# `apply_mood()`, así que no hay `mood_changed` que escuchar: hay que repintar
	# acá o la barra amanece con el valor de ayer.
	_refresh_mood(Game.mood)


func _refresh_day(day_index: int, title: String) -> void:
	_day_label.text = "Día %d/%d · %s" % [day_index + 1, Game.DAY_COUNT, title]


func _refresh_mood(new_mood: int) -> void:
	_mood_bar.value = new_mood
	_mood_label.text = "Ánimo: %d/%d" % [new_mood, Game.MOOD_MAX]


## Título del día según el guion. El HUD tiene que pintar algo apenas se carga
## la escena del día, sin esperar a que llegue `day_started`.
func _day_title(day_index: int) -> String:
	var data: Dictionary = Game.days.get_day(day_index)
	return String(data.get("title", ""))


## Muestra el cambio de ánimo animado con un Tween al lado de la caja de ánimo.
func _animate_delta(delta: int) -> void:
	if _delta_tween and _delta_tween.is_valid():
		_delta_tween.kill()

	var base_pos := Vector2.ZERO
	_delta_label.position = base_pos
	_delta_label.scale = Vector2(1.2, 1.2)
	_delta_label.pivot_offset = Vector2(20.0, 20.0)
	_delta_label.modulate.a = 0.0

	if delta > 0:
		_delta_label.text = "+%d" % delta
		_delta_label.add_theme_color_override(&"font_color", Color(0.25, 0.85, 0.35))
	else:
		_delta_label.text = "−%d" % absi(delta)
		_delta_label.add_theme_color_override(&"font_color", Color(0.95, 0.25, 0.25))

	var target_y := base_pos.y + (12.0 if delta < 0 else -12.0)

	_delta_tween = create_tween()
	# Pop y fade-in con rebote suave
	_delta_tween.set_parallel(true)
	_delta_tween.tween_property(_delta_label, "modulate:a", 1.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_delta_tween.tween_property(_delta_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_delta_tween.tween_property(_delta_label, "position:y", target_y, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Pausa para leerlo
	_delta_tween.chain().tween_interval(0.5)

	# Fade-out y desplazamiento final
	_delta_tween.chain().set_parallel(true)
	_delta_tween.tween_property(_delta_label, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_delta_tween.tween_property(_delta_label, "position:y", target_y + (12.0 if delta < 0 else -12.0), 0.35)
