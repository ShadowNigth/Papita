extends CharacterBody3D
## Combatant: base de jugador, bots, zombies y rehenes.
##
## Implementa movimiento estilo Counter-Strike (aceleracion, friccion, aire),
## inventario de armas, disparo con dispersion/retroceso/penetracion, dano con
## chaleco/casco, recarga, cuchillo, granadas y muerte.

class_name Combatant

signal died(victim, attacker, weapon_id: String, headshot: bool)
signal damaged(victim, amount: float, attacker, hitbox: String, weapon_id: String)
signal health_changed(victim, health: float, armor: float)
signal fired(origin: Vector3, loudness: float, team: int, weapon_id: String)
signal hit_confirmed(attacker, victim, damage: float, headshot: bool)
signal weapon_state_changed(combatant)

const GRAVITY := 20.0
const BASE_SPEED := 5.4
const JUMP_SPEED := 5.1
const PLAYER_LAYER := 4

var display_name := "Jugador"
var team := 1
var is_bot := false
var is_zombie := false
var is_hostage := false
var is_player := false

var max_health := 100.0
var health := 100.0
var max_armor := 100.0
var armor := 0.0
var helmet := false
var money := 800
var alive := true
var frozen := false
var invulnerable := false
var god_mode := false

var primary_id := ""
var secondary_id := ""
var grenades: Array[String] = []
var has_c4 := false
var silencer_on := false
var defusekit := false
var nightvision := false

var ammo: Dictionary = {}
var current_slot := 3
var current_id := "knife"
var current_grenade := 0
var reload_time_left := 0.0
var reload_total := 0.0
var reloading_id := ""
var next_fire_time := 0.0
var burst_left := 0
var burst_mode_weapons: Dictionary = {}
var zoom_level := 0
var zoom_max := 0
var recoil_pitch := 0.0
var recoil_yaw := 0.0
var last_damage_time := -10.0
var last_attacker: Node = null
var kills := 0
var deaths := 0
var headshots := 0
var total_shots := 0
var total_hits := 0
var round_kills := 0

var actor_model: ActorModel
var model_container: Node3D
var collision_shape: CollisionShape3D
var capsule: CapsuleShape3D

var move_speed_scale := 1.0
var wish_dir := Vector2.ZERO
var want_jump := false
var want_crouch := false
var want_walk := false
var wants_fire := false
var trigger_was_down := false
var crouching := false
var aim_pitch := 0.0
var footstep_timer := 0.0
var _was_grounded := true
var _spawn_position := Vector3.ZERO
var _slow_timer := 0.0
var _slow_amount := 1.0
var _rng := RandomNumberGenerator.new()
var _dead_timer := 0.0
var _flash_blind := 0.0
var _last_pain_sfx := 0.0


func _ready() -> void:
	collision_layer = PLAYER_LAYER
	collision_mask = 1 | PLAYER_LAYER
	add_to_group("combatant")
	_rng.randomize()
	_build_collision()


func _build_collision() -> void:
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.8
	collision_shape = CollisionShape3D.new()
	collision_shape.shape = capsule
	collision_shape.position = Vector3(0, 0.9, 0)
	add_child(collision_shape)
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.35
	slide_on_ceiling = false
	wall_min_slide_angle = deg_to_rad(8.0)


func configure(player_name: String, team_id: int, bot: bool) -> void:
	display_name = player_name
	team = team_id
	is_bot = bot
	add_to_group("team_ct" if team == Content.TEAM_CT else "team_t")
	_setup_model()


func _setup_model() -> void:
	if is_player:
		if actor_model != null:
			actor_model.visible = false
		if model_container != null:
			model_container.visible = false
		return
	if model_container == null:
		model_container = Node3D.new()
		model_container.name = "Model"
		add_child(model_container)
		actor_model = ActorModel.new()
		actor_model.name = "Actor"
		model_container.add_child(actor_model)
		actor_model.setup(team, is_zombie)
		actor_model.set_name_tag(display_name)


func setup_for_zombie(ztype: String, z_scale: float, z_color: Color, z_hp: float) -> void:
	is_zombie = true
	team = 3
	display_name = Content.zombie_type(ztype).get("name", "Zombie")
	max_health = z_hp
	health = z_hp
	remove_from_group("team_t")
	add_to_group("zombie")
	if is_player:
		if actor_model != null:
			actor_model.visible = false
		if model_container != null:
			model_container.visible = false
	else:
		if model_container == null:
			model_container = Node3D.new()
			model_container.name = "Model"
			add_child(model_container)
			actor_model = ActorModel.new()
			actor_model.name = "Actor"
			model_container.add_child(actor_model)
		actor_model.setup(3, true, z_color, z_scale)
		actor_model.visible = true
	capsule.height = 1.8 * z_scale
	capsule.radius = 0.36 * z_scale
	collision_shape.position = Vector3(0, 0.9 * z_scale, 0)
	primary_id = ""
	secondary_id = ""
	current_id = "knife"
	current_slot = 3


func _physics_process(delta: float) -> void:
	if not alive:
		velocity.y -= GRAVITY * delta
		if is_on_floor():
			velocity = Vector3.ZERO
		move_and_slide()
		_dead_timer += delta
		return
	_update_timers(delta)
	if frozen:
		velocity.x = 0
		velocity.z = 0
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		_update_model(delta)
		return
	_apply_movement(delta)
	_handle_weapon(delta)
	_update_model(delta)


func _update_timers(delta: float) -> void:
	reload_time_left = maxf(0.0, reload_time_left - delta)
	if _flash_blind > 0.0:
		_flash_blind = maxf(0.0, _flash_blind - delta)
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_amount = 1.0
	recoil_pitch = lerpf(recoil_pitch, 0.0, clampf(delta * 6.5, 0.0, 1.0))
	recoil_yaw = lerpf(recoil_yaw, 0.0, clampf(delta * 6.5, 0.0, 1.0))
	# Regeneracion del Juggernog (solo modo zombie).
	if is_zombie_mode_active() and has_meta("regen") and health < max_health:
		health = minf(max_health, health + 3.0 * delta)
		health_changed.emit(self, health, armor)


func is_zombie_mode_active() -> bool:
	return bool(get_meta("zombie_mode", false))


func _apply_movement(delta: float) -> void:
	var def := current_def()
	var speed_mult: float = float(def.get("speed_mult", 1.0))
	var target_speed := BASE_SPEED * speed_mult * _slow_amount * move_speed_scale
	if want_walk:
		target_speed *= 0.52
	if want_crouch and is_on_floor():
		target_speed *= 0.56
	if reload_time_left > 0.0:
		target_speed *= 0.92
	var wish := Vector3(wish_dir.x, 0, wish_dir.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	if is_on_floor():
		if wish.length() > 0.05:
			var accel := 11.0 if not crouching else 8.0
			velocity.x = move_toward(
				velocity.x, wish.x * target_speed, accel * delta * target_speed
			)
			velocity.z = move_toward(
				velocity.z, wish.z * target_speed, accel * delta * target_speed
			)
		else:
			var fric := 9.0 if not crouching else 6.0
			velocity.x = move_toward(velocity.x, 0.0, fric * delta * BASE_SPEED)
			velocity.z = move_toward(velocity.z, 0.0, fric * delta * BASE_SPEED)
		if want_jump:
			velocity.y = JUMP_SPEED
			want_jump = false
			AudioBank.play_at(
				"jump",
				self,
				global_position + Vector3(0, 0.1, 0),
				-8.0,
				_rng.randf_range(0.95, 1.05),
				18.0
			)
		elif velocity.y <= 0.0:
			velocity.y = -0.5
	else:
		if wish.length() > 0.05:
			velocity.x = move_toward(velocity.x, wish.x * target_speed, 2.2 * delta * target_speed)
			velocity.z = move_toward(velocity.z, wish.z * target_speed, 2.2 * delta * target_speed)
		velocity.y -= GRAVITY * delta
		want_jump = false
	# Crouch: agacha el cuerpo.
	var target_crouch := want_crouch and is_on_floor()
	if crouching != target_crouch:
		crouching = target_crouch
		capsule.height = 1.8 if not crouching else 1.15
		collision_shape.position.y = capsule.height * 0.5
	# Paso automatico (solo escalones reales, nunca en suelo plano).
	velocity = velocity.limit_length(30.0)
	move_and_slide()
	if is_on_floor() and wish.length() > 0.1 and get_slide_collision_count() > 0:
		_step_up(wish)
	_handle_footsteps(delta)
	if not _was_grounded and is_on_floor():
		AudioBank.play_at("land", self, global_position, -6.0, _rng.randf_range(0.9, 1.05), 22.0)
	_was_grounded = is_on_floor()


func _has_horizontal_step_collision(wish: Vector3) -> bool:
	var flat_wish := Vector3(wish.x, 0.0, wish.z)
	if flat_wish.length_squared() < 0.0025:
		return false
	flat_wish = flat_wish.normalized()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col == null:
			continue
		var n := col.get_normal()
		if absf(n.y) < 0.35:
			var flat_n := Vector3(n.x, 0.0, n.z)
			if flat_n.length_squared() > 0.0001 and flat_n.normalized().dot(flat_wish) < -0.2:
				return true
	return false


func _step_up(wish: Vector3) -> void:
	var max_step := 0.34
	if not _has_horizontal_step_collision(wish):
		return
	if test_move(global_transform, Vector3(0.0, max_step, 0.0)):
		return
	var raised := global_transform
	raised.origin.y += max_step
	var forward := Vector3(wish.x, 0.0, wish.z).normalized() * 0.16
	if test_move(raised, forward):
		return
	var fwd_xf := raised.translated(forward)
	if not test_move(fwd_xf, Vector3(0.0, -max_step - 0.03, 0.0)):
		return
	var lo := 0.0
	var hi := max_step + 0.03
	for _iter in 5:
		var mid := (lo + hi) * 0.5
		if test_move(fwd_xf, Vector3(0.0, -mid, 0.0)):
			hi = mid
		else:
			lo = mid
	var step_delta := max_step - lo
	if step_delta <= 0.02 or step_delta > max_step + 0.01:
		return
	var space := get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.new()
	rq.from = fwd_xf.origin + Vector3(0.0, 0.15, 0.0)
	rq.to = fwd_xf.origin - Vector3(0.0, max_step + 0.15, 0.0)
	rq.collision_mask = 1
	var hit := space.intersect_ray(rq)
	if not hit.is_empty() and Vector3(hit.normal).y < 0.7:
		return
	var old_y := global_position.y
	global_position = Vector3(fwd_xf.origin.x, old_y + step_delta + 0.004, fwd_xf.origin.z)
	velocity.y = -0.5
	_on_stepped_up(step_delta)


func _on_stepped_up(_step_delta: float) -> void:
	pass


func _handle_footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or speed < 2.0:
		return
	footstep_timer -= delta
	if footstep_timer <= 0.0:
		footstep_timer = clampf(0.62 - speed * 0.05, 0.26, 0.6)
		AudioBank.footstep(get_parent(), global_position, want_walk or crouching)


func _update_model(delta: float) -> void:
	if actor_model == null:
		return
	actor_model.animate(velocity, is_on_floor(), aim_pitch, crouching, delta)


# --- Armas ---------------------------------------------------------------------


func current_def() -> Dictionary:
	if current_id == "":
		return Content.WEAPONS.knife
	return Content.get_weapon(current_id)


func current_ammo() -> Vector2i:
	if not ammo.has(current_id):
		return Vector2i(0, 0)
	return ammo[current_id]


func _set_ammo(id: String, mag: int, reserve: int) -> void:
	ammo[id] = Vector2i(mag, reserve)


func give_weapon(id: String, equip_now: bool = true) -> void:
	var def := Content.get_weapon(id)
	if def.is_empty():
		return
	var slot: int = int(def.get("slot", 1))
	match slot:
		Content.SLOT_PRIMARY:
			primary_id = id
		Content.SLOT_SECONDARY:
			secondary_id = id
		Content.SLOT_GRENADE:
			if grenades.size() < 4:
				grenades.append(id)
			_set_ammo(id, 1, 1)
			if equip_now:
				select_slot(Content.SLOT_GRENADE)
			weapon_state_changed.emit(self)
			return
		Content.SLOT_C4:
			has_c4 = true
			_set_ammo("c4", 1, 0)
			if equip_now:
				select_slot(Content.SLOT_C4)
			weapon_state_changed.emit(self)
			return
	var mag: int = int(def.get("mag", 0))
	var reserve: int = int(def.get("reserve", 0))
	if not ammo.has(id) or slot == Content.SLOT_PRIMARY or slot == Content.SLOT_SECONDARY:
		_set_ammo(id, mag, reserve)
	if equip_now:
		select_slot(slot)
	weapon_state_changed.emit(self)


func has_weapon(id: String) -> bool:
	return (
		primary_id == id
		or secondary_id == id
		or grenades.has(id)
		or (id == "knife")
		or (id == "c4" and has_c4)
	)


func select_slot(slot: int) -> void:
	var id := ""
	match slot:
		Content.SLOT_PRIMARY:
			id = primary_id
		Content.SLOT_SECONDARY:
			id = secondary_id
		Content.SLOT_KNIFE:
			id = "knife"
		Content.SLOT_GRENADE:
			if grenades.is_empty():
				return
			if current_grenade >= grenades.size():
				current_grenade = 0
			id = grenades[current_grenade]
		Content.SLOT_C4:
			if not has_c4:
				return
			id = "c4"
	if id == "":
		return
	if id == current_id and reset_if_same(slot):
		return
	current_id = id
	current_slot = slot
	reload_time_left = 0.0
	zoom_level = 0
	var def := current_def()
	next_fire_time = _now() + float(def.get("draw", 0.5)) * (0.7 if has_meta("speed_cola") else 1.0)
	burst_left = 0
	if is_player:
		AudioBank.weapon_deploy(current_id, true)
	if actor_model and not is_player:
		actor_model.equip(def)
	weapon_state_changed.emit(self)


func reset_if_same(slot: int) -> bool:
	return slot != Content.SLOT_GRENADE


func cycle_weapon(direction: int) -> void:
	var slots: Array[int] = []
	if primary_id != "":
		slots.append(Content.SLOT_PRIMARY)
	if secondary_id != "":
		slots.append(Content.SLOT_SECONDARY)
	slots.append(Content.SLOT_KNIFE)
	if not grenades.is_empty():
		slots.append(Content.SLOT_GRENADE)
	if has_c4:
		slots.append(Content.SLOT_C4)
	if slots.is_empty():
		return
	var idx: int = slots.find(current_slot)
	if idx == -1:
		idx = 0
	idx = (idx + direction + slots.size()) % slots.size()
	select_slot(slots[idx])


func cycle_grenade() -> void:
	if grenades.size() < 2:
		return
	current_grenade = (current_grenade + 1) % grenades.size()
	if current_slot == Content.SLOT_GRENADE:
		current_id = grenades[current_grenade]
		next_fire_time = _now() + 0.3
		weapon_state_changed.emit(self)


func reload() -> void:
	if (
		current_slot == Content.SLOT_GRENADE
		or current_slot == Content.SLOT_C4
		or current_slot == Content.SLOT_KNIFE
	):
		return
	if reload_time_left > 0.0:
		return
	var def := current_def()
	var a := current_ammo()
	var mag_size: int = int(def.get("mag", 1))
	if a.x >= mag_size or a.y <= 0:
		return
	reload_total = float(def.get("reload", 2.0))
	if def.get("reload_shell", false):
		var need := mag_size - a.x
		reload_total = float(def.get("reload", 0.5)) * maxf(1.0, float(need))
	if has_meta("speed_cola"):
		reload_total *= 0.55
	reload_time_left = reload_total
	reloading_id = current_id
	burst_left = 0
	zoom_level = 0
	if is_player:
		AudioBank.weapon_reload_step(reloading_id, 0, true, get_parent(), global_position)
		_play_reload_sequence(def)
		_on_reload_started(reload_total)
	else:
		AudioBank.weapon_reload_step(reloading_id, 0, false, get_parent(), global_position)
	weapon_state_changed.emit(self)
	_start_reload_timer()


func _on_reload_started(_duration: float) -> void:
	pass


func _on_melee_attacked(_hit: bool, _heavy: bool = false) -> void:
	pass


func _on_grenade_thrown() -> void:
	pass


func _on_silencer_toggled(_enabled: bool) -> void:
	pass


func _start_reload_timer() -> void:
	var timer := get_tree().create_timer(reload_total)
	timer.timeout.connect(_finish_reload)


func _play_reload_sequence(def: Dictionary) -> void:
	var wid := reloading_id
	var t := get_tree().create_timer(reload_total * 0.48)
	t.timeout.connect(
		func() -> void:
			if alive and is_player:
				AudioBank.weapon_reload_step(wid, 1, true, get_parent(), global_position)
	)
	if def.get("reload_shell", false):
		var t2 := get_tree().create_timer(reload_total * 0.78)
		t2.timeout.connect(
			func() -> void:
				if alive and is_player:
					AudioBank.play_2d("pump", -4.0)
		)


func _finish_reload() -> void:
	if not alive:
		return
	var id := reloading_id if reloading_id != "" else current_id
	var def := Content.get_weapon(id)
	if def.is_empty():
		reload_time_left = 0.0
		return
	var a: Vector2i = ammo.get(id, Vector2i(0, 0))
	var mag_size: int = int(def.get("mag", 1))
	if a.y <= 0:
		reload_time_left = 0.0
		return
	var need := mag_size - a.x
	var take := mini(need, a.y)
	var new_reserve := a.y - take
	if has_meta("mule"):
		new_reserve = maxi(new_reserve, int(Content.get_weapon(id).get("reserve", 90)))
	_set_ammo(id, a.x + take, new_reserve)
	reload_time_left = 0.0
	if is_player:
		AudioBank.weapon_reload_step(id, 2, true, get_parent(), global_position)
	weapon_state_changed.emit(self)


func can_fire() -> bool:
	if not alive or frozen:
		return false
	var def := current_def()
	if def.is_empty():
		return false
	if _now() < next_fire_time:
		return false
	if reload_time_left > 0.0:
		return false
	if current_slot == Content.SLOT_GRENADE:
		return true
	if current_slot == Content.SLOT_KNIFE:
		return true
	var a := current_ammo()
	return a.x > 0


func is_burst_mode_active(wid: String = "") -> bool:
	var id := wid if wid != "" else current_id
	var def := Content.get_weapon(id)
	if int(def.get("burst", 0)) <= 1:
		return false
	if bool(def.get("burst_toggle", false)):
		return bool(burst_mode_weapons.get(id, false))
	return true


func fire_mode_label() -> String:
	var def := current_def()
	if is_burst_mode_active():
		return "RAFAGA x%d" % int(def.get("burst", 3))
	return "AUTO" if bool(def.get("auto", false)) else "SEMI"


func toggle_fire_mode() -> String:
	var def := current_def()
	if not bool(def.get("burst_toggle", false)) or reload_time_left > 0.0:
		return ""
	var enabled: bool = not bool(burst_mode_weapons.get(current_id, false))
	burst_mode_weapons[current_id] = enabled
	burst_left = 0
	next_fire_time = maxf(next_fire_time, _now() + 0.22)
	if is_player:
		AudioBank.play_2d("fire_mode", -4.0)
	weapon_state_changed.emit(self)
	if enabled:
		return "Cambiado a rafaga de %d disparos" % int(def.get("burst", 3))
	if bool(def.get("auto", false)):
		return "Cambiado a modo automatico"
	return "Cambiado a modo semiautomatico"


func _handle_weapon(_delta: float) -> void:
	if not wants_fire:
		trigger_was_down = false
	if not alive or frozen:
		burst_left = 0
		return
	var def := current_def()
	if current_slot == Content.SLOT_GRENADE:
		if wants_fire and _now() >= next_fire_time:
			_throw_grenade()
			wants_fire = false
		return
	if current_slot == Content.SLOT_KNIFE:
		if wants_fire and _now() >= next_fire_time:
			_melee_attack(false)
			wants_fire = false
		return
	if current_slot == Content.SLOT_C4:
		return
	if reload_time_left > 0.0:
		burst_left = 0
		return
	var burst_active := is_burst_mode_active()
	var burst_count: int = int(def.get("burst", 0)) if burst_active else 0
	var burst_rpm: float = float(def.get("burst_rpm", maxf(float(def.get("rpm", 600)), 900.0)))
	var burst_cd: float = float(def.get("burst_cooldown", 0.4))
	if burst_left > 0:
		if _now() >= next_fire_time:
			if reload_time_left <= 0.0 and current_ammo().x > 0:
				_do_fire()
				burst_left -= 1
				if burst_left > 0:
					next_fire_time = _now() + 60.0 / maxf(burst_rpm, 60.0)
				else:
					next_fire_time = _now() + burst_cd
			else:
				burst_left = 0
		return
	if not wants_fire:
		return
	var auto: bool = bool(def.get("auto", false)) and not burst_active
	if not auto:
		if trigger_was_down:
			return
		trigger_was_down = true
	if _now() < next_fire_time:
		return
	if current_ammo().x <= 0:
		if not trigger_was_down:
			trigger_was_down = true
			if is_player:
				AudioBank.play_2d(
					"empty_pistol" if current_slot == Content.SLOT_SECONDARY else "empty", -4.0
				)
		if Settings.data.gameplay.get("auto_reload", false):
			reload()
		return
	# En Deathmatch el disparo rompe la proteccion temporal de reaparicion.
	if invulnerable and has_meta("dm_spawn_shield"):
		invulnerable = false
		set_meta("dm_spawn_shield", false)
	if burst_count > 1:
		burst_left = burst_count - 1
		_do_fire()
		next_fire_time = _now() + 60.0 / maxf(burst_rpm, 60.0)
		return
	_do_fire()


func _now() -> float:
	return float(Time.get_ticks_msec()) * 0.001


func _do_fire() -> void:
	var def := current_def()
	var a := current_ammo()
	_set_ammo(current_id, maxi(0, a.x - 1), a.y)
	var rpm: float = maxf(float(def.get("rpm", 300)), 20.0)
	var rate := 60.0 / rpm
	if has_meta("double_tap"):
		rate *= 0.85
	if has_meta("speed_cola"):
		rate *= 0.97
	next_fire_time = _now() + rate
	total_shots += 1
	var origin := get_fire_origin()
	var dir := get_fire_direction()
	var silenced: bool = silencer_on and bool(def.get("silencer", false))
	var pellets: int = int(def.get("pellets", 1))
	var spread := _current_spread(def)
	for i in pellets:
		var d := dir
		if spread > 0.0001:
			d = _apply_cone(dir, spread)
		_hitscan(origin, d, def, i == 0)
	var loud := 55.0 if not silenced else 18.0
	AudioBank.weapon_fire_id(
		current_id, silenced, get_parent(), origin, is_player, 95.0 if not silenced else 42.0
	)
	fired.emit(origin, loud, team, current_id)
	var muzzle_pos := origin + dir * 0.5
	Fx.muzzle(get_parent(), muzzle_pos, dir)
	if is_player:
		AudioBank.play_2d("shell", -13.0, _rng.randf_range(0.92, 1.08))
	# Retroceso.
	var r: float = float(def.get("recoil", 1.0))
	var zoom_factor := 0.45 if zoom_level > 0 else 1.0
	recoil_pitch += r * 0.012 * zoom_factor * (0.7 if crouching else 1.0)
	recoil_yaw += _rng.randf_range(-1.0, 1.0) * r * 0.007 * zoom_factor
	if is_player:
		_apply_player_recoil(r, def)
	if current_id == "m3" and is_player:
		var tp := get_tree().create_timer(0.28)
		tp.timeout.connect(
			func() -> void:
				if alive and current_id == "m3":
					AudioBank.play_2d("pump", -6.0, _rng.randf_range(0.97, 1.03))
		)
	elif (current_id == "awp" or current_id == "scout") and is_player:
		var bolt_id := current_id
		var tb := get_tree().create_timer(0.34)
		tb.timeout.connect(
			func() -> void:
				if alive and current_id == bolt_id:
					AudioBank.weapon_reload_step(bolt_id, 2, true, get_parent(), global_position)
		)
	weapon_state_changed.emit(self)


func _apply_player_recoil(_r: float, _def: Dictionary) -> void:
	pass


func _current_spread(def: Dictionary) -> float:
	var base: float = float(def.get("spread", 0.5))
	var move_pen: float = float(def.get("move_spread", 1.8))
	var air_pen: float = float(def.get("air_spread", 5.0))
	var speed := Vector2(velocity.x, velocity.z).length()
	var move_factor := clampf(speed / BASE_SPEED, 0.0, 1.8)
	var spread := base + move_pen * move_factor
	if not is_on_floor():
		spread += air_pen
	if crouching:
		spread *= 0.62
	if want_walk:
		spread *= 0.8
	if current_id == "famas" and is_burst_mode_active():
		spread *= 0.68
	if zoom_level > 0:
		spread *= 0.35
	spread += recoil_pitch * 90.0 * 0.12
	if is_zombie:
		spread = 0.0
	return deg_to_rad(spread)


func _apply_cone(dir: Vector3, spread_rad: float) -> Vector3:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	var true_up := right.cross(dir).normalized()
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * spread_rad
	return (dir + right * cos(a) * r + true_up * sin(a) * r).normalized()


func _hitscan(origin: Vector3, dir: Vector3, def: Dictionary, _primary: bool) -> void:
	var space := get_world_3d().direct_space_state
	var range_f: float = float(def.get("range", 60.0))
	var penetration: int = int(def.get("penetration", 1))
	var from := origin
	var remaining := range_f
	var travelled := 0.0
	var pierced := 0
	var seg := 0
	while seg < 3 and remaining > 0.2:
		seg += 1
		var query := PhysicsRayQueryParameters3D.new()
		query.from = from
		query.to = from + dir * remaining
		query.collision_mask = 1 | PLAYER_LAYER
		query.collide_with_bodies = true
		var excl: Array[RID] = [get_rid()]
		query.exclude = excl
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return
		var collider = hit.collider
		var point: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var dist := travelled + from.distance_to(point)
		if collider is Combatant:
			var victim := collider as Combatant
			if victim == self:
				return
			if victim.team != team or victim.is_hostage:
				var hitbox := victim.hitbox_at(point)
				var dmg := calculate_damage(def, dist, hitbox, victim)
				var headshot := hitbox == "head"
				victim.take_damage(dmg, self, hitbox, current_id, pierced > 0)
				total_hits += 1
				hit_confirmed.emit(self, victim, dmg, headshot)
				var blood_dir := -dir
				Fx.blood(get_parent(), point, blood_dir, 16 if headshot else 10)
				if headshot:
					AudioBank.play_at(
						"helmet_hit" if victim.helmet else "headshot",
						get_parent(),
						point,
						-2.0,
						1.0,
						28.0
					)
				else:
					AudioBank.play_at(
						"kevlar_hit" if victim.armor > 0.0 else "flesh_hit",
						get_parent(),
						point,
						-4.0,
						1.0,
						25.0
					)
				if headshot and Settings.data.gameplay.get("headshot_sound", true):
					if is_player:
						AudioBank.play_2d("headshot", -4.5)
				if is_player and Settings.data.gameplay.get("hitmarker", true):
					AudioBank.play_2d("hitmarker", -12.0)
			return
		# Impacto en geometria.
		Fx.impact(get_parent(), point, normal, _surface_kind(collider))
		if pierced >= penetration or penetration <= 0:
			return
		# Intenta perforar: busca el punto de salida.
		var exit_query := PhysicsRayQueryParameters3D.new()
		exit_query.from = point + dir * 0.06
		exit_query.to = point + dir * (0.18 + penetration * 0.22)
		exit_query.collision_mask = 1
		exit_query.exclude = excl
		var exit_hit := space.intersect_ray(exit_query)
		if exit_hit.is_empty():
			return
		travelled += from.distance_to(point)
		pierced += 1
		remaining -= from.distance_to(point) + 0.3
		from = exit_hit.position + dir * 0.08
		remaining -= 0.2
		if pierced == 1:
			AudioBank.play_at("ricochet", get_parent(), point, -10.0, 1.0, 18.0)


func _surface_kind(collider: Object) -> String:
	if collider is StaticBody3D:
		var body := collider as StaticBody3D
		if body.has_meta("surface"):
			return String(body.get_meta("surface"))
	return "concrete"


func hitbox_at(point: Vector3) -> String:
	var feet := global_position.y
	var local := point.y - feet
	var h := local / maxf(capsule.height, 0.5)
	if is_zombie:
		h = local / (1.8 * (capsule.height / 1.8))
	if h > 0.83:
		return "head"
	if h > 0.42:
		return "chest"
	return "legs"


func calculate_damage(def: Dictionary, distance: float, hitbox: String, victim: Combatant) -> float:
	var base: float = float(def.get("damage", 20.0))
	var falloff: float = float(def.get("falloff", 25.0))
	var min_mult: float = float(def.get("min_mult", 0.6))
	var over := maxf(0.0, distance - falloff)
	var dist_mult := clampf(pow(0.9, over / maxf(falloff, 1.0)), min_mult, 1.0)
	var dmg := base * dist_mult
	match hitbox:
		"head":
			dmg *= 4.0
			if victim.helmet:
				dmg *= 0.55
		"legs":
			dmg *= 0.75
	# Chaleco.
	if victim.armor > 0.0:
		var pen: float = float(def.get("armor_pen", 0.6))
		var absorbed := (1.0 - pen) * 0.55
		dmg *= 1.0 - absorbed
	return dmg


func take_damage(
	amount: float, attacker: Node, hitbox: String, weapon_id: String, penetrated: bool = false
) -> void:
	if not alive or invulnerable or god_mode:
		return
	if attacker is Combatant:
		var killer := attacker as Combatant
		if killer.team == team and not killer.is_zombie and not is_zombie:
			if not bool(Settings.data.gameplay.get("friendly_fire", false)):
				return
	var dmg := amount
	if armor > 0.0:
		var armor_dmg := dmg * 0.5
		armor = maxf(0.0, armor - armor_dmg)
	health -= dmg
	last_damage_time = _now()
	last_attacker = attacker
	health_changed.emit(self, health, armor)
	damaged.emit(self, dmg, attacker, hitbox, weapon_id)
	if health > 0.0 and _now() - _last_pain_sfx > 0.65:
		_last_pain_sfx = _now()
		var pain_key := "zombie_death" if is_zombie else "pain"
		if weapon_id == "fall":
			pain_key = "fall_pain"
		AudioBank.play_at(
			pain_key, get_parent(), global_position + Vector3(0, 1.2, 0), -5.0, 1.0, 22.0
		)
	if health <= 0.0:
		die(attacker, weapon_id, hitbox == "head", penetrated)


func die(attacker: Node, weapon_id: String, headshot: bool, wallbang: bool = false) -> void:
	if not alive:
		return
	alive = false
	health = 0.0
	armor = 0.0
	helmet = false
	deaths += 1
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 1
	wants_fire = false
	reload_time_left = 0.0
	burst_left = 0
	zoom_level = 0
	if actor_model:
		actor_model.play_death(headshot)
	AudioBank.play_at(
		"death_cry",
		get_parent(),
		global_position + Vector3(0, 1.2, 0),
		-4.0,
		_rng.randf_range(0.9, 1.1),
		30.0
	)
	AudioBank.play_at("body_fall", get_parent(), global_position, -5.0, 1.0, 25.0)
	if attacker is Combatant:
		var killer := attacker as Combatant
		if killer != self:
			killer.kills += 1
			killer.round_kills += 1
			if headshot:
				killer.headshots += 1
				Settings.add_progress("headshots")
			if killer.is_player:
				if weapon_id == "knife":
					Settings.grant_achievement("knife")
				if wallbang:
					Settings.grant_achievement("wallbang")
				Settings.add_progress("kills")
				Settings.add_progress("accuracy_hits")
			if killer.is_player and killer.round_kills >= 5:
				Settings.grant_achievement("ace")
	died.emit(self, attacker, weapon_id, headshot)
	_drop_weapon()


func _drop_weapon() -> void:
	if primary_id == "":
		return
	var game := get_tree().get_first_node_in_group("game")
	if game and String(game.get("mode")) == "deathmatch":
		return
	if game and game.has_method("spawn_pickup"):
		var a: Vector2i = ammo.get(primary_id, Vector2i(0, 0))
		game.call(
			"spawn_pickup", primary_id, global_position + Vector3(0, 0.3, 0), primary_id, a.x, a.y
		)


func respawn(pos: Vector3, health_amount: float = -1.0) -> void:
	alive = true
	frozen = false
	health = max_health if health_amount < 0.0 else minf(health_amount, max_health)
	collision_layer = PLAYER_LAYER
	collision_mask = 1 | PLAYER_LAYER
	global_position = pos + Vector3(0, 0.1, 0)
	velocity = Vector3.ZERO
	wants_fire = false
	trigger_was_down = false
	reload_time_left = 0.0
	if actor_model:
		if is_player:
			actor_model.visible = false
		else:
			actor_model.revive()
			actor_model.visible = true
	if is_player and model_container:
		model_container.visible = false
	_was_grounded = true
	if current_id == "":
		current_id = "knife"
		current_slot = Content.SLOT_KNIFE


func equip_armor(with_helmet: bool = false) -> void:
	armor = MAX_ARMOR_VALUE
	helmet = with_helmet


const MAX_ARMOR_VALUE := 100.0


func blind(duration: float) -> void:
	_flash_blind = maxf(_flash_blind, duration)


func is_blind() -> bool:
	return _flash_blind > 0.0


func blind_factor() -> float:
	return clampf(_flash_blind / 2.0, 0.0, 1.0)


func slow(amount: float, duration: float) -> void:
	_slow_amount = clampf(amount, 0.35, 1.0)
	_slow_timer = duration


# --- Combate cuerpo a cuerpo y granadas ---------------------------------------


func alt_melee_attack() -> void:
	if not alive or frozen or current_slot != Content.SLOT_KNIFE:
		return
	if _now() < next_fire_time:
		return
	_melee_attack(true)


func _melee_attack(heavy: bool = false) -> void:
	if invulnerable and has_meta("dm_spawn_shield"):
		invulnerable = false
		set_meta("dm_spawn_shield", false)
	var def := current_def()
	var rpm := float(def.get("stab_rpm", 60.0) if heavy else def.get("rpm", 120.0))
	next_fire_time = _now() + 60.0 / maxf(rpm, 20.0)
	AudioBank.play_at(
		"knife_swing", get_parent(), global_position, -4.0, _rng.randf_range(0.9, 1.1), 22.0
	)
	if is_player:
		AudioBank.play_2d("knife_swing", -6.0)
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 1.2, 0)
	var forward := get_fire_direction()
	var reach := 1.75 if heavy else 2.05
	for i in 2:
		var dir := forward if i == 0 else (forward + Vector3(0, -0.25, 0)).normalized()
		var query := PhysicsRayQueryParameters3D.new()
		query.from = origin
		query.to = origin + dir * reach
		query.collision_mask = 1 | PLAYER_LAYER
		var excl: Array[RID] = [get_rid()]
		query.exclude = excl
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider = hit.collider
		if collider is Combatant:
			var victim := collider as Combatant
			if victim == self:
				continue
			if victim.team != team or victim.is_hostage:
				var back := victim.global_transform.basis.z.dot(get_fire_direction()) > 0.25
				var dmg := 40.0
				if heavy:
					dmg = (
						float(def.get("stab_back_damage", 180.0))
						if back
						else float(def.get("stab_damage", 65.0))
					)
				else:
					dmg = (
						float(def.get("back_damage", 90.0))
						if back
						else float(def.get("damage", 40.0))
					)
				victim.take_damage(dmg, self, "chest", "knife")
				total_hits += 1
				hit_confirmed.emit(self, victim, dmg, back)
				Fx.blood(get_parent(), hit.position, -dir, 18 if (back or heavy) else 10)
				AudioBank.play_at(
					"knife_stab" if (back or heavy) else "knife_hit",
					get_parent(),
					hit.position,
					0.0,
					1.0,
					25.0
				)
				_on_melee_attacked(true, heavy)
				return
		Fx.impact(get_parent(), hit.position, hit.normal, "concrete")
		AudioBank.play_at("knife_wall", get_parent(), hit.position, -3.0, 1.0, 20.0)
		_on_melee_attacked(true, heavy)
		return
	_on_melee_attacked(false, heavy)


func _throw_grenade() -> void:
	if grenades.is_empty():
		return
	var id: String = grenades[current_grenade]
	var def := Content.get_weapon(id)
	var origin := get_fire_origin()
	var dir := get_fire_direction()
	grenades.remove_at(current_grenade)
	if grenades.is_empty():
		current_slot = Content.SLOT_KNIFE
		current_id = "knife"
	else:
		current_grenade = mini(current_grenade, grenades.size() - 1)
		current_id = grenades[current_grenade]
	next_fire_time = _now() + 0.9
	var game := get_tree().get_first_node_in_group("game")
	if game and game.has_method("spawn_grenade"):
		game.call("spawn_grenade", self, id, origin + dir * 0.4, dir * 17.0 + Vector3(0, 3.0, 0))
	AudioBank.play_at(
		"grenade_throw", get_parent(), origin, -3.0, _rng.randf_range(0.97, 1.03), 25.0
	)
	if is_player:
		AudioBank.play_2d("fire_in_hole", -3.0)
	elif not is_zombie:
		AudioBank.play_at("fire_in_hole", get_parent(), origin, -4.0, 1.0, 32.0)
	_on_grenade_thrown()
	weapon_state_changed.emit(self)


func toggle_silencer() -> void:
	var def := current_def()
	if not bool(def.get("silencer", false)):
		return
	silencer_on = not silencer_on
	next_fire_time = _now() + 0.5
	if is_player:
		AudioBank.weapon_silencer(current_id, silencer_on)
	_on_silencer_toggled(silencer_on)
	weapon_state_changed.emit(self)


func toggle_zoom() -> void:
	var def := current_def()
	var z: float = float(def.get("zoom", 0.0))
	if z <= 0.0 or reload_time_left > 0.0:
		return
	var is_sniper := String(def.get("cls", "")) == "sniper"
	zoom_max = 2 if is_sniper else 1
	zoom_level = (zoom_level + 1) % (zoom_max + 1)
	if is_player:
		AudioBank.play_2d("zoom", -4.0)
	next_fire_time = maxf(next_fire_time, _now() + 0.16)
	weapon_state_changed.emit(self)


func get_fire_origin() -> Vector3:
	if is_player and has_meta("camera"):
		var cam = get_meta("camera")
		if cam and is_instance_valid(cam):
			return cam.global_position
	return global_position + Vector3(0, 1.45 if not crouching else 1.0, 0)


func get_fire_direction() -> Vector3:
	if is_player and has_meta("camera"):
		var cam = get_meta("camera")
		if cam and is_instance_valid(cam):
			return -cam.global_transform.basis.z
	return -global_transform.basis.z


func face_towards(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) < 0.05:
		return
	look_at(flat, Vector3.UP)


func ammo_text() -> String:
	var a := current_ammo()
	if current_slot == Content.SLOT_KNIFE:
		return "--"
	if current_slot == Content.SLOT_GRENADE:
		return "%d" % grenades.size()
	if current_slot == Content.SLOT_C4:
		return "C4"
	if reload_time_left > 0.0:
		return "RECARGANDO"
	return "%d / %d" % [a.x, a.y]


func has_any_primary() -> bool:
	return primary_id != ""


func is_enemy_of(other: Combatant) -> bool:
	if other == null or other == self:
		return false
	if is_zombie or other.is_zombie:
		return is_zombie != other.is_zombie
	return team != other.team
