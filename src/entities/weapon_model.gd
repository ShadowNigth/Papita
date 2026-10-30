extends RefCounted
## WeaponModel: construye el modelo 3D de cualquier arma con primitivas.
##
## Se usa tanto para el viewmodel en primera persona como para el arma que
## llevan los bots en las manos.

class_name WeaponModel

static var _metal: StandardMaterial3D
static var _dark: StandardMaterial3D
static var _wood: StandardMaterial3D
static var _tan: StandardMaterial3D
static var _glass: StandardMaterial3D


static func _materials() -> void:
	if _metal != null:
		return
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.19, 0.2, 0.22)
	_metal.roughness = 0.42
	_metal.metallic = 0.85
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.06, 0.06, 0.07)
	_dark.roughness = 0.6
	_dark.metallic = 0.4
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = Color(0.42, 0.26, 0.12)
	_wood.roughness = 0.72
	_tan = StandardMaterial3D.new()
	_tan.albedo_color = Color(0.35, 0.3, 0.2)
	_tan.roughness = 0.65
	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.1, 0.15, 0.2)
	_glass.roughness = 0.05
	_glass.metallic = 0.6


static func _box(
	parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func _cyl(
	parent: Node3D,
	radius: float,
	height: float,
	pos: Vector3,
	mat: Material,
	rot: Vector3 = Vector3(90, 0, 0)
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Genera un arma. El eje +Z del nodo apunta en la direccion de disparo.
static func build(def: Dictionary) -> Node3D:
	_materials()
	var root := Node3D.new()
	root.name = "WeaponModel"
	var vm: Dictionary = def.get("vm", {})
	var kind: String = vm.get("kind", "rifle")
	var color: Color = vm.get("color", Color(0.2, 0.2, 0.22))
	var metal := _metal.duplicate()
	metal.albedo_color = color
	var wood: bool = vm.get("wood", false)
	var accent := _wood if wood else _dark
	var length: float = float(vm.get("len", 0.7))
	match kind:
		"pistol":
			_box(root, Vector3(0.045, 0.05, 0.24), Vector3(0, 0, 0.06), metal)
			_box(
				root, Vector3(0.04, 0.11, 0.05), Vector3(0, -0.07, -0.02), accent, Vector3(-8, 0, 0)
			)
			_box(root, Vector3(0.03, 0.03, 0.16), Vector3(0, 0.018, 0.15), _dark)
			_cyl(root, 0.012, 0.05, Vector3(0, 0.015, 0.23), _dark)
			if vm.get("big", false):
				_box(root, Vector3(0.052, 0.06, 0.2), Vector3(0, 0.0, 0.1), metal)
			if vm.get("silencer", false):
				_cyl(root, 0.026, 0.16, Vector3(0, 0.015, 0.3), _dark)
			if vm.get("dual", false):
				var left := build_single_pistol(metal, accent)
				left.position = Vector3(-0.17, -0.02, 0.02)
				left.rotation_degrees.y = 4.0
				root.add_child(left)
		"smg":
			_box(root, Vector3(0.055, 0.09, 0.36), Vector3(0, 0, 0.06), metal)
			_box(
				root, Vector3(0.04, 0.14, 0.05), Vector3(0, -0.1, -0.02), accent, Vector3(-8, 0, 0)
			)
			_box(root, Vector3(0.035, 0.16, 0.06), Vector3(0, -0.11, 0.12), _dark, Vector3(6, 0, 0))
			_cyl(root, 0.014, 0.16, Vector3(0, 0.015, 0.32), _dark)
			_box(root, Vector3(0.03, 0.03, 0.18), Vector3(0, 0.06, 0.02), _dark)
			if not vm.get("bullpup", false):
				_box(root, Vector3(0.035, 0.09, 0.16), Vector3(0, -0.01, -0.16), accent)
			if vm.get("silencer", false):
				_cyl(root, 0.028, 0.14, Vector3(0, 0.015, 0.42), _dark)
			_box(root, Vector3(0.03, 0.06, 0.05), Vector3(0, 0.08, 0.16), _dark)
		"rifle":
			_box(root, Vector3(0.06, 0.1, 0.42), Vector3(0, 0, 0.04), metal)
			_box(root, Vector3(0.045, 0.16, 0.06), Vector3(0, -0.12, 0.1), _dark, Vector3(10, 0, 0))
			_box(
				root, Vector3(0.04, 0.13, 0.05), Vector3(0, -0.09, -0.05), accent, Vector3(-8, 0, 0)
			)
			_cyl(root, 0.014, 0.34, Vector3(0, 0.01, 0.4), _dark)
			_box(root, Vector3(0.035, 0.035, 0.2), Vector3(0, 0.065, 0.06), _dark)
			_box(
				root,
				Vector3(0.06, 0.1, 0.22),
				Vector3(0, -0.01, -0.24),
				metal if not wood else _wood
			)
			_box(root, Vector3(0.025, 0.025, 0.16), Vector3(0, 0.09, 0.18), _dark)
			if vm.get("scope", false):
				_cyl(root, 0.032, 0.22, Vector3(0, 0.12, 0.08), _dark)
				_box(root, Vector3(0.02, 0.05, 0.04), Vector3(0, 0.075, 0.06), _dark)
			if vm.get("silencer", false):
				_cyl(root, 0.03, 0.18, Vector3(0, 0.01, 0.58), _dark)
			if vm.get("bipod", false):
				_box(
					root,
					Vector3(0.02, 0.14, 0.02),
					Vector3(-0.04, -0.08, 0.34),
					_dark,
					Vector3(0, 0, -20)
				)
				_box(
					root,
					Vector3(0.02, 0.14, 0.02),
					Vector3(0.04, -0.08, 0.34),
					_dark,
					Vector3(0, 0, 20)
				)
		"sniper":
			_box(root, Vector3(0.06, 0.1, 0.5), Vector3(0, 0, 0.02), metal if not wood else _wood)
			_box(root, Vector3(0.045, 0.13, 0.05), Vector3(0, -0.1, -0.04), accent)
			_box(
				root,
				Vector3(0.06, 0.14, 0.24),
				Vector3(0, -0.02, -0.3),
				_wood if not wood else metal
			)
			_cyl(root, 0.016, 0.5, Vector3(0, 0.012, 0.48), _dark)
			_cyl(root, 0.034, 0.3, Vector3(0, 0.13, 0.06), _dark)
			_box(root, Vector3(0.022, 0.06, 0.05), Vector3(0, 0.08, 0.02), _dark)
			_box(root, Vector3(0.022, 0.06, 0.05), Vector3(0, 0.08, 0.16), _dark)
			_box(root, Vector3(0.02, 0.1, 0.06), Vector3(0, -0.06, 0.42), _dark, Vector3(20, 0, 0))
		"shotgun":
			_box(root, Vector3(0.065, 0.1, 0.46), Vector3(0, 0, 0.0), metal)
			_cyl(root, 0.018, 0.55, Vector3(0, 0.02, 0.46), _dark)
			_cyl(root, 0.022, 0.4, Vector3(0, -0.045, 0.4), _dark)
			_box(root, Vector3(0.05, 0.09, 0.2), Vector3(0, -0.04, 0.34), _wood if wood else _dark)
			_box(root, Vector3(0.055, 0.12, 0.26), Vector3(0, -0.02, -0.22), _wood)
			_box(root, Vector3(0.03, 0.04, 0.2), Vector3(0, 0.06, 0.0), _dark)
		"lmg":
			_box(root, Vector3(0.12, 0.14, 0.5), Vector3(0, 0, 0.02), metal)
			_cyl(root, 0.02, 0.5, Vector3(0, 0.02, 0.48), _dark)
			_box(root, Vector3(0.06, 0.22, 0.16), Vector3(0, -0.14, 0.04), _dark)
			_box(root, Vector3(0.05, 0.12, 0.24), Vector3(0, -0.02, -0.3), metal)
			_box(
				root,
				Vector3(0.02, 0.16, 0.02),
				Vector3(-0.08, -0.1, 0.42),
				_dark,
				Vector3(0, 0, -18)
			)
			_box(
				root, Vector3(0.02, 0.16, 0.02), Vector3(0.08, -0.1, 0.42), _dark, Vector3(0, 0, 18)
			)
		"knife":
			_box(root, Vector3(0.022, 0.035, 0.13), Vector3(0, 0, 0.02), _dark)
			var blade := _box(root, Vector3(0.035, 0.012, 0.2), Vector3(0, 0.0, 0.17), _metal)
			blade.rotation_degrees.x = 0
			_box(root, Vector3(0.06, 0.012, 0.02), Vector3(0, 0, 0.09), _dark)
		"grenade":
			var sphere := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.055
			sm.height = 0.11
			sphere.mesh = sm
			sphere.material_override = metal
			sphere.position = Vector3(0, 0, 0.06)
			root.add_child(sphere)
			_box(root, Vector3(0.03, 0.02, 0.03), Vector3(0, 0.06, 0.06), _dark)
		"c4":
			_box(root, Vector3(0.22, 0.06, 0.15), Vector3(0, 0, 0.07), _tan)
			_box(
				root,
				Vector3(0.14, 0.012, 0.09),
				Vector3(0, 0.037, 0.07),
				MaterialLib.emissive(Color(0.8, 0.15, 0.1), 1.3)
			)
		_:
			_box(root, Vector3(0.06, 0.1, 0.4), Vector3(0, 0, 0.05), metal)
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	var muzzle_z: float = 0.0
	match kind:
		"pistol":
			muzzle_z = 0.24 if not vm.get("silencer", false) else 0.38
		"smg":
			muzzle_z = 0.32 if not vm.get("silencer", false) else 0.5
		"rifle":
			muzzle_z = 0.58 if not vm.get("silencer", false) else 0.68
		"sniper":
			muzzle_z = 0.74
		"shotgun":
			muzzle_z = 0.74
		"lmg":
			muzzle_z = 0.74
		"knife":
			muzzle_z = 0.18
		_:
			muzzle_z = 0.15
	muzzle.position = Vector3(0, 0.01, muzzle_z)
	root.add_child(muzzle)
	if length > 0:
		root.set_meta("length", length)
	return root


static func build_single_pistol(metal: Material, accent: Material) -> Node3D:
	var root := Node3D.new()
	_box(root, Vector3(0.045, 0.05, 0.24), Vector3(0, 0, 0.06), metal)
	_box(root, Vector3(0.04, 0.11, 0.05), Vector3(0, -0.07, -0.02), accent, Vector3(-8, 0, 0))
	_box(root, Vector3(0.03, 0.03, 0.14), Vector3(0, 0.018, 0.15), _dark)
	return root


static func muzzle_of(node: Node3D) -> Node3D:
	if node == null:
		return null
	return node.get_node_or_null("Muzzle") as Node3D
