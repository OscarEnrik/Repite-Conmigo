extends Control
## Pantalla de final de semana (`res://scenes/ui/ending.tscn`).
##
## La carga `Game.finish_week()`, que deja el resultado en `Game.ending_id`, el
## promedio en `Game.history` y los días superados en `Game.days_passed`. Acá solo
## se muestra: la decisión de qué final toca no vive en la UI.
##
## Reemplaza a la vieja pantalla de "game over" del flujo de combate.

## Título por final. La clave es `Game.ending_id`.
const TITLES := {
	&"ending_bright": "Una semana distinta",
	&"ending_bittersweet": "Se sostuvo, a duras penas",
	&"ending_gloomy": "La tristeza se acumuló",
}

@onready var _title_label: Label = %TitleLabel
@onready var _days_label: Label = %DaysLabel
@onready var _average_label: Label = %AverageLabel
@onready var _retry_button: Button = %RetryButton
@onready var _menu_button: Button = %MenuButton


func _ready() -> void:
	get_tree().paused = false
	Game.state = Game.State.ENDING

	_title_label.text = String(TITLES.get(Game.ending_id, "Fin de la semana"))
	_days_label.text = "Días superados: %d/%d" % [Game.days_passed, Game.DAY_COUNT]
	_average_label.text = "Ánimo promedio: %d/100" % roundi(Game.average_mood())

	_retry_button.pressed.connect(Game.restart_run)
	_menu_button.pressed.connect(Game.go_to_menu)
	_retry_button.grab_focus()
