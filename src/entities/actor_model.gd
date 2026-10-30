extends Node3D
## ActorModel: soldado / zombie procedural con animacion simple y arma en mano.

class_name ActorModel

var team := 1
var is_zombie := false
var zombie_color := Color(0.4, 0.5, 0.35)
var body_scale := 1.0
var alive := true

var _body: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _weapon_holder: Node3D
var _weapon_model: Node3D
var _label: Label3D
var _phase := 0.0
var _crouch := false
var _death_tween: Tween


func setup(
	team_id: int, zombie: bool = false, z_color: Color = Color(0.4, 0.5, 0.35), s: float = 1.0
) -> void:
	for child in get_children():
		child.queue_free()
	team = team_id
	is_zombie = zombie
	zombie_color = z_color
	body_scale = s
	scale = Vector3.ONE * s
	_build()


func _mat(color: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	return MaterialLib.simple(color, rough, metal)


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var uniform := Color(0.18, 0.23, 0.3)
	var skin := Color(0.72, 0.56, 0.42)
	var vest_col := Color(0.12, 0.15, 0.19)
	if team == Content.TEAM_T:
		uniform = Color(0.36, 0.3, 0.2)
		vest_col = Color(0.24, 0.2, 0.14)
	if is_zombie:
		uniform = Color(0.2, 0.2, 0.18)
		vest_col = Color(0.16, 0.16, 0.14)
		skin = zombie_color
	var uniform_mat := _mat(uniform)
	var vest_mat := _mat(vest_col, 0.7)
	var skin_mat := _mat(skin, 0.85)
	var boot_mat := _mat(Color(0.08, 0.08, 0.08), 0.8)
	var helmet_mat := _mat(
		Color(0.15, 0.18, 0.16) if team == Content.TEAM_CT else Color(0.3, 0.26, 0.18), 0.5, 0.2
	)

	# Piernas con pivote en la cadera.
	_leg_l = Node3D.new()
	_leg_l.position = Vector3(-0.115, 0.92, 0)
	_body.add_child(_leg_l)
	_part(_leg_l, Vector3(0.17, 0.82, 0.2), Vector3(0, -0.42, 0), uniform_mat)
	_part(_leg_l, Vector3(0.18, 0.12, 0.28), Vector3(0, -0.84, 0.04), boot_mat)
	_leg_r = Node3D.new()
	_leg_r.position = Vector3(0.115, 0.92, 0)
	_body.add_child(_leg_r)
	_part(_leg_r, Vector3(0.17, 0.82, 0.2), Vector3(0, -0.42, 0), uniform_mat)
	_part(_leg_r, Vector3(0.18, 0.12, 0.28), Vector3(0, -0.84, 0.04), boot_mat)

	# Torso.
	_torso = Node3D.new()
	_torso.position = Vector3(0, 1.28, 0)
	_body.add_child(_torso)
	_part(_torso, Vector3(0.46, 0.58, 0.26), Vector3.ZERO, uniform_mat)
	_part(_torso, Vector3(0.48, 0.42, 0.3), Vector3(0, 0.02, 0), vest_mat)
	_part(_torso, Vector3(0.2, 0.12, 0.32), Vector3(0, 0.16, 0), vest_mat)
	_part(
		_torso,
		Vector3(0.36, 0.08, 0.28),
		Vector3(0, 0.3, 0),
		_mat(Color(0.55, 0.5, 0.4) if not is_zombie else Color(0.3, 0.32, 0.24))
	)
	if is_zombie:
		# Manchas y ropa rota.
		_part(
			_torso,
			Vector3(0.16, 0.2, 0.31),
			Vector3(0.1, -0.1, 0),
			_mat(Color(0.3, 0.08, 0.06), 0.9)
		)
		_part(
			_leg_l, Vector3(0.18, 0.3, 0.22), Vector3(0.0, -0.55, 0), _mat(Color(0.26, 0.22, 0.18))
		)

	# Cabeza y cuello.
	_head = Node3D.new()
	_head.position = Vector3(0, 1.72, 0)
	_body.add_child(_head)
	_part(_head, Vector3(0.16, 0.1, 0.16), Vector3(0, -0.1, 0), skin_mat)
	_part(_head, Vector3(0.26, 0.28, 0.26), Vector3(0, 0.04, 0), skin_mat)
	_part(_head, Vector3(0.28, 0.09, 0.28), Vector3(0, 0.2, 0), helmet_mat)
	_part(_head, Vector3(0.29, 0.06, 0.12), Vector3(0, 0.14, -0.1), helmet_mat)
	# Ojos brillantes en zombies.
	if is_zombie:
		_part(
			_head,
			Vector3(0.05, 0.03, 0.02),
			Vector3(-0.07, 0.05, -0.14),
			MaterialLib.emissive(Color(1.0, 0.75, 0.2), 3.0)
		)
		_part(
			_head,
			Vector3(0.05, 0.03, 0.02),
			Vector3(0.07, 0.05, -0.14),
			MaterialLib.emissive(Color(1.0, 0.75, 0.2), 3.0)
		)
	else:
		_part(
			_head,
			Vector3(0.05, 0.02, 0.02),
			Vector3(-0.06, 0.05, -0.14),
			_mat(Color(0.05, 0.05, 0.05))
		)
		_part(
			_head,
			Vector3(0.05, 0.02, 0.02),
			Vector3(0.06, 0.05, -0.14),
			_mat(Color(0.05, 0.05, 0.05))
		)
		_part(
			_head, Vector3(0.12, 0.06, 0.02), Vector3(0, -0.04, -0.14), _mat(Color(0.5, 0.35, 0.3))
		)

	# Brazos con pivote en el hombro.
	_arm_l = Node3D.new()
	_arm_l.position = Vector3(-0.3, 1.5, 0)
	_body.add_child(_arm_l)
	_part(_arm_l, Vector3(0.14, 0.52, 0.16), Vector3(0, -0.26, 0), uniform_mat)
	_part(_arm_l, Vector3(0.13, 0.12, 0.15), Vector3(0, -0.56, 0), skin_mat)
	_arm_r = Node3D.new()
	_arm_r.position = Vector3(0.3, 1.5, 0)
	_body.add_child(_arm_r)
	_part(_arm_r, Vector3(0.14, 0.52, 0.16), Vector3(0, -0.26, 0), uniform_mat)
	_part(_arm_r, Vector3(0.13, 0.12, 0.15), Vector3(0, -0.56, 0), skin_mat)

	_weapon_holder = Node3D.new()
	_weapon_holder.position = Vector3(-0.18, 1.32, -0.26)
	_weapon_holder.rotation_degrees = Vector3(0, 180, 0)
	_body.add_child(_weapon_holder)

	_label = Label3D.new()
	_label.text = ""
	_label.font_size = 44
	_label.pixel_size = 0.004
	_label.position = Vector3(0, 2.1, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.outline_size = 8
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.modulate = Color(0.6, 0.85, 1.0) if team == Content.TEAM_CT else Color(1.0, 0.75, 0.4)
	add_child(_label)

	if is_zombie:
		# Postura encorvada, brazos al frente.
		_torso.rotation_degrees.x = 8.0
		_arm_l.rotation_degrees.x = -75.0
		_arm_r.rotation_degrees.x = -80.0
		_weapon_holder.visible = false


func set_name_tag(text: String) -> void:
	if is_zombie:
		_label.visible = false
		return
	_label.text = text


func equip(def: Dictionary) -> void:
	if _weapon_holder == null or is_zombie:
		return
	if _weapon_model and is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
	_weapon_model = WeaponModel.build(def)
	_weapon_holder.add_child(_weapon_model)
	_weapon_holder.visible = true
	_arm_l.rotation_degrees = Vector3(-55, 0, 18)
	_arm_r.rotation_degrees = Vector3(-65, 0, -12)


func hide_weapon() -> void:
	if _weapon_model and is_instance_valid(_weapon_model):
		_weapon_model.queue_free()
	_weapon_model = null


func animate(velocity: Vector3, grounded: bool, pitch: float, crouch: bool, delta: float) -> void:
	if not alive:
		return
	if is_zombie:
		_animate_zombie(velocity, delta)
		return
	var planar := Vector2(velocity.x, velocity.z).length()
	var speed_f := clampf(planar / 5.0, 0.0, 1.6)
	_phase += delta * (4.0 + planar * 1.9)
	var swing := sin(_phase) * 0.55 * speed_f
	if not grounded:
		swing = 0.25
	_leg_l.rotation_degrees.x = swing
	_leg_r.rotation_degrees.x = -swing
	_crouch = crouch
	var target_y := 1.28
	if crouch:
		target_y = 0.95
		_leg_l.rotation_degrees.x = 0.5
		_leg_r.rotation_degrees.x = -0.15
	_torso.position.y = lerpf(_torso.position.y, target_y, delta * 10.0)
	_head.position.y = _torso.position.y + 0.44
	_head.rotation_degrees.x = clampf(pitch, -38.0, 32.0) * 0.35
	_body.position.y = absf(sin(_phase * 2.0)) * 0.012 * speed_f
	_arm_l.rotation_degrees.x = -55.0 + sin(_phase) * 2.0 * speed_f
	_arm_r.rotation_degrees.x = -65.0 + sin(_phase + 1.0) * 2.0 * speed_f


func _animate_zombie(velocity: Vector3, delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	_phase += delta * (3.0 + planar * 2.0)
	var s := sin(_phase) * 0.7
	_leg_l.rotation_degrees.x = s
	_leg_r.rotation_degrees.x = -s
	_arm_l.rotation_degrees.x = -70.0 + sin(_phase * 1.3) * 14.0
	_arm_r.rotation_degrees.x = -78.0 + cos(_phase * 1.1) * 12.0
	_torso.rotation_degrees.z = sin(_phase * 0.7) * 5.0
	_head.rotation_degrees.z = sin(_phase * 0.9) * 8.0
	_body.position.y = absf(sin(_phase)) * 0.03


func play_death() -> void:
	alive = false
	hide_weapon()
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.set_parallel(true)
	_death_tween.tween_property(_body, "rotation_degrees:x", 88.0, 0.55).set_ease(Tween.EASE_OUT)
	_death_tween.tween_property(_body, "position:y", 0.22, 0.55)
	_death_tween.tween_property(_head, "rotation_degrees:z", 32.0, 0.55)
	_death_tween.tween_property(_arm_l, "rotation_degrees:z", 38.0, 0.6)
	_death_tween.tween_property(_arm_r, "rotation_degrees:z", -42.0, 0.6)
	if _label:
		_label.visible = false


func revive() -> void:
	alive = true
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	_body.rotation_degrees = Vector3.ZERO
	_body.position = Vector3.ZERO
	_head.rotation_degrees = Vector3.ZERO
	_arm_l.rotation_degrees = Vector3.ZERO
	_arm_r.rotation_degrees = Vector3.ZERO
	if _label:
		_label.visible = true
