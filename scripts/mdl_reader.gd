class_name MdlReader
extends RefCounted
## Lector de modelos StudioModel v10 (.mdl) de Counter-Strike 1.5.
##
## Devuelve un `ArrayMesh` por modelo (una superficie por malla, con su textura)
## y los metadatos: huesos, secuencias y caja de colision.
##
## Detalles del formato que cuestan caro si se ignoran (todos comprobados contra
## los 96 modelos del repositorio y contra el codigo del motor Xash3D):
##
##  * `mstudiomesh_t.triindex` es un offset **absoluto** desde el inicio del
##    fichero, no relativo a la malla.
##  * Cada vertice de los comandos de triangulos ocupa **4 shorts**:
##    (indice, indice_normal, s, t). Leerlo como un short por vertice descoloca
##    todo a partir del segundo triangulo.
##  * Los vertices estan en espacio **local del hueso**: hay que aplicarles la
##    matriz de la pose de reposo (bind pose) componiendo la jerarquia.
##  * `mstudiobone_t.scale[]` es el factor de compresion de los controladores
##    (1/256), **no** una escala de la matriz. Multiplicarla colapsa el modelo.

const MAGIC := "IDST"
const VERSION := 10

var ruta: String = ""
var nombre: String = ""
var datos: PackedByteArray = PackedByteArray()
var paleta: CsPalette

var huesos: Array[Dictionary] = []
var secuencias: Array[Dictionary] = []
var texturas: Array[Dictionary] = []
var bind_pose: Array[Transform3D] = []
var bind_pose_local: Array[Transform3D] = []

var numbodyparts: int = 0
var bodypartindex: int = 0
var min_size: Vector3 = Vector3.ZERO
var max_size: Vector3 = Vector3.ZERO

var errores: Array[String] = []


static func cargar(ruta_mdl: String, pal: CsPalette) -> MdlReader:
	var m := MdlReader.new()
	m.paleta = pal
	m.ruta = ruta_mdl
	m._leer()
	return m


func _leer() -> void:
	if not FileAccess.file_exists(ruta):
		errores.append("no existe: " + ruta)
		return
	datos = FileAccess.get_file_as_bytes(ruta)
	if datos.size() < 244:
		errores.append("fichero demasiado corto")
		return

	var magic := datos.slice(0, 4).get_string_from_ascii()
	var version := datos.decode_s32(4)
	if magic != MAGIC:
		errores.append("magic %s != IDST" % magic)
	if version != VERSION:
		errores.append("version %d != 10" % version)

	nombre = datos.slice(8, 72).get_string_from_ascii()
	min_size = Vector3(datos.decode_float(88), datos.decode_float(92), datos.decode_float(96))
	max_size = Vector3(datos.decode_float(100), datos.decode_float(104), datos.decode_float(108))

	var numbones := datos.decode_s32(140)
	var boneindex := datos.decode_s32(144)
	var numseq := datos.decode_s32(164)
	var seqindex := datos.decode_s32(168)
	var numtex := datos.decode_s32(180)
	var textureindex := datos.decode_s32(184)
	numbodyparts = datos.decode_s32(204)
	bodypartindex = datos.decode_s32(208)

	_leer_huesos(numbones, boneindex)
	_calcular_bind_pose()
	_construir_poses_locales()
	_leer_secuencias(numseq, seqindex)
	_leer_texturas(numtex, textureindex)


func _leer_huesos(n: int, base0: int) -> void:
	for i in mini(n, 512):
		var b := base0 + i * 112
		if b + 112 > datos.size():
			break
		var pos := Vector3(datos.decode_float(b + 64), datos.decode_float(b + 68), datos.decode_float(b + 72))
		var rot := Vector3(datos.decode_float(b + 76), datos.decode_float(b + 80), datos.decode_float(b + 84))
		var esc := Vector3(datos.decode_float(b + 88), datos.decode_float(b + 92), datos.decode_float(b + 96))
		var esc_rot := Vector3(datos.decode_float(b + 100), datos.decode_float(b + 104), datos.decode_float(b + 108))
		huesos.append({
			"nombre": datos.slice(b, b + 32).get_string_from_ascii(),
			"padre": datos.decode_s32(b + 32),
			"pos": pos,
			"rot": rot,
			"esc_pos": esc,
			"esc_rot": esc_rot,
		})


## Compone la jerarquia de huesos en la pose de reposo.
func _calcular_bind_pose() -> void:
	bind_pose.clear()
	for i in huesos.size():
		var h: Dictionary = huesos[i]
		var pos: Vector3 = h["pos"]
		var rot: Vector3 = h["rot"]
		# Usar el mismo orden de ángulos GoldSrc que en las poses animadas y
		# en bind_pose_local; Basis.from_euler usa el orden Euler de Godot.
		var t := Transform3D(Basis(_cuaternion(rot)), pos)
		var padre: int = h["padre"]
		if padre >= 0 and padre < bind_pose.size():
			t = bind_pose[padre] * t
		bind_pose.append(t)


func _leer_secuencias(n: int, base0: int) -> void:
	for i in mini(n, 2048):
		var b := base0 + i * 176
		if b + 176 > datos.size():
			break
		# mstudioseqdesc_t (176 B): label[32] fps@32 flags@36 activity@40 ...
		# numframes@56 ... numblends@120 animindex@124 (offset absoluto)
		secuencias.append({
			"nombre": datos.slice(b, b + 32).get_string_from_ascii(),
			"fps": datos.decode_float(b + 32),
			"flags": datos.decode_s32(b + 36),
			"cuadros": datos.decode_s32(b + 56),
			"blends": datos.decode_s32(b + 120),
			"animindex": datos.decode_s32(b + 124),
		})


func _leer_texturas(n: int, base0: int) -> void:
	for i in mini(n, 64):
		var b := base0 + i * 80
		if b + 80 > datos.size():
			break
		var ancho := datos.decode_s32(b + 68)
		var alto := datos.decode_s32(b + 72)
		var idx := datos.decode_s32(b + 76)
		var tex := {
			"nombre": datos.slice(b, b + 64).get_string_from_ascii(),
			"ancho": ancho,
			"alto": alto,
			"imagen": null,
		}
		if idx > 0 and idx < datos.size() and ancho > 0 and alto > 0 and ancho * alto < 4194304:
			var fin_pixeles: int = idx + ancho * alto
			if fin_pixeles <= datos.size():
				var indices := datos.slice(idx, fin_pixeles)
				var paleta_textura := PackedColorArray()
				# A diferencia de los miptex de BSP, cada textura StudioModel
				# lleva su tabla RGB de 256 colores inmediatamente después de
				# los píxeles indexados (768 bytes por textura).
				if fin_pixeles + 256 * 3 <= datos.size():
					paleta_textura.resize(256)
					for color_idx in 256:
						var color_ofs: int = fin_pixeles + color_idx * 3
						paleta_textura[color_idx] = Color8(datos[color_ofs], datos[color_ofs + 1], datos[color_ofs + 2])
				tex["imagen"] = paleta.indices_a_imagen(indices, ancho, alto, paleta_textura)
		texturas.append(tex)


## Construye el modelo en pose de reposo. Una superficie por malla.
func construir_malla() -> ArrayMesh:
	var malla := ArrayMesh.new()
	if datos.is_empty():
		return malla

	for bp in mini(numbodyparts, 32):
		var b := bodypartindex + bp * 76
		if b + 76 > datos.size():
			continue
		var nummodels := datos.decode_s32(b + 64)
		var modelindex := datos.decode_s32(b + 72)
		for mo in mini(nummodels, 32):
			var mbase := modelindex + mo * 112
			if mbase + 112 > datos.size():
				continue
			var nummesh := datos.decode_s32(mbase + 72)
			var meshindex := datos.decode_s32(mbase + 76)
			var numverts := datos.decode_s32(mbase + 80)
			var vertinfo := datos.decode_s32(mbase + 84)
			var vertindex := datos.decode_s32(mbase + 88)
			if numverts <= 0 or numverts > 65535 or vertindex + numverts * 12 > datos.size():
				continue
			for m in mini(nummesh, 256):
				var mb := meshindex + m * 20
				if mb + 20 > datos.size():
					continue
				var numtris := datos.decode_s32(mb)
				var triindex := datos.decode_s32(mb + 4)
				var skinref := datos.decode_s32(mb + 8)
				_anadir_superficie(malla, numtris, triindex, vertindex,
					vertinfo, numverts, skinref)
	return malla


func _anadir_superficie(malla: ArrayMesh, numtris: int, triindex: int,
		vertindex: int, vertinfo: int, numverts: int, skinref: int) -> void:
	if triindex <= 0 or triindex >= datos.size() or numtris <= 0:
		return
	var tex: Dictionary = texturas[clampi(skinref, 0, maxi(0, texturas.size() - 1))] if not texturas.is_empty() else {}
	var ancho: float = maxf(1.0, float(tex.get("ancho", 1)))
	var alto: float = maxf(1.0, float(tex.get("alto", 1)))

	var vertices := PackedVector3Array()
	vertices.resize(numverts)
	for i in numverts:
		var o := vertindex + i * 12
		var v := Vector3(datos.decode_float(o), datos.decode_float(o + 4), datos.decode_float(o + 8))
		var hueso := 0
		if vertinfo + i < datos.size():
			hueso = datos[vertinfo + i]
		if hueso < bind_pose.size():
			v = bind_pose[hueso] * v
		vertices[i] = v

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var agregados := 0
	var normal := Vector3.UP
	var pos := triindex
	var hechos := 0
	while hechos < numtris and pos + 2 <= datos.size():
		var cnt := datos.decode_s16(pos)
		pos += 2
		if cnt == 0:
			break
		var n := absi(cnt)
		if n < 3 or pos + n * 8 > datos.size():
			break
		var idx := PackedInt32Array()
		var uvs := PackedVector2Array()
		for k in n:
			var o := pos + k * 8
			idx.append(datos.decode_s16(o))
			uvs.append(Vector2(datos.decode_s16(o + 4) / ancho, datos.decode_s16(o + 6) / alto))
		pos += n * 8
		if cnt < 0:
			for k in range(1, n - 1):
				agregados += _emitir(st, vertices, uvs, idx[0], idx[k], idx[k + 1], normal)
				hechos += 1
		else:
			for k in range(2, n):
				if k % 2 == 0:
					agregados += _emitir(st, vertices, uvs, idx[k - 2], idx[k - 1], idx[k], normal)
				else:
					agregados += _emitir(st, vertices, uvs, idx[k - 1], idx[k - 2], idx[k], normal)
				hechos += 1

	if agregados == 0:
		return
	st.generate_normals()
	malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = false
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	if tex.get("imagen") != null:
		var it := ImageTexture.create_from_image(tex["imagen"] as Image)
		material.albedo_texture = it
	malla.surface_set_material(malla.get_surface_count() - 1, material)


## Anade un triangulo y devuelve cuantos vertices se escribieron (0 si se
## descarta porque algun indice se sale de rango).
func _emitir(st: SurfaceTool, vertices: PackedVector3Array, uvs: PackedVector2Array,
		a: int, b: int, c: int, normal: Vector3) -> int:
	if a < 0 or b < 0 or c < 0:
		return 0
	if a >= vertices.size() or b >= vertices.size() or c >= vertices.size():
		return 0
	if a >= uvs.size() or b >= uvs.size() or c >= uvs.size():
		return 0
	for par in [[a, uvs[a]], [b, uvs[b]], [c, uvs[c]]]:
		st.set_normal(normal)
		st.set_uv(par[1])
		st.add_vertex(vertices[par[0]])
	return 3



# ---------------------------------------------------------------------------
# Animacion: equivale a R_StudioCalcBones + SV_StudioSetupBones del motor.
# ---------------------------------------------------------------------------

## Lee un canal RLE de animacion y devuelve los dos valores a interpolar.
## Port literal de R_StudioCalcBones (public/xash3d_mathlib.c de Xash3D).
func _canal(base: int, cuadro: int) -> Vector2i:
	if base < 0 or base + 2 > datos.size():
		return Vector2i.ZERO
	var pos := base
	var valid := datos[pos]
	var total := datos[pos + 1]
	var j := cuadro
	if total < valid:
		j = 0
	while total <= j and pos + 2 < datos.size():
		j -= total
		pos += (valid + 1) * 2
		if pos + 2 > datos.size():
			return Vector2i.ZERO
		valid = datos[pos]
		total = datos[pos + 1]
		if total < valid:
			j = 0

	var v1 := 0
	var v2 := 0
	if valid > j:
		v1 = _short(pos + (j + 1) * 2)
		if valid > j + 1:
			v2 = _short(pos + (j + 2) * 2)
		elif total > j + 1:
			v2 = v1
		else:
			v2 = _short(pos + (valid + 2) * 2)
	else:
		v1 = _short(pos + valid * 2)
		if total > j + 1:
			v2 = v1
		else:
			v2 = _short(pos + (valid + 2) * 2)
	return Vector2i(v1, v2)


func _short(pos: int) -> int:
	if pos < 0 or pos + 2 > datos.size():
		return 0
	return datos.decode_s16(pos)


## Valor (posicion o rotacion) de un canal de un hueso, interpolado.
## Devuelve (valor_cuadro_a, valor_cuadro_b) en unidades del modelo / radianes.
func _canal_hueso(hueso: int, panim: int, canal: int, cuadro: int) -> Vector2:
	var off := datos.decode_u16(panim + canal * 2)
	var h: Dictionary = huesos[hueso]
	var base: float = 0.0
	var escala: float = 1.0
	if canal < 3:
		base = (h["pos"] as Vector3)[canal]
		escala = (h["esc_pos"] as Vector3)[canal]
	else:
		base = (h["rot"] as Vector3)[canal - 3]
		escala = (h["esc_rot"] as Vector3)[canal - 3]
	if off == 0:
		return Vector2(base, base)
	var crudo := _canal(panim + off, cuadro)
	return Vector2(base + crudo.x * escala, base + crudo.y * escala)


## Cuaternion desde (pitch, yaw, roll) EN RADIANES, como AngleQuaternion(studio=true).
static func _cuaternion(angulos: Vector3) -> Quaternion:
	var sp := sin(angulos.x * 0.5)
	var cp := cos(angulos.x * 0.5)
	var sy := sin(angulos.y * 0.5)
	var cy := cos(angulos.y * 0.5)
	var sr := sin(angulos.z * 0.5)
	var cr := cos(angulos.z * 0.5)
	return Quaternion(
		sr * cp * cy - cr * sp * sy,
		cr * sp * cy + sr * cp * sy,
		cr * cp * sy - sr * sp * cy,
		cr * cp * cy + sr * sp * sy)


## Transform LOCAL de cada hueso para la secuencia y el cuadro (con decimales).
## El resultado se aplica con `Skeleton3D.set_bone_pose`.
func pose(secuencia: int, cuadro: float) -> Array[Transform3D]:
	var salida: Array[Transform3D] = []
	if secuencia < 0 or secuencia >= secuencias.size() or huesos.is_empty():
		return bind_pose_local.duplicate()

	var desc: Dictionary = secuencias[secuencia]
	var total := maxi(1, int(desc["cuadros"]))
	var f := fmod(maxf(cuadro, 0.0), float(total))
	var entero := int(f)
	var s := f - float(entero)
	var tabla := int(desc["animindex"])

	for i in huesos.size():
		var panim := tabla + i * 12           # un mstudioanim_t (6 uint16) por hueso
		if tabla <= 0 or panim + 12 > datos.size():
			salida.append(bind_pose_local[i] if i < bind_pose_local.size() else Transform3D())
			continue
		# Se recogen los pares (cuadro A, cuadro B) de los 6 canales: 3 de
		# posicion y 3 de rotacion, todos en el mismo orden que el motor.
		var pa := PackedFloat32Array()
		var pb := PackedFloat32Array()
		var ra := PackedFloat32Array()
		var rb := PackedFloat32Array()
		for c in 3:
			var v := _canal_hueso(i, panim, c, entero)
			pa.append(v.x)
			pb.append(v.y)
			var w := _canal_hueso(i, panim, c + 3, entero)
			ra.append(w.x)
			rb.append(w.y)
		var pos_a := Vector3(pa[0], pa[1], pa[2])
		var pos_b := Vector3(pb[0], pb[1], pb[2])
		var rot_a := _cuaternion(Vector3(ra[0], ra[1], ra[2]))
		var rot_b := _cuaternion(Vector3(rb[0], rb[1], rb[2]))
		salida.append(Transform3D(Basis(rot_a.slerp(rot_b, s)), pos_a.lerp(pos_b, s)))
	return salida


## Poses locales de reposo (una por hueso), para el Skeleton3D.
func _construir_poses_locales() -> void:
	bind_pose_local.clear()
	for h in huesos:
		bind_pose_local.append(Transform3D(Basis(_cuaternion(h["rot"])), h["pos"]))


## Esqueleto listo para Godot, con la misma jerarquia que el .mdl.
func construir_esqueleto() -> Skeleton3D:
	var esq := Skeleton3D.new()
	if bind_pose_local.is_empty():
		_construir_poses_locales()
	for i in huesos.size():
		var h: Dictionary = huesos[i]
		esq.add_bone(String(h["nombre"]))
		esq.set_bone_parent(i, int(h["padre"]))
		esq.set_bone_rest(i, bind_pose_local[i])
		esq.reset_bone_pose(i)
	return esq


## Malla con huesos y pesos por vertice (1 hueso por vertice, como el original).
## Los vertices van en espacio de modelo en reposo: `create_skin_from_rest_transforms`
## calcula los binds a partir de ahi y Godot hace el skinning en la GPU.
func construir_malla_animada() -> ArrayMesh:
	var malla := ArrayMesh.new()
	if datos.is_empty():
		return malla
	for bp in mini(numbodyparts, 32):
		var b := bodypartindex + bp * 76
		if b + 76 > datos.size():
			continue
		var nummodels := datos.decode_s32(b + 64)
		var modelindex := datos.decode_s32(b + 72)
		for mo in mini(nummodels, 32):
			var mbase := modelindex + mo * 112
			if mbase + 112 > datos.size():
				continue
			var nummesh := datos.decode_s32(mbase + 72)
			var meshindex := datos.decode_s32(mbase + 76)
			var numverts := datos.decode_s32(mbase + 80)
			var vertinfo := datos.decode_s32(mbase + 84)
			var vertindex := datos.decode_s32(mbase + 88)
			if numverts <= 0 or numverts > 65535 or vertindex + numverts * 12 > datos.size():
				continue
			for m in mini(nummesh, 256):
				var mb := meshindex + m * 20
				if mb + 20 > datos.size():
					continue
				_anadir_superficie_animada(malla, datos.decode_s32(mb), datos.decode_s32(mb + 4),
					vertindex, vertinfo, numverts, datos.decode_s32(mb + 8))
	return malla


func _anadir_superficie_animada(malla: ArrayMesh, numtris: int, triindex: int,
		vertindex: int, vertinfo: int, numverts: int, skinref: int) -> void:
	if triindex <= 0 or triindex >= datos.size() or numtris <= 0:
		return
	var tex: Dictionary = {}
	if not texturas.is_empty():
		tex = texturas[clampi(skinref, 0, texturas.size() - 1)]
	var ancho: float = maxf(1.0, float(tex.get("ancho", 1)))
	var alto: float = maxf(1.0, float(tex.get("alto", 1)))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var pos := triindex
	var hechos := 0
	var agregados := 0
	while hechos < numtris and pos + 2 <= datos.size():
		var cnt := datos.decode_s16(pos)
		pos += 2
		if cnt == 0:
			break
		var n := absi(cnt)
		if n < 3 or pos + n * 8 > datos.size():
			break
		var idx := PackedInt32Array()
		var uvs := PackedVector2Array()
		for k in n:
			var o := pos + k * 8
			idx.append(datos.decode_s16(o))
			uvs.append(Vector2(datos.decode_s16(o + 4) / ancho, datos.decode_s16(o + 6) / alto))
		pos += n * 8
		# `tri` guarda índices locales del comando, no índices de vértice:
		# así cada UV sigue emparejada con su vértice al expandir tiras/fans.
		var tri := PackedInt32Array()
		if cnt < 0:
			for k in range(1, n - 1):
				tri.append_array(PackedInt32Array([0, k, k + 1]))
				hechos += 1
		else:
			for k in range(2, n):
				if k % 2 == 0:
					tri.append_array(PackedInt32Array([k - 2, k - 1, k]))
				else:
					tri.append_array(PackedInt32Array([k - 1, k - 2, k]))
				hechos += 1
		for t in range(0, tri.size(), 3):
			var ia: int = tri[t]
			var ib: int = tri[t + 1]
			var ic: int = tri[t + 2]
			var a: int = idx[ia]
			var bb: int = idx[ib]
			var cc: int = idx[ic]
			if minf(minf(a, bb), cc) < 0 or maxf(maxf(a, bb), cc) >= numverts:
				continue
			for esquina in range(3):
				var indice_uv: int = tri[t + esquina]
				var vi: int = idx[indice_uv]
				var o: int = vertindex + vi * 12
				var v := Vector3(datos.decode_float(o), datos.decode_float(o + 4), datos.decode_float(o + 8))
				var hueso := 0
				if vertinfo + vi < datos.size():
					hueso = datos[vertinfo + vi]
				# a espacio de modelo en reposo (el Skin se encarga del resto)
				if hueso < bind_pose.size():
					v = bind_pose[hueso] * v
				st.set_bones(PackedInt32Array([hueso, 0, 0, 0]))
				st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
				st.set_uv(uvs[indice_uv])
				st.add_vertex(v)
				agregados += 1
	if agregados == 0:
		return
	st.generate_normals()
	malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())

	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	if tex.get("imagen") != null:
		material.albedo_texture = ImageTexture.create_from_image(tex["imagen"] as Image)
	malla.surface_set_material(malla.get_surface_count() - 1, material)


func indice_secuencia(nombre_buscado: String) -> int:
	for i in secuencias.size():
		if String(secuencias[i]["nombre"]) == nombre_buscado:
			return i
	return -1


func lista_secuencias() -> PackedStringArray:
	var salida := PackedStringArray()
	for s in secuencias:
		salida.append(String(s["nombre"]))
	return salida


func caja() -> AABB:
	if min_size == Vector3.ZERO and max_size == Vector3.ZERO:
		return AABB(Vector3(-8, -8, 0), Vector3(16, 16, 72))
	return AABB(min_size, max_size - min_size)


func resumen() -> String:
	return "%s: %d huesos, %d seq, %d texturas%s" % [
		ruta.get_file(), huesos.size(), secuencias.size(), texturas.size(),
		"" if errores.is_empty() else "  ERRORES: " + ", ".join(errores)]
