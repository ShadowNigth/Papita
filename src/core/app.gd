extends Node
## App: raiz del juego. Alterna entre menu y partida, guarda progreso y
## mantiene el estado global (tiempo jugado, pausa, mouse).

var menu: Menu
var match_game: MatchGame
var _last_params: Dictionary = {}
var _save_clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.ensure_actions()
	Settings.apply_controls()
	InputSetup.apply_bindings(Settings.data.controls)
	get_window().title = "PAPITA: CS 1.5 Reforged"
	_apply_icon()
	goto_menu()
	Settings.progress_changed.connect(_on_progress_changed)


func _apply_icon() -> void:
	var img := Image.new()
	var err := img.load("res://icon.svg")
	if err == OK:
		DisplayServer.set_icon(img)


func _process(delta: float) -> void:
	_save_clock += delta
	if _save_clock > 15.0:
		_save_clock = 0.0
		if match_game and is_instance_valid(match_game):
			Settings.data.progress["play_time"] = (
				float(Settings.data.progress.get("play_time", 0.0)) + 15.0
			)
			Settings.queue_save()


func goto_menu() -> void:
	get_tree().paused = false
	if match_game and is_instance_valid(match_game):
		match_game.queue_free()
		match_game = null
	if menu and is_instance_valid(menu):
		menu.queue_free()
	menu = Menu.new()
	menu.name = "Menu"
	add_child(menu)
	menu.start_requested.connect(start_match)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioBank.stop_all()
	AudioBank.set_music("menu_music", 2.0)
	AudioBank.set_ambience("night", 2.5)


func start_match(map_id: String, mode: String, team: int, bots: int, diff: int) -> void:
	get_tree().paused = false
	_last_params = {"map": map_id, "mode": mode, "team": team, "bots": bots, "diff": diff}
	if menu and is_instance_valid(menu):
		menu.queue_free()
		menu = null
	if match_game and is_instance_valid(match_game):
		match_game.queue_free()
		match_game = null
	AudioBank.stop_all()
	match_game = MatchGame.new()
	match_game.name = "Match"
	add_child(match_game)
	match_game.start_match(map_id, mode, team, bots, diff)


func restart_match() -> void:
	if _last_params.is_empty():
		goto_menu()
		return
	start_match(
		String(_last_params.map),
		String(_last_params.mode),
		int(_last_params.team),
		int(_last_params.bots),
		int(_last_params.diff)
	)


func _on_progress_changed() -> void:
	pass


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Settings.flush()
