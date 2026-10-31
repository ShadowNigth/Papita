extends RefCounted
## BspLoader: cargador nativo de mapas originales GoldSrc v30 (.bsp) de Counter-Strike 1.5.
##
## Reconstruye la geometria 1:1 exacta del mapa clasico, extrae spawns CT/T, sitios A/B,
## rehenes, luces, escaleras, puertas y cristales/cajas rompibles, y reemplaza las
## texturas pixeladas de 1999 por materiales PBR realistas de alta definicion modulados
## por el color original del WAD y los lightmaps de radiosidad horneados en el .bsp.

class_name BspLoader

const SCALE := 0.025
const WATER_SHADER := preload("res://shaders/water.gdshader")


static func gs_to_gd(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * SCALE, z * SCALE, -y * SCALE)


static func _parse_vec3_raw(text: String) -> Vector3:
	var parts := text.strip_edges().split(" ", false)
	if parts.size() < 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


static func _parse_entities(ent_text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var in_block := false
	var cur: Dictionary = {}
	for raw_line in ent_text.split("\n"):
		var line := raw_line.strip_edges()
		if line == "{":
			in_block = true
			cur = {}
		elif line == "}":
			if in_block and not cur.is_empty():
				out.append(cur)
			in_block = false
		elif in_block and line.begins_with('"'):
			var q1: int = line.find('"', 1)
			if q1 > 1:
				var key := line.substr(1, q1 - 1)
				var q2: int = line.find('"', q1 + 1)
				if q2 > q1:
					var q3: int = line.find('"', q2 + 1)
					if q3 >= q2 + 1:
						cur[key] = line.substr(q2 + 1, q3 - q2 - 1)
	return out


## Extrae los metadatos tacticos del .bsp (spawns, sitios de bomba, rehenes, luces y limites)
## para que `Maps.build()` entregue un layout 100 % compatible con `MatchGame` y `MapBuilder`.
static func load_metadata(
	map_id: String, bsp_name: String, theme: String, sky_mode: String
) -> Dictionary:
	var path := "res://assets/maps/cs15/%s.bsp" % bsp_name
	if not FileAccess.file_exists(path):
		return {}
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 128 or bytes.decode_s32(0) != 30:
		return {}

	var ent_ofs := bytes.decode_u32(4)
	var ent_len := bytes.decode_u32(8)
	var mod_ofs := bytes.decode_u32(4 + 14 * 8)
	var mod_len := bytes.decode_u32(4 + 14 * 8 + 4)
	var num_models := mod_len / 64

	var ent_slice := bytes.slice(ent_ofs, mini(bytes.size(), ent_ofs + ent_len))
	var zero_idx: int = ent_slice.find(0)
	if zero_idx >= 0:
		ent_slice = ent_slice.slice(0, zero_idx)
	var ents := _parse_entities(ent_slice.get_string_from_ascii())

	var w_min := Vector3(-40.0, -10.0, -40.0)
	var w_max := Vector3(40.0, 15.0, 40.0)
	if num_models > 0:
		var min_gs := Vector3(
			bytes.decode_float(mod_ofs),
			bytes.decode_float(mod_ofs + 4),
			bytes.decode_float(mod_ofs + 8)
		)
		var max_gs := Vector3(
			bytes.decode_float(mod_ofs + 12),
			bytes.decode_float(mod_ofs + 16),
			bytes.decode_float(mod_ofs + 20)
		)
		var a := gs_to_gd(min_gs.x, min_gs.y, min_gs.z)
		var b := gs_to_gd(max_gs.x, max_gs.y, max_gs.z)
		w_min = Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
		w_max = Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))

	var raw_ct: Array[Vector3] = []
	var raw_t: Array[Vector3] = []
	for e in ents:
		var cls := String(e.get("classname", ""))
		if (cls == "info_player_start" or cls == "info_player_deathmatch") and e.has("origin"):
			var gs := _parse_vec3_raw(String(e["origin"]))
			# El origen GoldSrc del jugador esta a 36 unidades (0.90 m) sobre el piso.
			var p := gs_to_gd(gs.x, gs.y, gs.z) - Vector3(0.0, 0.88, 0.0)
			if cls == "info_player_start":
				raw_ct.append(p)
			else:
				raw_t.append(p)

	var min_spawn_y := 0.0
	var max_spawn_y := 4.0
	var all_sp := raw_ct + raw_t
	if not all_sp.is_empty():
		min_spawn_y = all_sp[0].y
		max_spawn_y = all_sp[0].y
		for sp in all_sp:
			min_spawn_y = minf(min_spawn_y, sp.y)
			max_spawn_y = maxf(max_spawn_y, sp.y)

	var mid_x := (w_min.x + w_max.x) * 0.5
	var mid_z := (w_min.z + w_max.z) * 0.5
	var world_offset := Vector3(-mid_x, -min_spawn_y, -mid_z)

	var spawns_ct: Array[Vector3] = []
	for p in raw_ct:
		spawns_ct.append(p + world_offset)
	var spawns_t: Array[Vector3] = []
	for p in raw_t:
		spawns_t.append(p + world_offset)

	var sites: Array[Dictionary] = []
	var hostages: Array[Vector3] = []
	var rescue_zones: Array[Vector3] = []
	var lights: Array[Dictionary] = []
	var site_idx := 0

	for e in ents:
		var cls := String(e.get("classname", ""))
		if cls == "func_bomb_target" or cls == "info_bomb_target":
			var sc := _entity_world_point(e, bytes, mod_ofs, num_models, true) + world_offset
			var s_sz := _entity_world_size_xz(e, bytes, mod_ofs, num_models)
			var sname := "A" if site_idx == 0 else ("B" if site_idx == 1 else "C")
			site_idx += 1
			sites.append(
				{"name": sname, "center": sc, "size": s_sz, "radius": maxf(s_sz.x, s_sz.y) * 0.5}
			)
		elif cls == "hostage_entity" or cls == "monster_scientist":
			if e.has("origin"):
				var hgs := _parse_vec3_raw(String(e["origin"]))
				hostages.append(
					gs_to_gd(hgs.x, hgs.y, hgs.z) - Vector3(0.0, 0.85, 0.0) + world_offset
				)
		elif cls == "func_hostage_rescue" or cls == "info_hostage_rescue":
			rescue_zones.append(
				_entity_world_point(e, bytes, mod_ofs, num_models, true) + world_offset
			)
		elif (cls == "light" or cls == "light_spot") and e.has("origin") and lights.size() < 28:
			var lgs := _parse_vec3_raw(String(e["origin"]))
			var lp := gs_to_gd(lgs.x, lgs.y, lgs.z) + world_offset
			var lcol := Color(1.0, 0.9, 0.74)
			var lener := 1.35
			if e.has("_light"):
				var parts := String(e["_light"]).strip_edges().split(" ", false)
				if parts.size() >= 3:
					lcol = Color(
						clampf(float(parts[0]) / 255.0, 0.1, 1.0),
						clampf(float(parts[1]) / 255.0, 0.1, 1.0),
						clampf(float(parts[2]) / 255.0, 0.1, 1.0)
					)
				if parts.size() >= 4:
					lener = clampf(float(parts[3]) / 220.0, 0.45, 2.4)
			lights.append({"p": lp, "color": lcol, "energy": lener, "range": 14.0, "shadow": false})

	if rescue_zones.is_empty() and not spawns_ct.is_empty():
		rescue_zones.append(spawns_ct[0])

	var bmin := w_min + world_offset
	var bmax := w_max + world_offset
	var bounds := Rect2(
		Vector2(bmin.x, bmin.z), Vector2(maxf(24.0, bmax.x - bmin.x), maxf(24.0, bmax.z - bmin.z))
	)

	var layout := {
		"id": map_id,
		"bsp": bsp_name,
		"bsp_offset": world_offset,
		"theme": theme,
		"sky": sky_mode,
		"ambience":
		(
			"zombie"
			if map_id.begins_with("zm_")
			else ("industrial" if theme in ["industrial", "railyard", "office"] else "dust")
		),
		"bounds": bounds,
		"nav_y_min": bmin.y - 1.5,
		"nav_y_max": bmax.y + 1.5,
		"playable_y_min": -3.5,
		"playable_y_max": (max_spawn_y - min_spawn_y) + 5.5,
		"ground_mat": "sand",
		"blocks": [],
		"props": [],
		"lights": lights,
		"water": [],
		"spawns_ct": spawns_ct,
		"spawns_t": spawns_t,
		"sites": sites,
		"hostages": hostages,
		"rescue": rescue_zones,
		"zombie_spawns": [],
		"perks": [],
		"mystery": Vector3.ZERO,
		"ammo_crate": Vector3.ZERO,
		"mode": "zombie" if map_id.begins_with("zm_") else "",
	}

	if map_id.begins_with("zm_"):
		_populate_zombie_stations(layout)
	return layout


static func _populate_zombie_stations(layout: Dictionary) -> void:
	var cts: Array = layout.get("spawns_ct", [])
	var ts: Array = layout.get("spawns_t", [])
	layout["zombie_spawns"] = ts.duplicate() if not ts.is_empty() else cts.duplicate()
	layout["sites"] = []
	layout["hostages"] = []
	layout["rescue"] = []
	var anchors: Array[Vector3] = []
	for p: Vector3 in cts:
		anchors.append(p)
	for p: Vector3 in ts:
		anchors.append(p)
	if anchors.is_empty():
		return
	var perk_ids := ["jugg", "speed", "double", "revive", "mule"]
	var perks: Array[Dictionary] = []
	var step := maxi(1, anchors.size() / (perk_ids.size() + 2))
	for i in perk_ids.size():
		var idx := mini(anchors.size() - 1, (i + 1) * step)
		perks.append({"id": perk_ids[i], "pos": anchors[idx] + Vector3(1.1, 0.0, 0.6)})
	layout["perks"] = perks
	layout["mystery"] = anchors[anchors.size() / 2] + Vector3(-1.0, 0.0, 0.8)
	layout["ammo_crate"] = anchors[0] + Vector3(1.4, 0.0, -0.9)


static func _entity_world_size_xz(
	e: Dictionary, bytes: PackedByteArray, mod_ofs: int, num_models: int
) -> Vector2:
	var mod := String(e.get("model", ""))
	if mod.begins_with("*"):
		var mi := int(mod.substr(1))
		if mi > 0 and mi < num_models:
			var bo := mod_ofs + mi * 64
			var sx := absf(bytes.decode_float(bo + 12) - bytes.decode_float(bo)) * SCALE
			var sz := absf(bytes.decode_float(bo + 16) - bytes.decode_float(bo + 4)) * SCALE
			return Vector2(clampf(sx, 7.0, 18.0), clampf(sz, 7.0, 18.0))
	return Vector2(8.5, 8.5)


static func _entity_world_point(
	e: Dictionary, bytes: PackedByteArray, mod_ofs: int, num_models: int, floor_z: bool
) -> Vector3:
	var orig := Vector3.ZERO
	if e.has("origin"):
		orig = _parse_vec3_raw(String(e["origin"]))
	var mod := String(e.get("model", ""))
	if mod.begins_with("*"):
		var mi := int(mod.substr(1))
		if mi > 0 and mi < num_models:
			var bo := mod_ofs + mi * 64
			var min_x := bytes.decode_float(bo)
			var min_y := bytes.decode_float(bo + 4)
			var min_z := bytes.decode_float(bo + 8)
			var max_x := bytes.decode_float(bo + 12)
			var max_y := bytes.decode_float(bo + 16)
			var max_z := bytes.decode_float(bo + 20)
			var cx := (min_x + max_x) * 0.5 + orig.x
			var cy := (min_y + max_y) * 0.5 + orig.y
			var cz := (min_z if floor_z else (min_z + max_z) * 0.5) + orig.z
			return gs_to_gd(cx, cy, cz)
	return gs_to_gd(orig.x, orig.y, orig.z)


# --- Construccion de geometria 3D y colisiones del .bsp -----------------------


static func build_into(
	bsp_name: String, world_offset: Vector3, theme: String, geo_root: Node3D, props_root: Node3D
) -> Dictionary:
	var path := "res://assets/maps/cs15/%s.bsp" % bsp_name
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 128 or bytes.decode_s32(0) != 30:
		return {}

	var ent_ofs := bytes.decode_u32(4)
	var ent_len := bytes.decode_u32(8)
	var pln_ofs := bytes.decode_u32(4 + 1 * 8)
	var tex_ofs := bytes.decode_u32(4 + 2 * 8)
	var vrt_ofs := bytes.decode_u32(4 + 3 * 8)
	var txi_ofs := bytes.decode_u32(4 + 6 * 8)
	var fac_ofs := bytes.decode_u32(4 + 7 * 8)
	var lgt_ofs := bytes.decode_u32(4 + 8 * 8)
	var lgt_len := bytes.decode_u32(4 + 8 * 8 + 4)
	var edg_ofs := bytes.decode_u32(4 + 12 * 8)
	var sfe_ofs := bytes.decode_u32(4 + 13 * 8)
	var mod_ofs := bytes.decode_u32(4 + 14 * 8)
	var mod_len := bytes.decode_u32(4 + 14 * 8 + 4)
	var num_models := mod_len / 64

	var ent_slice := bytes.slice(ent_ofs, mini(bytes.size(), ent_ofs + ent_len))
	var zero_idx: int = ent_slice.find(0)
	if zero_idx >= 0:
		ent_slice = ent_slice.slice(0, zero_idx)
	var ents := _parse_entities(ent_slice.get_string_from_ascii())

	# Tabla de texturas miptex: nombre, dimensiones, categoria PBR y color base real.
	var tex_infos := _read_textures(bytes, tex_ofs, theme)

	# Clasificacion de modelos brush (*1..*N) por entidad.
	var model_ent: Dictionary = {}
	for e in ents:
		var mstr := String(e.get("model", ""))
		if mstr.begins_with("*"):
			var midx := int(mstr.substr(1))
			if midx > 0 and midx < num_models:
				model_ent[midx] = e

	var st_by_bucket: Dictionary = {}
	var mat_by_bucket: Dictionary = {}
	var col_faces_by_surf: Dictionary = {}
	var sky_col_faces := PackedVector3Array()
	var doors: Array[Dictionary] = []

	var wetness := 0.22 if theme in ["jungle", "railyard"] else 0.04
	var ctx := {
		"bytes": bytes,
		"pln_ofs": pln_ofs,
		"vrt_ofs": vrt_ofs,
		"txi_ofs": txi_ofs,
		"fac_ofs": fac_ofs,
		"lgt_ofs": lgt_ofs,
		"lgt_len": lgt_len,
		"edg_ofs": edg_ofs,
		"sfe_ofs": sfe_ofs,
		"mod_ofs": mod_ofs,
		"tex_infos": tex_infos,
		"world_offset": world_offset,
		"wetness": wetness,
	}

	# Modelo 0: worldspawn principal.
	_append_model_faces(
		0,
		Vector3.ZERO,
		true,
		false,
		1.0,
		ctx,
		st_by_bucket,
		mat_by_bucket,
		col_faces_by_surf,
		sky_col_faces
	)

	# Modelos 1..N: brush entities (func_wall, func_illusionary, func_breakable, puertas, escaleras, agua).
	for mi in range(1, num_models):
		if not model_ent.has(mi):
			continue
		var e: Dictionary = model_ent[mi]
		var cls := String(e.get("classname", ""))
		var e_orig_gs := _parse_vec3_raw(String(e.get("origin", "0 0 0")))
		var e_orig_gd := gs_to_gd(e_orig_gs.x, e_orig_gs.y, e_orig_gs.z)

		match cls:
			"func_wall", "func_conveyor", "func_pendulum", "func_plat":
				var rmode := int(e.get("rendermode", "0"))
				var ramt := int(e.get("renderamt", "255"))
				if rmode == 4 and ramt == 0:
					# Muro invisible de colision.
					var dummy_st: Dictionary = {}
					var dummy_mat: Dictionary = {}
					_append_model_faces(
						mi,
						e_orig_gd,
						true,
						true,
						0.0,
						ctx,
						dummy_st,
						dummy_mat,
						col_faces_by_surf,
						sky_col_faces
					)
				else:
					var alpha := (
						clampf(float(ramt) / 255.0, 0.25, 1.0)
						if (rmode != 0 and rmode != 4)
						else 1.0
					)
					_append_model_faces(
						mi,
						e_orig_gd,
						true,
						false,
						alpha,
						ctx,
						st_by_bucket,
						mat_by_bucket,
						col_faces_by_surf,
						sky_col_faces
					)
			"func_illusionary":
				var rmode2 := int(e.get("rendermode", "0"))
				var ramt2 := int(e.get("renderamt", "255"))
				if not (rmode2 != 0 and ramt2 <= 8):
					_append_model_faces(
						mi,
						e_orig_gd,
						false,
						false,
						1.0,
						ctx,
						st_by_bucket,
						mat_by_bucket,
						col_faces_by_surf,
						sky_col_faces
					)
			"func_water":
				_append_model_faces(
					mi,
					e_orig_gd,
					false,
					false,
					0.8,
					ctx,
					st_by_bucket,
					mat_by_bucket,
					col_faces_by_surf,
					sky_col_faces
				)
			"func_breakable", "func_pushable":
				_build_breakable_entity(mi, e, e_orig_gd, ctx, props_root)
			"func_door", "func_door_rotating":
				var d_info := _build_door_entity(mi, e, cls, e_orig_gd, ctx, props_root)
				if not d_info.is_empty():
					doors.append(d_info)
			"func_ladder":
				_build_ladder_area(mi, e_orig_gd, bytes, mod_ofs, world_offset, props_root)

	# Commit de mallas visuales combinadas (~18 draw calls para todo el mapa .bsp).
	for bkey in st_by_bucket.keys():
		var st: SurfaceTool = st_by_bucket[bkey]
		st.generate_tangents()
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mi_node := MeshInstance3D.new()
		mi_node.name = "BspMesh_" + String(bkey)
		mi_node.mesh = mesh
		mi_node.material_override = mat_by_bucket[bkey]
		var is_trans := String(bkey).begins_with("glass") or String(bkey).begins_with("water")
		mi_node.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if is_trans
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
		geo_root.add_child(mi_node)

	# Commit de colisiones estaticas agrupadas por tipo de superficie acustica.
	for surf in col_faces_by_surf.keys():
		var faces_arr: PackedVector3Array = col_faces_by_surf[surf]
		if faces_arr.size() < 3:
			continue
		var sb := StaticBody3D.new()
		sb.name = "BspCol_" + String(surf)
		sb.collision_layer = 1
		sb.collision_mask = 0
		sb.set_meta("surface", surf)
		var cs := CollisionShape3D.new()
		var concave := ConcavePolygonShape3D.new()
		concave.backface_collision = true
		concave.set_faces(faces_arr)
		cs.shape = concave
		sb.add_child(cs)
		geo_root.add_child(sb)

	var sky_rid := RID()
	if sky_col_faces.size() >= 3:
		var sky_sb := StaticBody3D.new()
		sky_sb.name = "BspSkyClip"
		sky_sb.collision_layer = 1
		sky_sb.collision_mask = 0
		sky_sb.set_meta("surface", "concrete")
		sky_sb.set_meta("is_sky_clip", true)
		var sky_cs := CollisionShape3D.new()
		var sky_shape := ConcavePolygonShape3D.new()
		sky_shape.backface_collision = true
		sky_shape.set_faces(sky_col_faces)
		sky_cs.shape = sky_shape
		sky_sb.add_child(sky_cs)
		geo_root.add_child(sky_sb)
		sky_rid = sky_sb.get_rid()

	# Cajas y barriles fisicos interactivos estilo CS2 repartidos en zonas abiertas.
	_spawn_cs2_props(ents, world_offset, props_root)

	return {"doors": doors, "sky_rid": sky_rid}


static func _append_model_faces(
	model_idx: int,
	entity_offset: Vector3,
	with_collision: bool,
	invisible_only: bool,
	alpha_override: float,
	ctx: Dictionary,
	st_by_bucket: Dictionary,
	mat_by_bucket: Dictionary,
	col_faces_by_surf: Dictionary,
	sky_col_faces: PackedVector3Array
) -> void:
	var bytes: PackedByteArray = ctx["bytes"]
	var pln_ofs: int = ctx["pln_ofs"]
	var vrt_ofs: int = ctx["vrt_ofs"]
	var txi_ofs: int = ctx["txi_ofs"]
	var fac_ofs: int = ctx["fac_ofs"]
	var lgt_ofs: int = ctx["lgt_ofs"]
	var lgt_len: int = ctx["lgt_len"]
	var edg_ofs: int = ctx["edg_ofs"]
	var sfe_ofs: int = ctx["sfe_ofs"]
	var mod_ofs: int = ctx["mod_ofs"]
	var tex_infos: Array = ctx["tex_infos"]
	var world_offset: Vector3 = ctx["world_offset"]
	var wetness: float = ctx["wetness"]

	var mo := mod_ofs + model_idx * 64
	var first_face := bytes.decode_s32(mo + 56)
	var num_faces := bytes.decode_s32(mo + 60)
	var total_offset := world_offset + entity_offset

	for fi in range(first_face, first_face + num_faces):
		var fo := fac_ofs + fi * 20
		var plane_id := bytes.decode_s16(fo)
		var side := bytes.decode_s16(fo + 2)
		var first_edge := bytes.decode_s32(fo + 4)
		var num_edges := bytes.decode_s16(fo + 8)
		var texinfo_id := bytes.decode_s16(fo + 10)
		var lightofs := bytes.decode_s32(fo + 16)
		if num_edges < 3 or texinfo_id < 0:
			continue

		var tio := txi_ofs + texinfo_id * 40
		var sx := bytes.decode_float(tio)
		var sy := bytes.decode_float(tio + 4)
		var sz := bytes.decode_float(tio + 8)
		var so := bytes.decode_float(tio + 12)
		var tx := bytes.decode_float(tio + 16)
		var ty := bytes.decode_float(tio + 20)
		var tz := bytes.decode_float(tio + 24)
		var to_off := bytes.decode_float(tio + 28)
		var miptex_id := bytes.decode_u32(tio + 32)
		var tflags := bytes.decode_u32(tio + 36)
		if miptex_id >= tex_infos.size():
			continue

		var tinfo: Dictionary = tex_infos[miptex_id]
		var role := String(tinfo["role"])
		if role == "skip":
			continue

		# Normal de la cara en espacio Godot.
		var po := pln_ofs + plane_id * 20
		var pnx := bytes.decode_float(po)
		var pny := bytes.decode_float(po + 4)
		var pnz := bytes.decode_float(po + 8)
		if side != 0:
			pnx = -pnx
			pny = -pny
			pnz = -pnz
		var n_gd := Vector3(pnx, pnz, -pny).normalized()

		# Vertices y coordenadas UV de lightmap.
		var pts_gd := PackedVector3Array()
		var us := PackedFloat32Array()
		var vs := PackedFloat32Array()
		var min_u := 1e9
		var max_u := -1e9
		var min_v := 1e9
		var max_v := -1e9

		for ei in num_edges:
			var se := bytes.decode_s32(sfe_ofs + (first_edge + ei) * 4)
			var vi := 0
			if se >= 0:
				vi = bytes.decode_u16(edg_ofs + se * 4)
			else:
				vi = bytes.decode_u16(edg_ofs + (-se) * 4 + 2)
			var vo := vrt_ofs + vi * 12
			var vx := bytes.decode_float(vo)
			var vy := bytes.decode_float(vo + 4)
			var vz := bytes.decode_float(vo + 8)
			pts_gd.append(gs_to_gd(vx, vy, vz) + total_offset)
			var u := vx * sx + vy * sy + vz * sz + so
			var v := vx * tx + vy * ty + vz * tz + to_off
			us.append(u)
			vs.append(v)
			min_u = minf(min_u, u)
			max_u = maxf(max_u, u)
			min_v = minf(min_v, v)
			max_v = maxf(max_v, v)

		# Colisiones (sky y clip van a sky_col_faces para no tapar el horneado de navegacion).
		if with_collision and role != "water":
			if role == "sky" or role == "clip" or (tflags & 1) != 0:
				for k in range(1, num_edges - 1):
					sky_col_faces.append(pts_gd[0])
					sky_col_faces.append(pts_gd[k])
					sky_col_faces.append(pts_gd[k + 1])
			else:
				var surf_name := String(tinfo["surf"])
				if not col_faces_by_surf.has(surf_name):
					col_faces_by_surf[surf_name] = PackedVector3Array()
				var col_arr: PackedVector3Array = col_faces_by_surf[surf_name]
				for k in range(1, num_edges - 1):
					col_arr.append(pts_gd[0])
					col_arr.append(pts_gd[k])
					col_arr.append(pts_gd[k + 1])
				col_faces_by_surf[surf_name] = col_arr

		if invisible_only or role == "sky" or role == "clip" or (tflags & 1) != 0:
			continue

		# Muestreo del lightmap radiosity de 24 bits del .bsp en cada vertice.
		var base_col: Color = tinfo["color"]
		var vcols := PackedColorArray()
		var smin := int(floor(min_u / 16.0))
		var smax := int(ceil(max_u / 16.0))
		var tmin := int(floor(min_v / 16.0))
		var tmax := int(ceil(max_v / 16.0))
		var lw := smax - smin + 1
		var lh := tmax - tmin + 1
		var valid_lm := (
			lightofs >= 0
			and lgt_len > 0
			and lw > 0
			and lh > 0
			and lw < 256
			and lh < 256
			and (lightofs + lw * lh * 3) <= lgt_len
		)

		for ei in num_edges:
			var l_rgb := Vector3(0.85, 0.85, 0.85)
			if valid_lm:
				var lu := clampi(int(roundf(us[ei] / 16.0)) - smin, 0, lw - 1)
				var lv := clampi(int(roundf(vs[ei] / 16.0)) - tmin, 0, lh - 1)
				var px_ofs := lgt_ofs + lightofs + (lv * lw + lu) * 3
				var lr := pow(clampf(float(bytes[px_ofs]) / 255.0 * 2.35, 0.0, 1.6), 0.68)
				var lg := pow(clampf(float(bytes[px_ofs + 1]) / 255.0 * 2.35, 0.0, 1.6), 0.68)
				var lb := pow(clampf(float(bytes[px_ofs + 2]) / 255.0 * 2.35, 0.0, 1.6), 0.68)
				l_rgb = Vector3(lerpf(0.42, 1.16, lr), lerpf(0.42, 1.16, lg), lerpf(0.42, 1.16, lb))
			vcols.append(
				Color(
					clampf(base_col.r * l_rgb.x, 0.06, 1.35),
					clampf(base_col.g * l_rgb.y, 0.06, 1.35),
					clampf(base_col.b * l_rgb.z, 0.06, 1.35),
					alpha_override
				)
			)

		var bucket := String(tinfo["bucket"])
		if alpha_override < 0.96 and role == "solid":
			bucket = "glass"
		if not st_by_bucket.has(bucket):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st_by_bucket[bucket] = st
			mat_by_bucket[bucket] = _material_for_bucket(bucket, base_col, wetness)
		var st_ref: SurfaceTool = st_by_bucket[bucket]
		var tw := maxf(16.0, float(tinfo["w"]))
		var th := maxf(16.0, float(tinfo["h"]))
		for k in range(1, num_edges - 1):
			for idx: int in [0, k, k + 1]:
				st_ref.set_normal(n_gd)
				st_ref.set_color(vcols[idx])
				st_ref.set_uv(Vector2(us[idx] / tw, vs[idx] / th))
				st_ref.add_vertex(pts_gd[idx])


static func _material_for_bucket(bucket: String, sample_col: Color, wetness: float) -> Material:
	match bucket:
		"water":
			var wmat := ShaderMaterial.new()
			wmat.shader = WATER_SHADER
			wmat.set_shader_parameter("shallow_color", Color(0.16, 0.34, 0.36, 0.78))
			wmat.set_shader_parameter("deep_color", Color(0.05, 0.14, 0.18, 0.92))
			return wmat
		"cutout":
			return MaterialLib.cutout_grate(Color(0.85, 0.85, 0.85))
		"glass":
			return MaterialLib.glass_pane(Color(0.68, 0.82, 0.9, 0.36))
		"emissive":
			return MaterialLib.emissive(sample_col.lightened(0.35), 2.4)
		_:
			var parts := bucket.split("_")
			var kind := parts[0]
			var variant := int(parts[1]) if parts.size() > 1 else 0
			return MaterialLib.bsp_surface(kind, variant, wetness)


static func _read_textures(bytes: PackedByteArray, tex_ofs: int, theme: String) -> Array:
	var out: Array = []
	var num_tex := bytes.decode_u32(tex_ofs)
	for ti in num_tex:
		var rel := bytes.decode_s32(tex_ofs + 4 + ti * 4)
		if rel < 0:
			out.append(
				{
					"name": "null",
					"w": 64,
					"h": 64,
					"role": "skip",
					"bucket": "plaster_0",
					"surf": "concrete",
					"color": Color(0.75, 0.75, 0.75)
				}
			)
			continue
		var to := tex_ofs + rel
		var name_slice := bytes.slice(to, mini(bytes.size(), to + 16))
		var z: int = name_slice.find(0)
		if z >= 0:
			name_slice = name_slice.slice(0, z)
		var tname := name_slice.get_string_from_ascii().to_lower()
		var tw := maxi(16, int(bytes.decode_u32(to + 16)))
		var th := maxi(16, int(bytes.decode_u32(to + 20)))
		var m0 := int(bytes.decode_u32(to + 24))
		var m3 := int(bytes.decode_u32(to + 36))

		var classified := _classify_texture(tname, theme)
		var col: Color = classified["fallback_color"]
		if m0 > 0 and m3 > 0:
			# Textura embebida en el .bsp: lee color promedio real desde el mipmap 3 (1/8).
			var mw := maxi(1, tw / 8)
			var mh := maxi(1, th / 8)
			var pix_ofs := to + m3
			var pal_ofs := pix_ofs + mw * mh + 2
			if pal_ofs + 768 <= bytes.size():
				var rs := 0.0
				var gs := 0.0
				var bs := 0.0
				var cnt := 0
				var is_cut := tname.begins_with("{")
				for py in mh:
					for px in mw:
						var pidx := int(bytes[pix_ofs + py * mw + px])
						if is_cut and pidx == 255:
							continue
						rs += float(bytes[pal_ofs + pidx * 3])
						gs += float(bytes[pal_ofs + pidx * 3 + 1])
						bs += float(bytes[pal_ofs + pidx * 3 + 2])
						cnt += 1
				if cnt > 0:
					col = Color(
						rs / float(cnt) / 255.0, gs / float(cnt) / 255.0, bs / float(cnt) / 255.0
					)
		elif BspPalette.COLORS.has(tname):
			col = BspPalette.COLORS[tname]

		# Realza ligeramente la luminancia para que luzca nitida y viva con ACES tonemapper.
		col = Color(
			clampf(pow(maxf(col.r, 0.02), 0.82) * 1.12, 0.14, 1.0),
			clampf(pow(maxf(col.g, 0.02), 0.82) * 1.12, 0.14, 1.0),
			clampf(pow(maxf(col.b, 0.02), 0.82) * 1.12, 0.14, 1.0)
		)
		var tex_entry := {
			"name": tname,
			"w": tw,
			"h": th,
			"role": classified["role"],
			"bucket": classified["bucket"],
			"surf": classified["surf"],
			"color": col,
		}
		out.append(tex_entry)
	return out


static func _classify_texture(tname: String, theme: String) -> Dictionary:
	if tname in ["aaatrigger", "trigger", "origin", "null", "hint", "skip", "bevel"]:
		return {
			"role": "skip", "bucket": "plaster_0", "surf": "concrete", "fallback_color": Color.WHITE
		}
	if tname == "sky":
		return {
			"role": "sky", "bucket": "plaster_0", "surf": "concrete", "fallback_color": Color.WHITE
		}
	if tname == "clip":
		return {
			"role": "clip", "bucket": "plaster_0", "surf": "concrete", "fallback_color": Color.WHITE
		}
	if tname.begins_with("!") or "water" in tname or "slime" in tname or "liquid" in tname:
		return {
			"role": "water",
			"bucket": "water",
			"surf": "sand",
			"fallback_color": Color(0.2, 0.42, 0.46)
		}
	if tname.begins_with("{"):
		return {
			"role": "cutout",
			"bucket": "cutout",
			"surf": "metal",
			"fallback_color": Color(0.55, 0.56, 0.54)
		}
	if "glass" in tname or "wndw" in tname:
		return {
			"role": "glass",
			"bucket": "glass",
			"surf": "concrete",
			"fallback_color": Color(0.7, 0.84, 0.9)
		}
	if (
		tname.begins_with("~")
		or "+0~" in tname
		or "+a~" in tname
		or "lght" in tname
		or "lgt" in tname
	):
		return {
			"role": "emissive",
			"bucket": "emissive",
			"surf": "metal",
			"fallback_color": Color(1.0, 0.94, 0.82)
		}

	var variant := int(absi(tname.hash())) % 2
	var kind := "concrete"
	var surf := "concrete"
	var fb := Color(0.66, 0.64, 0.58)
	if theme == "desert" or theme == "desert_night":
		fb = Color(0.78, 0.67, 0.48)
		kind = "plaster"
	elif theme == "jungle":
		fb = Color(0.52, 0.55, 0.46)
		kind = "stone"
	elif theme == "office":
		fb = Color(0.76, 0.76, 0.74)

	if "crate" in tname or "box" in tname or "crat" in tname:
		kind = "crate"
		surf = "wood"
		fb = Color(0.62, 0.45, 0.25)
	elif "wood" in tname or "wd" in tname or "plank" in tname or "pine" in tname or "desk" in tname:
		kind = "wood"
		surf = "wood"
		fb = Color(0.54, 0.36, 0.2)
	elif "brick" in tname or "brk" in tname:
		kind = "brick"
		surf = "concrete"
		fb = Color(0.64, 0.42, 0.32)
	elif "sand" in tname or "dust" in tname or "dirt" in tname or "grnd" in tname:
		kind = "sand"
		surf = "sand"
		fb = Color(0.78, 0.68, 0.48)
	elif "snow" in tname:
		kind = "snow"
		surf = "sand"
		fb = Color(0.88, 0.9, 0.94)
	elif "grss" in tname or "grass" in tname or "moss" in tname:
		kind = "grass"
		surf = "sand"
		fb = Color(0.38, 0.48, 0.28)
	elif (
		"cobb" in tname or "pave" in tname or "road" in tname or "asph" in tname or "strt" in tname
	):
		kind = "cobble"
		surf = "concrete"
		fb = Color(0.52, 0.5, 0.47)
	elif "rck" in tname or "rk" in tname or "rock" in tname or "cliff" in tname or "stone" in tname:
		kind = "stone"
		surf = "concrete"
		fb = Color(0.56, 0.54, 0.48)
	elif "tile" in tname or "flr" in tname or "marble" in tname:
		kind = "tile"
		surf = "concrete"
		fb = Color(0.7, 0.69, 0.65)
	elif "crpt" in tname or "carpet" in tname or "rug" in tname:
		kind = "carpet"
		surf = "sand"
		fb = Color(0.36, 0.4, 0.48)
	elif "roof" in tname or "shing" in tname:
		kind = "roof"
		surf = "concrete"
		fb = Color(0.62, 0.36, 0.25)
	elif "rust" in tname:
		kind = "rust"
		surf = "metal"
		fb = Color(0.52, 0.34, 0.24)
	elif (
		"metal" in tname
		or "mtl" in tname
		or "steel" in tname
		or "silo" in tname
		or "duct" in tname
		or "vent" in tname
		or "train" in tname
		or "door" in tname
		or "elev" in tname
		or "babtech" in tname
		or "lab" in tname
	):
		kind = "metal"
		surf = "metal"
		fb = Color(0.52, 0.55, 0.58)
	elif "plaster" in tname or "stucco" in tname or "wll" in tname or "wall" in tname:
		kind = "plaster"
		surf = "concrete"

	return {
		"role": "solid",
		"bucket": "%s_%d" % [kind, variant],
		"surf": surf,
		"fallback_color": fb,
	}


# --- Entidades interactivas del .bsp (rompibles, puertas, escaleras, props CS2) -


static func _build_breakable_entity(
	model_idx: int, e: Dictionary, e_orig_gd: Vector3, ctx: Dictionary, props_root: Node3D
) -> void:
	var st_map: Dictionary = {}
	var mat_map: Dictionary = {}
	var col_map: Dictionary = {}
	var sky_unused := PackedVector3Array()
	var rmode := int(e.get("rendermode", "0"))
	var ramt := int(e.get("renderamt", "255"))
	var alpha := clampf(float(ramt) / 255.0, 0.28, 1.0) if rmode != 0 else 1.0
	_append_model_faces(
		model_idx, e_orig_gd, true, false, alpha, ctx, st_map, mat_map, col_map, sky_unused
	)
	if col_map.is_empty():
		return

	var mat_code := int(e.get("material", "0"))
	var bkind := "wood"
	if mat_code == 0 or alpha < 0.92 or st_map.has("glass"):
		bkind = "glass"
	elif mat_code == 2:
		bkind = "metal"
	var hp: float = clampf(float(e.get("health", "35")), 12.0, 180.0)

	var sb := StaticBody3D.new()
	sb.name = "Breakable_%d" % model_idx
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.set_meta("surface", bkind if bkind != "glass" else "concrete")
	sb.set_meta("breakable_hp", hp)
	sb.set_meta("breakable_kind", bkind)

	var center_accum := Vector3.ZERO
	var vert_cnt := 0
	for surf in col_map.keys():
		var farr: PackedVector3Array = col_map[surf]
		for v in farr:
			center_accum += v
		vert_cnt += farr.size()
		if farr.size() >= 3:
			var cs := CollisionShape3D.new()
			var concave := ConcavePolygonShape3D.new()
			concave.backface_collision = true
			concave.set_faces(farr)
			cs.shape = concave
			sb.add_child(cs)
	if vert_cnt > 0:
		sb.set_meta("breakable_center", center_accum / float(vert_cnt))

	for bkey in st_map.keys():
		var st: SurfaceTool = st_map[bkey]
		st.generate_tangents()
		var mesh := st.commit()
		if mesh and mesh.get_surface_count() > 0:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat_map[bkey]
			sb.add_child(mi)
	props_root.add_child(sb)


static func damage_breakable(body: StaticBody3D, amount: float) -> bool:
	if body == null or not is_instance_valid(body) or not body.has_meta("breakable_hp"):
		return false
	var hp := float(body.get_meta("breakable_hp")) - amount
	body.set_meta("breakable_hp", hp)
	var bkind := String(body.get_meta("breakable_kind"))
	var center: Vector3 = body.get_meta("breakable_center", body.global_position)
	if hp <= 0.0:
		Fx.debris_burst(body.get_parent(), center, bkind, 8)
		body.queue_free()
		return true
	if bkind == "glass":
		AudioBank.play_at(
			"glass_hit", body.get_parent(), center, -5.0, randf_range(0.95, 1.1), 24.0
		)
	return false


static func _build_door_entity(
	model_idx: int,
	_e: Dictionary,
	cls: String,
	e_orig_gd: Vector3,
	ctx: Dictionary,
	props_root: Node3D
) -> Dictionary:
	var st_map: Dictionary = {}
	var mat_map: Dictionary = {}
	var col_map: Dictionary = {}
	var sky_unused := PackedVector3Array()
	_append_model_faces(
		model_idx, e_orig_gd, true, false, 1.0, ctx, st_map, mat_map, col_map, sky_unused
	)
	if col_map.is_empty():
		return {}

	var sb := StaticBody3D.new()
	sb.name = "BspDoor_%d" % model_idx
	sb.add_to_group("bsp_door")
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.set_meta("surface", "metal")

	var bmin := Vector3(1e9, 1e9, 1e9)
	var bmax := Vector3(-1e9, -1e9, -1e9)
	for surf in col_map.keys():
		var farr: PackedVector3Array = col_map[surf]
		for v in farr:
			bmin = Vector3(minf(bmin.x, v.x), minf(bmin.y, v.y), minf(bmin.z, v.z))
			bmax = Vector3(maxf(bmax.x, v.x), maxf(bmax.y, v.y), maxf(bmax.z, v.z))
		if farr.size() >= 3:
			var cs := CollisionShape3D.new()
			var concave := ConcavePolygonShape3D.new()
			concave.backface_collision = true
			concave.set_faces(farr)
			cs.shape = concave
			sb.add_child(cs)
	for bkey in st_map.keys():
		var st: SurfaceTool = st_map[bkey]
		st.generate_tangents()
		var mesh := st.commit()
		if mesh and mesh.get_surface_count() > 0:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat_map[bkey]
			sb.add_child(mi)
	props_root.add_child(sb)

	var center := (bmin + bmax) * 0.5
	var size := bmax - bmin
	var slide := Vector3(0.0, maxf(2.1, size.y * 0.92), 0.0)
	if cls == "func_door" and size.x > size.z and size.x > size.y:
		slide = Vector3(size.x * 0.88, 0.0, 0.0)
	elif cls == "func_door" and size.z >= size.x and size.z > size.y:
		slide = Vector3(0.0, 0.0, size.z * 0.88)
	return {
		"node": sb,
		"center": center,
		"closed_pos": Vector3.ZERO,
		"open_pos": slide,
		"open_t": 0.0,
		"was_open": false,
	}


static func _build_ladder_area(
	model_idx: int,
	e_orig_gd: Vector3,
	bytes: PackedByteArray,
	mod_ofs: int,
	world_offset: Vector3,
	props_root: Node3D
) -> void:
	var mo := mod_ofs + model_idx * 64
	var a := gs_to_gd(
		bytes.decode_float(mo), bytes.decode_float(mo + 4), bytes.decode_float(mo + 8)
	)
	var b := gs_to_gd(
		bytes.decode_float(mo + 12), bytes.decode_float(mo + 16), bytes.decode_float(mo + 20)
	)
	var lmin := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)) + world_offset + e_orig_gd
	var lmax := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)) + world_offset + e_orig_gd
	var area := Area3D.new()
	area.name = "Ladder_%d" % model_idx
	area.add_to_group("ladder")
	area.collision_layer = 0
	area.collision_mask = 4
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (lmax - lmin) + Vector3(0.42, 0.3, 0.42)
	cs.shape = box
	area.position = (lmin + lmax) * 0.5
	area.add_child(cs)
	area.body_entered.connect(
		func(body: Node) -> void:
			if body is Combatant:
				(body as Combatant).ladder_contacts += 1
	)
	area.body_exited.connect(
		func(body: Node) -> void:
			if body is Combatant:
				var c := body as Combatant
				c.ladder_contacts = maxi(0, c.ladder_contacts - 1)
	)
	props_root.add_child(area)


static func _spawn_cs2_props(
	ents: Array[Dictionary], world_offset: Vector3, props_root: Node3D
) -> void:
	var anchors: Array[Vector3] = []
	for e in ents:
		var cls := String(e.get("classname", ""))
		if (
			cls in ["info_player_start", "info_player_deathmatch", "hostage_entity"]
			and e.has("origin")
		):
			var gs := _parse_vec3_raw(String(e["origin"]))
			anchors.append(gs_to_gd(gs.x, gs.y, gs.z) - Vector3(0.0, 0.86, 0.0) + world_offset)
	if anchors.is_empty():
		return
	var kinds := ["crate", "barrel", "canister", "pallet"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4219
	var placed: Array[Vector3] = []
	var step := maxi(1, anchors.size() / 16)
	for i in range(0, anchors.size(), step):
		if placed.size() >= 18:
			break
		var base := anchors[i]
		var ang := rng.randf() * TAU
		var pos := base + Vector3(cos(ang) * 2.35, 0.08, sin(ang) * 2.35)
		var overlap := false
		for p in placed:
			if p.distance_to(pos) < 3.0:
				overlap = true
				break
		if overlap:
			continue
		placed.append(pos)
		var prop := PhysicsProp.new()
		var kind: String = String(kinds[placed.size() % kinds.size()])
		prop.setup_prop(kind, pos, rng.randf_range(0.0, 360.0))
		props_root.add_child(prop)
