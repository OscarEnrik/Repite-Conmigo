class_name DialogueBox
extends CanvasLayer
## Caja de diálogo: el prompt del turno con las 3 salidas de Loretta y, al cerrar
## el día, el panel de resultado.
##
## No conoce días, escenas ni nodos de nadie: le pregunta a `Game` y escucha a
## `Events`. `Main` la instancia una sola vez, así sobrevive a los cambios de día.
##
## `layer = 5`: encima del HUD (layer 1) y debajo de `PauseMenu` (layer 10), para
## que la pausa tape el diálogo. `process_mode` heredado: en pausa no responde.

## Carita del feedback, por tipo de opción.
const FEEDBACK_EMOJI := {
	&"choke": "😖",
	&"motivate": "🙂",
	&"sound": "😐",
}

@onready var _dialogue_panel: PanelContainer = %DialoguePanel
@onready var _prompt_label: Label = %PromptLabel
@onready var _options_container: VBoxContainer = %OptionsContainer
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _result_panel: PanelContainer = %DayResultPanel
@onready var _result_label: Label = %ResultLabel
@onready var _result_button: Button = %ResultButton

## Botones de opción, en el orden en que están en el contenedor. Se arman en
## `_ready()` para no depender de un `$Path` ni de nombres fijos.
var _option_buttons: Array[Button] = []


func _ready() -> void:
	visible = false
	_result_panel.visible = false

	for child in _options_container.get_children():
		var button := child as Button
		if button == null:
			continue
		button.pressed.connect(_on_option_pressed.bind(_option_buttons.size()))
		_option_buttons.append(button)

	_result_button.pressed.connect(_on_result_pressed)
	Events.dialogue_turn_started.connect(_show_turn)
	Events.day_finished.connect(_show_result)


# --- Turnos -----------------------------------------------------------------

## `Events.dialogue_turn_started`: pinta el turno nuevo y habilita las opciones.
##
## El feedback del turno anterior **se mantiene**: así el jugador ve qué le costó
## su última frase mientras elige la siguiente. Solo se limpia al empezar el día,
## o sea en el turno 0.
func _show_turn(_day_index: int, turn_index: int) -> void:
	if turn_index == 0:
		_feedback_label.text = ""

	var turn: Dictionary = Game.current_turn_data()
	_prompt_label.text = String(turn.get("prompt", ""))

	_set_options_enabled(true)
	for i in _option_buttons.size():
		var button := _option_buttons[i]
		var option := Game.option_at(i)
		button.text = String(option.get("text", ""))
		if option.is_empty():
			button.disabled = true

	_result_panel.visible = false
	_dialogue_panel.visible = true
	visible = true

	if not _option_buttons.is_empty() and not _option_buttons[0].disabled:
		_option_buttons[0].grab_focus()


## Un clic aplica la opción y cierra el turno.
## Los botones se deshabilitan **antes** de tocar `Game`: si no, dos clics seguidos
## en el mismo turno se comerían dos opciones (y un turno de más).
func _on_option_pressed(index: int) -> void:
	_set_options_enabled(false)

	var option: Dictionary = Game.option_at(index)
	var delta := Game.choose_option(index)
	var emoji: String = FEEDBACK_EMOJI.get(option.get("kind", &""), "")
	_feedback_label.text = "%s  %s" % [_format_delta(delta), emoji]

	Game.advance_turn()


# --- Resultado del día ------------------------------------------------------

## `Events.day_finished`: el día se cerró. El panel espera un clic de confirmación
## y recién ahí sigue la semana (`Game.next_day()`).
func _show_result(_day_index: int, passed: bool) -> void:
	_result_label.text = "Día superado" if passed else "Se acumula la tristeza"
	_dialogue_panel.visible = false
	_result_panel.visible = true
	_result_button.grab_focus()


func _on_result_pressed() -> void:
	_result_panel.visible = false
	visible = false
	Game.next_day()


# --- Utilidades -------------------------------------------------------------

func _set_options_enabled(enabled: bool) -> void:
	for button in _option_buttons:
		button.disabled = not enabled


## "+10" / "−12" / "0". Se usa el signo menos tipográfico (−) para que no se
## confunda con un guion en el medio del texto.
func _format_delta(delta: int) -> String:
	if delta > 0:
		return "+%d" % delta
	if delta < 0:
		return "−%d" % absi(delta)
	return "0"
