class_name NavGrid
extends RefCounted
## Grafo de navegación construido desde el propio `.bsp`.
##
## No es un NavMesh inventado encima del mapa: sale de los datos que el
## original ya trae, igual que hacía el motor.
##
## * **Sólido o no**: el árbol BSP (planos, nodos y hojas) responde en
##   O(profundidad) si un punto está dentro de una pared. Es lo que hacía
##   `SV_PointContents`.
## * **Dónde se puede pisar**: las caras del modelo 0 cuya normal mira hacia
##   arriba, muestreadas cada `PASO` unidades. Cada muestra se acepta solo si
##   cabe el actor de pie (comprobando 8 puntos alrededor a la altura del pecho
##   y el hueco de la cabeza).
## * **Cómo se conecta**: nodos vecinos con desnivel menor que `DESNIVEL_MAX`
##   (escalones y rampas), sin pared en medio. Las escaleras de mano se añaden
##   como transiciones verticales aparte, desde los `func_ladder` del mapa.
##
## Todo el cálculo va en **unidades GoldSrc**, como el motor; la conversión a
## metros se hace al devolver el camino. El espejo en Python
## (`tools/nav_validate.py`) valida este mismo algoritmo contra los 10 mapas.

const PASO := 40.0             # separación de muestras: 1 m
const RADIO_ACTOR := 16.0      # radio de la cápsula del jugador (32 u de diámetro)
const ALTURA_PECHO := 20.0     # altura de la comprobación de cuerpo
const ALTURA_CABEZA := 58.0    # altura de la comprobación de cabeza
const DESNIVEL_MAX := 40.0     # escalón máximo entre dos nodos
const MARGEN_ESCALERA := 72.0
const TOLERANCIA_ESCALERA_Z := 64.0
const ALTURA_ESCALERA_MAX := 768.0
const PASO_MUESTREO_ESCALERA := 20.0
const ALTURA_CUERPO_ESCALERA := 20.0
const ALTURA_CABEZA_ESCALERA := 58.0
const NORMAL_SUELO := 0.6      # coseno mínimo entre la normal y la vertical
const CONT_VACIO := -1

const TEXTURAS_IGNORADAS := ["sky", "clip", "hint", "skip", "null", "origin",
	"aaatrigger", "water", "lava", "slime", "trigger"]

const DESPLAZAMIENTOS := [
	Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0),
	Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7),
]

var bsp: BspReader
var posiciones: Array[Vector3] = []          # unidades GoldSrc
var vecinos: Array[PackedInt32Array] = []
var costes: Array[PackedFloat32Array] = []
var caras_suelo: int = 0
var caras_usadas: int = 0
var _celdas: Dictionary = {}                 # Vector2i -> PackedInt32Array
var _aristas_escalera: Dictionary = {}       # Vector2i(a,b) -> transición vertical
var _ms_construccion: int = 0
var escaleras_conectadas: int = 0


## Construye el grafo del mapa. Devuelve un objeto vacío (0 nodos) si algo
## falla: quien lo use debe comprobar `valido()`.
static func construir(p_bsp: BspReader) -> NavGrid:
	var g := NavGrid.new()
	g.bsp = p_bsp
	var t0 := Time.get_ticks_msec()
	g._construir()
	g._conectar()
	g._conectar_escaleras()
	g._ms_construccion = Time.get_ticks_msec() - t0
	return g


func valido() -> bool:
	return not posiciones.is_empty()


func resumen() -> String:
	return "%d nodos de navegación en %d caras, %d escaleras (%d ms)" % [
		posiciones.size(), caras_usadas, escaleras_conectadas, _ms_construccion]


func _construir() -> void:
	if bsp == null or bsp.planos_normal.is_empty():
		return
	var primera := bsp.mundo_primera_cara
	var total := bsp.mundo_num_caras
	if total <= 0:
		primera = 0
		total = bsp.cara_plano.size()
	for cara in range(primera, mini(primera + total, bsp.cara_plano.size())):
		var normal := _normal_cara(cara)
		if normal.z < NORMAL_SUELO:
			continue
		if _textura_ignorada(cara):
			continue
		caras_suelo += 1
		var poly := _poligono_goldsrc(cara)
		if poly.size() < 3:
			continue
		var plano := normal.dot(poly[0])
		var minx := INF
		var maxx := -INF
		var miny := INF
		var maxy := -INF
		for v: Vector3 in poly:
			minx = minf(minx, v.x)
			maxx = maxf(maxx, v.x)
			miny = minf(miny, v.y)
			maxy = maxf(maxy, v.y)
		var usada := false
		for gx in range(ceili(minx / PASO), floori(maxx / PASO) + 1):
			for gy in range(ceili(miny / PASO), floori(maxy / PASO) + 1):
				var px := gx * PASO
				var py := gy * PASO
				if not _dentro_convexo(poly, Vector2(px, py)):
					continue
				var pz := (plano - normal.x * px - normal.y * py) / normal.z
				if not _hay_hueco(px, py, pz):
					continue
				if _anadir(Vector3(px, py, pz)):
					usada = true
		if usada:
			caras_usadas += 1


## Normal de la cara con el lado aplicado (el `side` del formato invierte el
## plano). Las de suelo son las que miran hacia arriba.
func _normal_cara(cara: int) -> Vector3:
	var plano := bsp.cara_plano[cara]
	if plano < 0 or plano >= bsp.planos_normal.size():
		return Vector3.ZERO
	var n := bsp.planos_normal[plano]
	if cara < bsp.cara_lado.size() and bsp.cara_lado[cara] != 0:
		n = -n
	return n


func _textura_ignorada(cara: int) -> bool:
	var ti := bsp.cara_texinfo[cara]
	if ti < 0 or ti >= bsp.texinfo_miptex.size():
		return true
	var miptex := bsp.texinfo_miptex[ti]
	if miptex < 0 or miptex >= bsp.texturas.size():
		return true
	var nombre := String(bsp.texturas[miptex].get("nombre", "")).to_lower()
	for prefijo: String in TEXTURAS_IGNORADAS:
		if nombre.begins_with(prefijo):
			return true
	return false


## Vértices de la cara en unidades GoldSrc, en orden.
func _poligono_goldsrc(cara: int) -> Array[Vector3]:
	var salida: Array[Vector3] = []
	var ini := bsp.cara_firstedge[cara]
	var n := bsp.cara_numedges[cara]
	for k in n:
		var se := bsp.surfedges[ini + k]
		var ar := absi(se)
		if ar * 2 + 1 >= bsp.aristas.size():
			continue
		var idx := bsp.aristas[ar * 2] if se >= 0 else bsp.aristas[ar * 2 + 1]
		if idx >= bsp.vertices_goldsrc.size():
			continue
		salida.append(bsp.vertices_goldsrc[idx])
	return salida


## Las caras de Quake son convexas: estar dentro es que todos los productos
## vectoriales con las aristas tengan el mismo signo.
func _dentro_convexo(poly: Array[Vector3], p: Vector2) -> bool:
	var signo := 0
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var cruz := (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
		if absf(cruz) < 1e-9:
			continue
		var s := 1 if cruz > 0.0 else -1
		if signo == 0:
			signo = s
		elif s != signo:
			return false
	return true


## ¿Cabe el actor de pie aquí? Se miran 8 puntos alrededor del cuerpo y el
## hueco de la cabeza. El margen se comprueba así y no encogiendo la cara
## porque el suelo de un mapa son cientos de trozos: encoger cada trozo deja
## los corredores partidos en tiras inútiles.
func _hay_hueco(x: float, y: float, z: float) -> bool:
	for d: Vector2 in DESPLAZAMIENTOS:
		if bsp.contenido_goldsrc(Vector3(x + d.x * RADIO_ACTOR, y + d.y * RADIO_ACTOR,
				z + ALTURA_CUERPO_ESCALERA)) != CONT_VACIO:
			return false
	return bsp.contenido_goldsrc(Vector3(x, y, z + ALTURA_CABEZA_ESCALERA)) == CONT_VACIO


## Añade un nodo si en esa celda no hay ya uno a una altura parecida (el mismo
## suelo puede venir de varias caras).
func _anadir(p: Vector3) -> bool:
	var celda := Vector2i(roundi(p.x / PASO), roundi(p.y / PASO))
	var existentes: PackedInt32Array = _celdas.get(celda, PackedInt32Array())
	for idx in existentes:
		if absf(posiciones[idx].z - p.z) < 24.0:
			return false
	var nuevo := posiciones.size()
	posiciones.append(p)
	vecinos.append(PackedInt32Array())
	costes.append(PackedFloat32Array())
	var lista := existentes
	lista.append(nuevo)
	_celdas[celda] = lista
	return true


func _conectar() -> void:
	var desplazamientos := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for clave: Vector2i in _celdas:
		var nodos: PackedInt32Array = _celdas[clave]
		for a in nodos:
			var pa := posiciones[a]
			for d: Vector2i in desplazamientos:
				var otros: PackedInt32Array = _celdas.get(clave + d, PackedInt32Array())
				for b in otros:
					var pb := posiciones[b]
					if absf(pa.z - pb.z) > DESNIVEL_MAX:
						continue
					var dist := pa.distance_to(pb)
					if dist > PASO * 1.75:
						continue
					vecinos[a].append(b)
					costes[a].append(dist)
					vecinos[b].append(a)
					costes[b].append(dist)


# ------------------------------------------------------------ escaleras de mano
## Distancia horizontal de un nodo a la caja de `func_ladder`.
func _distancia_xy_caja(p: Vector3, mn: Vector3, mx: Vector3) -> float:
	var dx := maxf(maxf(mn.x - p.x, 0.0), p.x - mx.x)
	var dy := maxf(maxf(mn.y - p.y, 0.0), p.y - mx.y)
	return Vector2(dx, dy).length()


func _raiz_union(padres: Array[int], i: int) -> int:
	while padres[i] != i:
		padres[i] = padres[padres[i]]
		i = padres[i]
	return i


func _unir_union(padres: Array[int], rangos: Array[int], a: int, b: int) -> void:
	a = _raiz_union(padres, a)
	b = _raiz_union(padres, b)
	if a == b:
		return
	if rangos[a] < rangos[b]:
		var temporal := a
		a = b
		b = temporal
	padres[b] = a
	if rangos[a] == rangos[b]:
		rangos[a] += 1


func _segmento_horizontal_libre(a: Vector3, b: Vector2, z: float) -> bool:
	for t in [0.2, 0.4, 0.6, 0.8]:
		var x := lerpf(a.x, b.x, t)
		var y := lerpf(a.y, b.y, t)
		if bsp.contenido_goldsrc(Vector3(x, y, z + ALTURA_CUERPO_ESCALERA)) != CONT_VACIO:
			return false
		if bsp.contenido_goldsrc(Vector3(x, y, z + ALTURA_CABEZA_ESCALERA)) != CONT_VACIO:
			return false
	return true


func _columna_escalera_libre(x: float, y: float, z0: float, z1: float) -> bool:
	var z := z0
	while z < z1:
		if bsp.contenido_goldsrc(Vector3(x, y, z + ALTURA_CUERPO_ESCALERA)) != CONT_VACIO:
			return false
		if bsp.contenido_goldsrc(Vector3(x, y, z + ALTURA_CABEZA_ESCALERA)) != CONT_VACIO:
			return false
		z += PASO_MUESTREO_ESCALERA
	return bsp.contenido_goldsrc(Vector3(x, y, z1 + ALTURA_CUERPO_ESCALERA)) == CONT_VACIO \
		and bsp.contenido_goldsrc(Vector3(x, y, z1 + ALTURA_CABEZA_ESCALERA)) == CONT_VACIO


## Conecta una sola pareja de rellanos por cada trigger utilizable. La subida
## se valida con el árbol BSP y queda marcada para que A* y el suavizado no la
## confundan con un atajo andando a través de la pared.
func _conectar_escaleras() -> void:
	if bsp == null or posiciones.is_empty():
		return
	var padres: Array[int] = []
	var rangos: Array[int] = []
	for i in posiciones.size():
		padres.append(i)
		rangos.append(0)
	for a in vecinos.size():
		for b in vecinos[a]:
			if a < b:
				_unir_union(padres, rangos, a, b)

	for entidad in bsp.entidades_de("func_ladder"):
		var caja := bsp.caja_entidad_goldsrc(entidad)
		if caja.size == Vector3.ZERO:
			continue
		var mn := caja.position
		var mx := caja.position + caja.size
		var alto_brush := mx.z - mn.z
		if alto_brush < 32.0 or alto_brush > ALTURA_ESCALERA_MAX:
			continue

		var bajos: Array[Dictionary] = []
		var altos: Array[Dictionary] = []
		for i in posiciones.size():
			var p := posiciones[i]
			var dxy := _distancia_xy_caja(p, mn, mx)
			if dxy > MARGEN_ESCALERA:
				continue
			var dz_bajo := absf(p.z - mn.z)
			var dz_alto := absf(p.z - mx.z)
			if dz_bajo <= TOLERANCIA_ESCALERA_Z:
				bajos.append({"nodo": i, "dxy": dxy, "dz": dz_bajo})
			if dz_alto <= TOLERANCIA_ESCALERA_Z:
				altos.append({"nodo": i, "dxy": dxy, "dz": dz_alto})
		if bajos.is_empty() or altos.is_empty():
			continue

		var mejor_puntuacion := INF
		var mejor_bajo := -1
		var mejor_alto := -1
		var mejor_columna := Vector2.ZERO
		for dato_bajo: Dictionary in bajos:
			var bajo := int(dato_bajo["nodo"])
			var pb := posiciones[bajo]
			for dato_alto: Dictionary in altos:
				var alto := int(dato_alto["nodo"])
				if bajo == alto or _raiz_union(padres, bajo) == _raiz_union(padres, alto):
					continue
				var pa := posiciones[alto]
				var subida := pa.z - pb.z
				if subida <= 32.0 or subida > alto_brush + 2.0 * TOLERANCIA_ESCALERA_Z:
					continue
				var horizontal := Vector2(pa.x - pb.x, pa.y - pb.y).length()
				if horizontal > MARGEN_ESCALERA * 2.0:
					continue

				var centro := (mn + mx) * 0.5
				var columnas: Array[Vector2] = [Vector2(pb.x, pb.y), Vector2(pa.x, pa.y),
					Vector2((pb.x + pa.x) * 0.5, (pb.y + pa.y) * 0.5), Vector2(centro.x, centro.y)]
			var columna_valida := false
			var columna := Vector2.ZERO
			var lateral := INF
			for xy: Vector2 in columnas:
				if _distancia_xy_caja(Vector3(xy.x, xy.y, 0.0), mn, mx) > MARGEN_ESCALERA:
					continue
				if not _columna_escalera_libre(xy.x, xy.y, pb.z, pa.z):
					continue
				if not _segmento_horizontal_libre(pb, xy, pb.z):
					continue
				if not _segmento_horizontal_libre(pa, xy, pa.z):
					continue
				var desvio := Vector2(pb.x - xy.x, pb.y - xy.y).length() \
					+ Vector2(pa.x - xy.x, pa.y - xy.y).length()
				if desvio < lateral:
					columna = xy
					lateral = desvio
					columna_valida = true
			if not columna_valida:
				continue

			var puntuacion := float(dato_bajo["dxy"]) + float(dato_alto["dxy"]) \
				+ 0.5 * (float(dato_bajo["dz"]) + float(dato_alto["dz"])) \
				+ 0.25 * horizontal + 0.1 * lateral
			if puntuacion < mejor_puntuacion:
				mejor_puntuacion = puntuacion
				mejor_bajo = bajo
				mejor_alto = alto
				mejor_columna = columna

		if mejor_bajo < 0 or mejor_alto < 0:
			continue
		var p_bajo := posiciones[mejor_bajo]
		var p_alto := posiciones[mejor_alto]
		var subida_total := p_alto.z - p_bajo.z
		var coste := (Vector2(p_bajo.x, p_bajo.y).distance_to(mejor_columna)
			+ subida_total
			+ Vector2(p_alto.x, p_alto.y).distance_to(mejor_columna)) * 1.2
		vecinos[mejor_bajo].append(mejor_alto)
		costes[mejor_bajo].append(coste)
		vecinos[mejor_alto].append(mejor_bajo)
		costes[mejor_alto].append(coste)
		var clave := Vector2i(mini(mejor_bajo, mejor_alto), maxi(mejor_bajo, mejor_alto))
		_aristas_escalera[clave] = {
			"bajo": mejor_bajo,
			"alto": mejor_alto,
			"columna": mejor_columna,
		}
		_unir_union(padres, rangos, mejor_bajo, mejor_alto)
		escaleras_conectadas += 1


# ------------------------------------------------------------------ consultas
## Nodo más cercano a un punto (en metros, coordenadas de Godot).
func nodo_mas_cercano(p_godot: Vector3) -> int:
	if posiciones.is_empty():
		return -1
	var g := BspReader._a_goldsrc(p_godot)
	var mejor := -1
	var mejor_d := INF
	for i in posiciones.size():
		var d := posiciones[i].distance_squared_to(g)
		if d < mejor_d:
			mejor = i
			mejor_d = d
	return mejor


## Camino entre dos puntos en metros (coordenadas de Godot). Devuelve una lista
## de puntos a seguir; vacía si no hay ruta.
func camino(desde_godot: Vector3, hasta_godot: Vector3) -> PackedVector3Array:
	var a := nodo_mas_cercano(desde_godot)
	var b := nodo_mas_cercano(hasta_godot)
	if a < 0 or b < 0:
		return PackedVector3Array()
	var nodos := camino_nodos(a, b)
	if nodos.is_empty():
		return PackedVector3Array()
	var salida := PackedVector3Array()
	for p in _puntos_camino_goldsrc(nodos):
		salida.append(BspReader._a_godot(p))
	return salida


## Suaviza solo los tramos caminables e intercala dos puntos verticales en cada
## escalera. Así A* no pierde la información especial al devolver el camino.
func _puntos_camino_goldsrc(ruta: PackedInt32Array) -> Array[Vector3]:
	var salida: Array[Vector3] = []
	if ruta.is_empty():
		return salida
	var tramo := PackedInt32Array([ruta[0]])
	for i in range(1, ruta.size()):
		var anterior := ruta[i - 1]
		var actual := ruta[i]
		var clave := Vector2i(mini(anterior, actual), maxi(anterior, actual))
		if not _aristas_escalera.has(clave):
			tramo.append(actual)
			continue
		_agregar_indices_suaves(salida, _suavizar(tramo))
		var datos: Dictionary = _aristas_escalera[clave]
		var columna: Vector2 = datos["columna"]
		var p_bajo: Vector3 = posiciones[int(datos["bajo"])]
		var p_alto: Vector3 = posiciones[int(datos["alto"])]
		var abajo := Vector3(columna.x, columna.y, p_bajo.z)
		var arriba := Vector3(columna.x, columna.y, p_alto.z)
		if anterior == int(datos["bajo"]):
			_agregar_punto_unico(salida, abajo)
			_agregar_punto_unico(salida, arriba)
		else:
			_agregar_punto_unico(salida, arriba)
			_agregar_punto_unico(salida, abajo)
		_agregar_punto_unico(salida, posiciones[actual])
		tramo = PackedInt32Array([actual])
	_agregar_indices_suaves(salida, _suavizar(tramo))
	return salida


func _agregar_indices_suaves(salida: Array[Vector3], ruta: PackedInt32Array) -> void:
	for idx in ruta:
		_agregar_punto_unico(salida, posiciones[idx])


func _agregar_punto_unico(salida: Array[Vector3], punto: Vector3) -> void:
	if salida.is_empty() or salida[salida.size() - 1].distance_to(punto) > 0.01:
		salida.append(punto)


## A* sobre los nodos. Devuelve los índices del camino, del principio al final.
func camino_nodos(desde: int, hasta: int) -> PackedInt32Array:
	var salida := PackedInt32Array()
	if desde < 0 or hasta < 0 or desde >= posiciones.size() or hasta >= posiciones.size():
		return salida
	if desde == hasta:
		salida.append(desde)
		return salida

	var n := posiciones.size()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var previo := PackedInt32Array()
	previo.resize(n)
	previo.fill(-1)
	var cerrado := PackedByteArray()
	cerrado.resize(n)
	var abierto := _Monticulo.new()

	var objetivo := posiciones[hasta]
	g[desde] = 0.0
	abierto.insertar(desde, posiciones[desde].distance_to(objetivo))

	var guardas := 0
	while abierto.tamano() > 0:
		var actual := abierto.sacar_min()
		if actual < 0:
			break
		if cerrado[actual] == 1:
			continue
		cerrado[actual] = 1
		if actual == hasta:
			var ruta := PackedInt32Array()
			var nodo := hasta
			while nodo >= 0:
				ruta.insert(0, nodo)
				nodo = previo[nodo]
			return ruta
		guardas += 1
		if guardas > n * 4:
			break        # grafo corrupto: no colgarse
		var vecs := vecinos[actual]
		var cos := costes[actual]
		for i in vecs.size():
			var v := vecs[i]
			if cerrado[v] == 1:
				continue
			var nuevo := g[actual] + cos[i]
			if nuevo < g[v]:
				g[v] = nuevo
				previo[v] = actual
				abierto.insertar(v, nuevo + posiciones[v].distance_to(objetivo))
	return salida


## Quita los nodos intermedios que no hacen falta: si de A a C se puede ir en
## línea recta sin chocar, B sobra. Un camino de rejilla da zigzag; sin esto los
## bots caminarían como borrachos.
func _suavizar(ruta: PackedInt32Array) -> PackedInt32Array:
	if ruta.size() <= 2:
		return ruta
	var salida := PackedInt32Array()
	salida.append(ruta[0])
	var ancla := 0
	for i in range(1, ruta.size()):
		if i == ruta.size() - 1:
			salida.append(ruta[i])
			continue
		if not _linea_libre(posiciones[ruta[ancla]], posiciones[ruta[i + 1]]):
			salida.append(ruta[i])
			ancla = i
	return salida


## ¿Se puede caminar en línea recta entre dos nodos? Se mira el pecho en tres
## puntos intermedios contra el árbol BSP.
func _linea_libre(a: Vector3, b: Vector3) -> bool:
	var z := maxf(a.z, b.z) + ALTURA_PECHO
	for t in [0.25, 0.5, 0.75]:
		var p := a.lerp(b, t)
		if bsp.contenido_goldsrc(Vector3(p.x, p.y, z)) != CONT_VACIO:
			return false
	return true


## Montículo binario mínimo: `Array.sort()` en cada paso es O(n log n) por
## iteración y A* se hace eterno en mapas de 10 000 nodos.
class _Monticulo:
	var _nodos: Array[int] = []
	var _costes: Array[float] = []

	func tamano() -> int:
		return _nodos.size()

	func insertar(nodo: int, coste: float) -> void:
		_nodos.append(nodo)
		_costes.append(coste)
		var i := _nodos.size() - 1
		while i > 0:
			var padre := (i - 1) >> 1
			if _costes[padre] <= _costes[i]:
				break
			_intercambiar(i, padre)
			i = padre

	func sacar_min() -> int:
		if _nodos.is_empty():
			return -1
		var cima := _nodos[0]
		var ultimo_n := _nodos.pop_back()
		var ultimo_c: float = _costes.pop_back()
		if not _nodos.is_empty():
			_nodos[0] = ultimo_n
			_costes[0] = ultimo_c
			var i := 0
			while true:
				var izq := i * 2 + 1
				var der := izq + 1
				var menor := i
				if izq < _nodos.size() and _costes[izq] < _costes[menor]:
					menor = izq
				if der < _nodos.size() and _costes[der] < _costes[menor]:
					menor = der
				if menor == i:
					break
				_intercambiar(i, menor)
				i = menor
		return cima

	func _intercambiar(a: int, b: int) -> void:
		var tn := _nodos[a]
		_nodos[a] = _nodos[b]
		_nodos[b] = tn
		var tc: float = _costes[a]
		_costes[a] = _costes[b]
		_costes[b] = tc
