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
	_leer_secuencias(numseq, seqindex)
	_leer_texturas(numtex, textureindex)


func _leer_huesos(n: int, base0: int) -> void:
	for i in mini(n, 512):
		var b := base0 + i * 112
		if b + 112 > datos.size():
			break
		huesos.append({
			"nombre": datos.slice(b, b + 32).get_string_from_ascii(),
			"padre": datos.decode_s32(b + 32),
			"pos": Vector3(datos.decode_float(b + 64), datos.decode_float(b + 68), datos.decode_float(b + 72)),
			"rot": Vector3(datos.decode_float(b + 76), datos.decode_float(b + 80), datos.decode_float(b + 84)),
		})


## Compone la jerarquia de huesos en la pose de reposo.
func _calcular_bind_pose() -> void:
	bind_pose.clear()
	for i in huesos.size():
		var h: Dictionary = huesos[i]
		var pos: Vector3 = h["pos"]
		var rot: Vector3 = h["rot"]
		var t := Transform3D(Basis.from_euler(rot), pos)
		var padre: int = h["padre"]
		if padre >= 0 and padre < bind_pose.size():
			t = bind_pose[padre] * t
		bind_pose.append(t)


func _leer_secuencias(n: int, base0: int) -> void:
	for i in mini(n, 2048):
		var b := base0 + i * 176
		if b + 176 > datos.size():
			break
		secuencias.append({
			"nombre": datos.slice(b, b + 32).get_string_from_ascii(),
			"fps": datos.decode_float(b + 32),
			"cuadros": datos.decode_s32(b + 36),
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
			if idx + ancho * alto <= datos.size():
				var indices := datos.slice(idx, idx + ancho * alto)
				tex["imagen"] = paleta.indices_a_imagen(indices, ancho, alto)
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
	var idx_prev := PackedInt32Array()
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
		idx_prev = idx

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


func caja() -> AABB:
	if min_size == Vector3.ZERO and max_size == Vector3.ZERO:
		return AABB(Vector3(-8, -8, 0), Vector3(16, 16, 72))
	return AABB(min_size, max_size - min_size)


func resumen() -> String:
	return "%s: %d huesos, %d seq, %d texturas%s" % [
		ruta.get_file(), huesos.size(), secuencias.size(), texturas.size(),
		"" if errores.is_empty() else "  ERRORES: " + ", ".join(errores)]
