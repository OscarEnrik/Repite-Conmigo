extends CanvasLayer
## Menú de pausa. Lo muestra scenes/main.gd cuando Events.game_paused se emite.
##
## process_mode = ALWAYS es obligatorio: este menú tiene que responder mientras
## get_tree().paused es true. Los hijos heredan el modo, no hay que tocarlos.

@onready var _resume_button: BaseButton = %ResumeButton
@onready var _restart_button: BaseButton = %RestartButton
@onready var _menu_button: BaseButton = %MenuButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_resume_button.pressed.connect(Game.resume_game)
	_restart_button.pressed.connect(Game.restart_run)
	_menu_button.pressed.connect(Game.go_to_menu)


func show_menu() -> void:
	visible = true
	_resume_button.grab_focus()


func hide_menu() -> void:
	visible = false
