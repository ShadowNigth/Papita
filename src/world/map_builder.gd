extends Node3D
## MapBuilder: convierte un layout de `Maps` en un escenario 3D jugable.
##
## Crea geometria con materiales PBR procedurales, cielo dinamico, sol,
## niebla volumetrica, luces, props, particulas ambientales, marcadores de
## objetivos y hornea la grilla de navegacion de los bots.

class_name MapBuilder

const SKY_SHADER := preload("res://shaders/sky.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")

const SKY_PRESETS := {
	"day":
	{
		"top": Color(0.20, 0.42, 0.68),
		"horizon": Color(0.78, 0.76, 0.66),
		"ground": Color(0.24, 0.2, 0.15),
		"sun": Color(1.0, 0.96, 0.88),
		"sun_energy": 2.4,
		"sun_rot": Vector3(-48, 38, 0),
		"ambient": 1.0,
		"stars": 0.0,
		"clouds": 0.5,
		"haze": 0.4,
		"vol_fog": 0.006,
		"fog_color": Color(0.7, 0.68, 0.6),
	},
	"dusk":
	{
		"top": Color(0.14, 0.2, 0.38),
		"horizon": Color(0.92, 0.52, 0.28),
		"ground": Color(0.16, 0.12, 0.1),
		"sun": Color(1.0, 0.62, 0.36),
		"sun_energy": 1.5,
		"sun_rot": Vector3(-12, 62, 0),
		"ambient": 0.55,
		"stars": 0.12,
		"clouds": 0.6,
		"haze": 0.55,
		"vol_fog": 0.012,
		"fog_color": Color(0.55, 0.4, 0.32),
	},
	"overcast":
	{
		"top": Color(0.35, 0.38, 0.42),
		"horizon": Color(0.62, 0.63, 0.62),
		"ground": Color(0.2, 0.2, 0.2),
		"sun": Color(0.82, 0.86, 0.92),
		"sun_energy": 0.9,
		"sun_rot": Vector3(-58, 24, 0),
		"ambient": 0.85,
		"stars": 0.0,
		"clouds": 0.85,
		"haze": 0.25,
		"vol_fog": 0.009,
		"fog_color": Color(0.6, 0.62, 0.63),
	},
	"night":
	{
		"top": Color(0.02, 0.04, 0.09),
		"horizon": Color(0.08, 0.11, 0.18),
		"ground": Color(0.03, 0.03, 0.04),
		"sun": Color(0.5, 0.65, 1.0),
		"sun_energy": 0.42,
		"sun_rot": Vector3(-38, 22, 0),
		"ambient": 0.22,
		"stars": 1.0,
		"clouds": 0.25,
		"haze": 0.2,
		"vol_fog": 0.016,
		"fog_color": Color(0.08, 0.1, 0.14),
	},
}

var data: Dictionary = {}
var nav: NavGraph
var environment: Environment
var sun: DirectionalLight3D

var _materials: Dictionary = {}
var _shadow_lights := 0
var _root_geo: Node3D
var _root_props: Node3D
var _root_fx: Node3D


func setup(layout: Dictionary) -> void:
	data = layout
	name = "Map_" + String(layout.get("id", "map"))
	_root_geo = Node3D.new()
	_root_geo.name = "Geometry"
	add_child(_root_geo)
	_root_props = Node3D.new()
	_root_props.name = "Props"
	add_child(_root_props)
	_root_fx = Node3D.new()
	_root_fx.name = "Fx"
	add_child(_root_fx)
	_build_environment()
	_build_ground()
	_build_blocks()
	_build_props()
	_build_water()
	_build_objective_markers()
	_build_particles()


func _theme() -> String:
	return String(data.get("theme", "desert"))


func _mat(kind: String, variant: int = 0) -> Material:
	var key := "%s|%d" % [kind, variant]
	if not _materials.has(key):
		var wet := 0.0
		if kind == "cobble" or kind == "asphalt":
			wet = 0.15
		_materials[key] = MaterialLib.surface(kind, _theme(), variant, wet)
	return _materials[key]


# --- Ambiente -----------------------------------------------------------------


func _build_environment() -> void:
	var preset: Dictionary = SKY_PRESETS.get(String(data.get("sky", "day")), SKY_PRESETS.day)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("top_color", preset.top)
	sky_mat.set_shader_parameter("horizon_color", preset.horizon)
	sky_mat.set_shader_parameter("ground_color", preset.ground)
	sky_mat.set_shader_parameter("sun_color", preset.sun)
	sky_mat.set_shader_parameter("sun_energy", 6.0 if data.get("sky", "day") != "night" else 2.2)
	sky_mat.set_shader_parameter("sun_size", 0.03 if data.get("sky", "day") != "night" else 0.02)
	sky_mat.set_shader_parameter("star_strength", preset.stars)
	sky_mat.set_shader_parameter("cloud_strength", preset.clouds)
	sky_mat.set_shader_parameter("haze", preset.haze)
	sky_mat.set_shader_parameter(
		"cloud_color",
		Color(0.95, 0.94, 0.9) if data.get("sky", "day") != "night" else Color(0.2, 0.24, 0.32)
	)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = preset.ambient
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = true
	env.ssao_radius = 1.7
	env.ssao_intensity = 2.6
	env.ssao_power = 1.4
	env.ssil_enabled = true
	env.ssil_radius = 3.0
	env.ssr_enabled = true
	env.ssr_max_steps = 56
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = preset.vol_fog
	env.volumetric_fog_albedo = preset.fog_color
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_gi_inject = 0.4
	env.volumetric_fog_ambient_inject = 0.35
	env.fog_enabled = false
	env.set_meta("volumetric_density", preset.vol_fog)
	env.set_meta("volumetric_color", preset.fog_color)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.08
	environment = env
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world_env.add_to_group("world_environment")
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = preset.sun
	sun.light_energy = preset.sun_energy
	sun.rotation_degrees = preset.sun_rot
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_fade_start = 0.8
	sun.shadow_bias = 0.03
	sun.light_volumetric_fog_energy = 1.4
	add_child(sun)
	# Ajusta el sol del shader del cielo con la direccion real de la luz.
	var dir := -Basis.from_euler(sun.rotation).z
	sky_mat.set_shader_parameter("sun_dir", dir)
	Settings.apply_environment(env)


func _build_ground() -> void:
	var half := data.bounds.size.x * 0.5 + 20.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(half * 2.0, 1.0, half * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(String(data.get("ground_mat", "sand")), 0)
	mi.position = Vector3(
		data.bounds.position.x + data.bounds.size.x * 0.5,
		-0.5,
		data.bounds.position.y + data.bounds.size.y * 0.5
	)
	_root_geo.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	shape.shape = box
	body.add_child(shape)
	body.position = mi.position
	_root_geo.add_child(body)


func _build_blocks() -> void:
	for b in data.blocks:
		var p: Vector3 = b.p
		var s: Vector3 = b.s
		if s.x <= 0.0 or s.y <= 0.0 or s.z <= 0.0:
			continue
		var mesh := BoxMesh.new()
		mesh.size = s
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mat(String(b.mat), int(absf(p.x + p.z) * 0.37) % 3)
		mi.position = p
		mi.rotation_degrees = b.get("rot", Vector3.ZERO)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_root_geo.add_child(mi)
		var body := StaticBody3D.new()
		body.position = p
		body.rotation_degrees = mi.rotation_degrees
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = s
		shape.shape = box
		body.add_child(shape)
		_root_geo.add_child(body)


func _build_props() -> void:
	for p in data.props:
		var node := _make_prop(String(p.type), float(p.s), int(p.yaw))
		if node:
			node.position = p.p
			_root_props.add_child(node)
	for l in data.lights:
		_add_light(l.p, l.color, l.energy, l.range, l.shadow)
	# Maquinas de perks y caja misteriosa (modo zombie).
	for perk in data.get("perks", []):
		_spawn_perk_machine(String(perk.id), perk.pos)
	if data.get("mystery", Vector3.ZERO) != Vector3.ZERO:
		_spawn_mystery_box(data.mystery)
	if data.get("ammo_crate", Vector3.ZERO) != Vector3.ZERO:
		_spawn_ammo_crate(data.ammo_crate)


func _make_prop(type: String, scale_f: float, yaw: int) -> Node3D:
	var node: Node3D = null
	match type:
		"crate":
			node = PropLib.crate(_theme(), 1.0)
		"barrels":
			node = PropLib.barrels(_theme(), 3)
		"sandbags":
			node = PropLib.sandbags(_theme(), 2.6)
		"car":
			node = PropLib.car(_theme())
		"truck":
			node = PropLib.truck(_theme())
		"tree":
			node = PropLib.tree(_theme(), 5.2)
		"palm":
			node = PropLib.palm(_theme(), 6.0)
		"street_lamp":
			node = PropLib.street_lamp(
				_theme(), data.get("sky", "day") == "night" or data.get("sky", "day") == "dusk"
			)
		"hanging_lamp":
			node = PropLib.hanging_lamp(_theme())
		"table":
			node = PropLib.table(_theme())
		"chair":
			node = PropLib.chair(_theme())
		"cabinet":
			node = PropLib.cabinet(_theme())
		"desk":
			node = PropLib.desk(_theme())
		"computer":
			node = PropLib.computer(_theme())
		"container":
			node = PropLib.container(_theme())
		"train":
			node = PropLib.train_wagon(_theme())
		"rubble":
			node = PropLib.rubble(_theme(), int(absf(scale_f * 100.0)) + yaw)
		"pallet":
			node = PropLib.pallet(_theme())
		"market_stall":
			node = PropLib.market_stall(_theme())
		"fountain":
			node = PropLib.fountain(_theme())
		"barricade":
			node = PropLib.barricade(_theme())
	if node:
		node.scale = Vector3.ONE * scale_f
		node.rotation_degrees.y = float(yaw)
	return node


func _add_light(p: Vector3, color: Color, energy: float, range_f: float, shadow: bool) -> void:
	var light := OmniLight3D.new()
	light.position = p
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_f
	light.omni_attenuation = 1.4
	light.shadow_enabled = shadow and _shadow_lights < 8
	if light.shadow_enabled:
		_shadow_lights += 1
	light.light_specular = 0.4
	light.light_volumetric_fog_energy = 0.8
	_root_props.add_child(light)


func _build_water() -> void:
	for w in data.get("water", []):
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(w.s.x, w.s.z)
		mesh.subdivide_width = 24
		mesh.subdivide_depth = 24
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := ShaderMaterial.new()
		mat.shader = WATER_SHADER
		mi.material_override = mat
		mi.position = w.p
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root_geo.add_child(mi)


func _build_objective_markers() -> void:
	for site in data.get("sites", []):
		var root := Node3D.new()
		root.position = site.center
		var disc := CylinderMesh.new()
		disc.top_radius = 3.2
		disc.bottom_radius = 3.2
		disc.height = 0.03
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.15, 0.1, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.6, 0.06, 0.03)
		mat.emission_energy_multiplier = 0.9
		mi.material_override = mat
		root.add_child(mi)
		var label := Label3D.new()
		label.text = String(site.name)
		label.font_size = 220
		label.pixel_size = 0.01
		label.position = Vector3(0, 2.2, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(1.0, 0.35, 0.25)
		label.outline_modulate = Color(0, 0, 0, 0.8)
		label.outline_size = 18
		label.no_depth_test = false
		root.add_child(label)
		_root_fx.add_child(root)
	if not data.get("rescue", []).is_empty():
		var first: Vector3 = data.rescue[0]
		var label := Label3D.new()
		label.text = "RESCATE"
		label.font_size = 160
		label.pixel_size = 0.012
		label.position = first + Vector3(0, 2.0, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.4, 1.0, 0.6)
		label.outline_size = 16
		_root_fx.add_child(label)


func _spawn_perk_machine(id: String, p: Vector3) -> void:
	var info: Dictionary = Content.PERKS.get(id, {})
	var root := Node3D.new()
	root.name = "Perk_" + id
	root.position = p
	var body := BoxMesh.new()
	body.size = Vector3(1.0, 2.0, 0.8)
	var mi := MeshInstance3D.new()
	mi.mesh = body
	mi.position = Vector3(0, 1.0, 0)
	mi.material_override = MaterialLib.simple(Color(0.16, 0.16, 0.18), 0.4, 0.6)
	root.add_child(mi)
	var panel := BoxMesh.new()
	panel.size = Vector3(0.78, 0.9, 0.06)
	var pmi := MeshInstance3D.new()
	pmi.mesh = panel
	pmi.position = Vector3(0, 1.35, 0.43)
	var glow: Color = info.get("color", Color(0.4, 0.8, 0.4))
	pmi.material_override = MaterialLib.emissive(glow, 2.4)
	root.add_child(pmi)
	var label := Label3D.new()
	label.text = String(info.get("name", id)).to_upper()
	label.font_size = 64
	label.pixel_size = 0.006
	label.position = Vector3(0, 2.15, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = glow
	label.outline_size = 10
	root.add_child(label)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.4, 0.8)
	light.light_color = glow
	light.light_energy = 1.4
	light.omni_range = 5.0
	root.add_child(light)
	var body_col := StaticBody3D.new()
	body_col.collision_layer = 1
	body_col.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 2.0, 0.8)
	shape.shape = box
	shape.position = Vector3(0, 1.0, 0)
	body_col.add_child(shape)
	root.add_child(body_col)
	root.add_to_group("perk_machine")
	root.set_meta("perk_id", id)
	_root_props.add_child(root)


func _spawn_mystery_box(p: Vector3) -> void:
	var root := Node3D.new()
	root.name = "MysteryBox"
	root.position = p
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 1.0, 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = Vector3(0, 0.5, 0)
	mi.material_override = MaterialLib.surface("crate", _theme(), 1)
	root.add_child(mi)
	var label := Label3D.new()
	label.text = "?"
	label.font_size = 220
	label.pixel_size = 0.008
	label.position = Vector3(0, 1.9, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.85, 0.25)
	label.outline_size = 22
	root.add_child(label)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.6, 0)
	light.light_color = Color(1.0, 0.75, 0.3)
	light.light_energy = 2.4
	light.omni_range = 7.0
	root.add_child(light)
	root.add_to_group("mystery_box")
	_root_props.add_child(root)


func _spawn_ammo_crate(p: Vector3) -> void:
	var root := Node3D.new()
	root.name = "AmmoCrate"
	root.position = p
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.7, 0.8)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = Vector3(0, 0.35, 0)
	mi.material_override = MaterialLib.simple(Color(0.24, 0.3, 0.18), 0.6, 0.2)
	root.add_child(mi)
	var stripe := BoxMesh.new()
	stripe.size = Vector3(1.02, 0.16, 0.82)
	var smi := MeshInstance3D.new()
	smi.mesh = stripe
	smi.position = Vector3(0, 0.5, 0)
	smi.material_override = MaterialLib.emissive(Color(0.45, 0.9, 0.4), 1.2)
	root.add_child(smi)
	var label := Label3D.new()
	label.text = "MUNICION"
	label.font_size = 64
	label.pixel_size = 0.005
	label.position = Vector3(0, 1.1, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.5, 1.0, 0.5)
	label.outline_size = 10
	root.add_child(label)
	root.add_to_group("ammo_crate")
	_root_props.add_child(root)


func _build_particles() -> void:
	var theme := _theme()
	var kinds: Array = []
	match theme:
		"desert", "desert_night":
			kinds.append({"kind": "dust", "color": Color(0.8, 0.7, 0.5), "amount": 90})
		"jungle":
			kinds.append({"kind": "firefly", "color": Color(0.7, 1.0, 0.4), "amount": 70})
		"railyard":
			kinds.append({"kind": "snow", "color": Color(0.95, 0.97, 1.0), "amount": 260})
		"mansion":
			kinds.append({"kind": "dust", "color": Color(0.6, 0.5, 0.4), "amount": 60})
	if data.get("sky", "day") == "night" and theme != "railyard":
		kinds.append({"kind": "firefly", "color": Color(0.9, 0.6, 0.3), "amount": 40})
	for cfg in kinds:
		_spawn_particles(cfg.kind, cfg.color, cfg.amount)


func _spawn_particles(kind: String, color: Color, amount: int) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 9.0
	particles.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 40, 120))
	particles.position = Vector3(0, 4, 0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(45, 4, 45)
	process.direction = Vector3(0, 1, 0) if kind == "snow" else Vector3(0.2, 0.1, 0.1)
	process.spread = 180.0
	process.gravity = Vector3(0, -0.25, 0) if kind == "snow" else Vector3(0, 0.02, 0)
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.4
	process.scale_min = 0.02 if kind != "snow" else 0.03
	process.scale_max = 0.08 if kind != "snow" else 0.06
	process.color = color
	process.emission_shape_offset = Vector3(0, 3, 0)
	if kind == "snow":
		process.initial_velocity_max = 1.2
		process.gravity = Vector3(0.2, -1.2, 0.1)
		process.turbulence_enabled = true
		process.turbulence_noise_strength = 0.6
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = (
		BaseMaterial3D.BLEND_MODE_ADD if kind == "firefly" else BaseMaterial3D.BLEND_MODE_MIX
	)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = MaterialLib.radial_texture(2.2, 48)
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6 if kind == "firefly" else 0.2
	quad.material = mat
	particles.draw_pass_1 = quad
	particles.process_material = process
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root_fx.add_child(particles)


# --- Navegacion ----------------------------------------------------------------


func bake_navigation() -> NavGraph:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bounds: Rect2 = data.bounds.grow(-2.5)
	nav = NavGraph.new()
	nav.setup(bounds, 0.8)
	var space := get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.62, 1.7, 0.62)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = 1
	params.collide_with_bodies = true
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = 1
	ray.collide_with_bodies = true
	var blocker := BoxShape3D.new()
	var origin_y := 9.0
	for cz in nav.rows:
		for cx in nav.cols:
			var wx := bounds.position.x + (cx + 0.5) * nav.cell
			var wz := bounds.position.y + (cz + 0.5) * nav.cell
			ray.from = Vector3(wx, origin_y, wz)
			ray.to = Vector3(wx, -3.0, wz)
			var hit := space.intersect_ray(ray)
			var tries := 0
			# Ignora techos altos: busca el piso real debajo de ellos.
			while not hit.is_empty() and hit.position.y > 2.9 and tries < 3:
				tries += 1
				ray.from = Vector3(wx, hit.position.y - 0.12, wz)
				hit = space.intersect_ray(ray)
			var h := 0.0
			var blocked := true
			if not hit.is_empty():
				h = hit.position.y
				params.transform = Transform3D(Basis(), Vector3(wx, h + 0.9, wz))
				var overlaps := space.intersect_shape(params, 1)
				blocked = not overlaps.is_empty()
				# Evita celdas sobre techos o superficies inalcanzables.
				if h > 3.2:
					blocked = true
			nav.set_cell(cx, cz, h, blocked)
	nav.finish()
	print("[MapBuilder] navegacion horneada: %dx%d celdas" % [nav.cols, nav.rows])
	return nav


func get_spawn(team: int, index: int = 0) -> Vector3:
	var arr: Array = (
		data.get("spawns_ct", []) if team == Content.TEAM_CT else data.get("spawns_t", [])
	)
	if arr.is_empty():
		return Vector3(0, 1.0, 0)
	return arr[index % arr.size()]


func get_site_positions() -> Array:
	var out: Array = []
	for s in data.get("sites", []):
		out.append(s.center)
	return out


func get_site_center(which: String) -> Vector3:
	for s in data.get("sites", []):
		if String(s.name) == which:
			return s.center
	return Vector3.ZERO
