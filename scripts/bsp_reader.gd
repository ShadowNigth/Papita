class_name BspReader
extends RefCounted
## Lector de mapas GoldSrc v30 (.bsp) de Counter-Strike 1.5.
##
## Extrae lo necesario para reconstruir el mapa en Godot:
##   * geometria (vertices, aristas, caras, texinfo)
##   * texturas miptex (con paleta de 256 colores)
##   * lightmaps horneados por radiosidad (lump 8)
##   * entidades (spawns, bomb targets, rehenes, luces, puertas)
##
## La logica de offsets esta contrastada con `tools/cs15_validate.py` (misma
## implementacion en Python) contra los 10 mapas del repositorio.
##
## Estructura del header: version (int32) + 15 lumps de (offset, length).

const LUMP_ENTIDADES := 0
const LUMP_PLANOS := 1
const LUMP_TEXTURAS := 2
const LUMP_VERTICES := 3
const LUMP_NODOS := 5
const LUMP_TEXINFO := 6
const LUMP_CARAS := 7
const LUMP_LUZ := 8
const LUMP_HOJAS := 10
const LUMP_MARKSURF := 11
const LUMP_ARISTAS := 12
const LUMP_SURFEDGES := 13
const LUMP_MODELOS := 14

const TAM_TEXINFO := 40
const TAM_CARA := 20

var ruta: String = ""
var version: int = 0
var datos: PackedByteArray = PackedByteArray()
var lumps_ofs: PackedInt32Array = PackedInt32Array()
var lumps_len: PackedInt32Array = PackedInt32Array()

var entidades: Array[Dictionary] = []
var vertices: PackedVector3Array = PackedVector3Array()
var aristas: PackedInt32Array = PackedInt32Array()      # pares de indices de vertice
var surfedges: PackedInt32Array = PackedInt32Array()

# texinfo: 8 floats por cara (s: 4, t: 4) + indices
var texinfo_s: PackedFloat32Array = PackedFloat32Array()
var texinfo_t: PackedFloat32Array = PackedFloat32Array()
var texinfo_miptex: PackedInt32Array = PackedInt32Array()

# caras
var cara_plano: PackedInt32Array = PackedInt32Array()
var cara_firstedge: PackedInt32Array = PackedInt32Array()
var cara_numedges: PackedInt32Array = PackedInt32Array()
var cara_texinfo: PackedInt32Array = PackedInt32Array()
var cara_lightofs: PackedInt32Array = PackedInt32Array()

# texturas
var texturas: Array[Dictionary] = []
var luz_ofs: int = 0
var luz_len: int = 0

# --- arbol BSP para saber si un punto es solido (lo usan los bots) ---------
# planos: normal (3 floats) + dist + tipo; nodos: plano + 2 hijos; hojas:
# contenido. Es lo que respondia `SV_PointContents` en GoldSrc.
var planos_normal: PackedVector3Array = PackedVector3Array()
var planos_dist: PackedFloat32Array = PackedFloat32Array()
var nodos_plano: PackedInt32Array = PackedInt32Array()
var nodos_hijos: PackedInt32Array = PackedInt32Array()      # 2 por nodo
var hojas_contenido: PackedInt32Array = PackedInt32Array()
var cara_lado: PackedInt32Array = PackedInt32Array()
## Vertices en unidades GoldSrc (sin convertir): el grafo de navegacion razona
## en las unidades del original y convierte al final.
var vertices_goldsrc: PackedVector3Array = PackedVector3Array()
var mundo_primera_cara: int = 0
var mundo_num_caras: int = 0

var errores: Array[String] = []
## Brush models (lump 14). El lump NO lleva contador: son dmodel_t de 64 bytes
## seguidos. El modelo 0 es el mundo; el resto son los "model *N" de las
## entidades (zonas de bomba, buyzones, puertas...).
var modelos: Array[AABB] = []
var modelos_goldsrc: Array[AABB] = []


static func cargar(ruta_bsp: String, paleta: CsPalette) -> BspReader:
	var b := BspReader.new()
	b.ruta = ruta_bsp
	b._leer(paleta)
	return b


func _leer(paleta: CsPalette) -> void:
	if not FileAccess.file_exists(ruta):
		errores.append("no existe el fichero")
		return
	datos = FileAccess.get_file_as_bytes(ruta)
	if datos.size() < 124:
		errores.append("fichero demasiado corto")
		return

	version = datos.decode_s32(0)
	if version != 30:
		errores.append("version %d (se esperaba 30)" % version)

	lumps_ofs.resize(15)
	lumps_len.resize(15)
	for i in 15:
		lumps_ofs[i] = datos.decode_s32(4 + i * 8)
		lumps_len[i] = datos.decode_s32(8 + i * 8)
		if lumps_ofs[i] < 0 or lumps_len[i] < 0 or lumps_ofs[i] + lumps_len[i] > datos.size():
			errores.append("lump %d fuera de rango" % i)

	_leer_entidades()
	_leer_modelos()
	_leer_vertices()
	_leer_texinfo()
	_leer_texturas(paleta)
	_leer_caras()
	_leer_arbol()

	luz_ofs = lumps_ofs[LUMP_LUZ]
	luz_len = lumps_len[LUMP_LUZ]


# --- entidades -------------------------------------------------------------
func _leer_entidades() -> void:
	var bruto := _trozo(LUMP_ENTIDADES)
	var texto := ""
	var fin := bruto.size()
	for i in bruto.size():
		if bruto[i] == 0:
			fin = i
			break
	texto = bruto.slice(0, fin).get_string_from_ascii()

	var actual := {}
	for linea_sucia in texto.split("\n"):
		var linea := linea_sucia.strip_edges()
		if linea == "{":
			actual = {}
		elif linea == "}":
			if not actual.is_empty():
				entidades.append(actual)
			actual = {}
		elif linea.begins_with("\""):
			var trozos := linea.split("\"")
			if trozos.size() >= 4:
				actual[trozos[1]] = trozos[3]


func entidades_de(clase: String) -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	for e in entidades:
		if String(e.get("classname", "")) == clase:
			salida.append(e)
	return salida


func puntos_de_aparicion() -> Array[Vector3]:
	var salida: Array[Vector3] = []
	for clase in ["info_player_start", "info_player_deathmatch"]:
		for e in entidades_de(clase):
			salida.append(origin_de(e))
	if salida.is_empty():
		# algunos mapas usan los especificos de equipo
		for clase in ["info_player_terrorist", "info_player_counterterrorist"]:
			for e in entidades_de(clase):
				salida.append(origin_de(e))
	return salida


static func origin_de(e: Dictionary) -> Vector3:
	var partes := String(e.get("origin", "0 0 0")).split(" ", false)
	if partes.size() < 3:
		return Vector3.ZERO
	# GoldSrc: +X este, +Y norte, +Z arriba. Godot: +X este, +Y arriba, -Z norte.
	return Vector3(float(partes[0]), float(partes[2]), -float(partes[1])) * BspReader.ESCALA


const ESCALA := 0.025


# --- brush models y zonas ---------------------------------------------------
func _leer_modelos() -> void:
	var ofs := lumps_ofs[LUMP_MODELOS]
	var ln := lumps_len[LUMP_MODELOS]
	if ofs <= 0 or ln < 64:
		return
	var n := ln / 64
	for i in n:
		var base := ofs + i * 64
		var mn := Vector3(datos.decode_float(base), datos.decode_float(base + 4),
			datos.decode_float(base + 8))
		var mx := Vector3(datos.decode_float(base + 12), datos.decode_float(base + 16),
			datos.decode_float(base + 20))
		modelos_goldsrc.append(AABB(mn, mx - mn))
		# Al invertir el eje Y de GoldSrc, las esquinas cambian de orden; un AABB
		# de Godot necesita posición mínima y tamaño no negativo.
		var ga := _a_godot(mn)
		var gb := _a_godot(mx)
		var gmin := Vector3(minf(ga.x, gb.x), minf(ga.y, gb.y), minf(ga.z, gb.z))
		var gmax := Vector3(maxf(ga.x, gb.x), maxf(ga.y, gb.y), maxf(ga.z, gb.z))
		modelos.append(AABB(gmin, gmax - gmin))


## Convierte un punto de GoldSrc a coordenadas de Godot (sin escalar; la escala
## ya la aplican los vertices). GoldSrc: +Z arriba, +Y norte.
static func _a_godot(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y) * ESCALA


## Caja de una entidad brush ("model" "*N"), en coordenadas de Godot.
func caja_entidad(e: Dictionary) -> AABB:
	var texto := String(e.get("model", ""))
	if not texto.begins_with("*"):
		return AABB()
	var idx := int(texto.substr(1))
	if idx < 0 or idx >= modelos.size():
		return AABB()
	return modelos[idx]


## Caja sin conversión de ejes (unidades GoldSrc), para navegación y parsing.
func caja_entidad_goldsrc(e: Dictionary) -> AABB:
	var texto := String(e.get("model", ""))
	if not texto.begins_with("*"):
		return AABB()
	var idx := int(texto.substr(1))
	if idx < 0 or idx >= modelos_goldsrc.size():
		return AABB()
	return modelos_goldsrc[idx]


## Zonas de una clase ("func_bomb_target", "func_buyzone",
## "func_hostage_rescue") como [{nombre, caja}].
func zonas(clase: String) -> Array[Dictionary]:
	var salida: Array[Dictionary] = []
	var n := 0
	for e in entidades_de(clase):
		var caja := caja_entidad(e)
		if caja.size == Vector3.ZERO:
			continue
		n += 1
		salida.append({
			"nombre": String(e.get("targetname", "%s%d" % [clase, n])),
			"caja": caja,
		})
	return salida


## Indice de la zona que contiene el punto, o -1. Estatica a proposito: quien
## pregunta (el director de partida) ya tiene la lista de zonas, no el BSP.
static func posicion_en_zona(pos: Vector3, lista: Array[Dictionary]) -> int:
	for i in lista.size():
		var caja: AABB = lista[i]["caja"]
		if caja.has_point(pos):
			return i
	return -1


# --- geometria -------------------------------------------------------------
func _leer_vertices() -> void:
	var bruto := _trozo(LUMP_VERTICES)
	var n := bruto.size() / 12
	vertices.resize(n)
	vertices_goldsrc.resize(n)
	for i in n:
		var o := i * 12
		var g := Vector3(bruto.decode_float(o), bruto.decode_float(o + 4),
			bruto.decode_float(o + 8))
		vertices_goldsrc[i] = g
		vertices[i] = _a_godot(g)


func _leer_texinfo() -> void:
	var bruto := _trozo(LUMP_TEXINFO)
	var n := bruto.size() / TAM_TEXINFO
	texinfo_s.resize(n * 4)
	texinfo_t.resize(n * 4)
	texinfo_miptex.resize(n)
	for i in n:
		var o := i * TAM_TEXINFO
		for k in 4:
			texinfo_s[i * 4 + k] = bruto.decode_float(o + k * 4)
			texinfo_t[i * 4 + k] = bruto.decode_float(o + 16 + k * 4)
		texinfo_miptex[i] = bruto.decode_s32(o + 32)


func _leer_texturas(paleta: CsPalette) -> void:
	var ofs := lumps_ofs[LUMP_TEXTURAS]
	var n := datos.decode_s32(ofs)
	if n <= 0 or n > 4096:
		errores.append("numero de texturas raro: %d" % n)
		return
	for i in n:
		var rel := datos.decode_s32(ofs + 4 + i * 4)
		var base := ofs + rel
		if base + 40 > datos.size():
			continue
		var nombre := datos.slice(base, base + 16).get_string_from_ascii()
		var ancho := datos.decode_s32(base + 16)
		var alto := datos.decode_s32(base + 20)
		var mip0 := datos.decode_s32(base + 24)
		var tex := {
			"nombre": nombre,
			"ancho": ancho,
			"alto": alto,
			"externa": mip0 == -1,
			"imagen": null,
			"color_medio": Color(0.55, 0.5, 0.45),
		}
		if mip0 != -1 and ancho > 0 and alto > 0 and ancho * alto < 4194304:
			var ini := base + mip0
			if ini + ancho * alto <= datos.size():
				var indices := datos.slice(ini, ini + ancho * alto)
				var img: Image = paleta.indices_a_imagen(indices, ancho, alto) as Image
				tex["imagen"] = img
				tex["color_medio"] = _color_medio(img)
		texturas.append(tex)


func _color_medio(img: Image) -> Color:
	# Muestreo disperso: 64 puntos bastan para saber de que color es la textura.
	var acum := Color(0, 0, 0, 1)
	var n := 0
	var paso_x: int = maxi(1, img.get_width() / 8)
	var paso_y: int = maxi(1, img.get_height() / 8)
	var y := 0
	while y < img.get_height():
		var x := 0
		while x < img.get_width():
			acum += img.get_pixel(x, y)
			n += 1
			x += paso_x
		y += paso_y
	if n == 0:
		return Color(0.55, 0.5, 0.45)
	return Color(acum.r / n, acum.g / n, acum.b / n)


func _leer_caras() -> void:
	var bruto := _trozo(LUMP_CARAS)
	var n := bruto.size() / TAM_CARA
	cara_plano.resize(n)
	cara_firstedge.resize(n)
	cara_numedges.resize(n)
	cara_texinfo.resize(n)
	cara_lightofs.resize(n)
	cara_lado.resize(n)
	for i in n:
		var o := i * TAM_CARA
		cara_plano[i] = bruto.decode_s16(o)
		cara_lado[i] = bruto.decode_s16(o + 2)
		cara_firstedge[i] = bruto.decode_s32(o + 4)
		cara_numedges[i] = bruto.decode_s16(o + 8)
		cara_texinfo[i] = bruto.decode_s16(o + 10)
		cara_lightofs[i] = bruto.decode_s32(o + 16)

	var bruto_surf := _trozo(LUMP_SURFEDGES)
	surfedges.resize(bruto_surf.size() / 4)
	for i in surfedges.size():
		surfedges[i] = bruto_surf.decode_s32(i * 4)

	var bruto_ar := _trozo(LUMP_ARISTAS)
	var na := bruto_ar.size() / 4
	aristas.resize(na * 2)
	for i in na:
		aristas[i * 2] = bruto_ar.decode_u16(i * 4)
		aristas[i * 2 + 1] = bruto_ar.decode_u16(i * 4 + 2)


## Lee planos (lump 1), nodos (lump 5) y hojas (lump 10), y saca del modelo 0
## el rango de caras del mundo. Con eso `contenido()` responde en O(profundidad)
## si un punto es solido, igual que hacia el motor original.
func _leer_arbol() -> void:
	var bruto_p := _trozo(LUMP_PLANOS)
	var np := bruto_p.size() / 20
	planos_normal.resize(np)
	planos_dist.resize(np)
	for i in np:
		var o := i * 20
		planos_normal[i] = Vector3(bruto_p.decode_float(o), bruto_p.decode_float(o + 4),
			bruto_p.decode_float(o + 8))
		planos_dist[i] = bruto_p.decode_float(o + 12)

	var bruto_n := _trozo(LUMP_NODOS)
	var nn := bruto_n.size() / 24
	nodos_plano.resize(nn)
	nodos_hijos.resize(nn * 2)
	for i in nn:
		var o := i * 24
		nodos_plano[i] = bruto_n.decode_s32(o)
		nodos_hijos[i * 2] = bruto_n.decode_s16(o + 4)
		nodos_hijos[i * 2 + 1] = bruto_n.decode_s16(o + 6)

	var bruto_h := _trozo(LUMP_HOJAS)
	var nh := bruto_h.size() / 28
	hojas_contenido.resize(nh)
	for i in nh:
		hojas_contenido[i] = bruto_h.decode_s32(i * 28)

	# dmodel_t 0: firstface/numfaces van en los bytes 56 y 60.
	if not modelos.is_empty():
		var base := lumps_ofs[LUMP_MODELOS]
		mundo_primera_cara = datos.decode_s32(base + 56)
		mundo_num_caras = datos.decode_s32(base + 60)


## Contenido del punto, en coordenadas de Godot: -1 vacio, -2 solido,
## -3 agua. Los puntos fuera del mapa son solidos, como en el original.
func contenido(p: Vector3) -> int:
	var g := _a_goldsrc(p)
	return contenido_goldsrc(g)


## Igual que `contenido()` pero en unidades GoldSrc (lo usa el grafo de
## navegacion, que razona en las unidades del original).
func contenido_goldsrc(p: Vector3) -> int:
	if planos_normal.is_empty() or nodos_hijos.is_empty():
		return -1
	var nodo := 0
	var guardas := 0
	while nodo >= 0:
		var plano := nodos_plano[nodo]
		if plano < 0 or plano >= planos_normal.size():
			return -1
		var n := planos_normal[plano]
		var d := n.dot(p) - planos_dist[plano]
		nodo = nodos_hijos[nodo * 2] if d >= 0.0 else nodos_hijos[nodo * 2 + 1]
		guardas += 1
		if guardas > 4096:
			return -1        # arbol corrupto: se trata como vacio
	var hoja := -nodo - 1
	if hoja < 0 or hoja >= hojas_contenido.size():
		return -1
	return hojas_contenido[hoja]


## Pasa un punto de Godot a las unidades del original (inversa de `_a_godot`).
static func _a_goldsrc(p: Vector3) -> Vector3:
	return Vector3(p.x / ESCALA, -p.z / ESCALA, p.y / ESCALA)


## Indices de vertice de una cara, en orden (puede ser un poligono).
func indices_cara(cara: int) -> PackedInt32Array:
	var salida := PackedInt32Array()
	var ini := cara_firstedge[cara]
	var n := cara_numedges[cara]
	for k in n:
		var se := surfedges[ini + k]
		var ar := absi(se)
		if ar * 2 + 1 >= aristas.size():
			continue
		salida.append(aristas[ar * 2] if se >= 0 else aristas[ar * 2 + 1])
	return salida


## Coordenadas de textura y de lightmap de un vertice de una cara.
func uv_de(cara: int, vertice: Vector3) -> Vector2:
	var ti := cara_texinfo[cara]
	if ti < 0 or ti * 4 + 3 >= texinfo_s.size():
		return Vector2.ZERO
	var gs := Vector3(vertice.x, -vertice.z, vertice.y) / ESCALA  # de vuelta a unidades GoldSrc
	var u := gs.x * texinfo_s[ti * 4] + gs.y * texinfo_s[ti * 4 + 1] + gs.z * texinfo_s[ti * 4 + 2] + texinfo_s[ti * 4 + 3]
	var v := gs.x * texinfo_t[ti * 4] + gs.y * texinfo_t[ti * 4 + 1] + gs.z * texinfo_t[ti * 4 + 2] + texinfo_t[ti * 4 + 3]
	var tex := texturas[clampi(texinfo_miptex[ti], 0, texturas.size() - 1)]
	var ancho: int = maxi(1, int(tex["ancho"]))
	var alto: int = maxi(1, int(tex["alto"]))
	return Vector2(u / ancho, v / alto)


## Caja de lightmap de una cara en luxeles: devuelve [min_s, min_t, ancho, alto].
func caja_lightmap(cara: int) -> Rect2i:
	var ti := cara_texinfo[cara]
	var idx := indices_cara(cara)
	if idx.is_empty() or ti < 0 or ti * 4 + 3 >= texinfo_s.size():
		return Rect2i()
	var min_s := INF
	var min_t := INF
	var max_s := -INF
	var max_t := -INF
	for i in idx:
		var vertice := vertices[i]
		var gs := Vector3(vertice.x, -vertice.z, vertice.y) / ESCALA
		var s := gs.x * texinfo_s[ti * 4] + gs.y * texinfo_s[ti * 4 + 1] + gs.z * texinfo_s[ti * 4 + 2] + texinfo_s[ti * 4 + 3]
		var t := gs.x * texinfo_t[ti * 4] + gs.y * texinfo_t[ti * 4 + 1] + gs.z * texinfo_t[ti * 4 + 2] + texinfo_t[ti * 4 + 3]
		min_s = minf(min_s, s)
		min_t = minf(min_t, t)
		max_s = maxf(max_s, s)
		max_t = maxf(max_t, t)
	var bs := int(floor(min_s / 16.0))
	var bt := int(floor(min_t / 16.0))
	var ancho := int(ceil(max_s / 16.0)) - bs + 1
	var alto := int(ceil(max_t / 16.0)) - bt + 1
	return Rect2i(bs, bt, maxi(1, ancho), maxi(1, alto))


## Pixels de luz de una cara (ancho*alto*3 bytes en RGB), o vacio si no tiene.
func luz_cara(cara: int, caja: Rect2i) -> PackedByteArray:
	var off := cara_lightofs[cara]
	if off < 0 or caja.size.x <= 0 or caja.size.y <= 0:
		return PackedByteArray()
	var n := caja.size.x * caja.size.y * 3
	var ini := luz_ofs + off
	if ini + n > datos.size():
		return PackedByteArray()
	return datos.slice(ini, ini + n)


## Posicion de un vertice de la cara en coordenadas de luxel (para UV2).
func uv_lightmap(cara: int, vertice: Vector3, caja: Rect2i) -> Vector2:
	var ti := cara_texinfo[cara]
	var gs := Vector3(vertice.x, -vertice.z, vertice.y) / ESCALA
	var s := gs.x * texinfo_s[ti * 4] + gs.y * texinfo_s[ti * 4 + 1] + gs.z * texinfo_s[ti * 4 + 2] + texinfo_s[ti * 4 + 3]
	var t := gs.x * texinfo_t[ti * 4] + gs.y * texinfo_t[ti * 4 + 1] + gs.z * texinfo_t[ti * 4 + 2] + texinfo_t[ti * 4 + 3]
	return Vector2((s / 16.0 - caja.position.x) / caja.size.x,
		(t / 16.0 - caja.position.y) / caja.size.y)


func _trozo(lump: int) -> PackedByteArray:
	var ofs := lumps_ofs[lump]
	var ln := lumps_len[lump]
	if ofs < 0 or ln <= 0 or ofs + ln > datos.size():
		return PackedByteArray()
	return datos.slice(ofs, ofs + ln)


func resumen() -> String:
	return "%s: %d vert, %d caras, %d texturas, %d entidades (%s)" % [
		ruta.get_file(), vertices.size(), cara_texinfo.size(), texturas.size(),
		entidades.size(), ", ".join(errores) if not errores.is_empty() else "sin errores"]
