extends Control
## Menú principal.

const SETTINGS_SCENE := "res://scenes/ui/settings_menu.tscn"

@onready var _new_game_button: Button = %NewGameButton
@onready var _continue_button: Button = %ContinueButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	Game.state = Game.State.MENU
	get_tree().paused = false

	var has_save := Save.has_save()
	_continue_button.disabled = not has_save
	if has_save:
		_continue_button.grab_focus()
	else:
		_new_game_button.grab_focus()

	# Salir no tiene sentido en la build web.
	if OS.has_feature("web"):
		_quit_button.visible = false

	_new_game_button.pressed.connect(_on_new_game_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


func _on_new_game_pressed() -> void:
	Save.delete_save()
	Game.start_run()


func _on_continue_pressed() -> void:
	Game.continue_run()


func _on_settings_pressed() -> void:
	var packed := load(SETTINGS_SCENE) as PackedScene
	if packed == null:
		push_error("MainMenu: no se pudo cargar '%s'." % SETTINGS_SCENE)
		return
	var settings_menu := packed.instantiate() as SettingsMenu
	add_child(settings_menu)
	visible = false
	settings_menu.closed.connect(_on_settings_closed)


func _on_settings_closed() -> void:
	visible = true
	_settings_button.grab_focus()


func _on_quit_pressed() -> void:
	Game.quit_game()
