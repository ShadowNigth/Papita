extends Control
## HUD: mira, vida/chaleco, municion, dinero, radar, killfeed, mensajes,
## avisos de bomba, informacion zombie, overlays de flash y mira telescopica.

class_name Hud

const SCOPE_SHADER := preload("res://shaders/scope.gdshader")

var game: MatchGame
var player: Player
var font_mono: Font = UITheme.FONT_MONO
var font_bold: Font = UITheme.FONT_BOLD
var font_body: Font = UITheme.FONT_BODY

var messages: Array = []
var killfeed: Array = []
var hitmarker_timer := 0.0
var hitmarker_headshot := false
var damage_timer := 0.0
var progress_text := ""
var progress_value := 0.0
var progress_visible := false
var _radar_texture: ImageTexture
var _vignette: ImageTexture
var _damage_rect: TextureRect
var _flash_rect: ColorRect
var _scope_rect: ColorRect
var _scope_mat: ShaderMaterial
var _health_pulse := 0.0
var _time := 0.0
var _zombie_flash := 0.0


func setup(game_ref: MatchGame) -> void:
	game = game_ref
	player = game.player
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(_on_resize)
	_build_overlays()
	_build_minimap()
	_build_vignette()
	game.message.connect(_on_message)
	game.kill_event.connect(_on_kill)
	game.player_died.connect(func() -> void: damage_timer = 1.0)
	if player:
		player.damaged.connect(func(_v, _a, _att, _hb, _w) -> void: damage_timer = 0.65)
	visible = true


func _on_resize() -> void:
	size = get_viewport_rect().size
	_update_overlay_sizes()
	queue_redraw()


func _build_overlays() -> void:
	_damage_rect = TextureRect.new()
	_damage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_damage_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_damage_rect.modulate = Color(1, 1, 1, 0)
	add_child(_damage_rect)

	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)

	_scope_rect = ColorRect.new()
	_scope_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope_mat = ShaderMaterial.new()
	_scope_mat.shader = SCOPE_SHADER
	_scope_rect.material = _scope_mat
	_scope_rect.visible = false
	add_child(_scope_rect)
	_update_overlay_sizes()


func _update_overlay_sizes() -> void:
	var vp := get_viewport_rect().size
	for c in [_damage_rect, _flash_rect, _scope_rect]:
		if c:
			c.size = vp
	_scope_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	if _vignette:
		_damage_rect.texture = _vignette


func _build_vignette() -> void:
	var s := 160
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s * 0.55)
			var a := clampf(pow(clampf(d - 0.35, 0.0, 1.0), 1.8), 0.0, 1.0)
			img.set_pixel(x, y, Color(0.6, 0.02, 0.02, a * 0.9))
	_vignette = ImageTexture.create_from_image(img)
	_damage_rect.texture = _vignette


func _build_minimap() -> void:
	if game == null or game.nav == null:
		return
	var nav := game.nav
	var img := Image.create(nav.cols, nav.rows, false, Image.FORMAT_RGBA8)
	for y in nav.rows:
		for x in nav.cols:
			var blocked := nav.blocked[y * nav.cols + x] == 1
			if blocked:
				img.set_pixel(x, y, Color(0.04, 0.05, 0.04, 0.85))
			else:
				var h: float = nav.heights[y * nav.cols + x]
				var shade := 0.22 + clampf(h / 4.0, 0.0, 1.0) * 0.18
				img.set_pixel(x, y, Color(0.13, shade, 0.14, 0.9))
	_radar_texture = ImageTexture.create_from_image(img)


func _on_message(text: String, color: Color, duration: float) -> void:
	messages.append({"text": text, "color": color, "until": _time + duration})
	if messages.size() > 4:
		messages.pop_front()


func _on_kill(
	killer: String, victim: String, weapon_id: String, headshot: bool, killer_team: int
) -> void:
	var wname := "C4"
	var def := Content.get_weapon(weapon_id)
	if not def.is_empty():
		wname = String(def.name)
	var color := UITheme.CT if killer_team == Content.TEAM_CT else UITheme.T
	var entry_text := "%s  [%s]  %s%s" % [killer, wname, victim, "  HS" if headshot else ""]
	var entry := {"text": entry_text, "color": color, "until": _time + 6.0}
	killfeed.append(entry)
	if killfeed.size() > 6:
		killfeed.pop_front()


func show_hitmarker(headshot: bool = false) -> void:
	hitmarker_timer = 0.22
	hitmarker_headshot = headshot


func on_damage_dealt(_victim: Combatant) -> void:
	hitmarker_timer = maxf(hitmarker_timer, 0.14)


func on_player_hurt(_amount: float) -> void:
	damage_timer = 0.7
	_health_pulse = 1.0


func on_zombie_killed(_victim: Combatant) -> void:
	_zombie_flash = 0.4


func on_buy(_id: String) -> void:
	_on_message("COMPRADO", UITheme.GREEN, 1.0)


func show_progress(text: String, value: float) -> void:
	progress_text = text
	progress_value = clampf(value, 0.0, 1.0)
	progress_visible = true


func hide_progress() -> void:
	progress_visible = false


func _process(delta: float) -> void:
	_time += delta
	hitmarker_timer = maxf(0.0, hitmarker_timer - delta)
	damage_timer = maxf(0.0, damage_timer - delta)
	_health_pulse = maxf(0.0, _health_pulse - delta * 2.0)
	_zombie_flash = maxf(0.0, _zombie_flash - delta)
	for i in range(messages.size() - 1, -1, -1):
		if messages[i].until < _time:
			messages.remove_at(i)
	for i in range(killfeed.size() - 1, -1, -1):
		if killfeed[i].until < _time:
			killfeed.remove_at(i)
	if game == null or player == null:
		return
	var blind := 0.0
	if player.has_method("blind_factor"):
		blind = player.blind_factor()
	var flash_a := clampf(blind * 0.95, 0.0, 0.97)
	_flash_rect.visible = flash_a > 0.004
	if _flash_rect.visible:
		_flash_rect.color = Color(1, 1, 1, flash_a)
	var low := clampf(1.0 - player.health / maxf(player.max_health, 1.0), 0.0, 1.0)
	var hurt := maxf(damage_timer * 1.1, low * 0.55)
	if player.health < 30.0 and player.alive:
		hurt = maxf(hurt, 0.25 + sin(_time * 5.0) * 0.08)
	_damage_rect.visible = hurt > 0.004
	if _damage_rect.visible:
		_damage_rect.modulate = Color(1, 1, 1, hurt)
	# Mira telescopica (solo rifles francotiradores; AUG y SG552 usan zoom limpio como en CS 1.5).
	var def_now := player.current_def()
	var scoped := (
		player.alive
		and player.zoom_level > 0
		and float(def_now.get("zoom", 0.0)) > 0.0
		and String(def_now.get("cls", "")) == "sniper"
	)
	_scope_rect.visible = scoped
	if scoped:
		_scope_mat.set_shader_parameter("radius", 0.44)
	queue_redraw()


func _draw() -> void:
	if game == null or player == null:
		return
	var vp := size
	if vp.x < 10:
		vp = get_viewport_rect().size
	var s := (
		clampf(minf(vp.x / 1600.0, vp.y / 900.0), 0.62, 1.6)
		* float(Settings.data.gameplay.get("hud_scale", 1.0))
	)
	_draw_crosshair(vp, s)
	_draw_vitals(vp, s)
	_draw_ammo(vp, s)
	_draw_top(vp, s)
	_draw_radar(vp, s)
	_draw_killfeed(vp, s)
	_draw_messages(vp, s)
	_draw_interaction(vp, s)
	_draw_hitmarker(vp, s)
	_draw_zombie(vp, s)
	_draw_fps(vp, s)


func _txt(
	pos: Vector2,
	text: String,
	size_px: int,
	color: Color,
	align: int = HORIZONTAL_ALIGNMENT_LEFT,
	width: float = -1.0,
	font: Font = UITheme.FONT_MONO
) -> void:
	draw_string(font, pos, text, align, width, size_px, color)


func _draw_crosshair(vp: Vector2, s: float) -> void:
	if not player.alive or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var cdef := player.current_def()
	if (
		player.zoom_level > 0
		and float(cdef.get("zoom", 0.0)) > 0.0
		and String(cdef.get("cls", "")) == "sniper"
	):
		return
	if game.ingame_ui and game.ingame_ui.get("buy_open"):
		return
	var center := vp * 0.5
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var gap := (4.0 + speed * 1.6 + (0.0 if player.is_on_floor() else 9.0)) * s
	gap += absf(player.recoil_pitch) * 900.0 * s
	gap = clampf(gap, 3.0, 34.0) * s
	var col := Color(0.35, 1.0, 0.52)
	var hex := String(Settings.data.gameplay.get("crosshair_color", "4ade80")).replace("#", "")
	if hex.is_valid_html_color():
		col = Color.from_string(hex, col)
	if Settings.data.gameplay.get("crosshair_dynamic", true):
		pass
	col.a = 0.92
	var thick := maxf(1.4, 2.0 * s)
	draw_line(center + Vector2(-gap - 7 * s, 0), center + Vector2(-gap, 0), col, thick)
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + 7 * s, 0), col, thick)
	draw_line(center + Vector2(0, -gap - 7 * s), center + Vector2(0, -gap), col, thick)
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + 7 * s), col, thick)
	draw_circle(center, maxf(1.0, 1.2 * s), Color(col.r, col.g, col.b, 0.8))
	# Punto de impacto / hitmarker.
	if hitmarker_timer > 0.0:
		var hc := Color(1.0, 0.85, 0.3) if hitmarker_headshot else Color(1.0, 1.0, 1.0)
		hc.a = clampf(hitmarker_timer / 0.22, 0.0, 1.0)
		var r1 := 10.0 * s
		var r2 := 20.0 * s
		draw_line(center + Vector2(r1, r1), center + Vector2(r2, r2), hc, 2.0 * s)
		draw_line(center + Vector2(-r1, r1), center + Vector2(-r2, r2), hc, 2.0 * s)
		draw_line(center + Vector2(r1, -r1), center + Vector2(r2, -r2), hc, 2.0 * s)
		draw_line(center + Vector2(-r1, -r1), center + Vector2(-r2, -r2), hc, 2.0 * s)
		draw_circle(center, 3.0 * s, Color(hc.r, hc.g, hc.b, hc.a * 0.8))


func _draw_vitals(vp: Vector2, s: float) -> void:
	var base := Vector2(42 * s, vp.y - 44 * s)
	var panel_w := 360 * s
	var panel_h := 96 * s
	draw_rect(
		Rect2(base + Vector2(-10, -74 * s), Vector2(panel_w, panel_h)),
		Color(0.02, 0.03, 0.02, 0.45),
		true
	)
	# Salud.
	var hp := clampf(player.health / maxf(player.max_health, 1.0), 0.0, 1.0)
	var hp_color := UITheme.GREEN if hp > 0.5 else (UITheme.ORANGE if hp > 0.25 else UITheme.RED)
	if _health_pulse > 0.0:
		hp_color = hp_color.lerp(Color.WHITE, _health_pulse * 0.5)
	draw_rect(
		Rect2(base + Vector2(0, -30 * s), Vector2(230 * s, 16 * s)),
		Color(0.08, 0.09, 0.08, 0.9),
		true
	)
	draw_rect(Rect2(base + Vector2(0, -30 * s), Vector2(230 * s * hp, 16 * s)), hp_color, true)
	draw_rect(
		Rect2(base + Vector2(0, -30 * s), Vector2(230 * s, 16 * s)), Color(0, 0, 0, 0.8), false, 1.0
	)
	_txt(base + Vector2(0, -40 * s), "VIDA", int(13 * s), UITheme.TEXT_DIM)
	_txt(
		base + Vector2(238 * s, -15 * s),
		"%d" % int(player.health),
		int(30 * s),
		hp_color,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_bold
	)
	# Chaleco.
	var ar := clampf(player.armor / 100.0, 0.0, 1.0)
	draw_rect(
		Rect2(base + Vector2(0, 2 * s), Vector2(230 * s, 9 * s)), Color(0.08, 0.09, 0.08, 0.9), true
	)
	draw_rect(
		Rect2(base + Vector2(0, 2 * s), Vector2(230 * s * ar, 9 * s)), Color(0.45, 0.65, 0.95), true
	)
	_txt(
		base + Vector2(0, 34 * s),
		"CHALECO %d%s" % [int(player.armor), "  +CASCO" if player.helmet else ""],
		int(13 * s),
		Color(0.6, 0.72, 0.9)
	)
	# Dinero.
	var money_col := UITheme.ACCENT
	_txt(
		base + Vector2(230 * s, 56 * s),
		"$%d" % player.money,
		int(24 * s),
		money_col,
		HORIZONTAL_ALIGNMENT_RIGHT,
		130 * s,
		font_bold
	)
	# Perks zombie.
	if game.mode == "zombie":
		var px := base + Vector2(0, -64 * s)
		for id in Content.PERKS.keys():
			var info: Dictionary = Content.PERKS[id]
			var owned: bool = player.has_meta("perk_" + id)
			var col: Color = info.color if owned else Color(0.12, 0.12, 0.12)
			draw_circle(px + Vector2(12 * s, 0), 11 * s, col)
			draw_arc(px + Vector2(12 * s, 0), 11 * s, 0, TAU, 20, Color(0, 0, 0, 0.8), 1.5)
			_txt(
				px + Vector2(7 * s, 5 * s),
				String(info.icon),
				int(12 * s),
				Color.WHITE if owned else Color(0.5, 0.5, 0.5),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_bold
			)
			px.x += 28 * s


func _draw_ammo(vp: Vector2, s: float) -> void:
	var right := Vector2(vp.x - 42 * s, vp.y - 44 * s)
	var def := player.current_def()
	var wname := String(def.get("name", "Cuchillo")).to_upper()
	_txt(
		right + Vector2(-330 * s, -74 * s),
		wname,
		int(20 * s),
		UITheme.TEXT,
		HORIZONTAL_ALIGNMENT_RIGHT,
		330 * s,
		font_bold
	)
	var a := player.current_ammo()
	var ammo_str := player.ammo_text()
	var ammo_col := UITheme.TEXT
	if player.current_slot != Content.SLOT_KNIFE and player.current_slot != Content.SLOT_C4:
		if a.x == 0:
			ammo_col = UITheme.RED
		elif a.x <= int(def.get("mag", 1)) * 0.25:
			ammo_col = UITheme.ORANGE
	_txt(
		right + Vector2(0, 2 * s),
		ammo_str,
		int(34 * s),
		ammo_col,
		HORIZONTAL_ALIGNMENT_RIGHT,
		330 * s,
		font_bold
	)
	var mode_txt := player.fire_mode_label()
	if not player.grenades.is_empty():
		mode_txt += "   GRANADAS %d" % player.grenades.size()
	_txt(
		right + Vector2(-330 * s, -34 * s),
		mode_txt,
		int(13 * s),
		UITheme.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_RIGHT,
		330 * s
	)
	# Barra de recarga.
	if player.reload_time_left > 0.0 and player.reload_total > 0.0:
		var k := 1.0 - player.reload_time_left / player.reload_total
		var bar := Rect2(right + Vector2(-230 * s, -22 * s), Vector2(230 * s, 6 * s))
		draw_rect(bar, Color(0.1, 0.1, 0.09, 0.85), true)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), UITheme.ACCENT, true)
		_txt(right + Vector2(-230 * s, -30 * s), "RECARGANDO", int(12 * s), UITheme.ACCENT_DIM)
	# Flashlight indicator.
	if player.flashlight and player.flashlight.visible:
		_txt(right + Vector2(-330 * s, -56 * s), "LINTERNA ON", int(12 * s), UITheme.ACCENT_DIM)


func _draw_top(vp: Vector2, s: float) -> void:
	var center := vp.x * 0.5
	var y := 34 * s
	var box_w := 150 * s
	if game.mode == "zombie":
		_txt(
			Vector2(center - box_w, y - 4 * s),
			"OLEADA %d" % game.zombie_wave,
			int(26 * s),
			Color(0.9, 0.55, 0.95),
			HORIZONTAL_ALIGNMENT_CENTER,
			box_w * 2,
			font_bold
		)
		_txt(
			Vector2(center - box_w, y + 18 * s),
			"ZOMBIES EN PIE: %d" % game._alive_zombies(),
			int(13 * s),
			UITheme.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER,
			box_w * 2
		)
		return
	draw_rect(
		Rect2(Vector2(center - box_w, 12 * s), Vector2(box_w * 2, 54 * s)),
		Color(0.02, 0.03, 0.02, 0.55),
		true
	)
	# Marcador CT / T.
	_txt(
		Vector2(center - box_w + 14 * s, y + 22 * s),
		"CT %d" % game.score_ct,
		int(22 * s),
		UITheme.CT,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_bold
	)
	_txt(
		Vector2(center + box_w - 14 * s, y + 22 * s),
		"%d T" % game.score_t,
		int(22 * s),
		UITheme.T,
		HORIZONTAL_ALIGNMENT_RIGHT,
		-1,
		font_bold
	)
	_txt(
		Vector2(center - 60 * s, y + 22 * s),
		game.time_string(),
		int(24 * s),
		UITheme.ACCENT,
		HORIZONTAL_ALIGNMENT_CENTER,
		120 * s,
		font_bold
	)
	var sub := "RONDA %d" % game.round_number
	if game.mode == "deathmatch":
		sub = "DEATHMATCH - META %d" % MatchGame.DM_FRAG_LIMIT
	elif game.round_state == "freeze":
		sub = "CONGELADO - COMPRA"
	_txt(
		Vector2(center - 120 * s, y + 42 * s),
		sub,
		int(13 * s),
		UITheme.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_CENTER,
		240 * s
	)
	if (
		game.mode == "deathmatch"
		and player.alive
		and player.has_meta("dm_spawn_shield")
		and bool(player.get_meta("dm_spawn_shield"))
	):
		_txt(
			Vector2(center - 140 * s, 78 * s),
			"PROTECCION DE REAPARICION",
			int(13 * s),
			UITheme.ACCENT,
			HORIZONTAL_ALIGNMENT_CENTER,
			280 * s,
			font_bold
		)
	if game.bomb and game.bomb.planted:
		var blink := 0.5 + 0.5 * sin(_time * 8.0)
		draw_rect(
			Rect2(Vector2(center - 110 * s, 74 * s), Vector2(220 * s, 28 * s)),
			Color(0.4, 0.02, 0.02, 0.5 + blink * 0.3),
			true
		)
		_txt(
			Vector2(center - 110 * s, 94 * s),
			"C4 PLANTADO",
			int(18 * s),
			Color(1.0, 0.35, 0.25),
			HORIZONTAL_ALIGNMENT_CENTER,
			220 * s,
			font_bold
		)
	elif (
		game.mode != "zombie"
		and game.round_state == "live"
		and game.time_string().begins_with("0:0")
	):
		pass
	if game.mode == "hostage":
		var rescued := 0
		for h in game.hostages:
			if h.rescued:
				rescued += 1
		_txt(
			Vector2(center - 120 * s, 78 * s),
			"REHENES %d/%d" % [rescued, game.hostages.size()],
			int(14 * s),
			UITheme.GREEN,
			HORIZONTAL_ALIGNMENT_CENTER,
			240 * s
		)


func _draw_radar(vp: Vector2, s: float) -> void:
	var size_px := 196 * s
	var origin := Vector2(vp.x - size_px - 30 * s, 96 * s)
	draw_rect(Rect2(origin, Vector2(size_px, size_px)), Color(0.015, 0.02, 0.015, 0.72), true)
	draw_rect(Rect2(origin, Vector2(size_px, size_px)), Color(0.4, 0.36, 0.2, 0.7), false, 1.5)
	if _radar_texture and game.nav:
		draw_texture_rect(
			_radar_texture,
			Rect2(origin + Vector2(4, 4), Vector2(size_px - 8, size_px - 8)),
			false,
			Color(0.8, 0.9, 0.8, 0.75)
		)
		# Entidades.
		var bounds := game.nav.bounds
		var to_radar := func(p: Vector3) -> Vector2:
			var u := (p.x - bounds.position.x) / maxf(bounds.size.x, 1.0)
			var v := (p.z - bounds.position.y) / maxf(bounds.size.y, 1.0)
			return origin + Vector2(4 + u * (size_px - 8), 4 + v * (size_px - 8))
		for c in game.all_combatants:
			if not is_instance_valid(c) or not c.alive:
				continue
			if c == player:
				continue
			var pos: Vector2 = to_radar.call(c.global_position)
			var col := UITheme.CT
			if c.is_hostage:
				col = Color(0.95, 0.9, 0.35)
			elif c.is_zombie:
				col = Color(0.45, 0.9, 0.3)
			elif c.team != player.team:
				col = UITheme.T
			draw_circle(pos, 3.2 * s, col)
		if game.bomb and game.bomb.planted:
			var bp: Vector2 = to_radar.call(game.bomb.global_position)
			draw_rect(Rect2(bp - Vector2(5, 5) * s, Vector2(10, 10) * s), Color(1, 0.15, 0.1))
		for site in game.layout.get("sites", []):
			var sp: Vector2 = to_radar.call(site.center)
			_txt(
				sp + Vector2(-5 * s, 5 * s),
				String(site.name),
				int(12 * s),
				Color(1, 0.5, 0.4),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_bold
			)
		# Jugador.
		var pp: Vector2 = to_radar.call(player.global_position)
		var yaw := player.global_rotation.y
		var dir := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(dir.y, -dir.x)
		var tri := PackedVector2Array(
			[
				pp + dir * 7.0 * s,
				pp - dir * 4.0 * s + side * 4.5 * s,
				pp - dir * 4.0 * s - side * 4.5 * s,
			]
		)
		draw_colored_polygon(tri, Color(1, 1, 1))
		draw_polyline(
			PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0, 0.8), 1.0
		)
	_txt(
		origin + Vector2(0, size_px + 16 * s), game.map_id.to_upper(), int(12 * s), UITheme.TEXT_DIM
	)


func _draw_killfeed(vp: Vector2, s: float) -> void:
	var y := 30 * s
	var x := vp.x - 330 * s
	for entry in killfeed:
		var alpha := clampf((entry.until - _time) / 1.2, 0.0, 1.0)
		var col: Color = entry.color
		col.a = alpha
		_txt(
			Vector2(x, y), String(entry.text), int(13 * s), col, HORIZONTAL_ALIGNMENT_RIGHT, 300 * s
		)
		y += 18 * s


func _draw_messages(vp: Vector2, s: float) -> void:
	var y := vp.y * 0.30
	for m in messages:
		var alpha := clampf((m.until - _time) / 0.8, 0.0, 1.0)
		var col: Color = m.color
		col.a = alpha
		_txt(
			Vector2(0, y),
			String(m.text),
			int(19 * s),
			col,
			HORIZONTAL_ALIGNMENT_CENTER,
			vp.x,
			font_bold
		)
		y += 28 * s


func _draw_interaction(vp: Vector2, s: float) -> void:
	var hint: String = game.interaction_hint_for(player) if player.alive else ""
	if hint != "":
		var w := 520 * s
		var rect := Rect2(Vector2(vp.x * 0.5 - w * 0.5, vp.y * 0.66), Vector2(w, 34 * s))
		draw_rect(rect, Color(0.02, 0.03, 0.02, 0.6), true)
		draw_rect(rect, Color(0.5, 0.45, 0.25, 0.7), false, 1.0)
		_txt(
			Vector2(vp.x * 0.5 - w * 0.5 + 10 * s, vp.y * 0.66 + 23 * s),
			hint,
			int(14 * s),
			UITheme.ACCENT,
			HORIZONTAL_ALIGNMENT_CENTER,
			w - 20 * s
		)
	# Progreso de plantado/desactivado.
	var ptext := ""
	var pval := 0.0
	if progress_visible:
		ptext = progress_text
		pval = progress_value
	if game.bomb and game.bomb.planted and game.bomb.defusing_by == player:
		ptext = "DESACTIVANDO C4"
		pval = game.bomb.defuse_amount
	if ptext != "":
		var w := 420 * s
		var rect := Rect2(Vector2(vp.x * 0.5 - w * 0.5, vp.y * 0.72), Vector2(w, 22 * s))
		draw_rect(rect, Color(0.02, 0.03, 0.02, 0.8), true)
		draw_rect(
			Rect2(rect.position, Vector2(w * clampf(pval, 0.0, 1.0), rect.size.y)),
			UITheme.ACCENT,
			true
		)
		draw_rect(rect, Color(0, 0, 0, 0.8), false, 1.0)
		_txt(
			Vector2(vp.x * 0.5 - w * 0.5, vp.y * 0.72 - 8 * s),
			ptext,
			int(13 * s),
			UITheme.TEXT,
			HORIZONTAL_ALIGNMENT_CENTER,
			w
		)


func _draw_hitmarker(vp: Vector2, s: float) -> void:
	if not player.alive:
		_txt(
			Vector2(0, vp.y * 0.42),
			"HAS CAIDO",
			int(48 * s),
			Color(0.85, 0.2, 0.18),
			HORIZONTAL_ALIGNMENT_CENTER,
			vp.x,
			font_bold
		)
		_txt(
			Vector2(0, vp.y * 0.42 + 34 * s),
			"Espera la proxima ronda",
			int(16 * s),
			UITheme.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER,
			vp.x
		)


func _draw_zombie(vp: Vector2, s: float) -> void:
	if game.mode != "zombie":
		return
	var info := game.current_wave_info()
	var origin := Vector2(30 * s, 40 * s)
	draw_rect(
		Rect2(origin + Vector2(-12, -20) * s, Vector2(330, 82) * s),
		Color(0.03, 0.02, 0.03, 0.65),
		true
	)
	_txt(
		origin,
		"MODO ZOMBIE",
		int(16 * s),
		Color(0.85, 0.45, 0.95),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_bold
	)
	var state_txt := "OLEADA %d" % int(info.wave)
	if String(info.state) == "intermission":
		state_txt = "PROXIMA OLEADA EN %d s" % int(ceil(float(info.intermission)))
	elif String(info.state) == "prep":
		state_txt = "PREPARATE... %d s" % int(ceil(float(info.intermission)))
	elif String(info.state) == "game_over":
		state_txt = "FIN DE LA PARTIDA"
	_txt(
		origin + Vector2(0, 24 * s),
		state_txt,
		int(18 * s),
		Color(1, 0.75, 0.7),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_bold
	)
	_txt(
		origin + Vector2(0, 46 * s),
		"ZOMBIES: %d   POR SALIR: %d" % [int(info.alive), int(info.remaining)],
		int(13 * s),
		UITheme.TEXT_DIM
	)
	# Puntos grandes a la derecha del centro superior.
	var pts := "$%d PTS" % int(game.zombie_points)
	_txt(
		Vector2(vp.x * 0.5 - 150 * s, 120 * s),
		pts,
		int(22 * s),
		UITheme.ACCENT,
		HORIZONTAL_ALIGNMENT_CENTER,
		300 * s,
		font_bold
	)
	if _zombie_flash > 0.0:
		draw_rect(Rect2(Vector2(0, 0), vp), Color(0.2, 1.0, 0.2, _zombie_flash * 0.15), true)


func _draw_fps(vp: Vector2, s: float) -> void:
	if not bool(Settings.data.gameplay.get("show_fps", false)):
		return
	_txt(
		Vector2(vp.x - 110 * s, 20 * s),
		"%d FPS" % Engine.get_frames_per_second(),
		int(13 * s),
		UITheme.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_RIGHT,
		90 * s
	)
