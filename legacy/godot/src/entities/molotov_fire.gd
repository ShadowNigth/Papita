extends Node3D
## MolotovFire: fuego incendiario dinamico estilo Counter-Strike 2.
##
## Se expande organicamente sobre el suelo respetando paredes y escalones,
## inflige dano progresivo y se apaga al contacto con granadas de humo (CS2).

class_name MolotovFire

const DURATION := 7.0
const TICK_INTERVAL := 0.20
const PATCH_RADIUS := 1.42

var attacker: Combatant = null
var game: Node = null
var elapsed := 0.0

var _tick_accum := 0.0
var _spread_accum := 0.0
var _pending_dirs: Array[Vector3] = []
var _patches: Array[Dictionary] = []
var _exposure: Dictionary = {}
var _light: OmniLight3D
var _loop_player: AudioStreamPlayer3D
var _extinguished := false
var _scorch_mat: StandardMaterial3D


func setup(owner_combatant: Combatant, game_ref: Node) -> void:
	attacker = owner_combatant
	game = game_ref


func _ready() -> void:
	add_to_group("molotov_fire")
	_build_scorch_material()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.52, 0.14)
	_light.light_energy = 3.8
	_light.omni_range = 10.5
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.85, 0.0)
	add_child(_light)

	AudioBank.play_at("glass_break", get_parent(), global_position, 0.0, 1.04, 42.0)
	AudioBank.play_at("molotov_ignite", get_parent(), global_position, 1.5, 1.0, 48.0)
	_start_loop_audio()

	# Parche central inmediato + cola de propagacion en dos anillos concentricos (CS2).
	_spawn_patch(global_position)
	for ring in 2:
		var count := 5 if ring == 0 else 7
		var dist := 1.25 if ring == 0 else 2.55
		var phase := 0.0 if ring == 0 else 0.42
		for i in count:
			var ang := phase + float(i) * (TAU / float(count)) + randf_range(-0.18, 0.18)
			var r := dist * randf_range(0.86, 1.14)
			_pending_dirs.append(Vector3(cos(ang) * r, 0.0, sin(ang) * r))


func _build_scorch_material() -> void:
	_scorch_mat = StandardMaterial3D.new()
	_scorch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_scorch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_scorch_mat.albedo_texture = MaterialLib.radial_texture(1.8, 64)
	_scorch_mat.albedo_color = Color(0.04, 0.03, 0.02, 0.76)
	_scorch_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _start_loop_audio() -> void:
	var stream := AudioBank._load_wav("ambience/burning1.wav", true)
	if stream == null:
		return
	_loop_player = AudioStreamPlayer3D.new()
	_loop_player.bus = "SFX"
	_loop_player.stream = stream
	_loop_player.volume_db = -3.0
	_loop_player.unit_size = 7.5
	_loop_player.max_distance = 36.0
	_loop_player.position = Vector3(0.0, 0.4, 0.0)
	add_child(_loop_player)
	_loop_player.play()


func _process(delta: float) -> void:
	if _extinguished:
		return
	elapsed += delta
	if elapsed >= DURATION:
		_finish_fire(false)
		return

	# Parpadeo organico de luz de fuego.
	if _light:
		var fade := clampf((DURATION - elapsed) / 1.2, 0.0, 1.0)
		_light.light_energy = (3.4 + sin(elapsed * 19.0) * 0.55 + cos(elapsed * 31.0) * 0.3) * fade

	# Propagacion progresiva sobre el suelo (primeros 1.5 s).
	if not _pending_dirs.is_empty():
		_spread_accum += delta
		while _spread_accum >= 0.10 and not _pending_dirs.is_empty():
			_spread_accum -= 0.10
			var offset: Vector3 = _pending_dirs.pop_front()
			_try_spread_to(offset)

	# Dano termico e interaccion con humo cada TICK_INTERVAL.
	_tick_accum += delta
	if _tick_accum >= TICK_INTERVAL:
		_tick_accum -= TICK_INTERVAL
		_check_smoke_overlap()
		if not _extinguished:
			_apply_burn_tick()


func _try_spread_to(offset: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var start := global_position + Vector3(0.0, 0.45, 0.0)
	var target_air := start + offset
	var wall_q := PhysicsRayQueryParameters3D.new()
	wall_q.from = start
	wall_q.to = target_air
	wall_q.collision_mask = 1
	var wall_hit := space.intersect_ray(wall_q)
	if not wall_hit.is_empty():
		target_air = start.lerp(wall_hit.position, 0.72)
	var floor_q := PhysicsRayQueryParameters3D.new()
	floor_q.from = target_air + Vector3(0.0, 0.7, 0.0)
	floor_q.to = target_air - Vector3(0.0, 2.6, 0.0)
	floor_q.collision_mask = 1
	var floor_hit := space.intersect_ray(floor_q)
	if floor_hit.is_empty():
		return
	var ground_pos: Vector3 = floor_hit.position
	if (
		game
		and game.has_method("is_point_smoked")
		and bool(game.call("is_point_smoked", ground_pos))
	):
		return
	for p in _patches:
		var existing_pos: Vector3 = p["pos"]
		if existing_pos.distance_to(ground_pos) < 0.75:
			return
	_spawn_patch(ground_pos)


func _spawn_patch(world_pos: Vector3) -> void:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = world_pos

	# Mancha de hollin sobre el piso.
	var scorch := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(1.85, 1.85)
	scorch.mesh = sq
	scorch.rotation_degrees = Vector3(-90.0, randf_range(0.0, 360.0), 0.0)
	scorch.position = Vector3(0.0, 0.025, 0.0)
	scorch.material_override = _scorch_mat
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(scorch)

	# Llamas vivas ascendentes.
	var flames := CPUParticles3D.new()
	flames.amount = 14
	flames.lifetime = 0.62
	flames.preprocess = 0.2
	flames.local_coords = false
	var fquad := QuadMesh.new()
	fquad.size = Vector2(0.85, 1.05)
	flames.mesh = fquad
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.vertex_color_use_as_albedo = true
	fmat.albedo_texture = MaterialLib.radial_texture(2.1, 64)
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flames.material_override = fmat
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.52
	flames.direction = Vector3.UP
	flames.spread = 22.0
	flames.initial_velocity_min = 0.85
	flames.initial_velocity_max = 2.15
	flames.gravity = Vector3(0.0, 2.2, 0.0)
	flames.scale_amount_min = 0.55
	flames.scale_amount_max = 1.15
	var grad := Gradient.new()
	grad.colors = PackedColorArray(
		[
			Color(1.0, 0.86, 0.32, 0.92),
			Color(1.0, 0.42, 0.08, 0.78),
			Color(0.45, 0.08, 0.02, 0.0),
		]
	)
	grad.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	flames.color_ramp = grad
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.position = Vector3(0.0, 0.18, 0.0)
	holder.add_child(flames)

	_patches.append({"pos": world_pos, "node": holder, "flames": flames})


func _apply_burn_tick() -> void:
	if game == null:
		return
	var combatants: Array = game.get("all_combatants")
	for c_any in combatants:
		if not (c_any is Combatant):
			continue
		var c := c_any as Combatant
		if not is_instance_valid(c) or not c.alive or c.is_hostage:
			continue
		var feet := c.global_position
		var in_fire := false
		for p in _patches:
			var ppos: Vector3 = p["pos"]
			var flat_d := Vector2(feet.x - ppos.x, feet.z - ppos.z).length()
			var dy := feet.y - ppos.y
			if flat_d <= PATCH_RADIUS and dy >= -0.65 and dy <= 1.85:
				in_fire = true
				break
		var key := String(c.name)
		if not in_fire:
			if _exposure.has(key):
				_exposure[key] = maxf(0.0, float(_exposure[key]) - TICK_INTERVAL * 1.5)
			continue
		var exp_t := float(_exposure.get(key, 0.0)) + TICK_INTERVAL
		_exposure[key] = exp_t
		# Dano progresivo como en CS2 (~32 DPS inicial subiendo hasta ~54 DPS).
		var dmg := clampf(6.4 + exp_t * 2.2, 6.4, 10.8)
		c.slow(0.82, 0.32)
		c.take_damage(dmg, attacker if is_instance_valid(attacker) else self, "legs", "molotov")


func _check_smoke_overlap() -> void:
	if game == null or not game.has_method("get_active_smokes"):
		return
	var smokes: Array = game.call("get_active_smokes")
	for s_any in smokes:
		var s: Dictionary = s_any
		extinguish_near(s.get("pos", Vector3.ZERO), float(s.get("radius", 4.5)))
		if _extinguished:
			return


func extinguish_near(smoke_pos: Vector3, smoke_radius: float) -> bool:
	if _extinguished:
		return true
	var reach := smoke_radius + 1.15
	if global_position.distance_to(smoke_pos) <= reach * 0.88:
		Fx.steam_puff(get_parent(), global_position + Vector3(0.0, 0.35, 0.0), 3.0)
		_finish_fire(true)
		return true
	var removed_any := false
	for i in range(_patches.size() - 1, -1, -1):
		var ppos: Vector3 = _patches[i]["pos"]
		if ppos.distance_to(smoke_pos) <= reach:
			var holder: Node3D = _patches[i]["node"]
			if is_instance_valid(holder):
				holder.queue_free()
			_patches.remove_at(i)
			removed_any = true
	if removed_any:
		Fx.steam_puff(get_parent(), smoke_pos + Vector3(0.0, 0.25, 0.0), 2.2)
	if _patches.size() <= 1:
		_finish_fire(true)
		return true
	return removed_any


func _finish_fire(immediate: bool) -> void:
	if _extinguished:
		return
	_extinguished = true
	_pending_dirs.clear()
	if _loop_player and is_instance_valid(_loop_player):
		_loop_player.stop()
	for p in _patches:
		var fl: CPUParticles3D = p["flames"]
		if is_instance_valid(fl):
			fl.emitting = false
	if immediate:
		queue_free()
		return
	var tw := create_tween()
	if _light:
		tw.tween_property(_light, "light_energy", 0.0, 0.55)
	else:
		tw.tween_interval(0.55)
	tw.tween_callback(queue_free)
