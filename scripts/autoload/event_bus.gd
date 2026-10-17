extends Node
## Autoload: `Events`
## Bus de eventos global.
## 
## Sirve para que el HUD, los menús y los días reaccionen a lo que pasa en el
## juego sin guardarse referencias entre sí. Menos acoplamiento = menos bugs
## cuando cambia el día que está cargado.
## 
## Escuchar:
##     Events.mood_changed.connect(_on_mood_changed)
## Emitir:
##     Events.mood_changed.emit(62, -12)
## 
## Regla de oro: acá va SOLO la declaración de señales, nunca lógica de juego.
## Quién emite cada señal de la semana es `Game` (scripts/autoload/game_manager.gd).

# --- Ciclo de partida ---
signal game_started
signal game_returned_to_menu

# --- Pausa ---
signal game_paused
signal game_resumed

# --- Día y diálogo ---
## `Game.start_day()` fijó el ánimo y el turno del día. `Main` carga la escena.
signal day_started(day_index: int, title: String)
## Loretta tiene que mostrar el prompt del turno `turn_index` (0-based).
signal dialogue_turn_started(day_index: int, turn_index: int)
## Se aplicó una opción. `mood_delta` ya viene escalado por la dificultad del día.
signal option_chosen(option_index: int, kind: StringName, mood_delta: int)
## El ánimo cambió. `delta` es el cambio pedido; el clamp a 0..100 puede absorber parte.
signal mood_changed(new_mood: int, delta: int)
## Se cerró el día. `passed` = llegó al `pass_threshold` del guion.
signal day_finished(day_index: int, passed: bool)
## Se cerró la semana. `ending_id` es `ending_bright` / `ending_bittersweet` / `ending_gloomy`.
signal week_finished(ending_id: StringName)

# --- Feedback ---
signal sfx_requested(sfx_id: StringName, position: Vector2)


## Desconecta TODAS las señales declaradas en este script.
## Llamalo antes de recargar un día si ves callbacks duplicados o
## errores de "instance is gone" de un día anterior.
func clear_all() -> void:
	var script: Script = get_script()
	if script == null:
		return
	for signal_info in script.get_script_signal_list():
		var signal_name: StringName = signal_info["name"]
		for connection in get_signal_connection_list(signal_name):
			disconnect(signal_name, connection["callable"])
