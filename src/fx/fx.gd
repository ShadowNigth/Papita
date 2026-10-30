extends RefCounted
## Fx: efectos de impacto, trazadoras, sangre, explosiones y humo.
##
## Todo se construye con particulas y mallas livianas creadas en runtime,
## sin assets externos, y se autodestruye al terminar.

class_name Fx

static var _spark_tex: ImageTexture
static var _soft_tex: ImageTexture
static var _tracer_mat: StandardMaterial3D
static var _blood_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D
static var _fire_mat: StandardMaterial3D
static var _hole_mat: StandardMaterial3D


static func _ensure_assets() -> void:
	if _spark_tex != null:
		return
	_spark_tex = MaterialLib.spark_texture(32)
	_soft_tex = MaterialLib.radial_texture(2.0, 96)
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tracer_mat.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
	_tracer_mat.albedo_texture = _spark_tex
	_tracer_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_tracer_mat.no_depth_test = false
	_blood_mat = StandardMaterial3D.new()
	_blood_mat.albedo_color = Color(0.32, 0.02, 0.02, 0.95)
	_blood_mat.roughness = 0.4
	_blood_mat.emission_enabled = true
	_blood_mat.emission = Color(0.15, 0.0, 0.0)
	_blood_mat.emission_energy_multiplier = 0.4
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.albedo_texture = _soft_tex
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_fire_mat = StandardMaterial3D.new()
	_fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_fire_mat.vertex_color_use_as_albedo = true
	_fire_mat.albedo_texture = _soft_tex
	_fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_hole_mat = StandardMaterial3D.new()
	_hole_mat.albedo_texture = MaterialLib.radial_texture(3.2, 32)
	_hole_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hole_mat.albedo_color = Color(0.05, 0.04, 0.03, 0.9)
	_hole_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hole_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


static func _particles(
	parent: Node3D, count: int, lifetime: float, tex: Texture2D
) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = count
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = false
	p.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	p.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


static func tracer(parent: Node3D, from: Vector3, to: Vector3) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	_ensure_assets()
	var dist := from.distance_to(to)
	if dist < 0.4:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.018, dist)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.2, 0.2, 1.0), 0.06)
	tw.tween_callback(mi.queue_free)


static func impact(
	parent: Node3D, pos: Vector3, normal: Vector3, kind: String = "concrete"
) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	_ensure_assets()
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var col := Color(1.0, 0.8, 0.45)
	if kind == "metal" or kind == "rust":
		col = Color(1.0, 0.9, 0.55)
	elif kind == "wood":
		col = Color(0.8, 0.55, 0.3)
	elif kind == "sand" or kind == "dirt":
		col = Color(0.75, 0.65, 0.45)
	var p := _particles(root, 10, 0.45, _spark_tex)
	p.direction = normal
	p.spread = 55.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.06
	p.color = col
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.06
	p.emitting = true
	if kind == "concrete" or kind == "stone" or kind == "plaster" or kind == "metal":
		var dust := _particles(root, 6, 0.7, _soft_tex)
		dust.direction = normal
		dust.spread = 35.0
		dust.initial_velocity_min = 0.4
		dust.initial_velocity_max = 1.4
		dust.gravity = Vector3(0, -0.4, 0)
		dust.scale_amount_min = 0.12
		dust.scale_amount_max = 0.3
		dust.color = Color(0.7, 0.66, 0.58, 0.35)
		dust.material_override = _smoke_mat
		dust.emitting = true
	if kind != "metal":
		var hole := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.14, 0.14)
		hole.mesh = quad
		hole.material_override = _hole_mat
		root.add_child(hole)
		hole.global_position = pos + normal * 0.01
		if normal.length() > 0.01:
			hole.look_at(pos + normal, Vector3.UP)
	AudioBank.play_at("wall_hit", root, Vector3.ZERO, -6.0, randf_range(0.9, 1.15), 30.0)
	var timer := root.get_tree().create_timer(2.2)
	timer.timeout.connect(root.queue_free)


static func blood(parent: Node3D, pos: Vector3, dir: Vector3, amount: int = 14) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	_ensure_assets()
	if Settings.data.gameplay.get("blood", 1.0) <= 0.0:
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var p := _particles(root, amount, 0.6, _soft_tex)
	p.direction = dir
	p.spread = 35.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -14.0, 0)
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.09
	p.color = Color(0.45, 0.02, 0.02, 1.0)
	p.material_override = _blood_mat
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.emitting = true
	var timer := root.get_tree().create_timer(1.6)
	timer.timeout.connect(root.queue_free)


static func muzzle(parent: Node3D, pos: Vector3, dir: Vector3) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	_ensure_assets()
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var sprite := Sprite3D.new()
	sprite.texture = _spark_tex
	sprite.pixel_size = 0.002
	sprite.modulate = Color(1.0, 0.8, 0.45, 1.0)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.scale = Vector3.ONE * randf_range(0.7, 1.1)
	root.add_child(sprite)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 3.0
	light.omni_range = 6.0
	light.shadow_enabled = false
	root.add_child(light)
	var tw := root.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.09)
	tw.tween_callback(root.queue_free)


static func shell_eject(parent: Node3D, pos: Vector3) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.018, 0.05)
	mi.mesh = mesh
	mi.material_override = MaterialLib.simple(Color(0.65, 0.52, 0.2), 0.35, 0.8)
	parent.add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween()
	var target := pos + Vector3(randf_range(-0.8, 0.8), -1.2, randf_range(-0.8, 0.8))
	tw.tween_property(mi, "global_position", target, 0.45)
	tw.tween_callback(mi.queue_free)


static func explosion(parent: Node3D, pos: Vector3, big: bool = true) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	_ensure_assets()
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var fire := _particles(root, 40 if big else 18, 0.7, _soft_tex)
	fire.direction = Vector3.UP
	fire.spread = 180.0
	fire.initial_velocity_min = 3.0
	fire.initial_velocity_max = 12.0
	fire.gravity = Vector3(0, -4.0, 0)
	fire.scale_amount_min = 0.3
	fire.scale_amount_max = 1.1
	fire.color = Color(1.0, 0.55, 0.15, 1.0)
	fire.material_override = _fire_mat
	fire.emitting = true
	var smoke := _particles(root, 22, 3.2, _soft_tex)
	smoke.direction = Vector3.UP
	smoke.spread = 90.0
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 3.0
	smoke.gravity = Vector3(0, 0.35, 0)
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.4
	smoke.color = Color(0.18, 0.17, 0.16, 0.6)
	smoke.material_override = _smoke_mat
	smoke.emitting = true
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 14.0 if big else 7.0
	light.omni_range = 22.0 if big else 12.0
	root.add_child(light)
	var tw := root.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_callback(root.queue_free)
	AudioBank.play_at("explosion", root, Vector3.ZERO, 4.0, randf_range(0.92, 1.05), 160.0)


static func smoke_cloud(parent: Node3D, pos: Vector3, radius: float = 4.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	_ensure_assets()
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	for i in 3:
		var p := _particles(root, 22, 5.5 + i, _soft_tex)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = radius * 0.6
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 1.0
		p.gravity = Vector3(0, 0.12, 0)
		p.scale_amount_min = radius * 0.7
		p.scale_amount_max = radius * 1.5
		p.color = Color(0.72, 0.73, 0.72, 0.35)
		p.material_override = _smoke_mat
		p.emitting = true
	var timer := root.get_tree().create_timer(7.5)
	timer.timeout.connect(root.queue_free)


static func flash(parent: Node3D, pos: Vector3) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	_ensure_assets()
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var sprite := Sprite3D.new()
	sprite.texture = _soft_tex
	sprite.pixel_size = 0.01
	sprite.modulate = Color(1, 1, 1, 1)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = true
	root.add_child(sprite)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 1, 1)
	light.light_energy = 18.0
	light.omni_range = 25.0
	root.add_child(light)
	var tw := root.create_tween()
	tw.tween_property(sprite, "scale", Vector3.ONE * 6.0, 0.25)
	tw.parallel().tween_property(sprite, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.35)
	tw.tween_callback(root.queue_free)


static func muzzle_flash_mesh(muzzle_pos: Vector3, dir: Vector3) -> MeshInstance3D:
	_ensure_assets()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = _spark_tex
	mat.albedo_color = Color(1.0, 0.8, 0.4)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.global_position = muzzle_pos
	mi.look_at(muzzle_pos + dir, Vector3.UP)
	return mi
