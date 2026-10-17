extends Node2D
## Escena de un día (res://scenes/levels/day_01.tscn … day_07.tscn).
##
## Cumple un solo rol: dar el contexto del día (la desgracia de Richard) y, cuando
## el jugador confirma, pasar al diálogo con `Game.begin_dialog()`.
##
## El día llega por `day_index` (0 = Lunes) para que las 7 escenas compartan este
## script y solo cambie ese número. **No hay texto hardcodeado**: sale del guion
## (`assets/data/days.json`, vía `Game.days`), así el copy se edita en un solo lado.
##
## No carga ni libera nada: quién instancia y libera esta escena es `Main`.

## Día que representa esta escena. 0 = Lunes, 6 = Domingo.
@export var day_index: int = 0

@onready var _intro_card: PanelContainer = %IntroCard
@onready var _title_label: Label = %DayTitleLabel
@onready var _intro_label: Label = %IntroLabel
@onready var _continue_button: Button = %ContinueButton


func _ready() -> void:
	_intro_card.visible = true
	_continue_button.visible = true

	var data: Dictionary = Game.days.get_day(day_index)
	if data.is_empty():
		push_error("DayScene: no hay datos para el día %d (¿falló la carga de '%s'?)." % [day_index + 1, DialogueDB.DATA_PATH])
		return

	_title_label.text = "Día %d · %s" % [day_index + 1, String(data.get("title", ""))]
	_intro_label.text = String(data.get("richard_intro", ""))

	_continue_button.pressed.connect(_on_continue_pressed)
	_continue_button.grab_focus()

	Events.dialogue_turn_started.connect(_on_dialogue_turn_started)


func _on_continue_pressed() -> void:
	# `begin_dialog()` ya ignora la llamada si no estamos en INTRO, así que un
	# doble clic no rompe nada.
	Game.begin_dialog()


## Ya empezó el diálogo: la tarjeta se retira.
##
## A 640×360 la caja de diálogo ocupa los 210 px de abajo, así que la intro y el
## diálogo no entran juntos. El contexto del día no se pierde: queda el título en
## el HUD, y cada prompt trae su propia situación.
func _on_dialogue_turn_started(_day_index: int, _turn_index: int) -> void:
	_intro_card.visible = false
