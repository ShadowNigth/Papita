extends RefCounted
## NavGraph: grilla de navegacion 2.5D con AStar3D nativo en C++ para los bots.
##
## Muestrea el mundo con rayos, guarda una malla de alturas y preconstruye
## un grafo AStar3D nativo una sola vez en `finish()`, logrando busquedas de
## ruta instantaneas sin asignaciones por frame en GDScript.

class_name NavGraph

var bounds: Rect2 = Rect2()
var cell := 0.8
var cols := 0
var rows := 0
var heights: PackedFloat32Array = PackedFloat32Array()
var blocked: PackedByteArray = PackedByteArray()
var ready := false

var _astar: AStar3D = AStar3D.new()


func setup(bounds_rect: Rect2, cell_size: float = 0.8) -> void:
	bounds = bounds_rect
	cell = cell_size
	cols = maxi(1, int(ceil(bounds.size.x / cell)))
	rows = maxi(1, int(ceil(bounds.size.y / cell)))
	var n := cols * rows
	heights.resize(n)
	heights.fill(0.0)
	blocked.resize(n)
	blocked.fill(1)
	ready = false


func set_cell(cx: int, cz: int, height: float, is_blocked: bool) -> void:
	if cx < 0 or cz < 0 or cx >= cols or cz >= rows:
		return
	var i := cz * cols + cx
	heights[i] = height
	blocked[i] = 1 if is_blocked else 0


func finish() -> void:
	_astar = AStar3D.new()
	var n := cols * rows
	_astar.reserve_space(n)
	for cz in rows:
		for cx in cols:
			var idx := cz * cols + cx
			if blocked[idx] == 0:
				_astar.add_point(idx, world_from_cell(Vector2i(cx, cz)), 1.0)
	for cz in rows:
		for cx in cols:
			var idx := cz * cols + cx
			if blocked[idx] != 0:
				continue
			var h0 := heights[idx]
			# Vecinos hacia adelante (evita conectar cada arista dos veces).
			if cx + 1 < cols:
				var ni := idx + 1
				if blocked[ni] == 0 and absf(heights[ni] - h0) <= 0.65:
					_astar.connect_points(idx, ni, true)
			if cz + 1 < rows:
				var ni2 := idx + cols
				if blocked[ni2] == 0 and absf(heights[ni2] - h0) <= 0.65:
					_astar.connect_points(idx, ni2, true)
			if cx + 1 < cols and cz + 1 < rows:
				var nd1 := idx + cols + 1
				if (
					blocked[nd1] == 0
					and blocked[idx + 1] == 0
					and blocked[idx + cols] == 0
					and absf(heights[nd1] - h0) <= 0.65
				):
					_astar.connect_points(idx, nd1, true)
			if cx - 1 >= 0 and cz + 1 < rows:
				var nd2 := idx + cols - 1
				if (
					blocked[nd2] == 0
					and blocked[idx - 1] == 0
					and blocked[idx + cols] == 0
					and absf(heights[nd2] - h0) <= 0.65
				):
					_astar.connect_points(idx, nd2, true)
	ready = true


func cell_index(cx: int, cz: int) -> int:
	return cz * cols + cx


func cell_from_world(p: Vector3) -> Vector2i:
	return Vector2i(
		int(floor((p.x - bounds.position.x) / cell)), int(floor((p.z - bounds.position.y) / cell))
	)


func world_from_cell(c: Vector2i) -> Vector3:
	var x := bounds.position.x + (c.x + 0.5) * cell
	var z := bounds.position.y + (c.y + 0.5) * cell
	var h := 0.0
	if c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows:
		h = heights[cell_index(c.x, c.y)]
	return Vector3(x, h + 0.05, z)


func is_walkable(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
		return false
	return blocked[cell_index(c.x, c.y)] == 0


func height_at(p: Vector3) -> float:
	var c := cell_from_world(p)
	if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
		return 0.0
	return heights[cell_index(c.x, c.y)]


func nearest_walkable(c: Vector2i, max_radius: int = 8) -> Vector2i:
	if is_walkable(c):
		return c
	for r in range(1, max_radius + 1):
		for dx in range(-r, r + 1):
			for dz in [-r, r]:
				var a := c + Vector2i(dx, dz)
				if is_walkable(a):
					return a
		for dz in range(-r + 1, r):
			for dx in [-r, r]:
				var b := c + Vector2i(dx, dz)
				if is_walkable(b):
					return b
	return c


## Ruta completa desde `from` hasta `to` usando AStar3D nativo en C++.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not ready:
		return out
	var start := nearest_walkable(cell_from_world(from))
	var goal := nearest_walkable(cell_from_world(to))
	if not is_walkable(start) or not is_walkable(goal):
		return out
	var start_i := cell_index(start.x, start.y)
	var goal_i := cell_index(goal.x, goal.y)
	if start_i == goal_i:
		out.append(world_from_cell(goal))
		return out
	if not _astar.has_point(start_i) or not _astar.has_point(goal_i):
		return out
	var raw := _astar.get_point_path(start_i, goal_i, true)
	if raw.is_empty():
		return out
	# Suavizado lineal acotado O(N) para conservar esquinas limpias sin tirones.
	var i := 0
	var last_idx := raw.size() - 1
	while i <= last_idx:
		out.append(raw[i])
		if i == last_idx:
			break
		var next := i + 1
		var max_j := mini(last_idx, i + 10)
		var j := max_j
		while j > i + 1:
			if _line_clear(raw[i], raw[j]):
				next = j
				break
			j -= 1
		i = next
	if out.is_empty() or out[out.size() - 1].distance_to(raw[last_idx]) > 0.15:
		out.append(raw[last_idx])
	return out


func _line_clear(a: Vector3, b: Vector3) -> bool:
	var dist := a.distance_to(b)
	var steps := maxi(2, int(dist / (cell * 0.75)))
	var prev_h := height_at(a)
	for s in range(1, steps + 1):
		var t := float(s) / float(steps)
		var p := a.lerp(b, t)
		var c := cell_from_world(p)
		if not is_walkable(c):
			return false
		var h := height_at(p)
		if absf(h - prev_h) > 0.7:
			return false
		prev_h = h
	return true


func random_point(rng: RandomNumberGenerator) -> Vector3:
	for i in 60:
		var c := Vector2i(rng.randi_range(0, cols - 1), rng.randi_range(0, rows - 1))
		if is_walkable(c):
			return world_from_cell(c)
	return world_from_cell(Vector2i(cols / 2, rows / 2))


func random_point_near(center: Vector3, radius: float, rng: RandomNumberGenerator) -> Vector3:
	for i in 30:
		var a := rng.randf() * TAU
		var r := rng.randf_range(radius * 0.3, radius)
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		var c := cell_from_world(p)
		if is_walkable(c):
			return world_from_cell(c)
	return world_from_cell(nearest_walkable(cell_from_world(center)))
