extends RigidBody3D
## Granada fisica (HE, flash, humo y Molotov estilo CS2) con rebotes y detonacion.

class_name Grenade

var grenade_id := "hegrenade"
var attacker: Combatant
var game: Node
var _fuse := 2.6
var _exploded := false
var _beep := 0.0
var _pending_floor_shatter := false
var _shatter_pos := Vector3.ZERO


func setup(id: String, owner_combatant: Combatant, game_ref: Node) -> void:
	grenade_id = id
	attacker = owner_combatant
	game = game_ref


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | PhysicsProp.PROP_LAYER
	mass = 0.45 if grenade_id == "molotov" else 0.4
	gravity_scale = 1.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.09
	shape.shape = sphere
	add_child(shape)
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.28 if grenade_id == "molotov" else 0.45
	mat.friction = 0.72
	physics_material_override = mat

	if grenade_id == "molotov":
		var m_def := Content.get_weapon("molotov")
		var mol_node := WeaponModel.build(m_def, true)
		mol_node.scale = Vector3.ONE * 1.15
		add_child(mol_node)
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.56, 0.16)
		glow.light_energy = 1.6
		glow.omni_range = 4.2
		glow.shadow_enabled = false
		add_child(glow)
		_fuse = 2.15
	else:
		var g_mdl := MdlLoader.build_world_weapon(grenade_id, true)
		if g_mdl != null:
			g_mdl.scale = Vector3.ONE * 1.15
			add_child(g_mdl)
		else:
			var mi := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.09
			mesh.height = 0.18
			mesh.radial_segments = 10
			mesh.rings = 5
			mi.mesh = mesh
			var color := Color(0.25, 0.32, 0.18)
			if grenade_id == "flashbang":
				color = Color(0.55, 0.55, 0.52)
			elif grenade_id == "smokegrenade":
				color = Color(0.35, 0.38, 0.35)
			mi.material_override = MaterialLib.simple(color, 0.5, 0.4)
			add_child(mi)
		_fuse = 2.1 + randf_range(0.0, 0.35)

	body_entered.connect(_on_body_entered)
	AudioBank.play_at("grenade_throw", self, global_position, -2.0, randf_range(0.95, 1.05), 30.0)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _exploded or grenade_id != "molotov":
		return
	for i in state.get_contact_count():
		var n := state.get_contact_local_normal(i)
		# Como en CS2: rebota en muros verticales pero estalla al tocar suelo/rampa.
		if n.y >= 0.46:
			_pending_floor_shatter = true
			_shatter_pos = state.get_contact_collider_position(i)
			break


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	if _pending_floor_shatter:
		_detonate_molotov(false)
		return
	_fuse -= delta
	if _fuse <= 0.0:
		if grenade_id == "molotov":
			_detonate_molotov(true)
		else:
			_explode()
		return
	if grenade_id == "hegrenade" and _fuse < 1.4:
		_beep -= delta
		if _beep <= 0.0:
			_beep = 0.45
			AudioBank.play_at("beep", self, global_position, -18.0, 1.6, 12.0)
	if global_position.y < -75.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if _exploded:
		return
	if body is PhysicsProp:
		(body as PhysicsProp).sleeping = false
	var speed := linear_velocity.length()
	if speed > 1.0:
		var bkey := "grenade_bounce"
		if grenade_id == "hegrenade":
			bkey = "he_bounce"
		elif grenade_id == "molotov":
			bkey = "glass_hit"
		AudioBank.play_at(
			bkey,
			self,
			global_position,
			clampf(-16.0 + speed, -18.0, -3.0),
			randf_range(0.95, 1.08),
			24.0
		)


func _detonate_molotov(airburst: bool) -> void:
	if _exploded:
		return
	_exploded = true
	var pos := (
		_shatter_pos
		if (_pending_floor_shatter and _shatter_pos != Vector3.ZERO)
		else global_position
	)
	if airburst:
		# En CS2 si supera ~2.1s en el aire estalla sin propagar fuego en el suelo.
		Fx.debris_burst(get_parent(), pos, "glass", 5)
		AudioBank.play_at("molotov_ignite", get_parent(), pos, 0.0, 1.15, 38.0)
		queue_free()
		return
	if game and game.has_method("is_point_smoked") and bool(game.call("is_point_smoked", pos)):
		Fx.debris_burst(get_parent(), pos, "glass", 4)
		Fx.steam_puff(get_parent(), pos + Vector3(0.0, 0.2, 0.0), 2.8)
		queue_free()
		return
	if game and game.has_method("spawn_molotov_fire"):
		game.call("spawn_molotov_fire", pos, attacker)
	queue_free()


func _explode() -> void:
	_exploded = true
	var pos := global_position
	match grenade_id:
		"hegrenade":
			Fx.explosion(get_parent(), pos, true)
			if game and game.has_method("explode"):
				game.call("explode", pos, 7.5, 98.0, attacker, "hegrenade")
		"flashbang":
			Fx.flash(get_parent(), pos)
			AudioBank.play_at("flashbang", get_parent(), pos, 4.0, 1.0, 70.0)
			if game and game.has_method("flash_at"):
				game.call("flash_at", pos, attacker)
		"smokegrenade":
			Fx.smoke_cloud(get_parent(), pos, 4.2)
			AudioBank.play_at("smoke", get_parent(), pos, 0.0, 1.0, 45.0)
			if game and game.has_method("add_smoke"):
				game.call("add_smoke", pos, 4.5, 14.0)
	queue_free()
