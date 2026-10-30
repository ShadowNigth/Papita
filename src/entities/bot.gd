extends Combatant
## Bot: IA tactica para Counter-Strike y para el modo Zombie.
##
## Percibe enemigos con linea de vision y oido, sigue objetivos (plantar,
## desactivar, rescatar rehenes) y combate con rafagas, strafing y recarga.

class_name Bot

var game: Node = null
var nav: NavGraph = null
var difficulty: Dictionary = {}
var state := "idle"
var objective_type := "attack"
var objective := Vector3.ZERO
var objective_site := "A"
var zombie_type := "walker"
var zombie_data: Dictionary = {}
var is_zombie_ai := false

var target_enemy: Combatant = null
var target_visible := false
var last_seen_pos := Vector3.ZERO
var last_seen_time := -99.0
var last_heard_pos := Vector3.ZERO
var last_heard_time := -99.0
var reaction_left := 0.0
var aim_point := Vector3.ZERO
var aim_error := 0.0
var path: PackedVector3Array = PackedVector3Array()
var path_index := 0
var path_target := Vector3.ZERO
var repath_timer := 0.0
var think_timer := 0.0
var fire_time := 0.0
var pause_time := 0.0
var strafe_dir := 1.0
var strafe_timer := 0.0
var stuck_timer := 0.0
var last_pos := Vector3.ZERO
var attack_cooldown := 0.0
var has_planted := false
var defusing := false
var patrol_point := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _last_state := ""


func _ready() -> void:
	super._ready()
	_rng.randomize()
	is_bot = true
	move_speed_scale = float(zombie_data.get("speed", 2.2)) / BASE_SPEED
	add_to_group("bot")


func setup_bot(
	bot_name: String, team_id: int, diff: Dictionary, game_ref: Node, nav_ref: NavGraph
) -> void:
	game = game_ref
	nav = nav_ref
	difficulty = diff
	display_name = bot_name
	configure(bot_name, team_id, true)
	max_health = float(diff.get("hp", 100))
	health = max_health
	aim_error = float(diff.get("aim_error", 2.5))
	reaction_left = float(diff.get("reaction", 0.35))
	objective = global_position
	patrol_point = global_position
	select_slot(Content.SLOT_KNIFE)


func setup_zombie(
	ztype: String, z_scale: float, z_hp: float, game_ref: Node, nav_ref: NavGraph
) -> void:
	game = game_ref
	nav = nav_ref
	zombie_type = ztype
	zombie_data = Content.zombie_type(ztype)
	is_zombie_ai = true
	difficulty = {"aim_error": 0.0, "reaction": 0.0}
	display_name = String(zombie_data.get("name", "Zombie"))
	setup_for_zombie(ztype, z_scale, zombie_data.get("color", Color(0.4, 0.5, 0.35)), z_hp)
	armor = float(zombie_data.get("armor", 0.0)) * 100.0
	is_bot = true
	move_speed_scale = float(zombie_data.get("speed", 2.2)) / BASE_SPEED
	add_to_group("bot")
	if actor_model:
		actor_model.set_name_tag("")


func _physics_process(delta: float) -> void:
	if not alive:
		super._physics_process(delta)
		return
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	think_timer -= delta
	repath_timer -= delta
	if think_timer <= 0.0:
		think_timer = 0.16 if not is_zombie_ai else 0.25
		_think()
	if is_zombie_ai:
		_zombie_movement(delta)
	else:
		_combat_movement(delta)
	super._physics_process(delta)
	_check_stuck(delta)


func _check_stuck(delta: float) -> void:
	if not is_on_floor():
		stuck_timer = 0.0
		return
	var moved := global_position.distance_to(last_pos)
	last_pos = global_position
	if moved < 0.02 and Vector2(velocity.x, velocity.z).length() > 0.4:
		stuck_timer += delta
		if stuck_timer > 0.35:
			stuck_timer = 0.0
			path.clear()
			path_index = 0
			want_jump = true
			strafe_dir *= -1.0
	else:
		stuck_timer = 0.0


# --- Percepcion ----------------------------------------------------------------


func _think() -> void:
	if not alive:
		return
	if is_zombie_ai:
		_think_zombie()
		return
	var enemy := _find_visible_enemy()
	target_visible = enemy != null
	if enemy:
		if target_enemy != enemy:
			reaction_left = float(difficulty.get("reaction", 0.35))
			if game and game.has_method("on_bot_spotted"):
				game.on_bot_spotted(self, enemy)
		target_enemy = enemy
		last_seen_pos = enemy.global_position
		last_seen_time = _now()
		aim_point = enemy.global_position + Vector3(0, 1.45 if not enemy.crouching else 1.0, 0)
		if _rng.randf() < 0.28:
			aim_point.y += 0.2
		var dist := global_position.distance_to(enemy.global_position)
		aim_point += Vector3(
			_rng.randf_range(-1, 1) * aim_error * 0.1 * dist * 0.1,
			_rng.randf_range(-1, 1) * aim_error * 0.06,
			_rng.randf_range(-1, 1) * aim_error * 0.1 * dist * 0.1
		)
		reaction_left = maxf(0.0, reaction_left - 0.16)
		if state != "engage":
			_set_state("engage")
	elif target_enemy and target_enemy.alive and _now() - last_seen_time < 6.0:
		_set_state("search")
		aim_point = last_seen_pos + Vector3(0, 1.2, 0)
	else:
		target_enemy = null
		if _now() - last_heard_time < 4.0:
			_set_state("investigate")
		else:
			_set_state(_objective_state())
	_manage_weapon()


func _find_visible_enemy() -> Combatant:
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3(0, 1.5, 0)
	var fov: float = float(difficulty.get("fov", 95.0))
	var best: Combatant = null
	var best_dist := 9999.0
	var forward := -global_transform.basis.z
	for other in _enemies():
		if not other.alive:
			continue
		var to := other.global_position + Vector3(0, 1.1, 0)
		var d := eye.distance_to(to)
		if d > 90.0 or d >= best_dist:
			continue
		var dir := (to - eye).normalized()
		if forward.dot(dir) < cos(deg_to_rad(fov * 0.5)) and d > 4.0:
			continue
		if is_instance_valid(game) and game.has_method("is_smoked") and game.is_smoked(eye, to):
			continue
		var query := PhysicsRayQueryParameters3D.new()
		query.from = eye
		query.to = to
		query.collision_mask = 1
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			continue
		# Enemigo muy cercano aunque este fuera del FOV (a la espalda incluido).
		if d < 3.0 or forward.dot(dir) > cos(deg_to_rad(fov * 0.5)):
			best = other
			best_dist = d
	return best


func _enemies() -> Array:
	var out: Array = []
	if game == null:
		return out
	for c in game.all_combatants:
		if not is_instance_valid(c) or not c.alive or c == self:
			continue
		if c.is_hostage:
			continue
		if is_enemy_of(c):
			out.append(c)
	return out


# --- Movimiento de combate -----------------------------------------------------


func _combat_movement(delta: float) -> void:
	var move_target := Vector3.ZERO
	var should_stop := false
	match state:
		"engage":
			if target_enemy and target_enemy.alive:
				move_target = target_enemy.global_position
				var dist := global_position.distance_to(move_target)
				var ideal_near := 6.0
				var ideal_far := 22.0
				if (
					current_id.begins_with("awp")
					or current_id.begins_with("scout")
					or current_id.begins_with("g3")
					or current_id.begins_with("sg5")
				):
					ideal_near = 18.0
					ideal_far = 45.0
				if dist < ideal_near:
					should_stop = false
					_strafe(delta, move_target, true)
				elif dist > ideal_far:
					_move_towards(move_target)
				else:
					should_stop = true
					_strafe(delta, move_target, false)
				_face_aim_point()
				_engage(delta)
			else:
				_set_state(_objective_state())
		"search":
			if nav:
				_move_towards(last_seen_pos)
				if global_position.distance_to(last_seen_pos) < 2.0:
					last_seen_time = -99.0
					_set_state(_objective_state())
		"investigate":
			_move_towards(last_heard_pos)
			if global_position.distance_to(last_heard_pos) < 2.5:
				last_heard_time = -99.0
				_set_state(_objective_state())
		"plant":
			if game and game.has_method("bot_try_plant"):
				if game.bot_try_plant(self):
					should_stop = true
				else:
					_move_towards(objective)
		"defuse":
			if game and game.has_method("bot_try_defuse"):
				if game.bot_try_defuse(self):
					should_stop = true
				else:
					_move_towards(objective)
		"rescue":
			_handle_rescue()
		"defend", "attack", "roam":
			_move_towards(objective)
			if global_position.distance_to(objective) < 3.5:
				should_stop = true
				if _now() - fire_time > 2.0:
					patrol_point = _random_near(objective, 6.0)
					objective = patrol_point
			_scan_idle(delta)
		_:
			_move_towards(objective)
	if should_stop:
		wish_dir = Vector2.ZERO
	if state != "engage" and target_enemy == null:
		_scan_idle(delta)
	_handle_reload_need()


func _strafe(delta: float, enemy_pos: Vector3, closing: bool) -> void:
	strafe_timer -= delta
	if strafe_timer <= 0.0:
		strafe_timer = _rng.randf_range(0.45, 1.2)
		strafe_dir = -strafe_dir if _rng.randf() < 0.7 else strafe_dir
	var to_enemy := enemy_pos - global_position
	to_enemy.y = 0
	var side := Vector3(-to_enemy.z, 0, to_enemy.x).normalized()
	var wish := side * strafe_dir * (0.7 if not closing else 0.3)
	if closing:
		wish += to_enemy.normalized() * -0.5
	wish_dir = Vector2(wish.x, wish.z)


func _move_towards(point: Vector3) -> void:
	if nav == null:
		var d := point - global_position
		d.y = 0
		if d.length() > 0.8:
			wish_dir = Vector2(d.x, d.z).normalized()
		else:
			wish_dir = Vector2.ZERO
		return
	var dist := global_position.distance_to(point)
	if dist < 0.9:
		wish_dir = Vector2.ZERO
		return
	if (
		path.is_empty()
		or path_index >= path.size()
		or repath_timer <= 0.0
		or path_target.distance_to(point) > 2.5
	):
		path = nav.find_path(global_position, point)
		path_index = 0
		path_target = point
		repath_timer = _rng.randf_range(1.2, 2.0)
	# Avanza por los waypoints.
	while path_index < path.size():
		var wp := path[path_index]
		wp.y = global_position.y
		if global_position.distance_to(wp) < 0.9:
			path_index += 1
		else:
			break
	if path_index >= path.size():
		wish_dir = Vector2.ZERO
		return
	var next := path[path_index]
	var flat := Vector3(next.x - global_position.x, 0, next.z - global_position.z)
	if flat.length() < 0.05:
		path_index += 1
		return
	var dir := flat.normalized()
	# Separacion simple de otros bots.
	if game:
		for other in game.all_combatants:
			if other == self or not is_instance_valid(other) or not other.alive:
				continue
			if not other.is_zombie and is_zombie:
				continue
			var away := global_position - other.global_position
			away.y = 0
			if away.length() < 1.3 and away.length() > 0.01:
				dir += away.normalized() * 0.8
	dir = dir.normalized()
	wish_dir = Vector2(dir.x, dir.z)
	# Salto si el siguiente waypoint esta mas alto.
	if next.y > global_position.y + 0.35 and is_on_floor():
		want_jump = true


func _random_near(center: Vector3, radius: float) -> Vector3:
	if nav:
		return nav.random_point_near(center, radius, _rng)
	var a := _rng.randf() * TAU
	return center + Vector3(cos(a), 0, sin(a)) * radius


func _face_aim_point() -> void:
	var flat := Vector3(aim_point.x, global_position.y, aim_point.z)
	if flat.distance_to(global_position) > 0.2:
		var target_yaw := atan2(-(flat.x - global_position.x), -(flat.z - global_position.z))
		global_rotation.y = lerp_angle(global_rotation.y, target_yaw, 0.25)


func _scan_idle(delta: float) -> void:
	strafe_timer -= delta
	if strafe_timer <= 0.0:
		strafe_timer = _rng.randf_range(1.5, 3.5)
		var look := _random_near(global_position, 12.0)
		var flat := Vector3(look.x, global_position.y, look.z)
		if flat.distance_to(global_position) > 0.5:
			var target_yaw := atan2(-(flat.x - global_position.x), -(flat.z - global_position.z))
			global_rotation.y = lerp_angle(global_rotation.y, target_yaw, 0.08)


# --- Disparo -------------------------------------------------------------------


func _engage(delta: float) -> void:
	if is_blind():
		wants_fire = false
		return
	var def := current_def()
	var dist := global_position.distance_to(aim_point)
	var can_shoot := reaction_left <= 0.0 and target_visible
	if not can_shoot:
		wants_fire = false
		return
	if reload_time_left > 0.0:
		wants_fire = false
		return
	var a := current_ammo()
	if a.x <= 0:
		wants_fire = false
		reload()
		return
	var burst_cfg: float = float(difficulty.get("burst", 0.25))
	fire_time -= delta
	pause_time -= delta
	if fire_time <= 0.0:
		wants_fire = false
		if pause_time <= 0.0:
			fire_time = _rng.randf_range(0.35, 0.9) * (1.0 - burst_cfg)
			pause_time = _rng.randf_range(0.12, 0.55)
		return
	wants_fire = true
	# No disparar si un companero esta en la linea.
	if _friendly_in_line():
		wants_fire = false
	# Con francos, esperar a estar quieto.
	if float(def.get("zoom", 0.0)) > 0.0:
		wants_fire = wants_fire and Vector2(velocity.x, velocity.z).length() < 1.2


func _friendly_in_line() -> bool:
	var space := get_world_3d().direct_space_state
	var from := get_fire_origin()
	var to := aim_point
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = PLAYER_LAYER
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	var other = hit.collider
	if other is Combatant:
		var c := other as Combatant
		return c.team == team and c != self
	return false


func _manage_weapon() -> void:
	if current_slot == Content.SLOT_KNIFE:
		if primary_id != "":
			select_slot(Content.SLOT_PRIMARY)
		elif secondary_id != "":
			select_slot(Content.SLOT_SECONDARY)
	elif current_slot != Content.SLOT_PRIMARY and current_slot != Content.SLOT_SECONDARY:
		if primary_id != "":
			select_slot(Content.SLOT_PRIMARY)
	var def := current_def()
	var a := current_ammo()
	if a.x <= 0 and a.y > 0 and reload_time_left <= 0.0:
		reload()
	elif (
		reload_time_left <= 0.0
		and float(a.x) <= float(def.get("mag", 1)) * 0.25
		and target_enemy == null
	):
		reload()


func _handle_reload_need() -> void:
	var a := current_ammo()
	if a.x <= 0 and a.y > 0 and reload_time_left <= 0.0:
		reload()


func _current_spread(def: Dictionary) -> float:
	var base := super._current_spread(def)
	if is_zombie_ai:
		return base
	var extra := deg_to_rad(aim_error * 0.32)
	if target_visible and target_enemy:
		var dist := global_position.distance_to(target_enemy.global_position)
		extra *= clampf(dist / 15.0, 0.5, 2.2)
	return base + extra


func _objective_state() -> String:
	if is_zombie_ai:
		return "zombie_chase"
	match objective_type:
		"plant":
			if global_position.distance_to(objective) < 4.0:
				return "plant"
			return "attack"
		"defuse":
			if global_position.distance_to(objective) < 3.0:
				return "defuse"
			return "defuse"
		"rescue":
			return "rescue"
		"defend":
			return "defend"
	return "attack"


func _handle_rescue() -> void:
	if game == null:
		return
	var target = game.nearest_hostage(global_position)
	if target == null:
		_move_towards(objective)
		return
	if global_position.distance_to(target.global_position) < 2.2:
		game.bot_grab_hostage(self, target)
		objective = game.rescue_point()
		wish_dir = Vector2.ZERO
		return
	_move_towards(target.global_position)


func _set_state(new_state: String) -> void:
	if state != new_state:
		state = new_state
		_last_state = new_state


# --- Zombies -------------------------------------------------------------------


func _think_zombie() -> void:
	var best: Combatant = null
	var best_dist := 9999.0
	if game:
		for c in game.survivors():
			if not is_instance_valid(c) or not c.alive:
				continue
			var d := global_position.distance_to(c.global_position)
			if d < best_dist:
				best_dist = d
				best = c
	target_enemy = best
	if best:
		last_seen_pos = best.global_position
		aim_point = best.global_position + Vector3(0, 1.2, 0)
		wants_fire = false
		state = "zombie_chase"
	else:
		state = "zombie_wander"
		wish_dir = Vector2.ZERO


func _zombie_movement(delta: float) -> void:
	if target_enemy == null or not target_enemy.alive:
		wish_dir = Vector2.ZERO
		return
	var dist := global_position.distance_to(target_enemy.global_position)
	var ranged: bool = bool(zombie_data.get("ranged", false))
	var attack_range := (
		float(zombie_data.get("range", 1.9)) if ranged else (2.0 if body_scale_large() else 1.85)
	)
	if dist <= attack_range:
		wish_dir = Vector2.ZERO
		_face_aim_point()
		if attack_cooldown <= 0.0:
			_zombie_attack(ranged)
	else:
		_move_towards(target_enemy.global_position)
		_face_aim_point()
		if dist < 8.0 and _rng.randf() < delta * 0.5:
			want_jump = true


func body_scale_large() -> bool:
	return zombie_type == "brute" or zombie_type == "boss"


func _zombie_attack(ranged: bool) -> void:
	attack_cooldown = float(zombie_data.get("attack_rate", 1.2)) * _rng.randf_range(0.85, 1.15)
	var dmg := float(zombie_data.get("damage", 18))
	if ranged and game and game.has_method("spawn_zombie_spit"):
		game.spawn_zombie_spit(self, target_enemy, dmg)
		AudioBank.play_at("zombie_attack", get_parent(), global_position, -2.0, 1.1, 25.0)
		return
	if target_enemy and global_position.distance_to(target_enemy.global_position) < 2.4:
		target_enemy.take_damage(dmg, self, "chest", "zombie_claw")
		AudioBank.play_at(
			"zombie_attack", get_parent(), global_position, 0.0, _rng.randf_range(0.9, 1.1), 30.0
		)
		if game and game.has_method("on_zombie_hit"):
			game.on_zombie_hit(self, target_enemy)


func hear_noise(origin: Vector3, loudness: float) -> void:
	if not alive or is_zombie_ai:
		return
	var dist := global_position.distance_to(origin)
	var hearing: float = float(difficulty.get("hearing", 20.0)) * clampf(loudness / 55.0, 0.4, 1.6)
	if dist < hearing:
		last_heard_pos = origin
		last_heard_time = _now()
		if state != "engage":
			_set_state("investigate")


func report_damage(attacker: Node) -> void:
	if attacker is Combatant:
		target_enemy = attacker as Combatant
		last_seen_pos = attacker.global_position
		last_seen_time = _now()
		aim_point = last_seen_pos + Vector3(0, 1.2, 0)
		reaction_left = float(difficulty.get("reaction", 0.3))
		if state != "engage":
			_set_state("engage")


func get_fire_origin() -> Vector3:
	return global_position + Vector3(0, 1.35 if not crouching else 0.95, 0)


func get_fire_direction() -> Vector3:
	var origin := get_fire_origin()
	var dir := aim_point - origin
	if dir.length() < 0.01:
		return -global_transform.basis.z
	return dir.normalized()
