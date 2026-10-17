class_name SettingsMenu
extends CanvasLayer
## Menú de opciones. Se agrega como HIJO de otro menú (ver main_menu.gd) y se
## libera solo al cerrarse.
##
## Para agregar una opción nueva:
##   1. sumá la variable y el setter en scripts/autoload/settings_manager.gd
##   2. agregá el control en scenes/ui/settings_menu.tscn (con nombre único)
##   3. conectalo acá abajo

signal closed

@onready var _master_slider: HSlider = %MasterSlider
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _fullscreen_check: CheckButton = %FullscreenCheck
@onready var _values_label: Label = %ValuesLabel
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_master_slider.value = Settings.master_volume
	_music_slider.value = Settings.music_volume
	_sfx_slider.value = Settings.sfx_volume
	_fullscreen_check.button_pressed = Settings.fullscreen
	_refresh_values()

	_master_slider.value_changed.connect(_on_master_changed)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_back_button.pressed.connect(_close)
	_back_button.grab_focus()


func _on_master_changed(value: float) -> void:
	Settings.set_audio_volume(&"master", value)
	_refresh_values()


func _on_music_changed(value: float) -> void:
	Settings.set_audio_volume(&"music", value)
	_refresh_values()


func _on_sfx_changed(value: float) -> void:
	Settings.set_audio_volume(&"sfx", value)
	_refresh_values()


func _on_fullscreen_toggled(enabled: bool) -> void:
	Settings.set_fullscreen(enabled)


func _refresh_values() -> void:
	_values_label.text = "Master %d%%   Música %d%%   SFX %d%%" % [
		roundi(Settings.master_volume * 100.0),
		roundi(Settings.music_volume * 100.0),
		roundi(Settings.sfx_volume * 100.0),
	]


func _close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()
