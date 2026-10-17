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
@onready var _mood_bar: ProgressBar = %MoodBar


func _ready() -> void:
	Events.mood_changed.connect(_on_mood_changed)
	Events.day_started.connect(_on_day_started)
	_refresh_day(Game.current_day, _day_title(Game.current_day))
	_refresh_mood(Game.mood)


func _on_mood_changed(new_mood: int, _delta: int) -> void:
	_refresh_mood(new_mood)


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
