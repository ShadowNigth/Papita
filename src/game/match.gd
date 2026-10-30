extends Node3D
## MatchGame: director de partida.
##
## Gestiona rondas, economia, compra de bots, objetivos (C4 y rehenes),
## killfeed, estadisticas y el modo Zombie con oleadas, perks y caja misteriosa.

class_name MatchGame

signal kill_event(
	killer: String, victim: String, weapon_id: String, headshot: bool, killer_team: int
)
signal message(text: String, color: Color, duration: float)
signal state_changed(state: String)
signal wave_changed(wave: int, state: String)
signal score_changed
signal player_died

const ROUND_END_DELAY := 4.5
const FREEZE_TIME := 4.0
const PLANT_TIME := 3.2
const BUY_WINDOW := 15.0
const MATCH_POINTS := 16

var mode := "bomb"
var map_id := "de_dust2"
var map_builder: MapBuilder
var nav: NavGraph
var layout: Dictionary = {}
var difficulty_index := 2
var difficulty: Dictionary = {}

var player: Player
var player_team := Content.TEAM_CT
var all_combatants: Array[Combatant] = []
var bots: Array[Bot] = []
var zombies: Array[Bot] = []
var hostages: Array[Hostage] = []
var bomb: Bomb
var pickups: Array[Node] = []
var smoke_clouds: Array[Dictionary] = []

var score_ct := 0
var score_t := 0
var round_number := 0
var round_state := "loading"
var round_time_left := 0.0
var freeze_time_left := 0.0
var state_timer := 0.0
var match_over := false
var t_target_site := "A"
var bomb_carrier: Combatant = null

var zombie_wave := 0
var zombie_state := "prep"
var zombie_points := 500
var zombie_spawn_queue := 0
var zombie_spawn_timer := 0.0
var zombie_config: Dictionary = {}
var intermission_time := 0.0
var player_revives := 0
var total_zombies_killed := 0
var wave_kills := 0
var survivors_alive := 0
var player_shots := 0
var player_hits := 0

var hud: Node
var ingame_ui: Node
var _interaction_text := ""
var _plant_progress := 0.0
var _plant_operator: Combatant = null
var _bot_planting: Dictionary = {}
var _bot_buy_pending: Array[Bot] = []
var _rng := RandomNumberGenerator.new()
var _start_money := 800
var _loss_streak := {1: 0, 2: 0}
var _last_spawn_index := 0
var _loading_layer: CanvasLayer
var _loading_label: Label
var _splashes := 0


func _ready() -> void:
	add_to_group("game")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	_build_loading_overlay()


func _build_loading_overlay() -> void:
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 220
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.02, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_layer.add_child(bg)
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.position = Vector2(0, 0)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading_layer.add_child(center)
	var title := Label.new()
	title.text = "PAPITA // CS 1.5 REFORGED"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.85, 0.78, 0.35))
	center.add_child(title)
	_loading_label = Label.new()
	_loading_label.text = "Cargando mapa y materiales..."
	_loading_label.add_theme_font_size_override("font_size", 16)
	_loading_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	center.add_child(_loading_label)
	add_child(_loading_layer)
	await get_tree().process_frame
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.position = Vector2(
		get_viewport().get_visible_rect().size.x * 0.5 - 260,
		get_viewport().get_visible_rect().size.y * 0.5
	)
	center.custom_minimum_size = Vector2(520, 100)


func start_match(map: String, game_mode: String, team: int, bot_count: int, diff: int) -> void:
	mode = game_mode
	map_id = map
	# En zombie siempre se juega de CT: los supervivientes son todos del mismo bando.
	player_team = Content.TEAM_CT if game_mode == "zombie" else team
	difficulty_index = diff
	difficulty = Content.difficulty(diff)
	_start_money = int(Settings.data.gameplay.get("start_money", 800))
	layout = Maps.build(map_id)
	difficulty_index = diff
	if _loading_label:
		_loading_label.text = "Construyendo %s..." % map_id
	await get_tree().process_frame
	map_builder = MapBuilder.new()
	add_child(map_builder)
	map_builder.setup(layout)
	if _loading_label:
		_loading_label.text = "Horneando navegacion..."
	await get_tree().process_frame
	nav = await map_builder.bake_navigation()
	AudioBank.set_ambience(String(layout.get("ambience", "dust")), 2.0)
	_spawn_player()
	_setup_ui()
	if mode == "zombie":
		AudioBank.set_music("zombie_music", 3.0)
		_setup_zombie()
		await get_tree().create_timer(0.4).timeout
	else:
		AudioBank.set_music("", 2.0)
		_spawn_bots(bot_count)
		if mode == "hostage":
			_spawn_hostages()
		await get_tree().create_timer(0.4).timeout
		start_round()
	if _loading_layer:
		_loading_layer.queue_free()
		_loading_layer = null
	capture_mouse(true)
	if hud:
		hud.set("visible", true)


func _setup_ui() -> void:
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "HudLayer"
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = preload("res://src/ui/hud.gd").new()
	hud_layer.add_child(hud)
	hud.call("setup", self)
	ingame_ui = preload("res://src/ui/ingame_ui.gd").new()
	add_child(ingame_ui)
	ingame_ui.call("setup", self)


func _spawn_player() -> void:
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.setup_player(player_team, String(Settings.data.profile.get("name", "Papita")))
	all_combatants.append(player)
	var spawn := map_builder.get_spawn(player_team, 0)
	player.global_position = spawn + Vector3(0, 0.2, 0)
	player.money = _start_money
	player.died.connect(_on_combatant_died)
	player.damaged.connect(_on_combatant_damaged)
	player.hit_confirmed.connect(_on_player_hit_confirmed)
	player.buy_requested.connect(func() -> void: _open_buy_menu())
	player.pause_requested.connect(func() -> void: _toggle_pause())
	player.console_requested.connect(_on_console_requested)
	player.help_requested.connect(func() -> void: _show_help())
	player.weapon_state_changed.connect(func(_c) -> void: _refresh_hud())


func _on_console_requested() -> void:
	if ingame_ui:
		ingame_ui.call("toggle_console")


func _refresh_hud() -> void:
	if hud:
		hud.call("queue_redraw")


func _free_if_valid(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()


func _spawn_bots(bot_count: int) -> void:
	var total := maxi(2, bot_count + 1)
	var half := int(ceil(float(total) / 2.0))
	var teammates := maxi(0, half - 1)
	var enemies := maxi(1, total - half)
	var names := Content.random_bot_names(
		total + 6, [String(Settings.data.profile.get("name", "Papita"))]
	)
	var idx := 0
	for i in teammates:
		var b := _create_bot(player_team, String(names[idx % names.size()]), i + 1)
		idx += 1
		bots.append(b)
	var enemy_team := Content.TEAM_T if player_team == Content.TEAM_CT else Content.TEAM_CT
	for i in enemies:
		var b := _create_bot(enemy_team, String(names[idx % names.size()]), i + 1)
		idx += 1
		bots.append(b)


func _create_bot(team_id: int, bot_name: String, index: int) -> Bot:
	var b := Bot.new()
	b.name = "Bot_%s_%d" % [bot_name, index]
	add_child(b)
	b.setup_bot(bot_name, team_id, difficulty, self, nav)
	var spawn := map_builder.get_spawn(team_id, index + 1)
	b.global_position = (
		spawn + Vector3(_rng.randf_range(-0.5, 0.5), 0.2, _rng.randf_range(-0.5, 0.5))
	)
	b.money = _start_money
	b.died.connect(_on_combatant_died)
	b.damaged.connect(_on_combatant_damaged)
	all_combatants.append(b)
	b.actor_model.equip(Content.WEAPONS.knife)
	return b


func _spawn_hostages() -> void:
	for i in layout.get("hostages", []).size():
		var pos: Vector3 = layout.hostages[i]
		var h := Hostage.new()
		h.name = "Hostage_%d" % i
		add_child(h)
		h.global_position = pos
		if mode == "hostage":
			h.setup_hostage(pos)
		hostages.append(h)
		all_combatants.append(h)


# --- Rondas --------------------------------------------------------------------


func start_round() -> void:
	if match_over or mode == "zombie":
		return
	round_state = "freeze"
	freeze_time_left = FREEZE_TIME
	round_time_left = float(Settings.data.gameplay.get("round_time", 300))
	round_number += 1
	bomb_carrier = null
	_plant_progress = 0.0
	_plant_operator = null
	_bot_planting.clear()
	_bot_buy_pending.clear()
	_clear_bomb()
	_clear_smokes()
	var site_names: Array = []
	for s in layout.get("sites", []):
		site_names.append(String(s.name))
	if site_names.is_empty():
		site_names = ["A"]
	t_target_site = site_names[_rng.randi_range(0, site_names.size() - 1)]
	_reset_round_combatants()
	_reset_hostages()
	_assign_objectives()
	if player and player.alive:
		player.input_enabled = true
		capture_mouse(true)
	message.emit("RONDA %d - COMPRA RAPIDA" % round_number, Color(0.9, 0.8, 0.4), 3.0)
	_queue_bot_buys()
	state_changed.emit(round_state)
	_after_freeze()


func _after_freeze() -> void:
	await get_tree().create_timer(FREEZE_TIME).timeout
	if not is_inside_tree() or match_over or round_state != "freeze":
		return
	round_state = "live"
	for c in all_combatants:
		c.frozen = false
	if player and player.alive:
		player.input_enabled = true
		capture_mouse(true)
	AudioBank.play_at("round_start", self, player.global_position, 0.0, 1.0, 60.0)
	message.emit("ADELANTE!", Color(0.7, 0.9, 0.5), 2.0)
	state_changed.emit(round_state)
	if mode == "bomb":
		_give_bomb_to_carrier()


func _reset_round_combatants() -> void:
	var team_spawn_index := {Content.TEAM_CT: 0, Content.TEAM_T: 0}
	for c in all_combatants:
		if c.is_hostage:
			continue
		if c.is_zombie:
			continue
		var idx: int = team_spawn_index.get(c.team, 0)
		team_spawn_index[c.team] = idx + 1
		var spawn := map_builder.get_spawn(c.team, idx)
		var was_dead := not c.alive
		c.round_kills = 0
		# Quien murio pierde el arma principal y la secundaria comprada: se
		# quedan tiradas en el mapa como pickup. Solo el cuchillo sobrevive.
		if was_dead:
			c.primary_id = ""
			c.secondary_id = ""
		if c.is_player:
			(c as Player).on_respawn(spawn)
		else:
			c.respawn(spawn)
		c.frozen = true
		if c.secondary_id == "":
			c.give_weapon("glock18" if c.team == Content.TEAM_T else "usp45", false)
		_restock_ammo(c)
		c.select_slot(Content.SLOT_PRIMARY if c.primary_id != "" else Content.SLOT_SECONDARY)
		c.set_meta("planted_this_round", false)
		c.set_meta("has_bomb", false)
		if c.is_player:
			(c as Player).input_enabled = false


func _restock_ammo(c: Combatant) -> void:
	for id in [c.primary_id, c.secondary_id]:
		if id == "":
			continue
		var def := Content.get_weapon(id)
		if def.is_empty():
			continue
		var current: Vector2i = c.ammo.get(id, Vector2i(0, 0))
		var mag: int = int(def.get("mag", 10))
		c._set_ammo(id, maxi(current.x, mag), int(def.get("reserve", 90)))


func _assign_objectives() -> void:
	var site_pos := map_builder.get_site_center(t_target_site)
	var other_site := "B" if t_target_site == "A" else "A"
	var other_pos := map_builder.get_site_center(other_site)
	bomb_carrier = null
	for c in all_combatants:
		if c.is_hostage or c.is_zombie:
			continue
		if not (c is Bot):
			continue
		var b := c as Bot
		if b.team == Content.TEAM_T:
			if mode == "bomb":
				b.objective_type = "attack"
				b.objective = site_pos
				if bomb_carrier == null and player_team != Content.TEAM_T:
					bomb_carrier = b
					b.has_c4 = true
					b.set_meta("has_bomb", true)
					b.objective_type = "plant"
			else:
				b.objective_type = "defend"
				b.objective = _hostage_center()
		else:
			if mode == "bomb":
				b.objective_type = "defend"
				b.objective = other_pos if _rng.randf() < 0.4 else site_pos
			else:
				b.objective_type = "rescue"
				b.objective = _hostage_center()
	if player and player_team == Content.TEAM_T and mode == "bomb":
		player.has_c4 = true
		player.set_meta("has_bomb", true)
		bomb_carrier = player
		player._set_ammo("c4", 1, 0)


func _give_bomb_to_carrier() -> void:
	if bomb_carrier and is_instance_valid(bomb_carrier) and bomb_carrier.alive:
		bomb_carrier.has_c4 = true
		bomb_carrier._set_ammo("c4", 1, 0)
		if bomb_carrier.is_bot:
			var b := bomb_carrier as Bot
			b.objective_type = "plant"
			b.objective = map_builder.get_site_center(t_target_site)


func _hostage_center() -> Vector3:
	var pts: Array = layout.get("hostages", [])
	if pts.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for p in pts:
		sum += p
	return sum / float(pts.size())


func _queue_bot_buys() -> void:
	for b in bots:
		if b.alive:
			_bot_buy(b)


func _bot_buy(bot: Bot) -> void:
	var t := bot.team
	var budget := bot.money
	var primary := ""
	var rifle := "ak47" if t == Content.TEAM_T else "m4a1"
	var cheap_rifle := "galil" if t == Content.TEAM_T else "famas"
	var smg := "mac10" if t == Content.TEAM_T else "mp5"
	var pistol := "deagle" if t == Content.TEAM_T else "deagle"
	if budget >= 4750 and _rng.randf() < 0.18:
		primary = "awp"
	elif budget >= Content.WEAPONS[rifle].price:
		primary = rifle
	elif budget >= Content.WEAPONS[cheap_rifle].price:
		primary = cheap_rifle
	elif budget >= Content.WEAPONS[smg].price:
		primary = smg
	elif budget >= Content.WEAPONS[pistol].price and _rng.randf() < 0.4:
		primary = pistol
	if primary != "":
		var price: int = int(Content.WEAPONS[primary].price)
		bot.money -= price
		bot.give_weapon(primary, true)
	if bot.armor <= 0 and bot.money >= 650:
		bot.money -= 650
		bot.equip_armor(false)
	if bot.money >= 1000 and _rng.randf() < 0.35:
		bot.money -= 300
		bot.give_weapon("hegrenade", false)
	if bot.money >= 350 and _rng.randf() < 0.3:
		bot.money -= 200
		bot.give_weapon("flashbang", false)
	bot.select_slot(Content.SLOT_PRIMARY if bot.primary_id != "" else Content.SLOT_SECONDARY)


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	if ingame_ui and ingame_ui.get("paused"):
		return
	_expire_smokes(delta)
	if mode == "zombie":
		_process_zombie_mode(delta)
		return
	_update_hostages()
	match round_state:
		"freeze":
			freeze_time_left -= delta
			if freeze_time_left <= 0.0:
				pass
		"live":
			round_time_left -= delta
			_check_round_end()
			if bomb and bomb.planted:
				pass
		"end":
			state_timer -= delta
			if state_timer <= 0.0:
				start_round()
	_update_interaction()


func _check_round_end() -> void:
	if match_over or round_state != "live":
		return
	var ct_alive := 0
	var t_alive := 0
	for c in all_combatants:
		if c.is_hostage or c.is_zombie or not c.alive:
			continue
		if c.team == Content.TEAM_CT:
			ct_alive += 1
		else:
			t_alive += 1
	if mode == "bomb":
		if bomb != null and is_instance_valid(bomb) and bomb.planted:
			if ct_alive == 0:
				_end_round(Content.TEAM_T, "BOMB DEFENDIDA")
				return
			return
		if ct_alive == 0 and t_alive == 0:
			_end_round(Content.TEAM_T, "EMPATE ROTO")
			return
		if t_alive == 0:
			_end_round(Content.TEAM_CT, "TERRORISTAS ELIMINADOS")
			return
		if ct_alive == 0:
			_end_round(Content.TEAM_T, "CT ELIMINADOS")
			return
		if round_time_left <= 0.0:
			_end_round(Content.TEAM_CT, "TIEMPO AGOTADO")
	else:
		if _all_hostages_rescued():
			_end_round(Content.TEAM_CT, "REHENES RESCATADOS")
			return
		if t_alive == 0:
			_end_round(Content.TEAM_CT, "TERRORISTAS ELIMINADOS")
			return
		if ct_alive == 0:
			_end_round(Content.TEAM_T, "CT ELIMINADOS")
			return
		if round_time_left <= 0.0:
			_end_round(Content.TEAM_T, "TIEMPO AGOTADO")


func _reset_hostages() -> void:
	var points: Array = layout.get("hostages", [])
	for i in hostages.size():
		var h := hostages[i]
		if i < points.size():
			h.global_position = points[i] + Vector3(0, 0.15, 0)
		h.rescued = false
		h.following = null
		h.alive = true
		h.wish_dir = Vector2.ZERO


func _update_hostages() -> void:
	var rescue := rescue_point()
	for h in hostages:
		if h.rescued or h.following == null:
			continue
		if h.global_position.distance_to(rescue) < 3.0:
			h.rescued = true
			h.stop_follow()
			var leader := h.following
			if leader == player:
				player.money = mini(Content.MAX_MONEY, player.money + Content.RESCUE_REWARD)
				Settings.add_progress("golden_rescues", 1.0)
			message.emit("REHEN RESCATADO", Color(0.5, 1.0, 0.6), 3.0)
			AudioBank.play_2d("radio", -2.0)
			if _all_hostages_rescued():
				_end_round(Content.TEAM_CT, "TODOS LOS REHENES A SALVO")


func _all_hostages_rescued() -> bool:
	if hostages.is_empty():
		return false
	for h in hostages:
		if not h.rescued:
			return false
	return true


func _end_round(winner: int, reason: String) -> void:
	if round_state != "live":
		return
	round_state = "end"
	state_timer = ROUND_END_DELAY
	if winner == Content.TEAM_CT:
		score_ct += 1
	else:
		score_t += 1
	AudioBank.play_2d("win_good" if winner == player_team else "win_bad", 0.0)
	message.emit(
		"%s GANA LA RONDA - %s" % ["CT" if winner == Content.TEAM_CT else "T", reason],
		Color(0.5, 0.85, 1.0) if winner == Content.TEAM_CT else Color(1.0, 0.7, 0.35),
		4.0
	)
	score_changed.emit()
	for c in all_combatants:
		if c.is_hostage or c.is_zombie:
			continue
		c.frozen = true
		if c.team == winner:
			c.money = mini(Content.MAX_MONEY, c.money + Content.WIN_REWARD)
			_loss_streak[Content.TEAM_T if winner == Content.TEAM_CT else Content.TEAM_CT] += 1
		else:
			var streak: int = int(_loss_streak.get(c.team, 0))
			var bonus: int = Content.LOSS_BONUS[clampi(streak, 0, Content.LOSS_BONUS.size() - 1)]
			c.money = mini(Content.MAX_MONEY, c.money + bonus)
	if bomb != null and is_instance_valid(bomb):
		bomb.stop_defuse()
	if player:
		player.input_enabled = false
	_check_match_end()


func _check_match_end() -> void:
	if score_ct >= MATCH_POINTS or score_t >= MATCH_POINTS:
		match_over = true
		round_state = "match_end"
		var won := (
			(score_ct >= MATCH_POINTS and player_team == Content.TEAM_CT)
			or (score_t >= MATCH_POINTS and player_team == Content.TEAM_T)
		)
		if won:
			Settings.add_progress("wins")
		Settings.add_progress("matches")
		if ingame_ui and ingame_ui.has_method("show_match_end"):
			ingame_ui.call("show_match_end", won, score_ct, score_t)


func _on_combatant_died(
	victim: Combatant, attacker: Node, weapon_id: String, headshot: bool
) -> void:
	var killer_name := ""
	var killer_team := 0
	if attacker is Combatant:
		var killer := attacker as Combatant
		killer_name = killer.display_name
		killer_team = killer.team
		if killer.team != victim.team or killer.is_zombie != victim.is_zombie:
			var def := Content.get_weapon(weapon_id)
			var award: int = int(def.get("award", 300)) if not def.is_empty() else 300
			killer.money = mini(Content.MAX_MONEY, killer.money + award)
			if killer.is_player:
				AudioBank.play_2d("money", -12.0)
				Settings.add_progress("kills")
		else:
			killer.money = maxi(0, killer.money - Content.TEAMKILL_PENALTY)
			message.emit("FUEGO AMIGO! -$%d" % Content.TEAMKILL_PENALTY, Color(1, 0.3, 0.25), 3.0)
	elif weapon_id == "c4":
		killer_name = "C4"
	kill_event.emit(killer_name, victim.display_name, weapon_id, headshot, killer_team)
	if victim == player:
		player_died.emit()
		player.input_enabled = false
		capture_mouse(false)
		if mode == "zombie":
			_handle_player_death_zombie()
		if ingame_ui and ingame_ui.has_method("show_death"):
			ingame_ui.call("show_death", killer_name)
	if victim.is_zombie:
		total_zombies_killed += 1
		wave_kills += 1
		var victim_zombie := victim as Bot
		if attacker == player and victim_zombie != null:
			var base: int = int(Content.zombie_type(victim_zombie.zombie_type).get("points", 60))
			var mult := 2 if player.has_meta("double_tap") else 1
			zombie_points += base * mult
		AudioBank.play_at("zombie_death", get_parent(), victim.global_position, 0.0, 1.0, 40.0)
		if hud:
			hud.call("on_zombie_killed", victim)
		_cleanup_zombie_later(victim as Bot)
	if _alive_count(Content.TEAM_CT) == 0 or _alive_count(Content.TEAM_T) == 0:
		_check_round_end()


func _on_combatant_damaged(
	victim: Combatant, _amount: float, attacker: Node, _hitbox: String, _wid: String
) -> void:
	if attacker == player and victim != player and hud:
		hud.call("on_damage_dealt", victim)
	if victim == player:
		player.set_meta("last_hurt_time", Time.get_ticks_msec())
		if hud:
			hud.call("on_player_hurt", _amount)
	if victim is Bot and _amount > 0:
		(victim as Bot).report_damage(attacker)


func _on_player_hit_confirmed(_attacker, victim, damage: float, headshot: bool) -> void:
	player_hits += 1
	if mode == "zombie" and victim is Combatant and victim.is_zombie:
		var mult := 2 if player.has_meta("double_tap") else 1
		zombie_points += 10 * mult
	if hud and hud.has_method("show_hitmarker"):
		hud.call("show_hitmarker", headshot)


func _alive_count(team_id: int) -> int:
	var n := 0
	for c in all_combatants:
		if c.is_hostage or c.is_zombie:
			continue
		if c.team == team_id and c.alive:
			n += 1
	return n


func _cleanup_zombie_later(z: Bot) -> void:
	if z == null:
		return
	var tw := z.create_tween()
	tw.tween_interval(9.0)
	tw.tween_callback(
		func() -> void:
			if not is_instance_valid(z):
				return
			zombies.erase(z)
			all_combatants.erase(z)
			z.queue_free()
	)


func _alive_zombies() -> int:
	var n := 0
	for z in zombies:
		if is_instance_valid(z) and z.alive:
			n += 1
	return n


# --- Interaccion ---------------------------------------------------------------


func _update_interaction() -> void:
	if player == null or not player.alive:
		_interaction_text = ""
		return
	_interaction_text = interaction_hint_for(player)


func interaction_hint_for(p: Player) -> String:
	if mode == "zombie":
		for node in get_tree().get_nodes_in_group("perk_machine"):
			if node.global_position.distance_to(p.global_position) < 2.4:
				var id := String(node.get_meta("perk_id", ""))
				var price := int(Content.PERK_PRICES.get(id, 0))
				var owned := p.has_meta("perk_" + id)
				if owned:
					return "%s YA COMPRADO" % Content.PERKS[id].name.to_upper()
				return "[E] COMPRAR %s ($%d)" % [Content.PERKS[id].name.to_upper(), price]
		for node in get_tree().get_nodes_in_group("mystery_box"):
			if node.global_position.distance_to(p.global_position) < 2.4:
				return "[E] CAJA MISTERIOSA ($%d)" % Content.MYSTERY_BOX_PRICE
		for node in get_tree().get_nodes_in_group("ammo_crate"):
			if node.global_position.distance_to(p.global_position) < 2.4:
				return "[E] MUNICION ($%d)" % Content.ZOMBIE_AMMO_PRICE
		return ""
	if mode == "hostage" and p.team == Content.TEAM_CT:
		for h in hostages:
			if (
				not h.rescued
				and h.global_position.distance_to(p.global_position) < 2.5
				and h.following != p
			):
				return "[E] LIBERAR REHEN"
	if bomb and bomb.planted:
		if p.team == Content.TEAM_CT and bomb.global_position.distance_to(p.global_position) < 2.3:
			return "[E] DESACTIVAR C4 (mantener)"
		return ""
	if p.team == Content.TEAM_T and p.has_c4:
		var site := _site_at(p.global_position)
		if site != "":
			return "[E] PLANTAR C4 (mantener 3.2 s)"
	return ""


func interact_press(p: Player) -> void:
	if mode == "zombie":
		_try_zombie_purchase(p)
		return
	if p.team == Content.TEAM_CT:
		for h in hostages:
			if (
				not h.rescued
				and h.following != p
				and h.global_position.distance_to(p.global_position) < 2.5
			):
				h.start_follow(p)
				p.money = mini(Content.MAX_MONEY, p.money + 100)
				message.emit(
					"REHEN LIBERADO - GUIA A LA ZONA DE RESCATE", Color(0.5, 1.0, 0.6), 3.0
				)
				return


func interact_hold(p: Player, held_time: float) -> void:
	if not p.alive:
		return
	if mode == "zombie":
		return
	if p.team == Content.TEAM_T and p.has_c4 and bomb == null:
		var site := _site_at(p.global_position)
		if site != "":
			if _plant_operator != p:
				_plant_operator = p
				_plant_progress = 0.0
			_plant_progress += get_physics_process_delta_time()
			if hud and hud.has_method("show_progress"):
				hud.call(
					"show_progress", "PLANTANDO C4", clampf(_plant_progress / PLANT_TIME, 0.0, 1.0)
				)
			if _plant_progress >= PLANT_TIME:
				_plant_bomb(p, site)
	if p.team == Content.TEAM_CT and bomb and bomb.planted:
		if bomb.global_position.distance_to(p.global_position) < 2.3:
			bomb.begin_defuse(p)


func interact_release(p: Player) -> void:
	if _plant_operator == p:
		_plant_operator = null
		_plant_progress = 0.0
		if hud and hud.has_method("hide_progress"):
			hud.call("hide_progress")
	if bomb and bomb.planted and bomb.defusing_by == p:
		bomb.stop_defuse()


func _try_zombie_purchase(p: Player) -> void:
	for node in get_tree().get_nodes_in_group("perk_machine"):
		if node.global_position.distance_to(p.global_position) < 2.4:
			var id := String(node.get_meta("perk_id", ""))
			buy_perk(id, p)
			return
	for node in get_tree().get_nodes_in_group("mystery_box"):
		if node.global_position.distance_to(p.global_position) < 2.4:
			buy_mystery_box(p)
			return
	for node in get_tree().get_nodes_in_group("ammo_crate"):
		if node.global_position.distance_to(p.global_position) < 2.4:
			buy_ammo(p)
			return


func _site_at(pos: Vector3) -> String:
	for s in layout.get("sites", []):
		var center: Vector3 = s.center
		var size: Vector2 = s.size
		if absf(pos.x - center.x) < size.x * 0.5 and absf(pos.z - center.z) < size.y * 0.5:
			return String(s.name)
	return ""


func _plant_bomb(planter: Combatant, site: String) -> void:
	if bomb != null:
		return
	planted_call(planter, site)


func planted_call(planter: Combatant, site: String) -> void:
	var node := Bomb.new()
	add_child(node)
	var pos := planter.global_position
	var site_center := map_builder.get_site_center(site)
	if site_center != Vector3.ZERO:
		pos = site_center + Vector3(0, 0, 0.8)
	node.global_position = pos
	node.plant(pos)
	bomb = node
	node.defused.connect(_on_bomb_defused)
	node.exploded.connect(_on_bomb_exploded)
	planter.has_c4 = false
	planter.set_meta("has_bomb", false)
	_plant_progress = 0.0
	_plant_operator = null
	if hud and hud.has_method("hide_progress"):
		hud.call("hide_progress")
	planter.set_meta("planted_this_round", true)
	planter.money = mini(Content.MAX_MONEY, planter.money + Content.PLANT_REWARD)
	message.emit("C4 PLANTADO EN %s" % site, Color(1.0, 0.4, 0.3), 4.0)
	AudioBank.play_2d("plant", 0.0)
	round_time_left = 9999.0
	for c in all_combatants:
		if c.is_bot and not c.is_zombie:
			var b := c as Bot
			if b.team == Content.TEAM_CT:
				b.objective_type = "defuse"
				b.objective = node.global_position
			else:
				b.objective_type = "defend"
				b.objective = node.global_position
	_update_interaction()
	state_changed.emit(round_state)


func _on_bomb_defused() -> void:
	message.emit("BOMBA DESACTIVADA", Color(0.4, 0.8, 1.0), 4.0)
	var defuser: Combatant = null
	if bomb != null and is_instance_valid(bomb):
		defuser = bomb.defusing_by
	bomb = null
	if defuser != null and is_instance_valid(defuser):
		defuser.money = mini(Content.MAX_MONEY, defuser.money + Content.DEFUSE_REWARD)
		if defuser == player:
			Settings.grant_achievement("bombhero")
			AudioBank.play_2d("money", -10.0)
	_end_round(Content.TEAM_CT, "BOMBA DESACTIVADA")


func _on_bomb_exploded() -> void:
	message.emit("LA BOMBA EXPLOTO", Color(1.0, 0.4, 0.2), 4.0)
	var bpos := Vector3.ZERO
	if bomb != null and is_instance_valid(bomb):
		bpos = bomb.global_position
	bomb = null
	_end_round(Content.TEAM_T, "OBJETIVO DESTRUIDO")
	explode(bpos, 26.0, 400.0, null, "c4")
	if player and player.global_position.distance_to(bpos) < 30.0:
		player.apply_shake(1.0)


func _clear_bomb() -> void:
	if bomb and is_instance_valid(bomb):
		bomb.queue_free()
	bomb = null


func _clear_smokes() -> void:
	smoke_clouds.clear()


# --- Utilidades de combate -----------------------------------------------------


func spawn_pickup(
	weapon_id: String, position: Vector3, _id: String, mag: int, reserve: int
) -> void:
	var p := WeaponPickup.new()
	p.setup(weapon_id, mag, reserve)
	add_child(p)
	p.global_position = position
	pickups.append(p)


func spawn_grenade(attacker: Combatant, id: String, position: Vector3, velocity: Vector3) -> void:
	var g := Grenade.new()
	add_child(g)
	g.setup(id, attacker, self)
	g.global_position = position
	g.linear_velocity = velocity
	g.angular_velocity = Vector3(
		_rng.randf_range(-6, 6), _rng.randf_range(-6, 6), _rng.randf_range(-6, 6)
	)


func explode(
	center: Vector3, radius: float, damage: float, attacker: Node, weapon_id: String
) -> void:
	AudioBank.play_at("explosion", self, center, 6.0, _rng.randf_range(0.9, 1.05), 180.0)
	if player and player.alive:
		var d := player.global_position.distance_to(center)
		if d < radius * 2.5:
			player.apply_shake(clampf(1.4 - d / (radius * 2.5), 0.0, 1.2))
	for c in all_combatants:
		if not is_instance_valid(c) or not c.alive:
			continue
		if attacker is Combatant and c == attacker:
			continue
		var dist := c.global_position.distance_to(center)
		if dist > radius:
			continue
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.new()
		q.from = center
		q.to = c.global_position + Vector3(0, 1.0, 0)
		q.collision_mask = 1
		q.exclude = [c.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			continue
		var falloff := clampf(1.0 - dist / radius, 0.15, 1.0)
		var dmg := damage * falloff + damage * 0.15
		c.take_damage(dmg, attacker, "chest", weapon_id)
		if c.is_zombie and hud:
			hud.call("on_zombie_killed", c)


func flash_at(pos: Vector3, attacker: Node) -> void:
	var space := get_world_3d().direct_space_state
	for c in all_combatants:
		if not is_instance_valid(c) or not c.alive:
			continue
		var dist := c.global_position.distance_to(pos)
		if dist > 15.0:
			continue
		var q := PhysicsRayQueryParameters3D.new()
		q.from = pos
		q.to = c.global_position + Vector3(0, 1.2, 0)
		q.collision_mask = 1
		q.exclude = [c.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			continue
		var to_flash := (pos - (c.global_position + Vector3(0, 1.4, 0))).normalized()
		var facing := -c.global_transform.basis.z
		var dot := maxf(to_flash.dot(facing), -0.2)
		var strength := clampf(dot, 0.0, 1.0)
		var duration := clampf((1.0 - dist / 16.0) * (1.4 + strength * 2.4), 0.0, 4.2)
		c.blind(duration)
		if c is Bot:
			(c as Bot).wants_fire = false
		if c == player and attacker is Combatant and c.team == (attacker as Combatant).team:
			c.set_meta("flashed_by_team", true)


func add_smoke(pos: Vector3, radius: float, duration: float) -> void:
	smoke_clouds.append(
		{"pos": pos, "radius": radius, "until": Time.get_ticks_msec() + duration * 1000.0}
	)


func _expire_smokes(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for i in range(smoke_clouds.size() - 1, -1, -1):
		if int(smoke_clouds[i].until) < now:
			smoke_clouds.remove_at(i)


func is_smoked(a: Vector3, b: Vector3) -> bool:
	for s in smoke_clouds:
		var center: Vector3 = s.pos
		if _segment_sphere(a, b, center, float(s.radius)):
			return true
	return false


func _segment_sphere(a: Vector3, b: Vector3, center: Vector3, radius: float) -> bool:
	var ab := b - a
	var t := clampf((center - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	var closest := a + ab * t
	return closest.distance_to(center) <= radius


func nearest_hostage(from: Vector3) -> Hostage:
	var best: Hostage = null
	var best_dist := 9999.0
	for h in hostages:
		if h.rescued:
			continue
		var d := h.global_position.distance_to(from)
		if d < best_dist:
			best_dist = d
			best = h
	return best


func rescue_point() -> Vector3:
	var arr: Array = layout.get("rescue", [])
	if arr.is_empty():
		return map_builder.get_spawn(Content.TEAM_CT, 0)
	return arr[0]


func bot_try_plant(bot: Bot) -> bool:
	if bomb != null:
		return false
	if bot.global_position.distance_to(bot.objective) > 5.0:
		return false
	var site := _site_at(bot.global_position)
	if site == "":
		return false
	var t: float = float(_bot_planting.get(bot, 0.0)) + get_physics_process_delta_time()
	_bot_planting[bot] = t
	if t >= PLANT_TIME:
		_plant_bomb(bot, site)
		return true
	return true


func bot_try_defuse(bot: Bot) -> bool:
	if bomb == null or not bomb.planted:
		return false
	if bot.global_position.distance_to(bomb.global_position) > 2.2:
		return false
	bomb.begin_defuse(bot)
	return true


func bot_grab_hostage(_bot: Bot, hostage: Hostage) -> void:
	if hostage.following == null:
		hostage.start_follow(_bot)


func on_bot_spotted(_bot: Bot, _enemy: Combatant) -> void:
	for other in bots:
		if other == _bot or other.team != _bot.team or not other.alive:
			continue
		if other.global_position.distance_to(_bot.global_position) < 20.0:
			other.last_heard_pos = _bot.global_position
			other.last_heard_time = Time.get_ticks_msec() * 0.001


func on_zombie_hit(zombie: Bot, target: Combatant) -> void:
	if target == player and player and player.alive:
		player.apply_shake(0.35)
		if hud:
			hud.call("on_player_hurt", 15.0)
	if zombie == null:
		return


func capture_mouse(capture: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


# --- Compra del jugador --------------------------------------------------------


func _open_buy_menu() -> void:
	if round_state != "live" and round_state != "freeze":
		return
	if player == null or not player.alive:
		return
	var elapsed := float(Settings.data.gameplay.get("round_time", 300)) - round_time_left
	var buy_window := float(Settings.data.gameplay.get("buy_time", 45))
	if elapsed > buy_window and round_state == "live":
		message.emit("EL TIEMPO DE COMPRA TERMINO", Color(1, 0.5, 0.3), 2.0)
		return
	if ingame_ui:
		ingame_ui.call("open_buy_menu")


func buy_item(id: String) -> bool:
	if player == null or not player.alive:
		return false
	var price := Content.item_price(id)
	if player.money < price:
		AudioBank.play_2d("error", -4.0)
		message.emit("NO TIENES SUFICIENTE DINERO", Color(1, 0.35, 0.3), 2.0)
		return false
	if Content.is_equipment(id):
		match id:
			"kevlar":
				if player.armor >= 100.0:
					return false
				player.equip_armor(player.helmet)
			"helmet":
				if player.helmet:
					return false
				player.helmet = true
				player.equip_armor(true)
			"defusekit":
				if player.defusekit or player.team != Content.TEAM_CT:
					return false
				player.defusekit = true
	else:
		var def := Content.get_weapon(id)
		if def.is_empty():
			return false
		var slot: int = int(def.get("slot", 1))
		if slot == Content.SLOT_GRENADE:
			var limit := int(Content.GRENADE_LIMITS.get(id, 1))
			if player.grenades.size() >= 4 or _count_grenade(player, id) >= limit:
				return false
			player.give_weapon(id, false)
		elif slot == Content.SLOT_PRIMARY:
			if player.primary_id == id:
				return false
			player.give_weapon(id, true)
			player.primary_id = id
		elif slot == Content.SLOT_SECONDARY:
			if player.secondary_id == id:
				return false
			player.give_weapon(id, true)
		AudioBank.play_2d("buy", -4.0)
	player.money = maxi(0, player.money - price)
	if hud:
		hud.call("on_buy", id)
	return true


func _count_grenade(c: Combatant, id: String) -> int:
	var n := 0
	for g in c.grenades:
		if g == id:
			n += 1
	return n


# --- Zombie --------------------------------------------------------------------


func _setup_zombie() -> void:
	player.max_health = 100.0
	player.health = 100.0
	player.set_meta("zombie_mode", true)
	player.money = 0
	zombie_points = Content.ZOMBIE_START_POINTS
	zombie_wave = 0
	zombie_state = "prep"
	intermission_time = 18.0
	round_state = "zombie_prep"
	_spawn_survivor_bots()
	AudioBank.set_music("zombie_music", 2.0)
	message.emit("SOBREVIVE A LAS OLEADAS - CONSIGUE PUNTOS", Color(0.8, 0.4, 0.9), 5.0)
	wave_changed.emit(0, "prep")
	# Armas iniciales.
	player.give_weapon("mp5", true)
	player.give_weapon("deagle", false)
	player._set_ammo("mp5", 30, 120)
	player.select_slot(Content.SLOT_PRIMARY)
	player.money = 0
	player.global_position = map_builder.get_spawn(Content.TEAM_CT, 0) + Vector3(0, 0.2, 0)
	player.frozen = false
	player.input_enabled = true
	state_changed.emit(round_state)


func _spawn_survivor_bots() -> void:
	var names := Content.random_bot_names(6)
	var spawn := map_builder.get_spawn(Content.TEAM_CT, 0)
	for i in 3:
		var b := _create_bot(Content.TEAM_CT, names[i], i + 2)
		b.global_position = (
			spawn + Vector3(_rng.randf_range(-2.5, 2.5), 0.3, _rng.randf_range(-2.5, 2.5))
		)
		b.set_meta("survivor", true)
		b.max_health = 150.0
		b.health = 150.0
		b.give_weapon("mp5" if i % 2 == 0 else "ak47", true)
		b.equip_armor(true)
		b.objective_type = "defend"
		b.objective = spawn
		bots.append(b)
		survivors_alive += 1
	player.set_meta("survivor", true)


func _process_zombie_mode(delta: float) -> void:
	match zombie_state:
		"prep":
			intermission_time -= delta
			if intermission_time <= 0.0:
				_start_wave()
		"wave":
			_spawn_wave_zombies(delta)
			_check_wave_clear()
		"intermission":
			intermission_time -= delta
			if intermission_time <= 0.0:
				_start_wave()
	if player and player.alive:
		var blocked_ui: bool = ingame_ui != null and bool(ingame_ui.get("buy_open"))
		var paused_ui: bool = ingame_ui != null and bool(ingame_ui.get("paused"))
		if not blocked_ui and not paused_ui:
			player.input_enabled = true
	# Los aliados bot siguen al jugador cuando andan lejos.
	for b in bots:
		if not is_instance_valid(b) or not b.alive or b.is_zombie:
			continue
		if b.target_enemy == null and b.global_position.distance_to(player.global_position) > 16.0:
			b.objective_type = "defend"
			b.objective = player.global_position
	_update_interaction()


func _start_wave() -> void:
	zombie_wave += 1
	zombie_state = "wave"
	wave_kills = 0
	zombie_config = Content.wave_config(zombie_wave)
	zombie_spawn_queue = int(zombie_config.count)
	zombie_spawn_timer = 0.5
	round_state = "zombie_wave"
	AudioBank.play_2d("wave_start", 0.0)
	message.emit(
		"OLEADA %d - %d ZOMBIES" % [zombie_wave, zombie_spawn_queue], Color(0.9, 0.35, 0.3), 4.0
	)
	wave_changed.emit(zombie_wave, "wave")
	if bool(zombie_config.get("boss", false)):
		_spawn_zombie("boss")
		zombie_spawn_queue = maxi(0, zombie_spawn_queue - 1)
	state_changed.emit(round_state)


func _spawn_wave_zombies(delta: float) -> void:
	if zombie_spawn_queue <= 0:
		return
	zombie_spawn_timer -= delta
	if zombie_spawn_timer > 0.0:
		return
	zombie_spawn_timer = float(zombie_config.get("spawn_interval", 1.0))
	if _alive_zombies() >= int(zombie_config.get("max_alive", 24)):
		return
	var ztype := Content.pick_zombie_type(zombie_wave, _rng)
	_spawn_zombie(ztype)
	zombie_spawn_queue -= 1


func _spawn_zombie(ztype: String) -> void:
	var data := Content.zombie_type(ztype)
	var z := Bot.new()
	z.name = "Zombie_%d" % (_rng.randi() % 100000)
	add_child(z)
	var points: Array = layout.get("zombie_spawns", [])
	var pos := Vector3(0, 0.2, 0)
	if not points.is_empty():
		pos = points[0]
		for i in 8:
			var candidate: Vector3 = points[_rng.randi_range(0, points.size() - 1)]
			if player == null or candidate.distance_to(player.global_position) > 10.0:
				pos = candidate
				break
		pos = pos + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
	z.global_position = pos
	var scale_f: float = float(data.get("scale", 1.0))
	var hp: float = float(data.get("hp", 100)) * float(zombie_config.get("hp_mult", 1.0))
	z.setup_zombie(ztype, scale_f, hp, self, nav)
	z.move_speed_scale *= float(zombie_config.get("speed_mult", 1.0))
	z.died.connect(_on_combatant_died)
	z.damaged.connect(_on_combatant_damaged)
	zombies.append(z)
	all_combatants.append(z)
	AudioBank.play_at("zombie_spawn", self, pos, -4.0, _rng.randf_range(0.85, 1.1), 35.0)


func _check_wave_clear() -> void:
	if zombie_spawn_queue > 0:
		return
	if _alive_zombies() > 0:
		return
	zombie_state = "intermission"
	intermission_time = 9.0
	round_state = "zombie_intermission"
	var bonus := 150 + zombie_wave * 60
	zombie_points += bonus
	message.emit("OLEADA %d SUPERADA  +%d PTS" % [zombie_wave, bonus], Color(0.5, 0.9, 0.6), 5.0)
	wave_changed.emit(zombie_wave, "intermission")
	state_changed.emit(round_state)
	Settings.data.progress["zombie_best_wave"] = maxi(
		int(Settings.data.progress.get("zombie_best_wave", 0)), zombie_wave
	)
	Settings.queue_save()
	# Recuperacion de los supervivientes.
	for c in all_combatants:
		if c.is_zombie or c.is_hostage or not c.alive:
			continue
		c.health = minf(c.max_health, c.health + 35.0)
		c.health_changed.emit(c, c.health, c.armor)
		for id in c.ammo.keys():
			var a: Vector2i = c.ammo[id]
			var def := Content.get_weapon(id)
			var max_res := int(def.get("reserve", a.y))
			c.ammo[id] = Vector2i(a.x, mini(max_res, a.y + int(max_res * 0.4)))
	AudioBank.play_at("perk", self, player.global_position, 0.0, 1.0, 40.0)


func buy_perk(id: String, p: Player) -> bool:
	if p.has_meta("perk_" + id):
		AudioBank.play_2d("error", -6.0)
		return false
	var price := int(Content.PERK_PRICES.get(id, 2000))
	if zombie_points < price:
		AudioBank.play_2d("error", -4.0)
		message.emit("FALTAN PUNTOS (%d)" % price, Color(1, 0.4, 0.3), 2.0)
		return false
	zombie_points -= price
	p.set_meta("perk_" + id, true)
	match id:
		"jugg":
			p.max_health = 200.0
			p.health = 200.0
			p.set_meta("regen", true)
		"speed":
			p.set_meta("speed_cola", true)
		"double":
			p.set_meta("double_tap", true)
		"revive":
			p.set_meta("revive", true)
			player_revives += 1
		"mule":
			p.set_meta("mule", true)
	AudioBank.play_2d("perk", 0.0)
	message.emit("%s ADQUIRIDO" % Content.PERKS[id].name.to_upper(), Content.PERKS[id].color, 3.0)
	Settings.grant_achievement("rich")
	return true


func buy_mystery_box(p: Player) -> bool:
	if zombie_points < Content.MYSTERY_BOX_PRICE:
		AudioBank.play_2d("error", -4.0)
		message.emit("FALTAN PUNTOS", Color(1, 0.4, 0.3), 2.0)
		return false
	zombie_points -= Content.MYSTERY_BOX_PRICE
	var options := Content.weapons_for_mystery_box()
	var id: String = options[_rng.randi_range(0, options.size() - 1)]
	p.give_weapon(id, true)
	p._set_ammo(id, int(Content.WEAPONS[id].mag), int(Content.WEAPONS[id].reserve))
	AudioBank.play_2d("perk", -2.0)
	message.emit(
		"CAJA MISTERIOSA: %s" % Content.WEAPONS[id].name.to_upper(), Color(1.0, 0.85, 0.4), 3.5
	)
	return true


func buy_ammo(p: Player) -> bool:
	if zombie_points < Content.ZOMBIE_AMMO_PRICE:
		AudioBank.play_2d("error", -4.0)
		return false
	zombie_points -= Content.ZOMBIE_AMMO_PRICE
	for id in p.ammo.keys():
		var def := Content.get_weapon(id)
		if def.is_empty():
			continue
		var a: Vector2i = p.ammo[id]
		var max_res := int(def.get("reserve", a.y))
		p.ammo[id] = Vector2i(int(def.get("mag", a.x)), maxi(a.y, max_res))
	AudioBank.play_2d("money", -4.0)
	message.emit("MUNICION REABASTECIDA", Color(0.6, 1.0, 0.6), 2.5)
	return true


func _handle_player_death_zombie() -> void:
	if player.has_meta("revive") and player_revives > 0:
		player_revives -= 1
		player.set_meta("revive", false)
		var timer := get_tree().create_timer(3.0)
		timer.timeout.connect(
			func() -> void:
				if player:
					player.on_respawn(map_builder.get_spawn(Content.TEAM_CT, 0))
					player.health = 50.0
					player.max_health = 200.0 if player.has_meta("jugg") else 100.0
					player.armor = 100.0
					player.input_enabled = true
					capture_mouse(true)
					message.emit("REVIVISTE!", Color(0.5, 0.9, 1.0), 3.0)
					AudioBank.play_2d("perk", 0.0)
		)
		return
	zombie_state = "game_over"
	round_state = "game_over"
	var wave := zombie_wave
	Settings.data.progress["zombie_best_wave"] = maxi(
		int(Settings.data.progress.get("zombie_best_wave", 0)), wave
	)
	Settings.queue_save()
	if ingame_ui and ingame_ui.has_method("show_zombie_gameover"):
		ingame_ui.call("show_zombie_gameover", wave, total_zombies_killed)


func survivors() -> Array:
	var out: Array = []
	if player and player.alive and not player.is_zombie:
		out.append(player)
	for b in bots:
		if is_instance_valid(b) and b.alive and not b.is_zombie and not b.is_hostage:
			out.append(b)
	return out


func spawn_zombie_spit(zombie: Bot, target: Combatant, damage: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	mesh.mesh = sphere
	mesh.material_override = MaterialLib.emissive(Color(0.55, 0.9, 0.2), 3.0)
	add_child(mesh)
	var start := zombie.global_position + Vector3(0, 1.2, 0)
	var end := target.global_position + Vector3(0, 1.0, 0)
	mesh.global_position = start
	var tw := create_tween()
	tw.tween_property(mesh, "global_position", end, 0.35)
	tw.tween_callback(
		func() -> void:
			if target and is_instance_valid(target) and target.alive:
				target.take_damage(damage, zombie, "chest", "zombie_spit")
			mesh.queue_free()
	)
	var wait := get_tree().create_timer(0.4)
	wait.timeout.connect(_free_if_valid.bind(mesh))


func on_zombie_wave_hud() -> Dictionary:
	return {
		"wave": zombie_wave,
		"state": zombie_state,
		"alive": _alive_zombies(),
		"points": zombie_points,
		"remaining": zombie_spawn_queue,
		"intermission": intermission_time,
	}


# --- Auxiliares de UI ----------------------------------------------------------


func _toggle_pause() -> void:
	if ingame_ui:
		ingame_ui.call("toggle_pause")


func _show_help() -> void:
	if ingame_ui:
		ingame_ui.call("toggle_help")


func get_scoreboard() -> Array:
	var out: Array = []
	for c in all_combatants:
		if c.is_hostage or c.is_zombie:
			continue
		var row := {
			"name": c.display_name,
			"team": c.team,
			"kills": c.kills,
			"deaths": c.deaths,
			"headshots": c.headshots,
			"money": c.money,
			"alive": c.alive,
			"is_player": c.is_player,
		}
		out.append(row)
	out.sort_custom(func(a, b): return int(a.kills) > int(b.kills))
	return out


func time_string() -> String:
	if bomb and bomb.planted:
		return "%0.1f" % maxf(bomb.time_left, 0.0)
	var t := maxf(round_time_left, 0.0)
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func player_alive_count(team_id: int) -> int:
	return _alive_count(team_id)


func current_wave_info() -> Dictionary:
	return on_zombie_wave_hud()


func apply_difficulty_to_bots() -> void:
	for b in bots:
		b.difficulty = difficulty
		b.aim_error = float(difficulty.get("aim_error", 2.5))
		b.reaction_left = float(difficulty.get("reaction", 0.35))
		b.max_health = float(difficulty.get("hp", 100))
		b.health = minf(b.health, b.max_health)
