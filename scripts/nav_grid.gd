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
## * **Cómo se conecta**: nodos vecinos con un desnivel menor que `DESNIVEL_MAX`
##   (escaleras y rampas del original), sin pared en medio.
##
## Todo el cálculo va en **unidades GoldSrc**, como el motor; la conversión a
## metros se hace al devolver el camino. El espejo en Python
## (`tools/nav_validate.py`) valida este mismo algoritmo contra los 10 mapas.

const PASO := 40.0             # separación de muestras: 1 m
const RADIO_ACTOR := 16.0      # radio de la cápsula del jugador (32 u de diámetro)
const ALTURA_PECHO := 20.0     # altura de la comprobación de cuerpo
const ALTURA_CABEZA := 58.0    # altura de la comprobación de cabeza
const DESNIVEL_MAX := 40.0     # escalón máximo entre dos nodos
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
var _ms_construccion: int = 0


## Construye el grafo del mapa. Devuelve un objeto vacío (0 nodos) si algo
## falla: quien lo use debe comprobar `valido()`.
static func construir(p_bsp: BspReader) -> NavGrid:
	var g := NavGrid.new()
	g.bsp = p_bsp
	var t0 := Time.get_ticks_msec()
	g._construir()
	g._conectar()
	g._ms_construccion = Time.get_ticks_msec() - t0
	return g


func valido() -> bool:
	return not posiciones.is_empty()


func resumen() -> String:
	return "%d nodos de navegación en %d caras (%d ms)" % [
		posiciones.size(), caras_usadas, _ms_construccion]


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
				z + ALTURA_PECHO)) != CONT_VACIO:
			return false
	return bsp.contenido_goldsrc(Vector3(x, y, z + ALTURA_CABEZA)) == CONT_VACIO


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
	var suave := _suavizar(nodos)
	var salida := PackedVector3Array()
	for idx in suave:
		salida.append(BspReader._a_godot(posiciones[idx]))
	return salida


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
