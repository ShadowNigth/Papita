extends CanvasLayer
## InGameUI: menu de compra, pausa, marcador, consola, ayuda, muerte y fin de partida.

class_name InGameUI

var game: MatchGame
var paused := false
var buy_open := false
var console_open := false
var help_open := false
var scoreboard_visible := false

var _root: Control
var _buy_panel: PanelContainer
var _buy_grid: GridContainer
var _buy_money: Label
var _buy_category := 0
var _pause_panel: PanelContainer
var _scoreboard: Control
var _death_panel: PanelContainer
var _end_panel: PanelContainer
var _console_panel: PanelContainer
var _console_log: RichTextLabel
var _console_input: LineEdit
var _help_panel: PanelContainer
var _toast: Label
var _toast_time := 0.0
var _options: OptionsPanel


func setup(game_ref: MatchGame) -> void:
	game = game_ref
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_buy()
	_build_pause()
	_build_scoreboard()
	_build_death()
	_build_end()
	_build_console()
	_build_help()
	_build_toast()
	game.message.connect(func(_t, _c, _d) -> void: pass)
	game.player.scoreboard_changed.connect(_on_scoreboard)
	game.state_changed.connect(func(_s) -> void: _refresh_buy_money())


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _scoreboard.visible:
		_scoreboard.queue_redraw()
	if buy_open:
		_refresh_buy_money()


# --- Menu de compra ------------------------------------------------------------


func _build_buy() -> void:
	_buy_panel = UITheme.panel()
	_buy_panel.visible = false
	_buy_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_buy_panel.custom_minimum_size = Vector2(980, 580)
	_buy_panel.position = Vector2(160, 110)
	_root.add_child(_buy_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_buy_panel.add_child(vb)
	var header := HBoxContainer.new()
	var title := UITheme.title("TIENDA DE EQUIPAMIENTO", 24)
	header.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	_buy_money = UITheme.label("$800", 22, UITheme.ACCENT, true)
	_buy_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_buy_money)
	vb.add_child(header)
	var hint := UITheme.label(
		"B / ESC para cerrar   -   haz clic en un articulo para comprarlo", 12, UITheme.TEXT_DIM
	)
	vb.add_child(hint)
	UITheme.hsep(vb)
	var cat_row := HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 6)
	vb.add_child(cat_row)
	var categories := [
		"TODO",
		"PISTOLAS",
		"ESCOPETAS",
		"SUBFUSILES",
		"FUSILES",
		"FRANCOS",
		"AMETRALLADORAS",
		"GRANADAS",
		"EQUIPO"
	]
	for i in categories.size():
		var b := UITheme.button(String(categories[i]).substr(0, 12), 0, 12)
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(
			func() -> void:
				_buy_category = i
				_refresh_buy()
				AudioBank.play_ui("ui_click")
		)
		cat_row.add_child(b)
	_buy_grid = GridContainer.new()
	_buy_grid.columns = 4
	_buy_grid.add_theme_constant_override("h_separation", 8)
	_buy_grid.add_theme_constant_override("v_separation", 8)
	_buy_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_buy_grid)


func _refresh_buy() -> void:
	if _buy_grid == null:
		return
	for c in _buy_grid.get_children():
		c.queue_free()
	var cats := Content.buy_menu_for_team(game.player.team)
	var items: Array = []
	if _buy_category == 0:
		for cat in cats:
			for id in cat.items:
				if not items.has(id):
					items.append(id)
	else:
		var idx := _buy_category - 1
		if idx < cats.size():
			items = cats[idx].items
	for id in items:
		_buy_grid.add_child(_buy_card(String(id)))
	_refresh_buy_money()


func _buy_card(id: String) -> Control:
	var def := Content.get_weapon(id)
	var is_equip := Content.is_equipment(id)
	var price := Content.item_price(id)
	var owned := false
	if not is_equip:
		var slot: int = int(def.get("slot", 1))
		if slot == Content.SLOT_PRIMARY:
			owned = game.player.primary_id == id
		elif slot == Content.SLOT_SECONDARY:
			owned = game.player.secondary_id == id
		elif slot == Content.SLOT_GRENADE:
			owned = game.player.grenades.has(id)
	else:
		match id:
			"kevlar":
				owned = game.player.armor >= 100.0
			"helmet":
				owned = game.player.helmet
			"defusekit":
				owned = game.player.defusekit
	var card := Button.new()
	card.custom_minimum_size = Vector2(228, 96)
	card.set_meta("price", price)
	card.set_meta("owned", owned)
	card.disabled = owned or price > game.player.money
	card.add_theme_stylebox_override(
		"normal", _card_style(Color(0.07, 0.085, 0.06, 0.95), Color(0.3, 0.28, 0.16))
	)
	card.add_theme_stylebox_override(
		"hover", _card_style(Color(0.14, 0.17, 0.1, 0.98), UITheme.ACCENT)
	)
	card.add_theme_stylebox_override(
		"pressed", _card_style(Color(0.2, 0.22, 0.12, 1.0), UITheme.ACCENT)
	)
	card.add_theme_stylebox_override(
		"disabled", _card_style(Color(0.04, 0.05, 0.04, 0.9), Color(0.18, 0.18, 0.16))
	)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.position = Vector2(8, 6)
	box.size = Vector2(212, 84)
	card.add_child(box)
	var name_label := UITheme.label(Content.item_name(id).to_upper(), 13, UITheme.TEXT, true)
	box.add_child(name_label)
	var info := ""
	if is_equip:
		info = String(Content.EQUIPMENT[id].desc)
	else:
		var cls := UITheme.weapon_icon(def)
		info = "%s  DANO %d" % [cls, int(def.get("damage", 0))]
		if int(def.get("pellets", 1)) > 1:
			info += " x%d" % int(def.get("pellets", 1))
	var info_label := UITheme.label(info, 10, UITheme.TEXT_DIM)
	box.add_child(info_label)
	var price_label := UITheme.label(
		"GRATIS" if price == 0 else "$%d" % price,
		16,
		UITheme.ACCENT if not owned else UITheme.GREEN,
		true
	)
	box.add_child(price_label)
	if owned:
		price_label.text = "EN INVENTARIO"
	card.pressed.connect(
		func() -> void:
			if game.buy_item(id):
				_toast_show("%s COMPRADO" % Content.item_name(id).to_upper(), UITheme.GREEN)
				_refresh_buy()
			else:
				_toast_show("NO DISPONIBLE", UITheme.RED)
	)
	return card


func _card_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = 2
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = border
	s.corner_radius_top_left = 2
	s.corner_radius_bottom_right = 2
	return s


func _center_panel(panel: Control, size_px: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	panel.custom_minimum_size = size_px
	panel.position = (vp - size_px) * 0.5


func open_buy_menu() -> void:
	if paused:
		return
	var vp := get_viewport().get_visible_rect().size
	_center_panel(_buy_panel, Vector2(minf(980, vp.x - 80), minf(580, vp.y - 80)))
	buy_open = true
	_buy_panel.visible = true
	_refresh_buy()
	game.capture_mouse(false)
	game.player.input_enabled = false
	AudioBank.play_ui("ui_click", -2.0)


func close_buy_menu() -> void:
	buy_open = false
	_buy_panel.visible = false
	if not paused and not console_open:
		game.capture_mouse(true)
		game.player.input_enabled = game.player.alive


func _refresh_buy_money() -> void:
	if _buy_money == null or game == null or game.player == null:
		return
	var money := game.player.money
	_buy_money.text = "$%d" % money
	if not buy_open or _buy_grid == null:
		return
	for child in _buy_grid.get_children():
		var card := child as Button
		if card == null:
			continue
		var price := int(card.get_meta("price", 0))
		card.disabled = bool(card.get_meta("owned", false)) or price > money


# --- Pausa ---------------------------------------------------------------------


func _build_pause() -> void:
	_pause_panel = UITheme.panel()
	_pause_panel.visible = false
	_pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_panel.custom_minimum_size = Vector2(520, 430)
	_pause_panel.position = Vector2(540, 235)
	_root.add_child(_pause_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_pause_panel.add_child(vb)
	vb.add_child(UITheme.title("PAUSA", 32))
	var sub := UITheme.label(
		"%s  -  %s" % [game.map_id, game.layout.get("label", "")], 13, UITheme.TEXT_DIM
	)
	vb.add_child(sub)
	UITheme.hsep(vb)
	var resume := UITheme.button("REANUDAR", 0, 17)
	resume.pressed.connect(toggle_pause)
	vb.add_child(resume)
	var options := UITheme.button("OPCIONES", 0, 17)
	options.pressed.connect(_open_options)
	vb.add_child(options)
	var arsenal := UITheme.button("ESTADISTICAS DE LA PARTIDA", 0, 15)
	arsenal.pressed.connect(func() -> void: _on_scoreboard(true))
	vb.add_child(arsenal)
	var leave := UITheme.button("ABANDONAR PARTIDA", 0, 17)
	leave.pressed.connect(_leave_match)
	vb.add_child(leave)
	var quit := UITheme.button("CERRAR JUEGO", 0, 17)
	quit.pressed.connect(
		func() -> void:
			Settings.flush()
			get_tree().quit()
	)
	vb.add_child(quit)
	UITheme.spacer(vb, 6)
	vb.add_child(UITheme.label("ESC para volver  -  el juego queda en pausa", 11, UITheme.TEXT_DIM))


func toggle_pause() -> void:
	if buy_open:
		close_buy_menu()
		return
	if console_open:
		toggle_console()
		return
	if _options != null and is_instance_valid(_options):
		return
	paused = not paused
	get_tree().paused = paused
	_center_panel(_pause_panel, Vector2(520, 430))
	_pause_panel.visible = paused
	if paused:
		if game.player:
			game.player.input_enabled = false
		game.capture_mouse(false)
		AudioBank.play_ui("ui_click")
	else:
		game.capture_mouse(true)
		if game.player and game.player.alive:
			game.player.input_enabled = true


func _open_options() -> void:
	if _options != null and is_instance_valid(_options):
		return
	_options = OptionsPanel.new()
	_root.add_child(_options)
	_options.setup()
	_options.closed.connect(
		func() -> void:
			_options = null
			AudioBank.play_ui("ui_hover")
	)


func _leave_match() -> void:
	get_tree().paused = false
	Settings.flush()
	var app := get_tree().root.get_node_or_null("App")
	if app and app.has_method("goto_menu"):
		app.call("goto_menu")


# --- Marcador ------------------------------------------------------------------


func _build_scoreboard() -> void:
	_scoreboard = Control.new()
	_scoreboard.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard.visible = false
	_scoreboard.draw.connect(_draw_scoreboard)
	_root.add_child(_scoreboard)


func _on_scoreboard(visible: bool) -> void:
	scoreboard_visible = visible
	_scoreboard.visible = visible and not paused
	_scoreboard.size = get_viewport().get_visible_rect().size


func _draw_scoreboard() -> void:
	var vp := _scoreboard.size
	if vp.x < 10:
		vp = get_viewport().get_visible_rect().size
	var w := minf(vp.x * 0.72, 1000.0)
	var h := minf(vp.y * 0.7, 620.0)
	var origin := (vp - Vector2(w, h)) * 0.5
	_scoreboard.draw_rect(Rect2(origin, Vector2(w, h)), Color(0.02, 0.03, 0.02, 0.92), true)
	_scoreboard.draw_rect(Rect2(origin, Vector2(w, h)), Color(0.45, 0.4, 0.2), false, 1.5)
	_scoreboard.draw_string(
		UITheme.FONT_BOLD,
		origin + Vector2(24, 44),
		"%s  //  RONDA %d" % [game.map_id.to_upper(), game.round_number],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		26,
		UITheme.ACCENT
	)
	_scoreboard.draw_string(
		UITheme.FONT_MONO,
		origin + Vector2(w - 260, 44),
		"CT %d   -   %d T" % [game.score_ct, game.score_t],
		HORIZONTAL_ALIGNMENT_RIGHT,
		236,
		22,
		UITheme.TEXT
	)
	var row_y := origin.y + 78
	var cols := [
		origin.x + 24,
		origin.x + 330,
		origin.x + 430,
		origin.x + 520,
		origin.x + 650,
		origin.x + 760
	]
	var heads := ["JUGADOR", "BAJAS", "MUERTES", "HS", "DINERO", "ESTADO"]
	for i in heads.size():
		_scoreboard.draw_string(
			UITheme.FONT_MONO,
			Vector2(cols[i], row_y),
			heads[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			UITheme.TEXT_DIM
		)
	row_y += 22
	_scoreboard.draw_line(
		Vector2(origin.x + 18, row_y),
		Vector2(origin.x + w - 18, row_y),
		Color(0.3, 0.28, 0.18),
		1.0
	)
	row_y += 18
	var rows := game.get_scoreboard()
	for team_id in [Content.TEAM_CT, Content.TEAM_T]:
		if rows.any(func(r): return int(r.team) == team_id):
			_scoreboard.draw_string(
				UITheme.FONT_BOLD,
				Vector2(origin.x + 24, row_y),
				"CT" if team_id == Content.TEAM_CT else "T",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				15,
				UITheme.CT if team_id == Content.TEAM_CT else UITheme.T
			)
			row_y += 22
		for r in rows:
			if int(r.team) != team_id:
				continue
			var col: Color = UITheme.TEXT if r.alive else Color(0.45, 0.45, 0.42)
			if r.is_player:
				_scoreboard.draw_rect(
					Rect2(Vector2(origin.x + 14, row_y - 14), Vector2(w - 28, 22)),
					Color(0.9, 0.8, 0.3, 0.12),
					true
				)
			_scoreboard.draw_string(
				UITheme.FONT_MONO,
				Vector2(cols[0], row_y),
				String(r.name),
				HORIZONTAL_ALIGNMENT_LEFT,
				290,
				15,
				col
			)
			_scoreboard.draw_string(
				UITheme.FONT_MONO,
				Vector2(cols[1], row_y),
				"%d" % r.kills,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				15,
				col
			)
			_scoreboard.draw_string(
				UITheme.FONT_MONO,
				Vector2(cols[2], row_y),
				"%d" % r.deaths,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				15,
				col
			)
			_scoreboard.draw_string(
				UITheme.FONT_MONO,
				Vector2(cols[3], row_y),
				"%d" % r.headshots,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				15,
				col
			)
			_scoreboard.draw_string(
				UITheme.FONT_MONO,
				Vector2(cols[4], row_y),
				"$%d" % r.money,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				15,
				col
			)
			_scoreboard.draw_string(
				UITheme.FONT_MONO,
				Vector2(cols[5], row_y),
				"VIVO" if r.alive else "MUERTO",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				15,
				UITheme.GREEN if r.alive else UITheme.RED
			)
			row_y += 24
		row_y += 10
	if game.mode == "zombie":
		_scoreboard.draw_string(
			UITheme.FONT_MONO,
			origin + Vector2(24, h - 28),
			(
				"OLEADA %d   ZOMBIES ELIMINADOS %d   PUNTOS %d"
				% [game.zombie_wave, game.total_zombies_killed, game.zombie_points]
			),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			15,
			Color(0.8, 0.5, 0.9)
		)


# --- Muerte y fin de partida ---------------------------------------------------


func _build_death() -> void:
	_death_panel = UITheme.panel()
	_death_panel.visible = false
	_death_panel.custom_minimum_size = Vector2(560, 180)
	_death_panel.position = Vector2(520, 520)
	_root.add_child(_death_panel)
	var vb := VBoxContainer.new()
	_death_panel.add_child(vb)
	var title := UITheme.label("HAS CAIDO", 30, Color(0.9, 0.25, 0.2), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := UITheme.label("", 15, UITheme.TEXT_DIM)
	sub.name = "KillerLabel"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var tip := UITheme.label("Observa a tu equipo hasta la proxima ronda", 12, UITheme.TEXT_DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tip)


func show_death(killer: String) -> void:
	if game.mode == "zombie":
		return
	_center_panel(_death_panel, Vector2(560, 180))
	_death_panel.visible = true
	var l := _death_panel.find_child("KillerLabel", true, false) as Label
	if l:
		l.text = "Eliminado por %s" % (killer if killer != "" else "el entorno")
	var t := get_tree().create_timer(3.0, true, false, true)
	t.timeout.connect(func() -> void: _death_panel.visible = false)


func _build_end() -> void:
	_end_panel = UITheme.panel()
	_end_panel.visible = false
	_end_panel.custom_minimum_size = Vector2(640, 380)
	_end_panel.position = Vector2(480, 260)
	_root.add_child(_end_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.name = "Box"
	_end_panel.add_child(vb)


func show_match_end(won: bool, score_ct: int, score_t: int) -> void:
	_center_panel(_end_panel, Vector2(640, 380))
	_end_panel.visible = true
	game.capture_mouse(false)
	var vb := _end_panel.find_child("Box", true, false) as VBoxContainer
	for c in vb.get_children():
		c.queue_free()
	var title := UITheme.label(
		"VICTORIA" if won else "DERROTA", 42, UITheme.GREEN if won else UITheme.RED, true
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var score := UITheme.label("CT %d  -  %d T" % [score_ct, score_t], 26, UITheme.ACCENT, true)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(score)
	var stats := UITheme.label(
		(
			"Bajas: %d   Muertes: %d   Headshots: %d   Dinero: $%d"
			% [game.player.kills, game.player.deaths, game.player.headshots, game.player.money]
		),
		15,
		UITheme.TEXT
	)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(stats)
	UITheme.hsep(vb)
	var again := UITheme.button("REVANCHA", 0, 17)
	again.pressed.connect(
		func() -> void:
			get_tree().paused = false
			var app := get_tree().root.get_node_or_null("App")
			if app and app.has_method("restart_match"):
				app.call("restart_match")
	)
	vb.add_child(again)
	var leave := UITheme.button("VOLVER AL MENU", 0, 17)
	leave.pressed.connect(_leave_match)
	vb.add_child(leave)


func show_zombie_gameover(wave: int, kills: int) -> void:
	_center_panel(_end_panel, Vector2(640, 380))
	_end_panel.visible = true
	game.capture_mouse(false)
	var vb := _end_panel.find_child("Box", true, false) as VBoxContainer
	for c in vb.get_children():
		c.queue_free()
	var title := UITheme.label("GAME OVER", 46, Color(0.9, 0.28, 0.3), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := UITheme.label(
		"Llegaste a la oleada %d  -  %d zombies eliminados" % [wave, kills], 18, UITheme.TEXT, true
	)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var best := UITheme.label(
		"Record personal: oleada %d" % int(Settings.data.progress.get("zombie_best_wave", 0)),
		14,
		UITheme.ACCENT
	)
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(best)
	UITheme.hsep(vb)
	var again := UITheme.button("VOLVER A JUGAR", 0, 17)
	again.pressed.connect(
		func() -> void:
			get_tree().paused = false
			var app := get_tree().root.get_node_or_null("App")
			if app and app.has_method("restart_match"):
				app.call("restart_match")
	)
	vb.add_child(again)
	var leave := UITheme.button("VOLVER AL MENU", 0, 17)
	leave.pressed.connect(_leave_match)
	vb.add_child(leave)


# --- Consola -------------------------------------------------------------------


func _build_console() -> void:
	_console_panel = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.01, 0.015, 0.01, 0.9)
	s.border_width_top = 1
	s.border_color = Color(0.4, 0.36, 0.2, 0.7)
	_console_panel.add_theme_stylebox_override("panel", s)
	_console_panel.visible = false
	_console_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_console_panel.custom_minimum_size = Vector2(0, 300)
	_console_panel.offset_top = -300
	_root.add_child(_console_panel)
	var vb := VBoxContainer.new()
	_console_panel.add_child(vb)
	_console_log = RichTextLabel.new()
	_console_log.bbcode_enabled = true
	_console_log.scroll_following = true
	_console_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_console_log.add_theme_font_override("normal_font", UITheme.FONT_MONO)
	_console_log.add_theme_font_size_override("normal_font_size", 13)
	vb.add_child(_console_log)
	_console_input = LineEdit.new()
	_console_input.placeholder_text = "comando... (help, give ak47, noclip, god, kill, map de_dust2, wave 5, money 16000, clear)"
	_console_input.add_theme_font_override("font", UITheme.FONT_MONO)
	_console_input.text_submitted.connect(_on_console_command)
	vb.add_child(_console_input)
	var banner := "[color=#c8b23a]Consola Papita v1.0[/color] - escribe "
	banner += "[color=#c8b23a]help[/color] para ver comandos\n"
	_console_log.append_text(banner)


func toggle_console() -> void:
	console_open = not console_open
	_console_panel.visible = console_open
	if console_open:
		game.capture_mouse(false)
		game.player.input_enabled = false
		_console_input.grab_focus()
	else:
		_console_input.release_focus()
		if not buy_open and not paused:
			game.capture_mouse(true)
			game.player.input_enabled = true


func _on_console_command(text: String) -> void:
	var parts := text.strip_edges().split(" ", false)
	if parts.is_empty():
		return
	_console_log.append_text("[color=#6b8f5a]> %s[/color]\n" % text)
	var cmd := String(parts[0]).to_lower()
	var args := Array(parts.slice(1))
	var out := _run_command(cmd, args)
	if out != "":
		_console_log.append_text(out + "\n")
	_console_input.clear()


func _run_command(cmd: String, args: Array) -> String:
	match cmd:
		"help":
			return "Comandos: give <arma> | money <n> | god | noclip | kill | heal | bots <n> | wave <n> | nextwave | map <id> | difficulty <0-4> | time <seg> | selftest | clear | quit"
		"selftest":
			return _run_selftest()
		"clear":
			_console_log.clear()
			return ""
		"give":
			if args.is_empty():
				return "Uso: give <id de arma>"
			var id := String(args[0])
			if not Content.WEAPONS.has(id):
				return "Arma desconocida. Prueba ak47, m4a1, awp, deagle, mp5, hegrenade..."
			game.player.give_weapon(id, true)
			return "Entregado: " + id
		"money":
			var n := int(args[0]) if not args.is_empty() else 16000
			game.player.money = n
			if game.mode == "zombie":
				game.zombie_points = n
			return "Dinero: %d" % n
		"god":
			game.player.god_mode = not game.player.god_mode
			return "God mode: %s" % ("ON" if game.player.god_mode else "OFF")
		"noclip":
			game.player.invulnerable = not game.player.invulnerable
			game.player.collision_mask = (
				0 if game.player.invulnerable else 1 | Combatant.PLAYER_LAYER
			)
			game.player.velocity = Vector3.ZERO
			return "Noclip/invulnerable: %s" % ("ON" if game.player.invulnerable else "OFF")
		"kill":
			game.player.take_damage(1000.0, null, "head", "console")
			return "Kill aplicado"
		"heal":
			game.player.health = game.player.max_health
			game.player.armor = 100.0
			game.player.health_changed.emit(game.player, game.player.health, game.player.armor)
			return "Curado"
		"bots":
			return "Los bots se definen al iniciar la partida (menu principal)."
		"wave":
			if game.mode != "zombie":
				return "Solo en modo zombie."
			var w := maxi(1, int(args[0]) if not args.is_empty() else game.zombie_wave + 1)
			game.zombie_wave = w - 1
			game._start_wave()
			return "Saltando a oleada %d" % w
		"nextwave":
			if game.mode != "zombie":
				return "Solo en modo zombie."
			for z in game.zombies:
				if is_instance_valid(z) and z.alive:
					z.take_damage(99999.0, null, "chest", "console")
			game.zombie_spawn_queue = 0
			return "Oleada limpiada"
		"map":
			if args.is_empty():
				var map_ids := PackedStringArray(Content.MAPS.map(func(m): return m.id))
				return "Mapas: " + ", ".join(map_ids)
			var app := get_tree().root.get_node_or_null("App")
			if app and app.has_method("start_match"):
				app.call(
					"start_match",
					String(args[0]),
					game.mode,
					game.player_team,
					int(Settings.data.gameplay.get("bots", 7)),
					int(Settings.data.gameplay.get("difficulty", 2))
				)
			return "Cargando " + String(args[0])
		"difficulty":
			var d := clampi(int(args[0]) if not args.is_empty() else 2, 0, 4)
			game.difficulty = Content.difficulty(d)
			game.apply_difficulty_to_bots()
			return "Dificultad: " + String(game.difficulty.name)
		"time":
			game.round_time_left = float(args[0]) if not args.is_empty() else 30.0
			return "Tiempo de ronda ajustado"
		"quit":
			Settings.flush()
			get_tree().quit()
			return ""
	return "Comando desconocido: " + cmd


# --- Autodiagnostico -----------------------------------------------------------


func _run_selftest() -> String:
	var problems: Array[String] = []
	var gun_keys := [
		"id",
		"name",
		"slot",
		"team",
		"price",
		"damage",
		"rpm",
		"mag",
		"reserve",
		"reload",
		"spread",
		"recoil",
		"range",
		"auto",
		"speed_mult",
		"award",
		"sound"
	]
	var light_keys := ["id", "name", "slot", "team", "price", "damage", "rpm", "speed_mult"]
	for id in Content.WEAPONS.keys():
		var def: Dictionary = Content.WEAPONS[id]
		var slot := int(def.get("slot", 1))
		var need: Array = light_keys
		if slot == Content.SLOT_PRIMARY or slot == Content.SLOT_SECONDARY:
			need = gun_keys
		for key in need:
			if not def.has(key):
				problems.append("ARMA %s sin '%s'" % [id, key])
		var vm: Dictionary = def.get("vm", {})
		if not vm.has("kind"):
			problems.append("ARMA %s sin modelo 3D" % id)
	for m in Content.MAPS:
		var lay: Dictionary = Maps.build(String(m.id))
		if lay.is_empty():
			problems.append("MAPA %s sin layout" % m.id)
			continue
		var zombie_spawns: Array = lay.get("zombie_spawns", [])
		var spawns_ct: Array = lay.get("spawns_ct", [])
		var spawns_t: Array = lay.get("spawns_t", [])
		var sites: Array = lay.get("sites", [])
		if String(m.mode) == "zombie":
			if zombie_spawns.is_empty():
				problems.append("MAPA %s sin spawns de zombie" % m.id)
			continue
		if spawns_ct.is_empty():
			problems.append("MAPA %s sin spawns CT" % m.id)
		if spawns_t.is_empty():
			problems.append("MAPA %s sin spawns T" % m.id)
		if String(m.mode) == "bomb" and sites.size() < 2:
			problems.append("MAPA %s con menos de 2 sitios" % m.id)
	if problems.is_empty():
		return (
			"SELFTEST OK: %d armas y %d mapas validados."
			% [Content.WEAPONS.size(), Content.MAPS.size()]
		)
	var out := "SELFTEST: %d problemas\n" % problems.size()
	for line in problems:
		out += " - " + line + "\n"
	return out


# --- Ayuda ---------------------------------------------------------------------


func _build_help() -> void:
	_help_panel = UITheme.panel()
	_help_panel.visible = false
	_help_panel.custom_minimum_size = Vector2(760, 480)
	_root.add_child(_help_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_help_panel.add_child(vb)
	vb.add_child(UITheme.title("CONTROLES", 24))
	UITheme.hsep(vb)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	var bindings: Dictionary = Settings.data.controls
	for action in InputSetup.rebindable_actions():
		var l := UITheme.label(String(InputSetup.LABELS.get(action, action)), 14, UITheme.TEXT)
		grid.add_child(l)
		var k := UITheme.label(InputSetup.key_name(action, bindings), 14, UITheme.ACCENT, true)
		grid.add_child(k)
	UITheme.hsep(vb)
	vb.add_child(
		UITheme.label(
			"Ratón: apuntar / disparar (izq) / mira y silenciador (der) / rueda: cambiar arma",
			13,
			UITheme.TEXT_DIM
		)
	)
	vb.add_child(
		UITheme.label("F1 cierra esta ayuda  -  TAB marcador  -  ESC pausa", 13, UITheme.TEXT_DIM)
	)


func toggle_help() -> void:
	help_open = not help_open
	_center_panel(_help_panel, Vector2(760, 480))
	_help_panel.visible = help_open
	if help_open:
		game.capture_mouse(false)
		game.player.input_enabled = false
	else:
		game.capture_mouse(true)
		game.player.input_enabled = game.player.alive and not paused


# --- Avisos --------------------------------------------------------------------


func _build_toast() -> void:
	_toast = UITheme.label("", 18, UITheme.GREEN, true)
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(0, 120)
	_toast.modulate.a = 0.0
	_root.add_child(_toast)


func _toast_show(text: String, color: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.modulate.a = 1.0
	_toast_time = 1.6
	var vp := get_viewport().get_visible_rect().size
	_toast.size = Vector2(vp.x, 30)
	_toast.position = Vector2(0, vp.y * 0.22)


# --- Entrada -------------------------------------------------------------------


func _input(event: InputEvent) -> void:
	if _options != null and is_instance_valid(_options):
		return
	if event.is_action_pressed("pause") and (paused or buy_open or console_open or help_open):
		if buy_open:
			close_buy_menu()
		elif console_open:
			toggle_console()
		elif help_open:
			toggle_help()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if buy_open and event.is_action_pressed("buy"):
		close_buy_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("scoreboard") and not paused:
		_on_scoreboard(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("scoreboard"):
		_on_scoreboard(false)
	if console_open and event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.physical_keycode == KEY_ESCAPE:
			toggle_console()
			get_viewport().set_input_as_handled()
