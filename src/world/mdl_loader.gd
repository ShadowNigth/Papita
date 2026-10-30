extends RefCounted
## MdlLoader: cargador nativo y cache en memoria para modelos GoldSrc StudioModel v10 (.mdl)
## originales de Counter-Strike 1.5 (viewmodels v_*, armas p_*/w_*, soldados y rehenes).

class_name MdlLoader

const MDL_MAGIC: int = 0x54534449  # "IDST"
const MDL_VERSION: int = 10
const BASE_DIR := "res://assets/models/cs15/"

const STUDIO_NF_FLATSHADE: int = 0x0001
const STUDIO_NF_CHROME: int = 0x0002
const STUDIO_NF_FULLBRIGHT: int = 0x0004
const STUDIO_NF_ADDITIVE: int = 0x0020
const STUDIO_NF_MASKED: int = 0x0040

const VIEWMODEL_SCALE := 0.008
const ACTOR_SCALE := 0.0275
const HOSTAGE_SCALE := 0.0255
const WORLD_SCALE := 0.026

const CT_FACTIONS: Array[String] = ["urban", "gsg9", "sas", "gign"]
const T_FACTIONS: Array[String] = ["terror", "leet", "arctic", "guerilla"]

const WEAPON_STEM := {
	"knife": "knife",
	"glock18": "glock18",
	"usp45": "usp",
	"p228": "p228",
	"deagle": "deagle",
	"fiveseven": "fiveseven",
	"elite": "elite",
	"m3": "m3",
	"xm1014": "xm1014",
	"tmp": "tmp",
	"mac10": "mac10",
	"mp5": "mp5",
	"ump45": "ump45",
	"p90": "p90",
	"famas": "aug",
	"galil": "ak47",
	"ak47": "ak47",
	"m4a1": "m4a1",
	"sg552": "sg552",
	"aug": "aug",
	"scout": "scout",
	"awp": "awp",
	"g3sg1": "g3sg1",
	"sg550": "sg550",
	"m249": "m249",
	"hegrenade": "hegrenade",
	"flashbang": "flashbang",
	"smokegrenade": "smokegrenade",
	"c4": "c4",
}

const WEAPON_AIM_GROUP := {
	"knife": "knife",
	"glock18": "onehanded",
	"usp45": "onehanded",
	"p228": "onehanded",
	"deagle": "onehanded",
	"fiveseven": "onehanded",
	"elite": "dualpistols",
	"m3": "shotgun",
	"xm1014": "shotgun",
	"tmp": "onehanded",
	"mac10": "onehanded",
	"mp5": "mp5",
	"ump45": "carbine",
	"p90": "carbine",
	"famas": "carbine",
	"galil": "ak47",
	"ak47": "ak47",
	"m4a1": "carbine",
	"sg552": "ak47",
	"aug": "carbine",
	"scout": "rifle",
	"awp": "rifle",
	"g3sg1": "rifle",
	"sg550": "rifle",
	"m249": "m249",
	"hegrenade": "grenade",
	"flashbang": "grenade",
	"smokegrenade": "grenade",
	"c4": "c4",
}

static var _raw_cache: Dictionary = {}
static var _viewmodel_cache: Dictionary = {}
static var _world_cache: Dictionary = {}
static var _held_cache: Dictionary = {}
static var _actor_cache: Dictionary = {}


static func clear_caches() -> void:
	_raw_cache.clear()
	_viewmodel_cache.clear()
	_world_cache.clear()
	_held_cache.clear()
	_actor_cache.clear()


static func stem_for(weapon_id: String) -> String:
	return String(WEAPON_STEM.get(weapon_id, weapon_id))


static func aim_group_for(weapon_id: String) -> String:
	return String(WEAPON_AIM_GROUP.get(weapon_id, "carbine"))


static func viewmodel_path(weapon_id: String) -> String:
	var direct_r := BASE_DIR + "v_" + weapon_id + "_r.mdl"
	if FileAccess.file_exists(direct_r):
		return direct_r
	var direct := BASE_DIR + "v_" + weapon_id + ".mdl"
	if FileAccess.file_exists(direct):
		return direct
	var stem := stem_for(weapon_id)
	var r_path := BASE_DIR + "v_" + stem + "_r.mdl"
	if FileAccess.file_exists(r_path):
		return r_path
	return BASE_DIR + "v_" + stem + ".mdl"


static func world_weapon_path(weapon_id: String) -> String:
	var direct := BASE_DIR + "w_" + weapon_id + ".mdl"
	if FileAccess.file_exists(direct):
		return direct
	return BASE_DIR + "w_" + stem_for(weapon_id) + ".mdl"


static func held_weapon_path(weapon_id: String) -> String:
	var direct := BASE_DIR + "p_" + weapon_id + ".mdl"
	if FileAccess.file_exists(direct):
		return direct
	return BASE_DIR + "p_" + stem_for(weapon_id) + ".mdl"


# --- Conversion de coordenadas GoldSrc (+X fwd, +Y left, +Z up) -> Godot (+X right, +Y up, -Z fwd)


static func _gs_euler_to_godot_quat(rx: float, ry: float, rz: float) -> Quaternion:
	var cx := cos(rx * 0.5)
	var sx := sin(rx * 0.5)
	var cy := cos(ry * 0.5)
	var sy := sin(ry * 0.5)
	var cz := cos(rz * 0.5)
	var sz := sin(rz * 0.5)
	var qx := sx * cy * cz - cx * sy * sz
	var qy := cx * sy * cz + sx * cy * sz
	var qz := cx * cy * sz - sx * sy * cz
	var qw := cx * cy * cz + sx * sy * sz
	return Quaternion(-qy, qz, -qx, qw).normalized()


static func _gs_pos_to_godot(px: float, py: float, pz: float, scale_f: float) -> Vector3:
	return Vector3(-py * scale_f, pz * scale_f, -px * scale_f)


static func _gs_dir_to_godot(nx: float, ny: float, nz: float) -> Vector3:
	return Vector3(-ny, nz, -nx)


static func _read_cstring(data: PackedByteArray, offset: int, max_len: int) -> String:
	var end := offset
	var limit := mini(offset + max_len, data.size())
	while end < limit and data[end] != 0:
		end += 1
	if end <= offset:
		return ""
	return data.slice(offset, end).get_string_from_ascii()


# --- Parseo binario del archivo .mdl (cacheado una sola vez por ruta) ----------


static func _parse_raw(path: String) -> Dictionary:
	if _raw_cache.has(path):
		var cached: Dictionary = _raw_cache[path]
		return cached
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data: PackedByteArray = f.get_buffer(f.get_length())
	if data.size() < 244:
		return {}
	if data.decode_s32(0) != MDL_MAGIC or data.decode_s32(4) != MDL_VERSION:
		return {}

	var numbones := data.decode_s32(140)
	var boneidx := data.decode_s32(144)
	var numseq := data.decode_s32(164)
	var seqidx := data.decode_s32(168)
	var numtex := data.decode_s32(180)
	var texidx := data.decode_s32(184)
	var numskinref := data.decode_s32(192)
	var numskinfam := data.decode_s32(196)
	var skinidx := data.decode_s32(200)
	var numbp := data.decode_s32(204)
	var bpidx := data.decode_s32(208)
	var numatt := data.decode_s32(212)
	var attidx := data.decode_s32(216)

	var bones: Array[Dictionary] = []
	var used_bone_names: Dictionary = {}
	for i in numbones:
		var b := boneidx + i * 112
		if b + 112 > data.size():
			break
		var raw_name := _read_cstring(data, b, 32)
		var safe_name := raw_name
		for bad_ch in [":", "/", ".", "@", "%", "\\"]:
			safe_name = safe_name.replace(bad_ch, "_")
		if safe_name == "":
			safe_name = "bone_" + str(i)
		if used_bone_names.has(safe_name):
			safe_name = safe_name + "_" + str(i)
		used_bone_names[safe_name] = true
		var vals := PackedFloat32Array()
		var scales := PackedFloat32Array()
		vals.resize(6)
		scales.resize(6)
		for c in 6:
			vals[c] = data.decode_float(b + 64 + c * 4)
			scales[c] = data.decode_float(b + 88 + c * 4)
		var bone_entry := {
			"raw_name": raw_name,
			"name": safe_name,
			"parent": data.decode_s32(b + 32),
			"vals": vals,
			"scales": scales,
		}
		bones.append(bone_entry)

	var textures: Array[Dictionary] = []
	for i in numtex:
		var t := texidx + i * 80
		if t + 80 > data.size():
			break
		var tname := _read_cstring(data, t, 64)
		var flags := data.decode_s32(t + 64)
		var w := data.decode_s32(t + 68)
		var h := data.decode_s32(t + 72)
		var pidx := data.decode_s32(t + 76)
		var px_count := w * h
		if w <= 0 or h <= 0 or pidx < 0 or pidx + px_count + 768 > data.size():
			textures.append({"name": tname, "w": 1, "h": 1, "flags": 0, "img": null, "mat": null})
			continue
		var pal_ofs := pidx + px_count
		var lut := PackedInt32Array()
		lut.resize(256)
		var masked: bool = (flags & STUDIO_NF_MASKED) != 0
		for pi in 256:
			var r := int(data[pal_ofs + pi * 3])
			var g := int(data[pal_ofs + pi * 3 + 1])
			var bl := int(data[pal_ofs + pi * 3 + 2])
			var a := 0 if (masked and pi == 255) else 255
			lut[pi] = r | (g << 8) | (bl << 16) | (a << 24)
		var out32 := PackedInt32Array()
		out32.resize(px_count)
		for j in px_count:
			out32[j] = lut[data[pidx + j]]
		var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out32.to_byte_array())
		if not masked:
			img.generate_mipmaps()
		var gtex := ImageTexture.create_from_image(img)
		var mat := _make_mdl_material(gtex, flags)
		textures.append({"name": tname, "w": w, "h": h, "flags": flags, "img": img, "mat": mat})

	var skin_table := PackedInt32Array()
	if numskinref > 0 and numskinfam > 0 and skinidx >= 0:
		var total_skins := numskinref * numskinfam
		if skinidx + total_skins * 2 <= data.size():
			skin_table.resize(total_skins)
			for i in total_skins:
				skin_table[i] = data.decode_s16(skinidx + i * 2)

	var attachments: Array[Dictionary] = []
	for i in numatt:
		var ao := attidx + i * 88
		if ao + 88 > data.size():
			break
		var att_org := Vector3(
			data.decode_float(ao + 40), data.decode_float(ao + 44), data.decode_float(ao + 48)
		)
		var att_entry := {"bone": data.decode_s32(ao + 36), "org": att_org}
		attachments.append(att_entry)

	var seq_meta: Array[Dictionary] = []
	for i in numseq:
		var s := seqidx + i * 176
		if s + 176 > data.size():
			break
		var sm_entry := {
			"name": _read_cstring(data, s, 32),
			"fps": maxf(data.decode_float(s + 32), 1.0),
			"flags": data.decode_s32(s + 36),
			"num_frames": data.decode_s32(s + 56),
			"num_blends": maxi(data.decode_s32(s + 120), 1),
			"anim_ofs": data.decode_s32(s + 124),
			"seq_group": data.decode_s32(s + 156),
		}
		seq_meta.append(sm_entry)

	var bodyparts: Array[Dictionary] = []
	for bp in numbp:
		var bpo := bpidx + bp * 76
		if bpo + 76 > data.size():
			break
		var bp_name := _read_cstring(data, bpo, 64)
		var nummodels := data.decode_s32(bpo + 64)
		var midx := data.decode_s32(bpo + 72)
		if nummodels <= 0 or midx + 112 > data.size():
			continue
		# Submodelo 0 (por defecto en CS 1.5; omite mochila extra en bp > 0 si vacia).
		var nummesh := data.decode_s32(midx + 72)
		var meshidx := data.decode_s32(midx + 76)
		var numverts := data.decode_s32(midx + 80)
		var vinfoidx := data.decode_s32(midx + 84)
		var vertidx := data.decode_s32(midx + 88)
		var numnorms := data.decode_s32(midx + 92)
		var ninfoidx := data.decode_s32(midx + 96)
		var normidx := data.decode_s32(midx + 100)
		if numverts <= 0 or numnorms <= 0 or nummesh <= 0:
			continue
		if vertidx + numverts * 12 > data.size() or normidx + numnorms * 12 > data.size():
			continue
		var v_floats: PackedFloat32Array = (
			data.slice(vertidx, vertidx + numverts * 12).to_float32_array()
		)
		var n_floats: PackedFloat32Array = (
			data.slice(normidx, normidx + numnorms * 12).to_float32_array()
		)
		var v_bones: PackedByteArray = data.slice(vinfoidx, vinfoidx + numverts)
		var n_bones: PackedByteArray = data.slice(ninfoidx, ninfoidx + numnorms)

		var meshes: Array[Dictionary] = []
		for mi in nummesh:
			var msho := meshidx + mi * 20
			if msho + 20 > data.size():
				break
			var triidx := data.decode_s32(msho + 4)
			var skinref := data.decode_s32(msho + 8)
			var tex_i := skinref
			if skinref >= 0 and skinref < skin_table.size():
				tex_i = skin_table[skinref]
			var tw := 256.0
			var th := 256.0
			if tex_i >= 0 and tex_i < textures.size():
				tw = maxf(float(textures[tex_i]["w"]), 1.0)
				th = maxf(float(textures[tex_i]["h"]), 1.0)
			var corner_vi := PackedInt32Array()
			var corner_ni := PackedInt32Array()
			var corner_uv := PackedVector2Array()
			var p := triidx
			var end_p := data.size() - 2
			while p >= 0 and p <= end_p:
				var cmd := data.decode_s16(p)
				p += 2
				if cmd == 0:
					break
				var is_fan := cmd < 0
				var cnt := -cmd if is_fan else cmd
				if cnt <= 0 or p + cnt * 8 > data.size():
					break
				var sv_vi := PackedInt32Array()
				var sv_ni := PackedInt32Array()
				var sv_uv := PackedVector2Array()
				sv_vi.resize(cnt)
				sv_ni.resize(cnt)
				sv_uv.resize(cnt)
				for v in cnt:
					sv_vi[v] = data.decode_s16(p)
					sv_ni[v] = data.decode_s16(p + 2)
					sv_uv[v] = Vector2(
						float(data.decode_s16(p + 4)) / tw, float(data.decode_s16(p + 6)) / th
					)
					p += 8
				for v in range(2, cnt):
					var i0 := 0
					var i1 := 0
					var i2 := v
					if is_fan:
						i0 = 0
						i1 = v - 1
					elif (v % 2) == 0:
						i0 = v - 2
						i1 = v - 1
					else:
						i0 = v - 1
						i1 = v - 2
					corner_vi.append(sv_vi[i0])
					corner_vi.append(sv_vi[i1])
					corner_vi.append(sv_vi[i2])
					corner_ni.append(sv_ni[i0])
					corner_ni.append(sv_ni[i1])
					corner_ni.append(sv_ni[i2])
					corner_uv.append(sv_uv[i0])
					corner_uv.append(sv_uv[i1])
					corner_uv.append(sv_uv[i2])
			if not corner_vi.is_empty():
				var mesh_entry := {
					"tex_i": tex_i,
					"vi": corner_vi,
					"ni": corner_ni,
					"uv": corner_uv,
				}
				meshes.append(mesh_entry)
		if not meshes.is_empty():
			var bp_entry := {
				"name": bp_name,
				"v_floats": v_floats,
				"n_floats": n_floats,
				"v_bones": v_bones,
				"n_bones": n_bones,
				"meshes": meshes,
			}
			bodyparts.append(bp_entry)

	var parsed := {
		"data": data,
		"bones": bones,
		"textures": textures,
		"attachments": attachments,
		"seq_meta": seq_meta,
		"bodyparts": bodyparts,
	}
	_raw_cache[path] = parsed
	return parsed


static func _make_mdl_material(tex: Texture2D, flags: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.roughness = 0.72
	mat.metallic = 0.08
	mat.metallic_specular = 0.35
	if (flags & STUDIO_NF_CHROME) != 0:
		mat.metallic = 0.82
		mat.roughness = 0.24
		mat.metallic_specular = 0.85
	if (flags & STUDIO_NF_FULLBRIGHT) != 0:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if (flags & STUDIO_NF_ADDITIVE) != 0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	elif (flags & STUDIO_NF_MASKED) != 0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return mat


# --- Decodificacion de poses y secuencias --------------------------------------


static func _rest_local_transforms(bones: Array, scale_f: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(bones.size())
	for i in bones.size():
		var b: Dictionary = bones[i]
		var vals: PackedFloat32Array = b["vals"]
		var q := _gs_euler_to_godot_quat(vals[3], vals[4], vals[5])
		var pos := _gs_pos_to_godot(vals[0], vals[1], vals[2], scale_f)
		out[i] = Transform3D(Basis(q), pos)
	return out


static func _world_transforms(bones: Array, locals: Array[Transform3D]) -> Array[Transform3D]:
	var world: Array[Transform3D] = []
	world.resize(bones.size())
	for i in bones.size():
		var parent: int = int(bones[i]["parent"])
		if parent >= 0 and parent < i:
			world[i] = world[parent] * locals[i]
		else:
			world[i] = locals[i]
	return world


static func _decode_channel(
	data: PackedByteArray,
	anim_entry_ofs: int,
	ch_ofs: int,
	num_frames: int,
	base_v: float,
	scale_v: float
) -> PackedFloat32Array:
	var res := PackedFloat32Array()
	res.resize(num_frames)
	if ch_ofs <= 0:
		res.fill(base_v)
		return res
	var p := anim_entry_ofs + ch_ofs
	var limit := data.size() - 2
	var frame := 0
	while frame < num_frames and p <= limit:
		var valid := int(data[p])
		var total := int(data[p + 1])
		p += 2
		if total <= 0:
			break
		for t in total:
			if frame >= num_frames:
				break
			if valid == 0:
				res[frame] = base_v
			else:
				var k := t if t < valid else (valid - 1)
				var read_p := p + k * 2
				if read_p <= limit:
					res[frame] = base_v + float(data.decode_s16(read_p)) * scale_v
				else:
					res[frame] = base_v
			frame += 1
		p += valid * 2
	while frame < num_frames:
		res[frame] = base_v
		frame += 1
	return res


## Decodifica una secuencia a arreglos de posiciones/rotaciones por hueso y frame.
static func _decode_sequence_tracks(
	raw: Dictionary, seq_idx: int, scale_f: float, use_mid_blend: bool = true
) -> Dictionary:
	var seq_meta: Array = raw["seq_meta"]
	if seq_idx < 0 or seq_idx >= seq_meta.size():
		return {}
	var sm: Dictionary = seq_meta[seq_idx]
	if int(sm["seq_group"]) != 0:
		return {}
	var num_frames: int = maxi(int(sm["num_frames"]), 1)
	var num_blends: int = int(sm["num_blends"])
	var blend: int = (num_blends / 2) if use_mid_blend else 0
	var bones: Array = raw["bones"]
	var num_bones := bones.size()
	var data: PackedByteArray = raw["data"]
	var anim_base: int = int(sm["anim_ofs"]) + blend * num_bones * 12
	if anim_base < 0 or anim_base + num_bones * 12 > data.size():
		return {}

	var bone_pos_tracks: Array = []
	var bone_rot_tracks: Array = []
	bone_pos_tracks.resize(num_bones)
	bone_rot_tracks.resize(num_bones)

	for b in num_bones:
		var binfo: Dictionary = bones[b]
		var vals: PackedFloat32Array = binfo["vals"]
		var scales: PackedFloat32Array = binfo["scales"]
		var entry_ofs := anim_base + b * 12
		var ch0 := _decode_channel(
			data, entry_ofs, data.decode_u16(entry_ofs), num_frames, vals[0], scales[0]
		)
		var ch1 := _decode_channel(
			data, entry_ofs, data.decode_u16(entry_ofs + 2), num_frames, vals[1], scales[1]
		)
		var ch2 := _decode_channel(
			data, entry_ofs, data.decode_u16(entry_ofs + 4), num_frames, vals[2], scales[2]
		)
		var ch3 := _decode_channel(
			data, entry_ofs, data.decode_u16(entry_ofs + 6), num_frames, vals[3], scales[3]
		)
		var ch4 := _decode_channel(
			data, entry_ofs, data.decode_u16(entry_ofs + 8), num_frames, vals[4], scales[4]
		)
		var ch5 := _decode_channel(
			data, entry_ofs, data.decode_u16(entry_ofs + 10), num_frames, vals[5], scales[5]
		)
		var pos_arr := PackedVector3Array()
		var rot_arr: Array[Quaternion] = []
		pos_arr.resize(num_frames)
		rot_arr.resize(num_frames)
		for f in num_frames:
			pos_arr[f] = _gs_pos_to_godot(ch0[f], ch1[f], ch2[f], scale_f)
			rot_arr[f] = _gs_euler_to_godot_quat(ch3[f], ch4[f], ch5[f])
		bone_pos_tracks[b] = pos_arr
		bone_rot_tracks[b] = rot_arr

	return {
		"name": String(sm["name"]),
		"fps": float(sm["fps"]),
		"flags": int(sm["flags"]),
		"num_frames": num_frames,
		"pos": bone_pos_tracks,
		"rot": bone_rot_tracks,
	}


static func _find_seq_idx(raw: Dictionary, candidates: Array[String]) -> int:
	var seq_meta: Array = raw["seq_meta"]
	for want in candidates:
		for i in seq_meta.size():
			var sm: Dictionary = seq_meta[i]
			if int(sm["seq_group"]) == 0 and String(sm["name"]) == want:
				return i
	for want in candidates:
		for i in seq_meta.size():
			var sm: Dictionary = seq_meta[i]
			if int(sm["seq_group"]) == 0 and String(sm["name"]).begins_with(want):
				return i
	return 0 if not seq_meta.is_empty() else -1


# --- Construccion de ArrayMesh (estatico o con skinning GPU) -------------------


static func _build_array_mesh(
	raw: Dictionary,
	bone_worlds: Array[Transform3D],
	scale_f: float,
	skinned: bool,
	custom_mats: Array = [],
	bone_filter: Dictionary = {},
	only_first_bodypart: bool = true
) -> ArrayMesh:
	var arr_mesh := ArrayMesh.new()
	var bodyparts: Array = raw["bodyparts"]
	var textures: Array = raw["textures"]
	var max_bp := mini(bodyparts.size(), 1) if only_first_bodypart else bodyparts.size()

	for bp in max_bp:
		var bp_data: Dictionary = bodyparts[bp]
		var v_floats: PackedFloat32Array = bp_data["v_floats"]
		var n_floats: PackedFloat32Array = bp_data["n_floats"]
		var v_bones: PackedByteArray = bp_data["v_bones"]
		var n_bones: PackedByteArray = bp_data["n_bones"]
		var num_v := v_bones.size()
		var num_n := n_bones.size()

		var model_v := PackedVector3Array()
		var model_n := PackedVector3Array()
		model_v.resize(num_v)
		model_n.resize(num_n)
		for vi in num_v:
			var b_idx := int(v_bones[vi])
			var local_p := _gs_pos_to_godot(
				v_floats[vi * 3], v_floats[vi * 3 + 1], v_floats[vi * 3 + 2], scale_f
			)
			if b_idx >= 0 and b_idx < bone_worlds.size():
				model_v[vi] = bone_worlds[b_idx] * local_p
			else:
				model_v[vi] = local_p
		for ni in num_n:
			var nb_idx := int(n_bones[ni])
			var local_n := _gs_dir_to_godot(
				n_floats[ni * 3], n_floats[ni * 3 + 1], n_floats[ni * 3 + 2]
			)
			if nb_idx >= 0 and nb_idx < bone_worlds.size():
				model_n[ni] = (bone_worlds[nb_idx].basis * local_n).normalized()
			else:
				model_n[ni] = local_n.normalized()

		var meshes: Array = bp_data["meshes"]
		for mi in meshes.size():
			var mdata: Dictionary = meshes[mi]
			var c_vi: PackedInt32Array = mdata["vi"]
			var c_ni: PackedInt32Array = mdata["ni"]
			var c_uv: PackedVector2Array = mdata["uv"]
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var uvs := PackedVector2Array()
			var bones_arr := PackedInt32Array()
			var weights_arr := PackedFloat32Array()
			var indices := PackedInt32Array()
			var weld: Dictionary = {}

			var tri_count := c_vi.size() / 3
			for t in tri_count:
				var base_c := t * 3
				var vi0 := c_vi[base_c]
				var vi1 := c_vi[base_c + 1]
				var vi2 := c_vi[base_c + 2]
				if vi0 < 0 or vi0 >= num_v or vi1 < 0 or vi1 >= num_v or vi2 < 0 or vi2 >= num_v:
					continue
				if not bone_filter.is_empty():
					if not bone_filter.has(int(v_bones[vi0])):
						continue
				for c in 3:
					var ci := base_c + c
					var vi := c_vi[ci]
					var ni := clampi(c_ni[ci], 0, num_n - 1)
					var uv := c_uv[ci]
					var key: int = (
						(vi << 16)
						^ ni
						^ (int(roundf(uv.x * 4096.0)) * 73856093)
						^ (int(roundf(uv.y * 4096.0)) * 19349663)
					)
					if weld.has(key):
						var existing_idx: int = int(weld[key])
						var same_bone := (
							not skinned or bones_arr[existing_idx * 4] == int(v_bones[vi])
						)
						if (
							same_bone
							and uvs[existing_idx].distance_squared_to(uv) < 0.00001
							and verts[existing_idx].distance_squared_to(model_v[vi]) < 0.000001
							and norms[existing_idx].dot(model_n[ni]) > 0.98
						):
							indices.append(existing_idx)
							continue
					var new_idx := verts.size()
					verts.append(model_v[vi])
					norms.append(model_n[ni])
					uvs.append(uv)
					if skinned:
						bones_arr.append(int(v_bones[vi]))
						bones_arr.append(0)
						bones_arr.append(0)
						bones_arr.append(0)
						weights_arr.append(1.0)
						weights_arr.append(0.0)
						weights_arr.append(0.0)
						weights_arr.append(0.0)
					weld[key] = new_idx
					indices.append(new_idx)

			if indices.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = indices
			if skinned:
				arrays[Mesh.ARRAY_BONES] = bones_arr
				arrays[Mesh.ARRAY_WEIGHTS] = weights_arr
			var surf_idx := arr_mesh.get_surface_count()
			arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var tex_i: int = int(mdata["tex_i"])
			if not custom_mats.is_empty() and tex_i >= 0 and tex_i < custom_mats.size():
				arr_mesh.surface_set_material(surf_idx, custom_mats[tex_i])
			elif tex_i >= 0 and tex_i < textures.size() and textures[tex_i]["mat"] != null:
				arr_mesh.surface_set_material(surf_idx, textures[tex_i]["mat"])

	return arr_mesh


static func _make_skeleton(bones: Array, rest_locals: Array[Transform3D]) -> Skeleton3D:
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	for i in bones.size():
		var b: Dictionary = bones[i]
		skel.add_bone(String(b["name"]))
		var parent: int = int(b["parent"])
		if parent >= 0 and parent < i:
			skel.set_bone_parent(i, parent)
	for i in bones.size():
		skel.set_bone_rest(i, rest_locals[i])
	skel.reset_bone_poses()
	return skel


static func _tracks_to_animation(
	bones: Array, pos_tracks: Array, rot_tracks: Array, num_frames: int, fps: float, looped: bool
) -> Animation:
	var anim := Animation.new()
	var step := 1.0 / maxf(fps, 1.0)
	anim.length = maxf(float(maxi(num_frames - 1, 1)) * step, 0.05)
	anim.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	for b in bones.size():
		var bname := String(bones[b]["name"])
		var path := NodePath("Skeleton3D:" + bname)
		var p_arr: PackedVector3Array = pos_tracks[b]
		var r_arr: Array = rot_tracks[b]
		var pt := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(pt, path)
		anim.track_set_interpolation_type(pt, Animation.INTERPOLATION_LINEAR)
		var rt := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(rt, path)
		anim.track_set_interpolation_type(rt, Animation.INTERPOLATION_LINEAR_ANGLE)
		# Inserta claves (compactando tramos estaticos para maximo FPS).
		for f in num_frames:
			var keep_p := f == 0 or f == num_frames - 1
			if not keep_p:
				keep_p = (
					p_arr[f].distance_squared_to(p_arr[f - 1]) > 0.0000004
					or p_arr[f].distance_squared_to(p_arr[f + 1]) > 0.0000004
				)
			if keep_p:
				anim.position_track_insert_key(pt, float(f) * step, p_arr[f])
			var q_cur: Quaternion = r_arr[f]
			var keep_r := f == 0 or f == num_frames - 1
			if not keep_r:
				var q_prev: Quaternion = r_arr[f - 1]
				var q_next: Quaternion = r_arr[f + 1]
				keep_r = (absf(q_cur.dot(q_prev)) < 0.999985 or absf(q_cur.dot(q_next)) < 0.999985)
			if keep_r:
				anim.rotation_track_insert_key(rt, float(f) * step, q_cur)
	return anim


# --- 1) VIEWMODELS EN PRIMERA PERSONA (v_*.mdl) --------------------------------


static func build_viewmodel(weapon_id: String) -> Dictionary:
	var path := viewmodel_path(weapon_id)
	if not _viewmodel_cache.has(path):
		var raw := _parse_raw(path)
		if raw.is_empty():
			return {}
		var bones: Array = raw["bones"]
		var rest_locals := _rest_local_transforms(bones, VIEWMODEL_SCALE)
		var rest_worlds := _world_transforms(bones, rest_locals)
		# Materiales dedicados para viewmodel (sin proyectar sombras costosas).
		var vm_mats: Array = []
		var textures: Array = raw["textures"]
		for t in textures:
			var base_mat: StandardMaterial3D = t["mat"]
			if base_mat != null:
				var dup := base_mat.duplicate() as StandardMaterial3D
				dup.roughness = clampf(dup.roughness * 0.85, 0.18, 0.85)
				dup.metallic_specular = 0.48
				vm_mats.append(dup)
			else:
				vm_mats.append(null)
		var mesh := _build_array_mesh(raw, rest_worlds, VIEWMODEL_SCALE, true, vm_mats, {}, false)
		var lib := AnimationLibrary.new()
		var seq_names := PackedStringArray()
		var seq_meta: Array = raw["seq_meta"]
		var used_names: Dictionary = {}
		for s_idx in seq_meta.size():
			var decoded := _decode_sequence_tracks(raw, s_idx, VIEWMODEL_SCALE, false)
			if decoded.is_empty():
				continue
			var sname := String(decoded["name"])
			if used_names.has(sname):
				sname = sname + "_" + str(s_idx)
			used_names[sname] = true
			var looped := sname.begins_with("idle")
			var anim := _tracks_to_animation(
				bones,
				decoded["pos"],
				decoded["rot"],
				int(decoded["num_frames"]),
				float(decoded["fps"]),
				looped
			)
			lib.add_animation(sname, anim)
			seq_names.append(sname)
		_viewmodel_cache[path] = {
			"bones": bones,
			"rest_locals": rest_locals,
			"skin": null,
			"mesh": mesh,
			"lib": lib,
			"seqs": seq_names,
			"attachments": raw["attachments"],
		}

	var tpl: Dictionary = _viewmodel_cache[path]
	var root := Node3D.new()
	root.name = "CS15Viewmodel"
	var skel := _make_skeleton(tpl["bones"], tpl["rest_locals"])
	if tpl["skin"] == null:
		tpl["skin"] = skel.create_skin_from_rest_transforms()
	root.add_child(skel)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = tpl["mesh"]
	mi.skin = tpl["skin"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skel.add_child(mi)
	mi.skeleton = NodePath("..")

	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	var atts: Array = tpl["attachments"]
	var bones_list: Array = tpl["bones"]
	if not atts.is_empty():
		var att0: Dictionary = atts[0]
		var abone: int = int(att0["bone"])
		if abone >= 0 and abone < bones_list.size():
			var ba := BoneAttachment3D.new()
			ba.name = "MuzzleBone"
			skel.add_child(ba)
			ba.bone_idx = abone
			var org: Vector3 = att0["org"]
			muzzle.position = _gs_pos_to_godot(org.x, org.y, org.z, VIEWMODEL_SCALE)
			ba.add_child(muzzle)
		else:
			muzzle.position = Vector3(0.055, -0.035, -0.22)
			root.add_child(muzzle)
	else:
		muzzle.position = Vector3(0.055, -0.035, -0.22)
		root.add_child(muzzle)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("", tpl["lib"])

	return {
		"root": root,
		"anim_player": player,
		"muzzle": muzzle,
		"seqs": tpl["seqs"],
	}


# --- 2) ARMAS DEL MUNDO / PICKUPS / C4 / GRANADAS / MENU (w_*.mdl) -------------


static func build_world_model_from_path(
	path: String, upright: bool = false, scale_f: float = WORLD_SCALE
) -> Node3D:
	var cache_key := "%s|%.4f" % [path, scale_f]
	if not _world_cache.has(cache_key):
		var raw := _parse_raw(path)
		if raw.is_empty():
			return null
		var bones: Array = raw["bones"]
		var seq0 := _decode_sequence_tracks(raw, 0, scale_f, false)
		var locals: Array[Transform3D] = []
		if not seq0.is_empty():
			locals.resize(bones.size())
			var pos_t: Array = seq0["pos"]
			var rot_t: Array = seq0["rot"]
			for b in bones.size():
				var pa: PackedVector3Array = pos_t[b]
				var ra: Array = rot_t[b]
				locals[b] = Transform3D(Basis(ra[0]), pa[0])
		else:
			locals = _rest_local_transforms(bones, scale_f)
		var worlds := _world_transforms(bones, locals)
		var mesh := _build_array_mesh(raw, worlds, scale_f, false, [], {}, false)
		_world_cache[cache_key] = mesh

	var arr_mesh: ArrayMesh = _world_cache[cache_key]
	if arr_mesh == null or arr_mesh.get_surface_count() == 0:
		return null
	var root := Node3D.new()
	root.name = "CS15WorldModel"
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = arr_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aabb := arr_mesh.get_aabb()
	var center := aabb.position + aabb.size * 0.5
	if upright:
		# En CS 1.5 los w_*.mdl descansan de costado; los enderezamos para el escaparate 3D.
		if aabb.size.y < maxf(aabb.size.x, aabb.size.z) * 0.45:
			mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			mi.position = -(Basis.from_euler(mi.rotation) * center)
		else:
			mi.position = -center
	else:
		mi.position = Vector3(-center.x, -aabb.position.y, -center.z)
	root.add_child(mi)
	var muz := Node3D.new()
	muz.name = "Muzzle"
	muz.position = Vector3(0.0, 0.02, -maxf(aabb.size.z, aabb.size.x) * 0.5)
	root.add_child(muz)
	return root


static func build_world_weapon(weapon_id: String, upright: bool = false) -> Node3D:
	return build_world_model_from_path(world_weapon_path(weapon_id), upright, WORLD_SCALE)


static func build_world_item(item_stem: String, upright: bool = false) -> Node3D:
	var p := BASE_DIR + item_stem + ".mdl"
	if not FileAccess.file_exists(p):
		p = BASE_DIR + "w_" + item_stem + ".mdl"
	return build_world_model_from_path(p, upright, WORLD_SCALE)


# --- 3) ARMAS EN TERCERA PERSONA EN MANOS DE SOLDADOS (p_*.mdl) ----------------


static func get_held_weapon_meshes(weapon_id: String) -> Dictionary:
	var path := held_weapon_path(weapon_id)
	if _held_cache.has(path):
		var c: Dictionary = _held_cache[path]
		return c
	var raw := _parse_raw(path)
	if raw.is_empty():
		return {}
	var bones: Array = raw["bones"]
	var rest_locals := _rest_local_transforms(bones, ACTOR_SCALE)
	var rest_worlds := _world_transforms(bones, rest_locals)

	var r_hand_idx := -1
	var l_hand_idx := -1
	for i in bones.size():
		var rn := String(bones[i]["raw_name"])
		if rn == "Bip01 R Hand":
			r_hand_idx = i
		elif rn == "Bip01 L Hand":
			l_hand_idx = i

	if r_hand_idx < 0 and not bones.is_empty():
		r_hand_idx = bones.size() - 1

	var r_sub: Dictionary = {}
	var l_sub: Dictionary = {}
	for i in bones.size():
		var cur := i
		var safety := 0
		while cur >= 0 and safety < 64:
			if cur == r_hand_idx:
				r_sub[i] = true
				break
			if cur == l_hand_idx:
				l_sub[i] = true
				break
			cur = int(bones[cur]["parent"])
			safety += 1

	var r_mesh: ArrayMesh = null
	var l_mesh: ArrayMesh = null
	if r_hand_idx >= 0 and not r_sub.is_empty():
		var inv_r := rest_worlds[r_hand_idx].affine_inverse()
		var rel_r: Array[Transform3D] = []
		rel_r.resize(bones.size())
		for i in bones.size():
			rel_r[i] = inv_r * rest_worlds[i]
		r_mesh = _build_array_mesh(raw, rel_r, ACTOR_SCALE, false, [], r_sub, true)

	if l_hand_idx >= 0 and not l_sub.is_empty():
		var inv_l := rest_worlds[l_hand_idx].affine_inverse()
		var rel_l: Array[Transform3D] = []
		rel_l.resize(bones.size())
		for i in bones.size():
			rel_l[i] = inv_l * rest_worlds[i]
		l_mesh = _build_array_mesh(raw, rel_l, ACTOR_SCALE, false, [], l_sub, true)

	var out := {"r_mesh": r_mesh, "l_mesh": l_mesh}
	_held_cache[path] = out
	return out


# --- 4) SOLDADOS CS 1.5, REHENES Y ZOMBIES CON SKELETON3D + ANIMATIONPLAYER ----


static func _compose_upper_lower_animation(
	bones: Array,
	upper_mask: Dictionary,
	lower_seq: Dictionary,
	upper_seq: Dictionary,
	looped: bool,
	zombie_pose: bool = false
) -> Animation:
	if lower_seq.is_empty():
		return Animation.new()
	var nf: int = int(lower_seq["num_frames"])
	var fps: float = float(lower_seq["fps"])
	var l_pos: Array = lower_seq["pos"]
	var l_rot: Array = lower_seq["rot"]
	var u_pos: Array = upper_seq.get("pos", l_pos)
	var u_rot: Array = upper_seq.get("rot", l_rot)
	var u_nf: int = int(upper_seq.get("num_frames", nf))

	var merged_pos: Array = []
	var merged_rot: Array = []
	merged_pos.resize(bones.size())
	merged_rot.resize(bones.size())

	for b in bones.size():
		if upper_mask.has(b) and not upper_seq.is_empty():
			var out_p := PackedVector3Array()
			var out_r: Array[Quaternion] = []
			out_p.resize(nf)
			out_r.resize(nf)
			var up_b: PackedVector3Array = u_pos[b]
			var ur_b: Array = u_rot[b]
			var bname := String(bones[b]["raw_name"])
			var extra_q := Quaternion.IDENTITY
			if zombie_pose:
				if bname == "Bip01 Spine1":
					extra_q = Quaternion.from_euler(Vector3(0.0, 0.0, -0.22))
				elif bname == "Bip01 L UpperArm" or bname == "Bip01 R UpperArm":
					extra_q = Quaternion.from_euler(Vector3(0.0, 0.35, -0.45))
			for f in nf:
				var uf := f % maxi(u_nf, 1)
				out_p[f] = up_b[uf]
				var q_base: Quaternion = ur_b[uf]
				out_r[f] = (q_base * extra_q).normalized() if zombie_pose else q_base
			merged_pos[b] = out_p
			merged_rot[b] = out_r
		else:
			merged_pos[b] = l_pos[b]
			merged_rot[b] = l_rot[b]

	return _tracks_to_animation(bones, merged_pos, merged_rot, nf, fps, looped)


static func _make_zombie_materials(raw: Dictionary, z_color: Color) -> Array:
	var mats: Array = []
	var textures: Array = raw["textures"]
	for t in textures:
		var src_img: Image = t["img"]
		if src_img == null:
			mats.append(null)
			continue
		var z_img := src_img.duplicate() as Image
		z_img.decompress()
		var w := z_img.get_width()
		var h := z_img.get_height()
		# Tinte necrotico + manchas de sangre sobre la textura original CS 1.5.
		for y in h:
			for x in w:
				var c := z_img.get_pixel(x, y)
				var lum := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
				var zc := Color(
					lerpf(c.r * 0.55, z_color.r * (0.45 + lum * 0.9), 0.62),
					lerpf(c.g * 0.55, z_color.g * (0.45 + lum * 0.9), 0.62),
					lerpf(c.b * 0.5, z_color.b * (0.45 + lum * 0.85), 0.62),
					c.a
				)
				var hval: int = ((x * 73856093) ^ (y * 19349663)) & 1023
				if hval < 22 and y > h / 5 and y < (h * 4) / 5:
					zc = zc.lerp(Color(0.38, 0.04, 0.03, c.a), 0.72)
				z_img.set_pixel(x, y, zc)
		z_img.generate_mipmaps()
		var gtex := ImageTexture.create_from_image(z_img)
		var mat := _make_mdl_material(gtex, int(t["flags"]))
		mat.roughness = 0.86
		mats.append(mat)
	return mats


static func _get_actor_template(
	path: String, is_hostage: bool, is_zombie: bool, z_color: Color
) -> Dictionary:
	var color_key := (
		"%02x%02x%02x" % [int(z_color.r * 255.0), int(z_color.g * 255.0), int(z_color.b * 255.0)]
		if is_zombie
		else "std"
	)
	var cache_key := (
		"%s|%d|%d|%s" % [path, 1 if is_hostage else 0, 1 if is_zombie else 0, color_key]
	)
	if _actor_cache.has(cache_key):
		var c: Dictionary = _actor_cache[cache_key]
		return c

	var raw := _parse_raw(path)
	if raw.is_empty():
		return {}
	var scale_f := HOSTAGE_SCALE if is_hostage else ACTOR_SCALE
	var bones: Array = raw["bones"]
	var rest_locals := _rest_local_transforms(bones, scale_f)
	var rest_worlds := _world_transforms(bones, rest_locals)
	var custom_mats: Array = _make_zombie_materials(raw, z_color) if is_zombie else []
	var mesh := _build_array_mesh(raw, rest_worlds, scale_f, true, custom_mats, {}, true)

	var upper_mask: Dictionary = {}
	for i in bones.size():
		var rn := String(bones[i]["raw_name"])
		var p_idx: int = int(bones[i]["parent"])
		if rn.contains("Spine") or (p_idx >= 0 and upper_mask.has(p_idx)):
			upper_mask[i] = true

	var lib := AnimationLibrary.new()
	if is_hostage:
		var s_idle := _decode_sequence_tracks(raw, _find_seq_idx(raw, ["idle1", "idle3"]), scale_f)
		var s_walk := _decode_sequence_tracks(
			raw, _find_seq_idx(raw, ["walk", "walk_scared"]), scale_f
		)
		var s_run := _decode_sequence_tracks(raw, _find_seq_idx(raw, ["run", "run1"]), scale_f)
		var s_crouch := _decode_sequence_tracks(raw, _find_seq_idx(raw, ["crouch_idle"]), scale_f)
		var s_die := _decode_sequence_tracks(
			raw, _find_seq_idx(raw, ["diesimple", "dieforward"]), scale_f
		)
		if not s_idle.is_empty():
			lib.add_animation(
				"idle",
				_tracks_to_animation(
					bones,
					s_idle["pos"],
					s_idle["rot"],
					int(s_idle["num_frames"]),
					float(s_idle["fps"]),
					true
				)
			)
		if not s_walk.is_empty():
			lib.add_animation(
				"walk",
				_tracks_to_animation(
					bones,
					s_walk["pos"],
					s_walk["rot"],
					int(s_walk["num_frames"]),
					float(s_walk["fps"]),
					true
				)
			)
		if not s_run.is_empty():
			lib.add_animation(
				"run",
				_tracks_to_animation(
					bones,
					s_run["pos"],
					s_run["rot"],
					int(s_run["num_frames"]),
					float(s_run["fps"]),
					true
				)
			)
		if not s_crouch.is_empty():
			lib.add_animation(
				"crouch_idle",
				_tracks_to_animation(
					bones,
					s_crouch["pos"],
					s_crouch["rot"],
					int(s_crouch["num_frames"]),
					float(s_crouch["fps"]),
					true
				)
			)
		if not s_die.is_empty():
			lib.add_animation(
				"death1",
				_tracks_to_animation(
					bones,
					s_die["pos"],
					s_die["rot"],
					int(s_die["num_frames"]),
					float(s_die["fps"]),
					false
				)
			)
	else:
		var l_idle := _decode_sequence_tracks(raw, _find_seq_idx(raw, ["idle1"]), scale_f)
		var l_walk := _decode_sequence_tracks(raw, _find_seq_idx(raw, ["walk"]), scale_f)
		var l_run := _decode_sequence_tracks(raw, _find_seq_idx(raw, ["run"]), scale_f)
		var l_crouch_idle := _decode_sequence_tracks(
			raw, _find_seq_idx(raw, ["crouch_idle"]), scale_f
		)
		var l_crouch_run := _decode_sequence_tracks(raw, _find_seq_idx(raw, ["crouchrun"]), scale_f)
		var l_jump := _decode_sequence_tracks(raw, _find_seq_idx(raw, ["jump"]), scale_f)
		var s_death := _decode_sequence_tracks(
			raw, _find_seq_idx(raw, ["death1", "death2"]), scale_f
		)
		var s_head := _decode_sequence_tracks(raw, _find_seq_idx(raw, ["head", "death3"]), scale_f)

		if is_zombie:
			var u_z := _decode_sequence_tracks(
				raw, _find_seq_idx(raw, ["ref_aim_knife", "ref_aim_dualpistols"]), scale_f, true
			)
			lib.add_animation(
				"zombie_idle",
				_compose_upper_lower_animation(bones, upper_mask, l_idle, u_z, true, true)
			)
			lib.add_animation(
				"zombie_walk",
				_compose_upper_lower_animation(bones, upper_mask, l_walk, u_z, true, true)
			)
			lib.add_animation(
				"zombie_run",
				_compose_upper_lower_animation(bones, upper_mask, l_run, u_z, true, true)
			)
		else:
			var u_rifle := _decode_sequence_tracks(
				raw, _find_seq_idx(raw, ["ref_aim_carbine", "ref_aim_ak47"]), scale_f, true
			)
			var u_c_rifle := _decode_sequence_tracks(
				raw, _find_seq_idx(raw, ["crouch_aim_carbine", "crouch_aim_ak47"]), scale_f, true
			)
			var u_pistol := _decode_sequence_tracks(
				raw, _find_seq_idx(raw, ["ref_aim_onehanded"]), scale_f, true
			)
			var u_c_pistol := _decode_sequence_tracks(
				raw, _find_seq_idx(raw, ["crouch_aim_onehanded"]), scale_f, true
			)
			var u_knife := _decode_sequence_tracks(
				raw, _find_seq_idx(raw, ["ref_aim_knife"]), scale_f, true
			)
			var u_dual := _decode_sequence_tracks(
				raw, _find_seq_idx(raw, ["ref_aim_dualpistols"]), scale_f, true
			)

			lib.add_animation(
				"idle_rifle",
				_compose_upper_lower_animation(bones, upper_mask, l_idle, u_rifle, true)
			)
			lib.add_animation(
				"walk_rifle",
				_compose_upper_lower_animation(bones, upper_mask, l_walk, u_rifle, true)
			)
			lib.add_animation(
				"run_rifle", _compose_upper_lower_animation(bones, upper_mask, l_run, u_rifle, true)
			)
			lib.add_animation(
				"crouch_idle_rifle",
				_compose_upper_lower_animation(bones, upper_mask, l_crouch_idle, u_c_rifle, true)
			)
			lib.add_animation(
				"crouch_run_rifle",
				_compose_upper_lower_animation(bones, upper_mask, l_crouch_run, u_c_rifle, true)
			)
			lib.add_animation(
				"idle_pistol",
				_compose_upper_lower_animation(bones, upper_mask, l_idle, u_pistol, true)
			)
			lib.add_animation(
				"walk_pistol",
				_compose_upper_lower_animation(bones, upper_mask, l_walk, u_pistol, true)
			)
			lib.add_animation(
				"run_pistol",
				_compose_upper_lower_animation(bones, upper_mask, l_run, u_pistol, true)
			)
			lib.add_animation(
				"crouch_idle_pistol",
				_compose_upper_lower_animation(bones, upper_mask, l_crouch_idle, u_c_pistol, true)
			)
			lib.add_animation(
				"crouch_run_pistol",
				_compose_upper_lower_animation(bones, upper_mask, l_crouch_run, u_c_pistol, true)
			)
			lib.add_animation(
				"idle_knife",
				_compose_upper_lower_animation(bones, upper_mask, l_idle, u_knife, true)
			)
			lib.add_animation(
				"run_knife", _compose_upper_lower_animation(bones, upper_mask, l_run, u_knife, true)
			)
			lib.add_animation(
				"idle_dual", _compose_upper_lower_animation(bones, upper_mask, l_idle, u_dual, true)
			)
			lib.add_animation(
				"run_dual", _compose_upper_lower_animation(bones, upper_mask, l_run, u_dual, true)
			)
			if not l_jump.is_empty():
				lib.add_animation(
					"jump",
					_compose_upper_lower_animation(bones, upper_mask, l_jump, u_rifle, false)
				)

		if not s_death.is_empty():
			lib.add_animation(
				"death1",
				_tracks_to_animation(
					bones,
					s_death["pos"],
					s_death["rot"],
					int(s_death["num_frames"]),
					float(s_death["fps"]),
					false
				)
			)
		if not s_head.is_empty():
			lib.add_animation(
				"head",
				_tracks_to_animation(
					bones,
					s_head["pos"],
					s_head["rot"],
					int(s_head["num_frames"]),
					float(s_head["fps"]),
					false
				)
			)

	var r_hand_idx := -1
	var l_hand_idx := -1
	var head_idx := -1
	for i in bones.size():
		var rn := String(bones[i]["raw_name"])
		if rn == "Bip01 R Hand":
			r_hand_idx = i
		elif rn == "Bip01 L Hand":
			l_hand_idx = i
		elif rn == "Bip01 Head":
			head_idx = i

	var tpl := {
		"bones": bones,
		"rest_locals": rest_locals,
		"skin": null,
		"mesh": mesh,
		"lib": lib,
		"r_hand_idx": r_hand_idx,
		"l_hand_idx": l_hand_idx,
		"head_idx": head_idx,
		"stand_y": 0.0 if is_hostage else (36.7 * scale_f),
		"crouch_y": 0.0 if is_hostage else (18.0 * scale_f),
	}
	_actor_cache[cache_key] = tpl
	return tpl


static func build_actor(
	team_id: int,
	is_zombie: bool,
	is_hostage: bool,
	z_color: Color = Color(0.4, 0.5, 0.35),
	variant_seed: int = 0
) -> Dictionary:
	var path := BASE_DIR + "hostage.mdl"
	if not is_hostage:
		var pool: Array[String] = T_FACTIONS
		if team_id == Content.TEAM_CT and not is_zombie:
			pool = CT_FACTIONS
		var fac := pool[absi(variant_seed) % pool.size()]
		path = BASE_DIR + "player/%s/%s.mdl" % [fac, fac]

	var tpl := _get_actor_template(path, is_hostage, is_zombie, z_color)
	if tpl.is_empty():
		return {}

	var root := Node3D.new()
	root.name = "CS15Actor"
	var skel := _make_skeleton(tpl["bones"], tpl["rest_locals"])
	if tpl["skin"] == null:
		tpl["skin"] = skel.create_skin_from_rest_transforms()
	skel.position.y = float(tpl["stand_y"])
	root.add_child(skel)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = tpl["mesh"]
	mi.skin = tpl["skin"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	skel.add_child(mi)
	mi.skeleton = NodePath("..")

	var r_attach: BoneAttachment3D = null
	var r_idx: int = int(tpl["r_hand_idx"])
	if r_idx >= 0:
		r_attach = BoneAttachment3D.new()
		r_attach.name = "RightHand"
		skel.add_child(r_attach)
		r_attach.bone_idx = r_idx

	var l_attach: BoneAttachment3D = null
	var l_idx: int = int(tpl["l_hand_idx"])
	if l_idx >= 0:
		l_attach = BoneAttachment3D.new()
		l_attach.name = "LeftHand"
		skel.add_child(l_attach)
		l_attach.bone_idx = l_idx

	if is_zombie and int(tpl["head_idx"]) >= 0:
		var h_attach := BoneAttachment3D.new()
		h_attach.name = "ZombieEyes"
		skel.add_child(h_attach)
		h_attach.bone_idx = int(tpl["head_idx"])
		var eye_mat := MaterialLib.emissive(Color(1.0, 0.38, 0.08), 3.2)
		for side in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.016
			sph.height = 0.032
			sph.radial_segments = 6
			sph.rings = 4
			eye.mesh = sph
			eye.material_override = eye_mat
			eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			eye.position = Vector3(side * 0.035, 0.03, -0.11)
			h_attach.add_child(eye)

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("", tpl["lib"])

	return {
		"root": root,
		"skeleton": skel,
		"anim_player": player,
		"r_hand": r_attach,
		"l_hand": l_attach,
		"stand_y": float(tpl["stand_y"]),
		"crouch_y": float(tpl["crouch_y"]),
	}
