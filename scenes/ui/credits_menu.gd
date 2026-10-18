class_name CreditsMenu
extends CanvasLayer
## Pantalla de créditos. Se agrega como HIJO del menú principal (ver main_menu.gd)
## y se libera sola al cerrarse.

signal closed

@onready var _back_button: Button = %BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_back_button.pressed.connect(_close)
	_back_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	queue_free()
