extends RigidBody3D
## Granada fisica (HE, flash y humo) con rebotes y detonacion.

class_name Grenade

var grenade_id := "hegrenade"
var attacker: Combatant
var game: Node
var _fuse := 2.6
var _exploded := false
var _beep := 0.0


func setup(id: String, owner_combatant: Combatant, game_ref: Node) -> void:
	grenade_id = id
	attacker = owner_combatant
	game = game_ref


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	mass = 0.4
	gravity_scale = 1.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.09
	shape.shape = sphere
	add_child(shape)
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.45
	mat.friction = 0.7
	physics_material_override = mat
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
	body_entered.connect(_on_body_entered)
	_fuse = 2.2 + randf_range(0.0, 0.4)
	AudioBank.play_at("grenade_throw", self, global_position, -2.0, randf_range(0.95, 1.05), 30.0)


func _physics_process(delta: float) -> void:
	_fuse -= delta
	if _fuse <= 0.0 and not _exploded:
		_explode()
	if grenade_id == "hegrenade" and _fuse < 1.4:
		_beep -= delta
		if _beep <= 0.0:
			_beep = 0.45
			AudioBank.play_at("beep", self, global_position, -18.0, 1.6, 12.0)
	if global_position.y < -20.0:
		queue_free()


func _on_body_entered(_body: Node) -> void:
	var speed := linear_velocity.length()
	if speed > 1.0:
		AudioBank.play_at(
			"grenade_bounce",
			self,
			global_position,
			clampf(-18.0 + speed, -20.0, -4.0),
			randf_range(0.9, 1.2),
			22.0
		)


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
