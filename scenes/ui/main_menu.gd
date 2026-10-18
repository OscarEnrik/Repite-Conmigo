extends Control
## Menú principal.

const SETTINGS_SCENE := "res://scenes/ui/settings_menu.tscn"
const CREDITS_SCENE := "res://scenes/ui/credits_menu.tscn"

@onready var _new_game_button: BaseButton = get_node_or_null("%NewGameButton")
@onready var _continue_button: BaseButton = get_node_or_null("%ContinueButton")
@onready var _settings_button: BaseButton = get_node_or_null("%SettingsButton")
@onready var _credits_button: BaseButton = get_node_or_null("%CreditsButton") if has_node("%CreditsButton") else get_node_or_null("%CreditsButton2")


func _ready() -> void:
	Game.state = Game.State.MENU
	get_tree().paused = false

	var has_save := Save.has_save()
	if _continue_button:
		_continue_button.disabled = not has_save
		if has_save:
			_continue_button.grab_focus()
		elif _new_game_button:
			_new_game_button.grab_focus()
	elif _new_game_button:
		_new_game_button.grab_focus()

	if _new_game_button:
		_new_game_button.pressed.connect(_on_new_game_pressed)
	if _continue_button:
		_continue_button.pressed.connect(_on_continue_pressed)
	if _settings_button:
		_settings_button.pressed.connect(_on_settings_pressed)
	if _credits_button:
		_credits_button.pressed.connect(_on_credits_pressed)


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
	if _settings_button:
		_settings_button.grab_focus()


func _on_credits_pressed() -> void:
	var packed := load(CREDITS_SCENE) as PackedScene
	if packed == null:
		push_error("MainMenu: no se pudo cargar '%s'." % CREDITS_SCENE)
		return
	var credits_menu := packed.instantiate() as CreditsMenu
	add_child(credits_menu)
	visible = false
	credits_menu.closed.connect(_on_credits_closed)


func _on_credits_closed() -> void:
	visible = true
	if _credits_button:
		_credits_button.grab_focus()
