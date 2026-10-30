extends RefCounted
## Maps: layouts jugables construidos con un DSL de bloques y props.
##
## Cada mapa define geometria, props, luces, spawns y objetivos. El bloque
## resultante lo consume MapBuilder para crear la escena 3D y la malla de
## navegacion de los bots.

class_name Maps

const WALL := 3.2
const WALL_T := 0.42

# --- Helpers de construccion ---------------------------------------------------


static func _base(
	id: String, theme: String, sky: String, half: float, ground: String
) -> Dictionary:
	return {
		"id": id,
		"theme": theme,
		"sky": sky,
		"bounds": Rect2(-half, -half, half * 2.0, half * 2.0),
		"ground_mat": ground,
		"blocks": [],
		"props": [],
		"lights": [],
		"water": [],
		"spawns_ct": [],
		"spawns_t": [],
		"sites": [],
		"hostages": [],
		"rescue": [],
		"zombie_spawns": [],
		"perks": [],
		"mystery": Vector3.ZERO,
		"ammo_crate": Vector3.ZERO,
		"mode": "",
	}


static func _solid(
	L: Dictionary, p: Vector3, s: Vector3, mat: String, rot: Vector3 = Vector3.ZERO
) -> void:
	L.blocks.append({"p": p, "s": s, "mat": mat, "rot": rot})


static func _wall_x(
	L: Dictionary,
	x0: float,
	x1: float,
	z: float,
	h: float,
	mat: String,
	y0: float = 0.0,
	t: float = WALL_T
) -> void:
	_solid(L, Vector3((x0 + x1) * 0.5, y0 + h * 0.5, z), Vector3(absf(x1 - x0), h, t), mat)


static func _wall_z(
	L: Dictionary,
	z0: float,
	z1: float,
	x: float,
	h: float,
	mat: String,
	y0: float = 0.0,
	t: float = WALL_T
) -> void:
	_solid(L, Vector3(x, y0 + h * 0.5, (z0 + z1) * 0.5), Vector3(t, h, absf(z1 - z0)), mat)


## Muro con huecos (puertas y ventanas).
static func _wall_openings(
	L: Dictionary,
	axis: String,
	fixed: float,
	a0: float,
	a1: float,
	h: float,
	mat: String,
	openings: Array,
	thickness: float = WALL_T
) -> void:
	var start := minf(a0, a1)
	var end := maxf(a0, a1)
	var sorted := openings.duplicate()
	sorted.sort_custom(func(x, y): return float(x.get("off", 0)) < float(y.get("off", 0)))
	var cursor := start
	for op in sorted:
		var w: float = op.get("width", 1.0)
		var off: float = op.get("off", 0.0)
		var y0: float = op.get("y0", 0.0)
		var y1: float = minf(op.get("y1", 2.3), h)
		var o0 := clampf(off - w * 0.5, start + 0.3, end - 0.3)
		var o1 := clampf(off + w * 0.5, o0 + 0.4, end - 0.3)
		if o0 > cursor:
			_add_wall_seg(L, axis, fixed, cursor, o0, 0.0, h, mat, thickness)
		if y0 > 0.01:
			_add_wall_seg(L, axis, fixed, o0, o1, 0.0, y0, mat, thickness)
		if y1 < h - 0.01:
			_add_wall_seg(L, axis, fixed, o0, o1, y1, h, mat, thickness)
		cursor = maxf(cursor, o1)
	if cursor < end:
		_add_wall_seg(L, axis, fixed, cursor, end, 0.0, h, mat, thickness)


static func _add_wall_seg(
	L: Dictionary,
	axis: String,
	fixed: float,
	a0: float,
	a1: float,
	y0: float,
	y1: float,
	mat: String,
	t: float
) -> void:
	if a1 - a0 < 0.08 or y1 - y0 < 0.05:
		return
	if axis == "x":
		_wall_x(L, a0, a1, fixed, y1 - y0, mat, y0, t)
	else:
		_wall_z(L, a0, a1, fixed, y1 - y0, mat, y0, t)


static func _room(
	L: Dictionary, center: Vector2, size: Vector2, h: float, opts: Dictionary = {}
) -> void:
	var mat: String = opts.get("mat", "plaster")
	var floor_mat: String = opts.get("floor", "tile")
	var roof: bool = opts.get("roof", true)
	var doors: Array = opts.get("doors", [])
	var windows: Array = opts.get("windows", [])
	var half := size * 0.5
	var cx := center.x
	var cz := center.y
	# Piso interior.
	_solid(L, Vector3(cx, 0.04, cz), Vector3(size.x, 0.08, size.y), floor_mat)
	var walls := [
		{"side": 0, "axis": "x", "fixed": cz - half.y, "a0": cx - half.x, "a1": cx + half.x},
		{"side": 1, "axis": "x", "fixed": cz + half.y, "a0": cx - half.x, "a1": cx + half.x},
		{"side": 2, "axis": "z", "fixed": cx - half.x, "a0": cz - half.y, "a1": cz + half.y},
		{"side": 3, "axis": "z", "fixed": cx + half.x, "a0": cz - half.y, "a1": cz + half.y},
	]
	for w in walls:
		var ops: Array = []
		var base_coord: float = cx if w.axis == "x" else cz
		for d in doors:
			if int(d.side) != int(w.side):
				continue
			var door_op := {
				"off": base_coord + float(d.get("off", 0.0)),
				"width": float(d.get("width", 1.5)),
				"y0": 0.0,
				"y1": float(d.get("height", 2.35)),
			}
			ops.append(door_op)
		for win in windows:
			if int(win.side) != int(w.side):
				continue
			var win_op := {
				"off": base_coord + float(win.get("off", 0.0)),
				"width": float(win.get("width", 1.4)),
				"y0": float(win.get("sill", 1.0)),
				"y1": float(win.get("top", 2.1)),
			}
			ops.append(win_op)
		_wall_openings(L, w.axis, w.fixed, w.a0, w.a1, h, mat, ops)
	if roof:
		_solid(L, Vector3(cx, h + 0.12, cz), Vector3(size.x + 0.5, 0.24, size.y + 0.5), "roof")
		var light_range := maxf(size.x, size.y) * 0.7
		_light(L, Vector3(cx, h - 0.5, cz), Color(1.0, 0.86, 0.66), 2.4, light_range)


static func _stairs(
	L: Dictionary, center: Vector2, width: float, top: float, dir: int, mat: String
) -> void:
	var steps := maxi(4, int(top / 0.26))
	var step_h := top / steps
	var depth := 0.34
	for i in steps:
		var t := (i + 1) * step_h
		var off := i * depth
		var p := Vector3(center.x, t * 0.5, center.y)
		var s := Vector3(width, t, depth)
		match dir:
			0:
				p.z = center.y + off
			1:
				p.z = center.y - off
			2:
				p.x = center.x + off
			3:
				p.x = center.x - off
		_solid(L, p, s, mat)


static func _platform(
	L: Dictionary, center: Vector2, size: Vector2, top: float, mat: String, legs: bool = true
) -> void:
	_solid(L, Vector3(center.x, top - 0.18, center.y), Vector3(size.x, 0.36, size.y), mat)
	if legs:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_solid(
					L,
					Vector3(
						center.x + sx * (size.x * 0.5 - 0.3),
						top * 0.5,
						center.y + sz * (size.y * 0.5 - 0.3)
					),
					Vector3(0.25, top, 0.25),
					"metal"
				)


static func _prop(
	L: Dictionary, type: String, p: Vector3, s: float = 1.0, yaw: float = 0.0
) -> void:
	L.props.append({"type": type, "p": p, "s": s, "yaw": yaw})


static func _light(
	L: Dictionary, p: Vector3, color: Color, energy: float, rng: float, shadow: bool = true
) -> void:
	L.lights.append({"p": p, "color": color, "energy": energy, "range": rng, "shadow": shadow})


static func _crates(
	L: Dictionary, rng: RandomNumberGenerator, center: Vector2, radius: float, count: int
) -> void:
	for i in count:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.6, radius)
		var p := Vector3(center.x + cos(a) * r, 0.0, center.y + sin(a) * r)
		_prop(L, "crate", p, rng.randf_range(0.85, 1.3), rng.randf_range(0, 90))


static func _sandbag_line(L: Dictionary, from: Vector2, to: Vector2, count: int = 1) -> void:
	var dir := to - from
	for i in count:
		var t := (i + 0.5) / count
		var p2 := from + dir * t
		_prop(L, "sandbags", Vector3(p2.x, 0, p2.y), 1.0, rad_to_deg(dir.angle()) + 90.0)


static func _perimeter(L: Dictionary, half: float, mat: String) -> void:
	var h := 8.0
	_wall_x(L, -half - 2, half + 2, -half, h, mat, 0.0, 1.2)
	_wall_x(L, -half - 2, half + 2, half, h, mat, 0.0, 1.2)
	_wall_z(L, -half, half, -half, h, mat, 0.0, 1.2)
	_wall_z(L, -half, half, half, h, mat, 0.0, 1.2)


static func _spawns(L: Dictionary, center: Vector2, yaw: float, count: int = 5) -> Array:
	var out: Array = []
	for i in count:
		var a := TAU * float(i) / float(count)
		out.append(Vector3(center.x + cos(a) * 1.6, 0.15, center.y + sin(a) * 1.6))
	return out


static func _site(
	L: Dictionary, name: String, center: Vector2, size: Vector2 = Vector2(7, 7)
) -> void:
	L.sites.append({"name": name, "center": Vector3(center.x, 0.1, center.y), "size": size})


# --- Mapas ---------------------------------------------------------------------


static func build(id: String) -> Dictionary:
	match id:
		"de_dust2":
			return _dust2()
		"de_inferno":
			return _inferno()
		"de_aztec":
			return _aztec()
		"de_nuke":
			return _nuke()
		"de_train":
			return _train()
		"cs_office":
			return _office()
		"cs_italy":
			return _italy()
		"de_dust":
			return _dust()
		"zm_mansion":
			return _mansion()
		"zm_dust_night":
			return _dust_night()
	return _dust2()


static func _dust2() -> Dictionary:
	var L := _base("de_dust2", "desert", "day", 40.0, "sand")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1502
	_perimeter(L, 40.0, "plaster")
	# A: plataforma con rampa y cajas.
	_site(L, "A", Vector2(24, -18), Vector2(9, 8))
	_platform(L, Vector2(27, -22), Vector2(6, 5), 1.2, "stone")
	_crates(L, rng, Vector2(23, -16), 3.4, 5)
	_sandbag_line(L, Vector2(19, -22), Vector2(19, -15), 2)
	# Larga A: pasillo con puertas.
	_wall_x(L, 12, 34, -8, WALL, "plaster")
	_wall_x(L, 18, 34, 2, WALL, "plaster")
	_room(
		L,
		Vector2(33, -24),
		Vector2(10, 9),
		WALL,
		{
			"mat": "plaster",
			"floor": "stone",
			"roof": true,
			"doors": [{"side": 2, "off": 1.0, "width": 2.2}],
			"windows": [{"side": 1, "off": -2.0, "width": 2.0, "sill": 1.1}],
		}
	)
	# B: tuneles con techo.
	_site(L, "B", Vector2(-24, -14), Vector2(9, 8))
	_solid(L, Vector3(-24, 2.7, 12), Vector3(9.4, 0.5, 20), "concrete")
	_wall_z(L, 2, 22, -29.5, 2.7, "plaster")
	_wall_z(L, 2, 22, -18.5, 2.7, "plaster")
	_crates(L, rng, Vector2(-24, -12), 3.0, 4)
	_room(
		L,
		Vector2(-33, -25),
		Vector2(10, 9),
		WALL,
		{
			"mat": "plaster",
			"floor": "stone",
			"roof": true,
			"doors": [{"side": 3, "off": -1.0, "width": 2.0}],
		}
	)
	# Medio y puertas dobles.
	_wall_z(L, -6, 0, -4.2, WALL, "plaster")
	_wall_z(L, 2, 10, -4.2, WALL, "plaster")
	_wall_z(L, -6, 0, 4.2, WALL, "plaster")
	_wall_z(L, 2, 10, 4.2, WALL, "plaster")
	_solid(L, Vector3(0, 3.9, -1.0), Vector3(9, 0.4, 1.2), "plaster")
	_solid(L, Vector3(0, 3.9, 1.0), Vector3(9, 0.4, 1.2), "plaster")
	_prop(L, "car", Vector3(7, 0, 5), 1.0, 12.0)
	_prop(L, "crate", Vector3(-8, 0, 7), 1.1, 20.0)
	# Edificios de los flancos.
	_room(
		L,
		Vector2(-14, 18),
		Vector2(14, 12),
		WALL,
		{
			"mat": "plaster",
			"floor": "tile",
			"roof": true,
			"doors": [{"side": 1, "off": 0, "width": 2.4}, {"side": 3, "off": -3.0, "width": 1.8}],
			"windows":
			[
				{"side": 0, "off": 3.0, "width": 2.2, "sill": 1.2},
				{"side": 0, "off": -2.0, "width": 1.4}
			],
		}
	)
	_room(
		L,
		Vector2(16, 20),
		Vector2(12, 10),
		WALL,
		{
			"mat": "plaster",
			"floor": "stone",
			"roof": false,
			"doors": [{"side": 0, "off": 0, "width": 2.2}],
		}
	)
	_room(
		L,
		Vector2(-22, -30),
		Vector2(12, 8),
		WALL,
		{
			"mat": "plaster",
			"floor": "tile",
			"roof": true,
			"doors": [{"side": 1, "off": 0, "width": 2.0}],
		}
	)
	_room(
		L,
		Vector2(26, 8),
		Vector2(10, 12),
		WALL,
		{
			"mat": "plaster",
			"floor": "stone",
			"roof": true,
			"doors": [{"side": 2, "off": 2.0, "width": 2.0}],
		}
	)
	# Spawns.
	L.spawns_ct = _spawns(L, Vector2(0, -34), 0.0, 5)
	L.spawns_t = _spawns(L, Vector2(0, 34), PI, 5)
	_prop(L, "sandbags", Vector3(0, 0, 29), 1.4, 0.0)
	_prop(L, "truck", Vector3(-6, 0, 33), 1.0, 90.0)
	_prop(L, "tree", Vector3(34, 0, 30), 1.1, 0.0)
	_prop(L, "tree", Vector3(-33, 0, 26), 1.0, 0.0)
	_prop(L, "barrels", Vector3(-14, 0, -4), 1.0, 0.0)
	L.mode = "bomb"
	return L


static func _inferno() -> Dictionary:
	var L := _base("de_inferno", "mediterranean", "dusk", 34.0, "cobble")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2201
	_perimeter(L, 34.0, "plaster")
	_site(L, "A", Vector2(14, -12), Vector2(8, 8))
	_site(L, "B", Vector2(-15, -8), Vector2(8, 8))
	_prop(L, "fountain", Vector3(15, 0, -13), 1.0, 0.0)
	_prop(L, "market_stall", Vector3(-16, 0, -2), 1.0, 20.0)
	_prop(L, "market_stall", Vector3(-11, 0, -12), 1.0, -30.0)
	# Callejones y casas.
	_room(
		L,
		Vector2(-20, 12),
		Vector2(14, 12),
		WALL,
		{
			"mat": "plaster",
			"floor": "tile",
			"roof": true,
			"doors": [{"side": 1, "off": 0, "width": 2.0}, {"side": 3, "off": 2.0, "width": 1.6}],
			"windows": [{"side": 0, "off": 0, "width": 2.0, "sill": 1.0}],
		}
	)
	_room(
		L,
		Vector2(20, 14),
		Vector2(13, 12),
		WALL,
		{
			"mat": "brick",
			"floor": "wood",
			"roof": true,
			"doors": [{"side": 1, "off": -2.0, "width": 2.0}],
			"windows": [{"side": 2, "off": 0, "width": 1.6, "sill": 1.1}],
		}
	)
	_room(
		L,
		Vector2(30, -14),
		Vector2(10, 14),
		WALL,
		{
			"mat": "plaster",
			"floor": "stone",
			"roof": true,
			"doors": [{"side": 2, "off": 2.0, "width": 2.0}],
		}
	)
	_room(
		L,
		Vector2(-30, -16),
		Vector2(10, 16),
		WALL,
		{
			"mat": "brick",
			"floor": "tile",
			"roof": true,
			"doors": [{"side": 3, "off": 3.0, "width": 2.0}],
			"windows": [{"side": 1, "off": 0, "width": 2.2, "sill": 1.0}],
		}
	)
	# Balcon y escaleras junto a A.
	_platform(L, Vector2(7, -16), Vector2(6, 4), 2.3, "wood")
	_stairs(L, Vector2(7, -10.5), 2.4, 2.3, 0, "stone")
	_sandbag_line(L, Vector2(10, -6), Vector2(16, -6), 2)
	_wall_x(L, -6, 6, 4, WALL, "plaster")
	_wall_z(L, 4, 20, -6, WALL, "brick")
	_wall_z(L, -22, -4, 2, WALL, "plaster")
	_wall_x(L, -20, -8, 20, WALL, "brick")
	_crates(L, rng, Vector2(0, 10), 5.0, 5)
	_crates(L, rng, Vector2(22, -2), 4.0, 4)
	_prop(L, "car", Vector3(-2, 0, -20), 0.9, 175.0)
	_prop(L, "tree", Vector3(26, 0, 22), 0.9, 0.0)
	L.spawns_ct = _spawns(L, Vector2(-26, -28), 0.0, 5)
	L.spawns_t = _spawns(L, Vector2(26, 28), PI, 5)
	L.mode = "bomb"
	_light(L, Vector3(15, 3.0, -13), Color(1.0, 0.7, 0.4), 2.0, 10.0)
	return L


static func _aztec() -> Dictionary:
	var L := _base("de_aztec", "jungle", "dusk", 44.0, "grass")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3307
	_perimeter(L, 44.0, "stone")
	# Rio central con puente.
	_solid(L, Vector3(0, 0.12, 0), Vector3(86, 0.12, 12), "stone")
	L.water.append({"p": Vector3(0, 0.2, 0), "s": Vector3(86, 0.06, 11)})
	_wall_x(L, -42, -6, 6.2, 1.1, "stone")
	_wall_x(L, 6, 42, 6.2, 1.1, "stone")
	_wall_x(L, -42, -6, -6.2, 1.1, "stone")
	_wall_x(L, 6, 42, -6.2, 1.1, "stone")
	_platform(L, Vector2(0, 0), Vector2(8, 13), 0.55, "stone")
	_solid(L, Vector3(-3.6, 1.9, 0), Vector3(0.4, 3.2, 13), "stone")
	_solid(L, Vector3(3.6, 1.9, 0), Vector3(0.4, 3.2, 13), "stone")
	# Templo A.
	_site(L, "A", Vector2(24, -20), Vector2(10, 9))
	_room(
		L,
		Vector2(25, -21),
		Vector2(14, 12),
		3.6,
		{
			"mat": "stone",
			"floor": "stone",
			"roof": true,
			"doors": [{"side": 1, "off": 0, "width": 3.0}, {"side": 2, "off": 0, "width": 2.4}],
			"windows": [{"side": 0, "off": 0, "width": 2.4, "sill": 1.2}],
		}
	)
	_platform(L, Vector2(25, -21), Vector2(7, 6), 2.6, "stone")
	_stairs(L, Vector2(25, -13.5), 3.0, 2.6, 0, "stone")
	# B junto al templo oeste.
	_site(L, "B", Vector2(-24, -18), Vector2(9, 8))
	_room(
		L,
		Vector2(-26, -22),
		Vector2(14, 10),
		WALL,
		{
			"mat": "stone",
			"floor": "stone",
			"roof": false,
			"doors": [{"side": 1, "off": 2.0, "width": 2.6}],
		}
	)
	_wall_z(L, -30, -10, -16, WALL, "stone")
	# Vegetacion y cobertura.
	for i in 16:
		var a := rng.randf() * TAU
		var r := rng.randf_range(10, 40)
		_prop(L, "tree", Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(0.7, 1.2), 0.0)
	_crates(L, rng, Vector2(0, -8), 4.0, 4)
	_crates(L, rng, Vector2(0, 8), 4.0, 4)
	_prop(L, "rubble", Vector3(-12, 0, 0), 1.0, 20.0)
	_prop(L, "rubble", Vector3(12, 0, 0), 1.0, 60.0)
	L.spawns_ct = _spawns(L, Vector2(-34, -34), 0.0, 5)
	L.spawns_t = _spawns(L, Vector2(34, 34), PI, 5)
	L.mode = "bomb"
	_light(L, Vector3(25, 3.4, -21), Color(1.0, 0.75, 0.45), 2.0, 11.0)
	return L


static func _nuke() -> Dictionary:
	var L := _base("de_nuke", "industrial", "overcast", 30.0, "concrete")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4409
	_perimeter(L, 30.0, "concrete")
	_site(L, "A", Vector2(13, -10), Vector2(9, 8))
	_site(L, "B", Vector2(-13, -4), Vector2(8, 8))
	# Nave industrial con plataforma A elevada.
	_room(
		L,
		Vector2(14, -11),
		Vector2(18, 15),
		4.2,
		{
			"mat": "concrete",
			"floor": "concrete",
			"roof": true,
			"doors":
			[{"side": 2, "off": 2.0, "width": 2.6}, {"side": 1, "off": -3.0, "width": 2.2}],
			"windows": [{"side": 0, "off": 0, "width": 3.0, "sill": 1.4}],
		}
	)
	_platform(L, Vector2(17, -12), Vector2(9, 7), 2.4, "metal")
	_stairs(L, Vector2(10.5, -12), 2.6, 2.4, 2, "metal")
	_prop(L, "barrels", Vector3(9, 0, -16), 1.0, 0.0)
	# B en sala baja.
	_room(
		L,
		Vector2(-14, -6),
		Vector2(14, 13),
		3.6,
		{
			"mat": "concrete",
			"floor": "concrete",
			"roof": true,
			"doors": [{"side": 3, "off": 2.0, "width": 2.4}],
		}
	)
	_room(
		L,
		Vector2(-16, 16),
		Vector2(14, 12),
		WALL,
		{
			"mat": "metal",
			"floor": "concrete",
			"roof": true,
			"doors": [{"side": 1, "off": 0, "width": 2.4}, {"side": 2, "off": 0, "width": 2.0}],
		}
	)
	_room(
		L,
		Vector2(16, 16),
		Vector2(12, 10),
		WALL,
		{
			"mat": "concrete",
			"floor": "concrete",
			"roof": true,
			"doors": [{"side": 1, "off": 2.0, "width": 2.0}],
		}
	)
	_wall_x(L, -8, 8, 6, WALL, "concrete")
	_wall_z(L, -2, 26, 0, WALL, "metal")
	_wall_z(L, -2, 26, 4, WALL, "metal")
	_crates(L, rng, Vector2(0, -20), 5.0, 4)
	_prop(L, "container", Vector3(-8, 0, 26), 1.0, 0.0)
	_prop(L, "container", Vector3(9, 0, 26), 1.0, 0.0)
	_prop(L, "truck", Vector3(22, 0, 8), 1.0, 90.0)
	for i in 5:
		_light(L, Vector3(-16 + i * 8, 3.4, 22), Color(0.8, 0.9, 1.0), 2.0, 12.0)
	L.spawns_ct = _spawns(L, Vector2(-24, -24), 0.0, 5)
	L.spawns_t = _spawns(L, Vector2(22, 24), PI, 5)
	L.mode = "bomb"
	return L


static func _train() -> Dictionary:
	var L := _base("de_train", "railyard", "overcast", 40.0, "snow")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5501
	_perimeter(L, 40.0, "concrete")
	_site(L, "A", Vector2(19, -14), Vector2(9, 9))
	_site(L, "B", Vector2(-19, -10), Vector2(9, 9))
	# Vias y vagones.
	_solid(L, Vector3(0, 0.03, -2), Vector3(80, 0.06, 0.3), "metal")
	_solid(L, Vector3(0, 0.03, 3), Vector3(80, 0.06, 0.3), "metal")
	for i in 4:
		_prop(L, "train", Vector3(-24 + i * 15, 0, 0), 1.0, 0.0 if i % 2 == 0 else 180.0)
		if i % 2 == 1:
			_prop(L, "container", Vector3(-18 + i * 15, 0, 9), 1.0, 90.0)
	# Deposito cubierto.
	_room(
		L,
		Vector2(24, -20),
		Vector2(20, 16),
		5.0,
		{
			"mat": "concrete",
			"floor": "concrete",
			"roof": true,
			"doors": [{"side": 3, "off": 0, "width": 4.0}, {"side": 2, "off": -4.0, "width": 2.6}],
			"windows":
			[
				{"side": 0, "off": -4.0, "width": 3.0, "sill": 1.6},
				{"side": 0, "off": 4.0, "width": 3.0, "sill": 1.6}
			],
		}
	)
	_room(
		L,
		Vector2(-22, -19),
		Vector2(16, 14),
		WALL,
		{
			"mat": "brick",
			"floor": "concrete",
			"roof": true,
			"doors": [{"side": 1, "off": 0, "width": 2.6}],
		}
	)
	_room(
		L,
		Vector2(0, 26),
		Vector2(18, 12),
		WALL,
		{
			"mat": "metal",
			"floor": "concrete",
			"roof": true,
			"doors": [{"side": 0, "off": 0, "width": 3.0}],
		}
	)
	_wall_x(L, -10, 10, 12, 2.0, "concrete")
	_wall_x(L, -16, -4, -14, WALL, "brick")
	_crates(L, rng, Vector2(18, -6), 4.0, 5)
	_crates(L, rng, Vector2(-8, -22), 5.0, 4)
	_prop(L, "barrels", Vector3(-4, 0, 18), 1.0, 0.0)
	_prop(L, "street_lamp", Vector3(0, 0, 14), 1.0, 0.0)
	_prop(L, "street_lamp", Vector3(-14, 0, 2), 1.0, 0.0)
	L.spawns_ct = _spawns(L, Vector2(30, 30), 0.0, 5)
	L.spawns_t = _spawns(L, Vector2(-30, 30), PI, 5)
	L.mode = "bomb"
	return L


static func _office() -> Dictionary:
	var L := _base("cs_office", "office", "overcast", 32.0, "asphalt")
	var rng := RandomNumberGenerator.new()
	rng.seed = 6602
	_perimeter(L, 32.0, "concrete")
	# Edificio principal con oficinas.
	_room(
		L,
		Vector2(0, 2),
		Vector2(34, 26),
		4.0,
		{
			"mat": "plaster",
			"floor": "carpet",
			"roof": true,
			"doors":
			[
				{"side": 1, "off": -9.0, "width": 2.6},
				{"side": 1, "off": 9.0, "width": 2.6},
				{"side": 2, "off": 0, "width": 2.4},
				{"side": 3, "off": 0, "width": 2.4},
			],
			"windows":
			[
				{"side": 0, "off": -10.0, "width": 3.0, "sill": 1.1},
				{"side": 0, "off": 0.0, "width": 3.0, "sill": 1.1},
				{"side": 0, "off": 10.0, "width": 3.0, "sill": 1.1},
			],
		}
	)
	# Divisiones internas.
	_wall_z(L, -10, 4, -8, WALL, "plaster")
	_wall_z(L, -10, 4, 8, WALL, "plaster")
	_wall_x(L, -17, -8, -4, WALL, "plaster")
	_wall_x(L, 8, 17, -4, WALL, "plaster")
	_wall_x(L, -6, 6, 8, 2.2, "plaster")
	for i in 5:
		_prop(L, "desk", Vector3(-13 + i * 6.5, 0, 4), 1.0, 0.0)
		_prop(L, "computer", Vector3(-13 + i * 6.5, 0, 4), 1.0, 0.0)
		_prop(L, "chair", Vector3(-13 + i * 6.5, 0, 5.4), 1.0, rng.randf_range(0, 360))
	for i in 4:
		_prop(L, "cabinet", Vector3(-15.5, 0, -7 + i * 3.0), 1.0, 0.0)
	# Oficina trasera con rehenes.
	_room(
		L,
		Vector2(-20, -22),
		Vector2(14, 12),
		WALL,
		{
			"mat": "plaster",
			"floor": "carpet",
			"roof": true,
			"doors": [{"side": 1, "off": 0, "width": 2.0}],
		}
	)
	_prop(L, "desk", Vector3(-20, 0, -22), 1.0, 0.0)
	_prop(L, "cabinet", Vector3(-25, 0, -26), 1.0, 0.0)
	_prop(L, "cabinet", Vector3(-15, 0, -26), 1.0, 0.0)
	# Patio y camiones.
	_prop(L, "truck", Vector3(18, 0, 24), 1.0, 90.0)
	_prop(L, "car", Vector3(-16, 0, 22), 0.9, 80.0)
	_crates(L, rng, Vector2(20, 15), 3.0, 3)
	L.hostages = [Vector3(-20, 0.1, -22), Vector3(-22, 0.1, -19), Vector3(2, 0.1, 6)]
	L.rescue = [Vector3(0, 0.2, -29), Vector3(-4, 0.2, -29), Vector3(4, 0.2, -29)]
	L.spawns_ct = _spawns(L, Vector2(0, -28), 0.0, 5)
	L.spawns_t = _spawns(L, Vector2(22, 24), PI, 5)
	L.mode = "hostage"
	_light(L, Vector3(0, 3.5, 2), Color(1.0, 0.92, 0.8), 2.4, 18.0)
	return L


static func _italy() -> Dictionary:
	var L := _base("cs_italy", "italy", "day", 36.0, "cobble")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7703
	_perimeter(L, 36.0, "plaster")
	_prop(L, "fountain", Vector3(0, 0, 2), 1.0, 0.0)
	_room(
		L,
		Vector2(-20, 15),
		Vector2(16, 14),
		WALL,
		{
			"mat": "plaster",
			"floor": "tile",
			"roof": true,
			"doors": [{"side": 1, "off": 0, "width": 2.2}, {"side": 3, "off": 3.0, "width": 1.8}],
			"windows": [{"side": 0, "off": 2.0, "width": 2.0, "sill": 1.2}],
		}
	)
	_room(
		L,
		Vector2(20, 16),
		Vector2(14, 12),
		WALL,
		{
			"mat": "brick",
			"floor": "wood",
			"roof": true,
			"doors": [{"side": 2, "off": 0, "width": 2.2}],
		}
	)
	_room(
		L,
		Vector2(-22, -14),
		Vector2(14, 12),
		WALL,
		{
			"mat": "plaster",
			"floor": "stone",
			"roof": true,
			"doors": [{"side": 3, "off": 0, "width": 2.2}],
		}
	)
	_room(
		L,
		Vector2(21, -16),
		Vector2(14, 12),
		WALL,
		{
			"mat": "brick",
			"floor": "tile",
			"roof": true,
			"doors": [{"side": 2, "off": 2.0, "width": 2.2}],
			"windows": [{"side": 1, "off": 0, "width": 2.2, "sill": 1.0}],
		}
	)
	for i in 4:
		_prop(L, "market_stall", Vector3(-9 + i * 6, 0, 8), 1.0, rng.randf_range(-20, 20))
	_prop(L, "market_stall", Vector3(10, 0, -8), 1.0, 90.0)
	_prop(L, "car", Vector3(-6, 0, -24), 0.9, 20.0)
	_prop(L, "tree", Vector3(28, 0, 28), 1.0, 0.0)
	_crates(L, rng, Vector2(12, 2), 3.0, 3)
	_wall_x(L, -4, 8, 24, 2.4, "plaster")
	_wall_z(L, 4, 22, -6, 2.4, "brick")
	L.hostages = [Vector3(-20, 0.1, 15), Vector3(20, 0.1, 16), Vector3(21, 0.1, -16)]
	L.rescue = [Vector3(0, 0.2, -31), Vector3(4, 0.2, -31), Vector3(-4, 0.2, -31)]
	L.spawns_ct = _spawns(L, Vector2(0, -30), 0.0, 5)
	L.spawns_t = _spawns(L, Vector2(0, 30), PI, 5)
	L.mode = "hostage"
	return L


static func _dust() -> Dictionary:
	var L := _base("de_dust", "desert", "day", 32.0, "sand")
	var rng := RandomNumberGenerator.new()
	rng.seed = 8804
	_perimeter(L, 32.0, "plaster")
	_site(L, "A", Vector2(18, -12), Vector2(8, 8))
	_site(L, "B", Vector2(-18, -10), Vector2(8, 8))
	_room(
		L,
		Vector2(-18, 14),
		Vector2(16, 12),
		WALL,
		{
			"mat": "plaster",
			"floor": "stone",
			"roof": true,
			"doors": [{"side": 1, "off": 0, "width": 2.4}],
			"windows": [{"side": 0, "off": 0, "width": 2.0, "sill": 1.1}],
		}
	)
	_room(
		L,
		Vector2(18, 14),
		Vector2(14, 12),
		WALL,
		{
			"mat": "plaster",
			"floor": "stone",
			"roof": true,
			"doors": [{"side": 1, "off": 2.0, "width": 2.4}],
		}
	)
	_room(
		L,
		Vector2(-24, -22),
		Vector2(12, 10),
		WALL,
		{
			"mat": "stone",
			"floor": "stone",
			"roof": false,
			"doors": [{"side": 1, "off": 0, "width": 2.4}],
		}
	)
	_solid(L, Vector3(0, 1.4, 0), Vector3(14, 2.8, 6), "plaster")
	_wall_z(L, -24, -4, -8, WALL, "plaster")
	_wall_z(L, 4, 24, 8, WALL, "plaster")
	_crates(L, rng, Vector2(18, -12), 3.0, 4)
	_crates(L, rng, Vector2(-18, -10), 3.0, 4)
	_crates(L, rng, Vector2(0, 8), 3.0, 3)
	_prop(L, "sandbags", Vector3(8, 0, -20), 1.4, 90.0)
	_prop(L, "barrels", Vector3(-10, 0, -18), 1.0, 0.0)
	L.spawns_ct = _spawns(L, Vector2(-20, -28), 0.0, 5)
	L.spawns_t = _spawns(L, Vector2(20, 28), PI, 5)
	L.mode = "bomb"
	return L


static func _mansion() -> Dictionary:
	var L := _base("zm_mansion", "mansion", "night", 26.0, "stone")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9905
	_perimeter(L, 26.0, "stone")
	# Casa central con salon, pasillos y altillo.
	_room(
		L,
		Vector2(0, 0),
		Vector2(30, 22),
		4.4,
		{
			"mat": "wallpaper",
			"floor": "wood",
			"roof": true,
			"doors":
			[
				{"side": 1, "off": 0, "width": 3.0},
				{"side": 0, "off": 0, "width": 2.4},
				{"side": 2, "off": -4.0, "width": 2.2},
				{"side": 3, "off": 4.0, "width": 2.2},
			],
			"windows":
			[
				{"side": 0, "off": -9.0, "width": 2.0, "sill": 1.2},
				{"side": 0, "off": 9.0, "width": 2.0, "sill": 1.2},
			],
		}
	)
	_wall_z(L, -11, -2, -7, WALL, "stone")
	_wall_z(L, 2, 11, 7, WALL, "wallpaper")
	_wall_x(L, 7, 15, -4, WALL, "wallpaper")
	_platform(L, Vector2(10, 6), Vector2(8, 6), 2.6, "wood")
	_stairs(L, Vector2(5.5, 6), 2.6, 2.6, 2, "wood")
	_prop(L, "table", Vector3(-3, 0, 3), 1.0, 0.0)
	_prop(L, "chair", Vector3(-3, 0, 4.2), 1.0, 180.0)
	_prop(L, "cabinet", Vector3(-13, 0, -8), 1.0, 90.0)
	_prop(L, "hanging_lamp", Vector3(0, 0, 0), 1.0, 0.0)
	_prop(L, "hanging_lamp", Vector3(-9, 0, 7), 1.0, 0.0)
	_prop(L, "hanging_lamp", Vector3(10, 0, -7), 1.0, 0.0)
	_prop(L, "fountain", Vector3(0, 0, -18), 0.8, 0.0)
	for i in 7:
		var a := TAU * i / 7.0
		_prop(L, "barricade", Vector3(cos(a) * 11.0, 0, sin(a) * 9.0), 1.0, rad_to_deg(a) + 90.0)
		_prop(L, "rubble", Vector3(cos(a) * 20.0, 0, sin(a) * 18.0), 1.0, i * 40.0)
	_crates(L, rng, Vector2(-16, 13), 3.0, 3)
	_crates(L, rng, Vector2(16, -13), 3.0, 3)
	L.spawns_ct = [Vector3(0, 0.2, 6), Vector3(-2, 0.2, 6), Vector3(2, 0.2, 6), Vector3(0, 0.2, 4)]
	L.zombie_spawns = [
		Vector3(-22, 0.2, -22),
		Vector3(22, 0.2, -22),
		Vector3(-22, 0.2, 22),
		Vector3(22, 0.2, 22),
		Vector3(0, 0.2, -24),
		Vector3(0, 0.2, 24),
		Vector3(-24, 0.2, 0),
		Vector3(24, 0.2, 0),
		Vector3(-16, 0.2, 0),
		Vector3(16, 0.2, 0),
	]
	L.perks = [
		{"id": "jugg", "pos": Vector3(-12, 0.2, -8)},
		{"id": "speed", "pos": Vector3(12, 0.2, 8)},
		{"id": "double", "pos": Vector3(-12, 0.2, 8)},
		{"id": "revive", "pos": Vector3(12, 0.2, -8)},
	]
	L.mystery = Vector3(0, 0.2, 10)
	L.ammo_crate = Vector3(0, 0.2, -8)
	L.mode = "zombie"
	_light(L, Vector3(0, 2.0, 10), Color(0.9, 0.55, 0.3), 2.4, 14.0)
	return L


static func _dust_night() -> Dictionary:
	var L := _dust2()
	L.id = "zm_dust_night"
	L.theme = "desert_night"
	L.sky = "night"
	L.mode = "zombie"
	L.sites = []
	L.hostages = []
	L.rescue = []
	L.spawns_t = []
	L.spawns_ct = [Vector3(0, 0.2, 6), Vector3(-2, 0.2, 6), Vector3(2, 0.2, 6), Vector3(0, 0.2, 4)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 31009
	# Barricadas alrededor de la plaza central.
	for i in 10:
		var a := TAU * i / 10.0
		_prop(L, "barricade", Vector3(cos(a) * 12.0, 0, sin(a) * 10.0), 1.2, rad_to_deg(a) + 90.0)
		L.zombie_spawns.append(Vector3(cos(a) * 31.0, 0.2, sin(a) * 31.0))
	L.zombie_spawns.append(Vector3(22, 0.2, -18))
	L.zombie_spawns.append(Vector3(-24, 0.2, -14))
	L.perks = [
		{"id": "jugg", "pos": Vector3(-8, 0.2, 8)},
		{"id": "speed", "pos": Vector3(8, 0.2, 8)},
		{"id": "double", "pos": Vector3(-8, 0.2, -4)},
		{"id": "revive", "pos": Vector3(8, 0.2, -4)},
		{"id": "mule", "pos": Vector3(0, 0.2, -10)},
	]
	L.mystery = Vector3(0, 0.2, 14)
	L.ammo_crate = Vector3(-14, 0.2, 0)
	L.lights = [
		{
			"p": Vector3(0, 3.5, 0),
			"color": Color(1.0, 0.6, 0.32),
			"energy": 3.0,
			"range": 16.0,
			"shadow": true
		},
		{
			"p": Vector3(-14, 2.8, 0),
			"color": Color(0.9, 0.4, 0.25),
			"energy": 2.0,
			"range": 12.0,
			"shadow": true
		},
		{
			"p": Vector3(14, 2.8, 0),
			"color": Color(0.9, 0.4, 0.25),
			"energy": 2.0,
			"range": 12.0,
			"shadow": true
		},
	]
	for i in 8:
		var a := TAU * i / 8.0
		_prop(L, "street_lamp", Vector3(cos(a) * 20.0, 0, sin(a) * 20.0), 1.0, 0.0)
	return L
