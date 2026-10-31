extends RigidBody3D
## PhysicsProp: objeto fisico reactivo estilo Counter-Strike 2.
##
## Reacciona con impulsos reales en el punto de impacto ante balas, cuchillazos,
## explosiones de HE/C4 y empuje del jugador, con destruccion opcional en cajas.

class_name PhysicsProp

const PROP_LAYER := 8

var prop_kind := "crate"
var surface_type := "wood"
var hp := 55.0
var destructible := true
var _clank_cd := 0.0


func setup_prop(kind: String, pos: Vector3, yaw_deg: float = 0.0) -> void:
	prop_kind = kind
	position = pos
	rotation_degrees = Vector3(0.0, yaw_deg, 0.0)


func _ready() -> void:
	add_to_group("physics_prop")
	collision_layer = PROP_LAYER
	# Colisiona con mundo (1), granadas (2), jugadores que lo empujan (4) y otros props (8).
	collision_mask = 1 | 2 | 4 | PROP_LAYER
	can_sleep = true
	sleeping = true
	contact_monitor = true
	max_contacts_reported = 2
	var pmat := PhysicsMaterial.new()
	pmat.friction = 0.78
	pmat.bounce = 0.22
	physics_material_override = pmat
	_build_geometry()
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _clank_cd > 0.0:
		_clank_cd = maxf(0.0, _clank_cd - delta)
	if global_position.y < -65.0:
		queue_free()


func _build_geometry() -> void:
	match prop_kind:
		"barrel":
			surface_type = "metal"
			destructible = false
			mass = 16.0
			linear_damp = 0.45
			angular_damp = 0.65
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.31
			cyl.height = 0.92
			cs.shape = cyl
			cs.position = Vector3(0.0, 0.46, 0.0)
			add_child(cs)
			var mi := MeshInstance3D.new()
			var cmesh := CylinderMesh.new()
			cmesh.top_radius = 0.31
			cmesh.bottom_radius = 0.31
			cmesh.height = 0.92
			cmesh.radial_segments = 14
			mi.mesh = cmesh
			mi.position = Vector3(0.0, 0.46, 0.0)
			mi.material_override = MaterialLib.simple(Color(0.22, 0.34, 0.44), 0.42, 0.78)
			add_child(mi)
		"canister":
			surface_type = "metal"
			destructible = false
			mass = 6.5
			linear_damp = 0.35
			angular_damp = 0.5
			var cs2 := CollisionShape3D.new()
			var cyl2 := CylinderShape3D.new()
			cyl2.radius = 0.16
			cyl2.height = 0.56
			cs2.shape = cyl2
			cs2.position = Vector3(0.0, 0.28, 0.0)
			add_child(cs2)
			var mi2 := MeshInstance3D.new()
			var cmesh2 := CylinderMesh.new()
			cmesh2.top_radius = 0.15
			cmesh2.bottom_radius = 0.16
			cmesh2.height = 0.56
			cmesh2.radial_segments = 12
			mi2.mesh = cmesh2
			mi2.position = Vector3(0.0, 0.28, 0.0)
			mi2.material_override = MaterialLib.simple(Color(0.62, 0.2, 0.16), 0.38, 0.72)
			add_child(mi2)
		"pallet":
			surface_type = "wood"
			destructible = true
			hp = 45.0
			mass = 8.0
			linear_damp = 0.55
			angular_damp = 0.75
			var cs3 := CollisionShape3D.new()
			var box3 := BoxShape3D.new()
			box3.size = Vector3(0.95, 0.14, 0.78)
			cs3.shape = box3
			cs3.position = Vector3(0.0, 0.07, 0.0)
			add_child(cs3)
			var mi3 := MeshInstance3D.new()
			var bmesh3 := BoxMesh.new()
			bmesh3.size = box3.size
			mi3.mesh = bmesh3
			mi3.position = Vector3(0.0, 0.07, 0.0)
			mi3.material_override = MaterialLib.surface("wood", "desert", 1)
			add_child(mi3)
		_:
			# Caja fisica liviana estilo CS2 (se vuelca al dispararle y se astilla).
			surface_type = "wood"
			destructible = true
			hp = 52.0
			mass = 9.5
			linear_damp = 0.45
			angular_damp = 0.6
			var sz := Vector3(0.58, 0.58, 0.58)
			var cs4 := CollisionShape3D.new()
			var box4 := BoxShape3D.new()
			box4.size = sz
			cs4.shape = box4
			cs4.position = Vector3(0.0, sz.y * 0.5, 0.0)
			add_child(cs4)
			var mi4 := MeshInstance3D.new()
			var bmesh4 := BoxMesh.new()
			bmesh4.size = sz
			mi4.mesh = bmesh4
			mi4.position = Vector3(0.0, sz.y * 0.5, 0.0)
			mi4.material_override = MaterialLib.surface("crate", "desert", 0)
			add_child(mi4)


func _on_body_entered(_body: Node) -> void:
	if _clank_cd > 0.0:
		return
	var spd := linear_velocity.length()
	if spd < 1.35:
		return
	_clank_cd = 0.18
	var sfx := "prop_metal" if surface_type == "metal" else "prop_wood"
	AudioBank.play_at(
		sfx,
		get_parent(),
		global_position,
		clampf(-16.0 + spd * 1.4, -16.0, -3.0),
		randf_range(0.92, 1.08),
		24.0
	)


func apply_bullet_hit(point: Vector3, dir: Vector3, damage: float) -> void:
	sleeping = false
	var strength := clampf(damage * 0.18, 2.2, 14.0)
	var offset := point - (global_position + Vector3(0.0, 0.28, 0.0))
	apply_impulse(dir.normalized() * strength + Vector3(0.0, strength * 0.14, 0.0), offset)
	if _clank_cd <= 0.0:
		_clank_cd = 0.08
		var sfx := "prop_metal" if surface_type == "metal" else "prop_wood"
		AudioBank.play_at(sfx, get_parent(), point, -5.0, randf_range(0.94, 1.1), 24.0)
	if destructible:
		hp -= damage
		if hp <= 0.0:
			Fx.debris_burst(get_parent(), global_position + Vector3(0.0, 0.3, 0.0), surface_type, 7)
			queue_free()


func apply_blast(center: Vector3, radius: float, max_impulse: float = 26.0) -> void:
	var center_self := global_position + Vector3(0.0, 0.3, 0.0)
	var dist := center_self.distance_to(center)
	if dist > radius or dist < 0.001:
		return
	sleeping = false
	var falloff := clampf(1.0 - dist / radius, 0.12, 1.0)
	var dir := (center_self - center).normalized()
	var imp := (dir + Vector3(0.0, 0.65, 0.0)).normalized() * (max_impulse * falloff)
	apply_central_impulse(imp)
	apply_torque_impulse(
		Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)) * falloff
	)
	if destructible and falloff > 0.48:
		hp -= 75.0 * falloff
		if hp <= 0.0:
			Fx.debris_burst(get_parent(), center_self, surface_type, 8)
			queue_free()
