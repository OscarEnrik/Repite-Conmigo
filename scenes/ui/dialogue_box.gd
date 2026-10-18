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

@onready var _dialogue_panel: PanelContainer = %DialoguePanel
@onready var _prompt_label: Label = %PromptLabel
@onready var _options_container: HBoxContainer = %OptionsContainer
@onready var _confirm_button: Button = %ConfirmButton

## Botones de opción, en el orden en que están en el contenedor. Se arman en
## `_ready()` para no depender de un `$Path` ni de nombres fijos.
var _option_buttons: Array[Button] = []


func _ready() -> void:
	visible = false

	for child in _options_container.get_children():
		var button := child as Button
		if button == null:
			continue
		var index := _option_buttons.size()
		button.toggle_mode = true
		button.toggled.connect(_on_option_toggled.bind(index))
		_option_buttons.append(button)

	_confirm_button.pressed.connect(_on_confirm_pressed)
	Events.dialogue_turn_started.connect(_show_turn)
	Events.day_finished.connect(_show_result)


# --- Turnos -----------------------------------------------------------------

## `Events.dialogue_turn_started`: pinta el turno nuevo y habilita las opciones.
##
## El feedback del turno anterior **se mantiene**: así el jugador ve qué le costó
## su última frase mientras elige la siguiente. Solo se limpia al empezar el día,
## o sea en el turno 0.
func _show_turn(_day_index: int, _turn_index: int) -> void:
	var turn: Dictionary = Game.current_turn_data()
	_prompt_label.text = String(turn.get("prompt", ""))

	_set_options_enabled(true)
	for i in _option_buttons.size():
		var button := _option_buttons[i]
		var option := Game.option_at(i)
		button.text = String(option.get("text", ""))
		button.button_pressed = false
		if option.is_empty():
			button.disabled = true

	_confirm_button.disabled = true
	_confirm_button.visible = true

	_dialogue_panel.visible = true
	visible = true

	if not _option_buttons.is_empty() and not _option_buttons[0].disabled:
		_option_buttons[0].grab_focus()


## Al marcar una opción, se desmarcan automáticamente las demás (selección única).
## "Confirmar" se habilita solo si hay una opción elegida.
func _on_option_toggled(button_pressed: bool, index: int) -> void:
	if button_pressed:
		for j in _option_buttons.size():
			if j != index and _option_buttons[j].button_pressed:
				_option_buttons[j].button_pressed = false

	var has_selection := false
	for button in _option_buttons:
		if button.button_pressed and not button.disabled:
			has_selection = true
			break
	_confirm_button.disabled = not has_selection


## El jugador confirmó su selección: aplica la opción elegida y cierra el turno.
func _on_confirm_pressed() -> void:
	var selected_index: int = -1
	for i in _option_buttons.size():
		if _option_buttons[i].button_pressed and not _option_buttons[i].disabled:
			selected_index = i
			break

	if selected_index == -1:
		return

	_set_options_enabled(false)
	_confirm_button.disabled = true

	Game.choose_option(selected_index)
	Game.advance_turn()


# --- Fin del día ------------------------------------------------------------

## `Events.day_finished`: el día terminó. Se retira el diálogo y se avanza al siguiente día.
func _show_result(_day_index: int, _passed: bool) -> void:
	_set_options_enabled(false)
	await get_tree().create_timer(0.8).timeout
	_dialogue_panel.visible = false
	visible = false
	Game.next_day()


# --- Utilidades -------------------------------------------------------------

func _set_options_enabled(enabled: bool) -> void:
	for button in _option_buttons:
		button.disabled = not enabled
	if not enabled:
		_confirm_button.disabled = true
