extends RefCounted
## PropLib: mobiliario y decoracion 3D construida con primitivas.
##
## Cada funcion devuelve un Node3D listo para colgar del mapa. Los props
## grandes agregan colision para que el mundo se sienta solido.

class_name PropLib


static func _mesh(
	parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(radius: float, height: float, sides: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	return c


static func _add_collision(parent: Node3D, size: Vector3, pos: Vector3, rot_y: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = deg_to_rad(rot_y)
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


static func crate(theme: String, size: float = 1.0, collide: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Crate"
	var wood := MaterialLib.surface("crate", theme)
	var metal := MaterialLib.surface("metal", theme, 1)
	_mesh(root, _box(Vector3(size, size, size)), Vector3(0, size * 0.5, 0), wood)
	var t := size * 0.06
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_mesh(
				root,
				_box(Vector3(t, size * 1.01, t)),
				Vector3(sx * size * 0.47, size * 0.5, sz * size * 0.47),
				metal
			)
	_mesh(root, _box(Vector3(size * 1.01, t, t)), Vector3(0, size * 0.16, 0), metal)
	_mesh(root, _box(Vector3(size * 1.01, t, t)), Vector3(0, size * 0.84, 0), metal)
	if collide:
		_add_collision(root, Vector3(size, size, size), Vector3(0, size * 0.5, 0))
	return root


static func barrels(theme: String, count: int = 3, collide: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Barrels"
	var mat := MaterialLib.surface("rust", theme)
	var top := MaterialLib.surface("metal", theme, 2)
	for i in count:
		var off := Vector3(cos(i * 2.1) * 0.65, 0, sin(i * 1.7) * 0.65)
		var b := Node3D.new()
		b.position = off
		_mesh(b, _cyl(0.32, 0.95, 14), Vector3(0, 0.475, 0), mat)
		_mesh(b, _cyl(0.34, 0.06, 14), Vector3(0, 0.9, 0), top)
		_mesh(b, _cyl(0.34, 0.06, 14), Vector3(0, 0.45, 0), top)
		root.add_child(b)
	if collide:
		_add_collision(root, Vector3(1.6, 0.95, 1.6), Vector3(0, 0.475, 0))
	return root


static func sandbags(theme: String, length: float = 2.4, collide: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Sandbags"
	var mat := MaterialLib.surface("sandbag", theme)
	var rows := 2
	var cols := int(length / 0.62)
	for r in rows:
		for c in cols:
			var off := 0.31 if r % 2 == 1 else 0.0
			var pos := Vector3(-length * 0.5 + 0.31 + c * 0.62 + off, 0.16 + r * 0.28, 0)
			var bag := _mesh(root, _box(Vector3(0.6, 0.28, 0.42)), pos, mat)
			bag.rotation_degrees.y = (c % 2) * 6.0 - 3.0
	if collide:
		_add_collision(root, Vector3(length, 0.62, 0.5), Vector3(0, 0.31, 0))
	return root


static func car(
	theme: String, color: Color = Color(0.5, 0.12, 0.1), collide: bool = true
) -> Node3D:
	var root := Node3D.new()
	root.name = "Car"
	var paint := MaterialLib.simple(color, 0.35, 0.5)
	var glass := MaterialLib.surface("glass", theme)
	var rubber := MaterialLib.simple(Color(0.06, 0.06, 0.07), 0.95)
	var metal := MaterialLib.surface("metal", theme)
	_mesh(root, _box(Vector3(4.3, 0.55, 1.9)), Vector3(0, 0.65, 0), paint)
	_mesh(root, _box(Vector3(2.2, 0.55, 1.75)), Vector3(-0.15, 1.15, 0), paint)
	_mesh(root, _box(Vector3(2.0, 0.4, 1.55)), Vector3(-0.15, 1.2, 0), glass)
	_mesh(root, _box(Vector3(1.0, 0.18, 1.86)), Vector3(0.4, 1.42, 0), paint)
	for wx in [-1.35, 1.35]:
		for wz in [-0.86, 0.86]:
			var wheel := _mesh(root, _cyl(0.34, 0.24, 14), Vector3(wx, 0.36, wz), rubber)
			wheel.rotation_degrees.x = 90.0
	_mesh(root, _box(Vector3(0.16, 0.16, 1.4)), Vector3(2.15, 0.52, 0), metal)
	_mesh(
		root,
		_box(Vector3(0.1, 0.3, 0.5)),
		Vector3(2.22, 0.7, 0.55),
		MaterialLib.emissive(Color(1.0, 0.95, 0.8), 1.0)
	)
	_mesh(
		root,
		_box(Vector3(0.1, 0.3, 0.5)),
		Vector3(2.22, 0.7, -0.55),
		MaterialLib.emissive(Color(1.0, 0.95, 0.8), 1.0)
	)
	if collide:
		_add_collision(root, Vector3(4.3, 1.5, 1.9), Vector3(0, 0.75, 0))
	return root


static func truck(theme: String, collide: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Truck"
	var cabin := MaterialLib.surface("metal", theme, 1)
	var cargo := MaterialLib.surface("canvas", theme)
	var rubber := MaterialLib.simple(Color(0.05, 0.05, 0.05), 0.9)
	_mesh(root, _box(Vector3(2.4, 2.0, 2.4)), Vector3(2.6, 1.3, 0), cabin)
	_mesh(root, _box(Vector3(5.5, 2.4, 2.5)), Vector3(-1.2, 1.6, 0), cargo)
	_mesh(
		root,
		_box(Vector3(2.0, 0.8, 2.2)),
		Vector3(2.6, 2.0, 0),
		MaterialLib.surface("glass", theme)
	)
	for x in [2.9, 0.4, -2.6]:
		for z in [-1.05, 1.05]:
			var w := _mesh(root, _cyl(0.52, 0.35, 16), Vector3(x, 0.55, z), rubber)
			w.rotation_degrees.x = 90.0
	if collide:
		_add_collision(root, Vector3(8.0, 2.6, 2.5), Vector3(0, 1.3, 0))
	return root


static func tree(theme: String, height: float = 5.0, collide: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Tree"
	var bark := MaterialLib.surface("wood", theme, 2)
	var leaf_col := Color(0.25, 0.34, 0.16) if theme != "desert_night" else Color(0.12, 0.17, 0.1)
	var leaves := MaterialLib.simple(leaf_col, 0.9)
	_mesh(root, _cyl(0.22, height * 0.7, 8), Vector3(0, height * 0.35, 0), bark)
	for i in 5:
		var s := height * (0.42 - i * 0.03)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = s
		cone.height = s * 1.3
		cone.radial_segments = 9
		var mi := _mesh(root, cone, Vector3(0, height * 0.55 + i * height * 0.1, 0), leaves)
		mi.rotation_degrees.y = i * 37.0
	if collide:
		_add_collision(root, Vector3(0.6, height, 0.6), Vector3(0, height * 0.5, 0))
	return root


static func palm(theme: String, height: float = 6.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Palm"
	var bark := MaterialLib.surface("wood", theme, 1)
	var leaves := MaterialLib.simple(Color(0.22, 0.3, 0.14), 0.85)
	for i in 6:
		var seg := Node3D.new()
		seg.position = Vector3(sin(i * 0.3) * 0.25, i * height / 6.0, cos(i * 0.3) * 0.25)
		seg.rotation_degrees.z = -3.0
		_mesh(
			seg, _cyl(0.22 - i * 0.015, height / 6.0 + 0.05, 8), Vector3(0, height / 12.0, 0), bark
		)
		root.add_child(seg)
	for i in 7:
		var leaf := Node3D.new()
		leaf.position = Vector3(0, height - 0.1, 0)
		leaf.rotation_degrees.y = i * 51.4
		_mesh(leaf, _box(Vector3(2.6, 0.05, 0.4)), Vector3(1.3, 0, 0), leaves)
		leaf.rotation_degrees.z = -18.0
		root.add_child(leaf)
	return root


static func street_lamp(theme: String, lit: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "StreetLamp"
	var metal := MaterialLib.surface("metal", theme)
	_mesh(root, _cyl(0.09, 4.4, 8), Vector3(0, 2.2, 0), metal)
	_mesh(root, _box(Vector3(1.2, 0.1, 0.1)), Vector3(0.55, 4.4, 0), metal)
	var bulb_mat := MaterialLib.emissive(Color(1.0, 0.85, 0.6), 3.0 if lit else 0.2)
	_mesh(root, _box(Vector3(0.5, 0.18, 0.35)), Vector3(1.05, 4.3, 0), bulb_mat)
	if lit:
		var light := OmniLight3D.new()
		light.position = Vector3(1.05, 4.1, 0)
		light.light_color = Color(1.0, 0.82, 0.58)
		light.light_energy = 2.2
		light.omni_range = 12.0
		light.shadow_enabled = false
		root.add_child(light)
	return root


static func hanging_lamp(theme: String, energy: float = 2.4) -> Node3D:
	var root := Node3D.new()
	root.name = "HangingLamp"
	var metal := MaterialLib.surface("metal", theme)
	_mesh(root, _cyl(0.03, 1.2, 6), Vector3(0, 3.4, 0), metal)
	_mesh(root, _box(Vector3(0.6, 0.12, 0.6)), Vector3(0, 2.85, 0), metal)
	_mesh(
		root,
		_box(Vector3(0.5, 0.06, 0.5)),
		Vector3(0, 2.78, 0),
		MaterialLib.emissive(Color(1.0, 0.9, 0.7), 2.0)
	)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.6, 0)
	light.light_color = Color(1.0, 0.88, 0.7)
	light.light_energy = energy
	light.omni_range = 10.0
	light.shadow_enabled = true
	root.add_child(light)
	return root


static func table(theme: String) -> Node3D:
	var root := Node3D.new()
	var wood := MaterialLib.surface("wood", theme, 1)
	_mesh(root, _box(Vector3(1.8, 0.08, 0.9)), Vector3(0, 0.78, 0), wood)
	for x in [-0.8, 0.8]:
		for z in [-0.35, 0.35]:
			_mesh(root, _box(Vector3(0.08, 0.78, 0.08)), Vector3(x, 0.39, z), wood)
	_add_collision(root, Vector3(1.8, 0.85, 0.9), Vector3(0, 0.42, 0))
	return root


static func chair(theme: String) -> Node3D:
	var root := Node3D.new()
	var wood := MaterialLib.surface("wood", theme, 2)
	_mesh(root, _box(Vector3(0.5, 0.07, 0.5)), Vector3(0, 0.45, 0), wood)
	_mesh(root, _box(Vector3(0.5, 0.6, 0.07)), Vector3(0, 0.75, -0.22), wood)
	for x in [-0.2, 0.2]:
		for z in [-0.2, 0.2]:
			_mesh(root, _box(Vector3(0.06, 0.45, 0.06)), Vector3(x, 0.22, z), wood)
	return root


static func cabinet(theme: String) -> Node3D:
	var root := Node3D.new()
	var metal := MaterialLib.surface("metal", theme, 2)
	var wood := MaterialLib.surface("wood", theme)
	_mesh(root, _box(Vector3(1.4, 1.9, 0.6)), Vector3(0, 0.95, 0), metal)
	_mesh(root, _box(Vector3(1.3, 0.8, 0.05)), Vector3(0, 1.35, 0.32), wood)
	_mesh(
		root,
		_box(Vector3(0.05, 0.18, 0.05)),
		Vector3(0.5, 1.35, 0.36),
		MaterialLib.simple(Color(0.8, 0.8, 0.75), 0.3, 0.8)
	)
	_add_collision(root, Vector3(1.4, 1.9, 0.6), Vector3(0, 0.95, 0))
	return root


static func desk(theme: String) -> Node3D:
	var root := Node3D.new()
	var wood := MaterialLib.surface("wood", theme, 1)
	_mesh(root, _box(Vector3(2.2, 0.1, 1.0)), Vector3(0, 0.75, 0), wood)
	_mesh(root, _box(Vector3(0.6, 0.6, 0.8)), Vector3(0.6, 0.4, 0), wood)
	_add_collision(root, Vector3(2.2, 0.8, 1.0), Vector3(0, 0.4, 0))
	return root


static func computer(theme: String) -> Node3D:
	var root := Node3D.new()
	var dark := MaterialLib.simple(Color(0.1, 0.1, 0.11), 0.6)
	_mesh(root, _box(Vector3(0.55, 0.36, 0.04)), Vector3(0, 1.05, 0), dark)
	_mesh(
		root,
		_box(Vector3(0.5, 0.31, 0.02)),
		Vector3(0, 1.05, 0.03),
		MaterialLib.emissive(Color(0.2, 0.45, 0.65), 1.4)
	)
	_mesh(root, _box(Vector3(0.08, 0.2, 0.08)), Vector3(0, 0.9, 0), dark)
	_mesh(root, _box(Vector3(0.45, 0.03, 0.16)), Vector3(0, 0.78, 0.16), dark)
	return root


static func container(
	theme: String, color: Color = Color(0.35, 0.28, 0.18), collide: bool = true
) -> Node3D:
	var root := Node3D.new()
	root.name = "Container"
	var mat := MaterialLib.simple(color, 0.7, 0.3)
	var rib := MaterialLib.surface("rust", theme)
	_mesh(root, _box(Vector3(6.0, 2.6, 2.5)), Vector3(0, 1.3, 0), mat)
	for i in 10:
		_mesh(root, _box(Vector3(0.06, 2.5, 2.55)), Vector3(-2.7 + i * 0.6, 1.3, 0), rib)
	if collide:
		_add_collision(root, Vector3(6.0, 2.6, 2.5), Vector3(0, 1.3, 0))
	return root


static func train_wagon(theme: String, collide: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "TrainWagon"
	var body := MaterialLib.surface("rust", theme, 1)
	var metal := MaterialLib.surface("metal", theme, 2)
	_mesh(root, _box(Vector3(7.2, 2.9, 2.9)), Vector3(0, 1.75, 0), body)
	_mesh(root, _box(Vector3(7.25, 0.25, 2.95)), Vector3(0, 3.2, 0), metal)
	for x in [-2.4, 0.0, 2.4]:
		_mesh(root, _box(Vector3(0.08, 2.7, 2.96)), Vector3(x, 1.75, 0), metal)
	for x in [-2.8, 2.8]:
		for z in [-1.2, 1.2]:
			var w := _mesh(root, _cyl(0.45, 0.2, 14), Vector3(x, 0.45, z), metal)
			w.rotation_degrees.x = 90.0
	_mesh(root, _box(Vector3(7.4, 0.18, 0.3)), Vector3(0, 0.55, 1.2), metal)
	if collide:
		_add_collision(root, Vector3(7.2, 3.2, 2.9), Vector3(0, 1.6, 0))
	return root


static func rubble(theme: String, seed_val: int = 1) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var mat := MaterialLib.surface("stone", theme, seed_val % 3)
	for i in rng.randi_range(5, 11):
		var s := rng.randf_range(0.15, 0.55)
		var pos := Vector3(rng.randf_range(-1.2, 1.2), s * 0.4, rng.randf_range(-1.2, 1.2))
		var mi := _mesh(root, _box(Vector3(s, s * 0.8, s * 1.2)), pos, mat)
		mi.rotation_degrees = Vector3(
			rng.randf_range(-20, 20), rng.randf_range(0, 90), rng.randf_range(-20, 20)
		)
	return root


static func pallet(theme: String) -> Node3D:
	var root := Node3D.new()
	var wood := MaterialLib.surface("wood", theme, 2)
	for i in 5:
		_mesh(root, _box(Vector3(1.2, 0.05, 0.18)), Vector3(0, 0.15, -0.5 + i * 0.25), wood)
	for z in [-0.45, 0.0, 0.45]:
		_mesh(root, _box(Vector3(1.2, 0.12, 0.12)), Vector3(0, 0.06, z), wood)
	return root


static func market_stall(theme: String) -> Node3D:
	var root := Node3D.new()
	var wood := MaterialLib.surface("wood", theme, 1)
	var cloth := MaterialLib.surface("canvas", theme)
	_mesh(root, _box(Vector3(3.0, 0.1, 1.4)), Vector3(0, 0.9, 0), wood)
	for x in [-1.35, 1.35]:
		for z in [-0.6, 0.6]:
			_mesh(root, _box(Vector3(0.1, 2.4, 0.1)), Vector3(x, 1.2, z), wood)
	_mesh(root, _box(Vector3(3.2, 0.08, 1.7)), Vector3(0, 2.45, 0), cloth)
	_add_collision(root, Vector3(3.0, 1.0, 1.4), Vector3(0, 0.5, 0))
	return root


static func fountain(theme: String) -> Node3D:
	var root := Node3D.new()
	var stone := MaterialLib.surface("stone", theme, 1)
	_mesh(root, _cyl(2.4, 0.7, 20), Vector3(0, 0.35, 0), stone)
	_mesh(
		root,
		_cyl(2.1, 0.25, 20),
		Vector3(0, 0.6, 0),
		MaterialLib.simple(Color(0.15, 0.28, 0.3), 0.15, 0.4)
	)
	_mesh(root, _cyl(0.35, 1.6, 10), Vector3(0, 1.2, 0), stone)
	_mesh(root, _cyl(0.9, 0.18, 16), Vector3(0, 1.9, 0), stone)
	_add_collision(root, Vector3(4.8, 0.7, 4.8), Vector3(0, 0.35, 0))
	return root


static func barricade(theme: String) -> Node3D:
	var root := Node3D.new()
	var wood := MaterialLib.surface("wood", theme, 0)
	var metal := MaterialLib.surface("rust", theme)
	for i in 3:
		var mi := _mesh(root, _box(Vector3(2.2, 0.2, 0.1)), Vector3(0, 0.3 + i * 0.35, 0), wood)
		mi.rotation_degrees.z = (i - 1) * 3.0
	for x in [-0.9, 0.9]:
		_mesh(root, _box(Vector3(0.1, 1.2, 0.12)), Vector3(x, 0.6, 0), metal)
	_add_collision(root, Vector3(2.2, 1.2, 0.2), Vector3(0, 0.6, 0))
	return root


static func zombie_prop(theme: String, variant: int) -> Node3D:
	var root := Node3D.new()
	match variant % 4:
		0:
			root.add_child(crate(theme, 1.1))
		1:
			root.add_child(barrels(theme, 2))
		2:
			root.add_child(barricade(theme))
		_:
			root.add_child(rubble(theme, variant))
	return root


static func blood_decal(parent: Node3D, pos: Vector3, normal: Vector3, size: float = 2.0) -> void:
	var decal := Decal.new()
	decal.size = Vector3(size, 1.0, size)
	decal.albedo_mix = 0.9
	var tex := MaterialLib.radial_texture(1.2, 64)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.3, 0.02, 0.02, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	decal.texture_albedo = tex
	decal.modulate = Color(0.28, 0.02, 0.02, 0.9)
	decal.position = pos
	decal.normal = normal
	parent.add_child(decal)
