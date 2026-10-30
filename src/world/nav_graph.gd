extends RefCounted
## NavGraph: grilla de navegacion 2.5D con A* para los bots.
##
## En vez de hornear un NavMesh (lento y fragil con geometria procedural),
## se muestrea el mundo con rayos y se guarda una malla de alturas. Soporta
## desniveles, rampas y escaleras, y descarta celdas sin espacio libre.

class_name NavGraph

var bounds: Rect2 = Rect2()
var cell := 0.8
var cols := 0
var rows := 0
var heights: PackedFloat32Array = PackedFloat32Array()
var blocked: PackedByteArray = PackedByteArray()
var ready := false


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


func set_cell(cx: int, cz: int, height: float, is_blocked: bool) -> void:
	if cx < 0 or cz < 0 or cx >= cols or cz >= rows:
		return
	var i := cz * cols + cx
	heights[i] = height
	blocked[i] = 1 if is_blocked else 0


func finish() -> void:
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


## Ruta completa desde `from` hasta `to`. Devuelve puntos en world space.
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

	var n := cols * rows
	var g_score := PackedFloat32Array()
	g_score.resize(n)
	g_score.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	closed.fill(0)

	# Heap binario de indices, ordenado por f_score.
	var heap_i: Array[int] = []
	var heap_f: Array[float] = []
	var hf := PackedFloat32Array()
	hf.resize(n)
	hf.fill(INF)
	g_score[start_i] = 0.0
	hf[start_i] = _heuristic(start, goal)
	_heap_push(heap_i, heap_f, start_i, hf[start_i])
	var found := false
	var guard := 0
	while heap_i.size() > 0 and guard < n * 3:
		guard += 1
		var current := _heap_pop(heap_i, heap_f)
		if current == goal_i:
			found = true
			break
		if closed[current] == 1:
			continue
		closed[current] = 1
		var cx := current % cols
		var cz := int(current / cols)
		for dir: Vector2i in [
			Vector2i(1, 0),
			Vector2i(-1, 0),
			Vector2i(0, 1),
			Vector2i(0, -1),
			Vector2i(1, 1),
			Vector2i(1, -1),
			Vector2i(-1, 1),
			Vector2i(-1, -1)
		]:
			var nx := cx + dir.x
			var nz := cz + dir.y
			if nx < 0 or nz < 0 or nx >= cols or nz >= rows:
				continue
			var ni := nz * cols + nx
			if blocked[ni] == 1 or closed[ni] == 1:
				continue
			var dh: float = absf(heights[ni] - heights[current])
			if dh > 0.62:
				continue
			if dir.x != 0 and dir.y != 0:
				# Evita cortar esquinas en diagonal.
				if blocked[cz * cols + nx] == 1 or blocked[nz * cols + cx] == 1:
					continue
			var step := 1.4142 if (dir.x != 0 and dir.y != 0) else 1.0
			var tentative: float = g_score[current] + step + dh * 3.0
			if tentative < g_score[ni]:
				g_score[ni] = tentative
				came[ni] = current
				hf[ni] = tentative + _heuristic(Vector2i(nx, nz), goal)
				_heap_push(heap_i, heap_f, ni, hf[ni])
	if not found:
		return out
	# Reconstruccion.
	var chain: Array[int] = []
	var cur := goal_i
	var safety := 0
	while cur != -1 and safety < n:
		safety += 1
		chain.append(cur)
		if cur == start_i:
			break
		cur = came[cur]
	chain.reverse()
	var raw: Array[Vector3] = []
	for idx in chain:
		var c := Vector2i(idx % cols, int(idx / cols))
		raw.append(world_from_cell(c))
	# Suavizado: conserva solo los puntos necesarios.
	var i := 0
	while i < raw.size():
		out.append(raw[i])
		var next := raw.size() - 1
		var j := raw.size() - 1
		while j > i + 1:
			if _line_clear(raw[i], raw[j]):
				next = j
				break
			j -= 1
		if next <= i:
			break
		i = next
	if out.size() == 0 or out[out.size() - 1].distance_to(raw[raw.size() - 1]) > 0.15:
		out.append(raw[raw.size() - 1])
	return out


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx := absf(float(a.x - b.x))
	var dz := absf(float(a.y - b.y))
	return (dx + dz) + (1.4142 - 2.0) * minf(dx, dz)


func _line_clear(a: Vector3, b: Vector3) -> bool:
	var dist := a.distance_to(b)
	var steps := maxi(2, int(dist / (cell * 0.7)))
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


func _heap_push(heap_i: Array[int], heap_f: Array[float], idx: int, f: float) -> void:
	heap_i.append(idx)
	heap_f.append(f)
	var i := heap_i.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if heap_f[parent] <= heap_f[i]:
			break
		var ti := heap_i[parent]
		var tf := heap_f[parent]
		heap_i[parent] = heap_i[i]
		heap_f[parent] = heap_f[i]
		heap_i[i] = ti
		heap_f[i] = tf
		i = parent


func _heap_pop(heap_i: Array[int], heap_f: Array[float]) -> int:
	var top := heap_i[0]
	var last_i := heap_i[heap_i.size() - 1]
	var last_f := heap_f[heap_f.size() - 1]
	heap_i.remove_at(heap_i.size() - 1)
	heap_f.remove_at(heap_f.size() - 1)
	if heap_i.size() > 0:
		heap_i[0] = last_i
		heap_f[0] = last_f
		var i := 0
		var n := heap_i.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var smallest := i
			if l < n and heap_f[l] < heap_f[smallest]:
				smallest = l
			if r < n and heap_f[r] < heap_f[smallest]:
				smallest = r
			if smallest == i:
				break
			var ti := heap_i[smallest]
			var tf := heap_f[smallest]
			heap_i[smallest] = heap_i[i]
			heap_f[smallest] = heap_f[i]
			heap_i[i] = ti
			heap_f[i] = tf
			i = smallest
	return top


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
