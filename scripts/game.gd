class_name CsGame
extends Node3D
## Escena principal: carga la paleta, lee el .bsp, construye el mapa, coloca al
## jugador en un punto de aparicion y engancha el HUD.
##
## Uso:
##   godot --path .                          -> de_dust2
##   godot --path . -- --map de_nuke        -> otro mapa
##   godot --path . -- --map de_aztec --arma awp --bots 4

const MAPAS := {
	"de_dust2": "de_dust2.bsp",
	"de_dust": "de_dust.bsp",
	"de_inferno": "de_inferno.bsp",
	"de_nuke": "de_nuke.bsp",
	"de_train": "de_train.bsp",
	"de_aztec": "de_aztec.bsp",
	"cs_office": "cs_office.bsp",
	"cs_italy": "cs_italy.bsp",
	"cs_assault": "cs_assault.bsp",
	"cs_estate": "cs_estate.bsp",
}
const RAIZ_MAPAS := "res://assets/maps/cs15/"

var mapa_actual: String = "de_dust2"
var paleta: CsPalette
var bsp: BspReader
var jugador: CsPlayer
var hud: Hud
var info_mapa: Dictionary = {}

var _nodo_mapa: Node3D
var _actores: Array[ActorModel] = []
var director: MatchDirector
var menu_compra: BuyMenu
var nav: NavGrid
var equipo_jugador: String = "ct"
var _bots: Array[BotAI] = []
## 0 = fácil, 1 = normal, 2 = difícil (se cambia con `--skill`)
var dificultad: int = 1

## Cuantos bots se colocan (0 = ninguno). Se puede cambiar con `--bots N` o
## `--actores N` en la linea de comandos.
var num_actores: int = 4


func _ready() -> void:
	_crear_acciones()
	_leer_argumentos()
	paleta = CsPalette.cargar()
	cargar_mapa(mapa_actual)
	print("[papita] paleta: ", paleta.origen)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _leer_argumentos() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--map":
				if i + 1 < args.size():
					mapa_actual = args[i + 1]
			"--arma":
				if i + 1 < args.size():
					set_meta("arma_inicial", args[i + 1])
			"--actores", "--bots":
				if i + 1 < args.size():
					num_actores = int(args[i + 1])
			"--skill", "--dificultad":
				if i + 1 < args.size():
					dificultad = int(args[i + 1])
			"--secuencia":
				if i + 1 < args.size():
					set_meta("secuencia_forzada", args[i + 1])
			"--equipo":
				if i + 1 < args.size():
					equipo_jugador = args[i + 1].to_lower()
			"--rondas":
				if i + 1 < args.size():
					set_meta("max_rondas", int(args[i + 1]))


## Equipo valido (por si el argumento viene mal escrito).
func _equipo_valido() -> String:
	return equipo_jugador if equipo_jugador in ["ct", "t"] else "ct"


func cargar_mapa(id: String) -> void:
	if not MAPAS.has(id):
		push_warning("mapa desconocido '%s', uso de_dust2" % id)
		id = "de_dust2"
	mapa_actual = id

	if _nodo_mapa != null and is_instance_valid(_nodo_mapa):
		_nodo_mapa.queue_free()
	# Al recargar (F5) hay que tirar la partida anterior: si no, quedarian dos
	# directores y dos menus de compra vivos a la vez.
	if director != null and is_instance_valid(director):
		director.queue_free()
		director = null
	if menu_compra != null and is_instance_valid(menu_compra):
		var capa := menu_compra.get_parent()
		if capa != null:
			capa.queue_free()
		else:
			menu_compra.queue_free()
		menu_compra = null

	bsp = BspReader.cargar(RAIZ_MAPAS + String(MAPAS[id]), paleta)
	if not bsp.errores.is_empty():
		push_error("BSP: " + ", ".join(bsp.errores))
	print("[papita] ", bsp.resumen())

	var t0 := Time.get_ticks_msec()
	info_mapa = MapBuilder.construir(bsp)
	var t1 := Time.get_ticks_msec()
	print("[papita] mapa construido en %d ms: %d superficies, %d triangulos, %d puertas" % [
		t1 - t0, int(info_mapa.get("superficies", 0)), int(info_mapa.get("triangulos", 0)),
		int(info_mapa.get("puertas", 0))])

	_nodo_mapa = info_mapa["nodo"] as Node3D
	add_child(_nodo_mapa)

	# El grafo de navegación sale del propio .bsp (árbol BSP + caras de suelo).
	nav = NavGrid.construir(bsp)
	print("[papita] ", nav.resumen() if nav.valido() else "sin grafo de navegación")

	_colocar_jugador()
	_colocar_actores()
	_crear_hud()
	_crear_director()
	_crear_bots()
	_crear_fondo()


func _colocar_jugador() -> void:
	if jugador != null and is_instance_valid(jugador):
		jugador.queue_free()
	# assign() convierte el Array sin tipo del Dictionary a Array[Vector3];
	# una asignacion directa es error de ejecucion en Godot 4.
	var spawns: Array[Vector3] = []
	spawns.assign(info_mapa.get("spawns", []))
	var origen := Vector3(0, 2, 0)
	if not spawns.is_empty():
		origen = spawns[randi() % spawns.size()] + Vector3(0, 0.4, 0)
	jugador = CsPlayer.new()
	jugador.name = "jugador"
	jugador.equipo = _equipo_valido()
	jugador.add_to_group("jugador")
	jugador.position = origen
	add_child(jugador)

	var arma_inicial := String(get_meta("arma_inicial", ""))
	if not arma_inicial.is_empty():
		jugador.armas.append(arma_inicial)
		jugador.equipar(arma_inicial)
	else:
		jugador.equipar("glock18")


## Coloca los bots de las facciones originales. La IA que los mueve se crea
## aparte, en _crear_bots(), porque necesita el grafo de navegacion y al jugador.
func _colocar_actores() -> void:
	for a in _actores:
		if is_instance_valid(a):
			a.queue_free()
	_actores.clear()
	if num_actores <= 0:
		return

	# assign() convierte el Array sin tipo del Dictionary a Array[Vector3];
	# una asignacion directa es error de ejecucion en Godot 4.
	var spawns: Array[Vector3] = []
	spawns.assign(info_mapa.get("spawns", []))
	if spawns.is_empty():
		return
	var facciones := ["gign", "sas", "urban", "gsg9", "terror", "leet", "arctic", "guerilla"]
	for i in num_actores:
		var faccion: String = facciones[i % facciones.size()]
		var actor := ActorModel.new()
		actor.name = "actor_%s_%d" % [faccion, i]
		var ok := actor.cargar("player/%s/%s.mdl" % [faccion, faccion], paleta)
		if not ok and faccion != "urban":
			# si esa faccion falla, se usa urban, que siempre esta
			ok = actor.cargar("player/urban/urban.mdl", paleta)
		if not ok:
			actor.queue_free()
			continue
		actor.equipo = "t" if _equipo_valido() == "ct" else "ct"
		var destino := _spawn_lejos(jugador.global_position if jugador != null else Vector3.ZERO)
		actor.position = destino + Vector3(0, 0.1, 0)
		add_child(actor)
		var forzada := String(get_meta("secuencia_forzada", ""))
		if not forzada.is_empty():
			actor.reproducir(forzada)
		else:
			actor.reproducir("idle1")
		_actores.append(actor)
	print("[papita] %d actores animados (%s)" % [
		_actores.size(), ", ".join(a.secuencias_disponibles().slice(0, 6))])


## Crea la IA de cada actor. Los bots son del bando contrario al jugador.
func _crear_bots() -> void:
	_bots.clear()
	if _actores.is_empty():
		return
	for actor in _actores:
		if not is_instance_valid(actor):
			continue
		var bot := BotAI.new()
		bot.name = "ia_" + String(actor.name)
		actor.add_child(bot)
		bot.configurar(actor, jugador, nav, actor.equipo, dificultad)
		_bots.append(bot)
	print("[papita] %d bots (%s)" % [_bots.size(), _bots[0].nombre_dificultad()])


func _process(delta: float) -> void:
	# Durante la congelación y el final de ronda los bots no se mueven ni
	# disparan, igual que el jugador.
	var quietos := director == null or director.estado == MatchDirector.Estado.CONGELACION \
		or director.estado == MatchDirector.Estado.FIN_RONDA
	for bot in _bots:
		if is_instance_valid(bot):
			bot.congelar(quietos)


## Crea el director de partida (rondas, economía, objetivos) y el menú de compra.
func _crear_director() -> void:
	director = MatchDirector.new()
	director.name = "director"
	add_child(director)
	# `info_mapa` es un Dictionary sin tipos: asignar su Array a un
	# Array[Dictionary] directamente da error en ejecucion, hay que copiar.
	var zonas_bomba: Array[Dictionary] = []
	for z in info_mapa.get("zonas_bomba", []):
		zonas_bomba.append(z)
	var zonas_compra: Array[Dictionary] = []
	for z in info_mapa.get("zonas_compra", []):
		zonas_compra.append(z)
	director.max_rondas = int(get_meta("max_rondas", 0))
	# Las senales se conectan ANTES de configurar(): configurar() ya arranca la
	# primera ronda y sus mensajes tienen que llegar al HUD.
	jugador.baja_confirmada.connect(_on_baja)
	director.mensaje.connect(_on_mensaje)
	director.dinero_cambiado.connect(_on_dinero)
	director.estado_cambiado.connect(_on_estado_partida)
	director.ronda_iniciada.connect(_on_ronda_iniciada)
	director.ronda_terminada.connect(_on_ronda_terminada)
	director.partida_terminada.connect(_on_partida_terminada)
	director.configurar(jugador, _actores, zonas_bomba, zonas_compra, _equipo_valido())

	menu_compra = BuyMenu.new()
	menu_compra.name = "menu_compra"
	menu_compra.director = director
	var capa := CanvasLayer.new()
	capa.name = "capa_compra"
	capa.layer = 2
	add_child(capa)
	capa.add_child(menu_compra)


func _on_estado_partida(estado: int, restante: float) -> void:
	if hud == null or not is_instance_valid(hud):
		return
	hud.tiempo_ronda = restante
	hud.marcador = director.marcador()
	hud.enemigos = director.enemigos_vivos()
	match estado:
		MatchDirector.Estado.CONGELACION:
			hud.fase = "Congelación · compra (B)"
		MatchDirector.Estado.EN_JUEGO:
			hud.fase = "En juego"
		MatchDirector.Estado.BOMBA_PLANTADA:
			hud.fase = "Bomba plantada"
		MatchDirector.Estado.FIN_RONDA:
			hud.fase = "Fin de ronda"
	if director.bomba != null and is_instance_valid(director.bomba) and director.bomba.activa:
		hud.tiempo_bomba = director.bomba.restante
	else:
		hud.tiempo_bomba = -1.0


func _on_baja(_arma: String) -> void:
	if director != null and is_instance_valid(director):
		director.registrar_baja(_arma)


func _on_mensaje(texto: String) -> void:
	if hud != null and is_instance_valid(hud):
		hud.aviso(texto, 2.5)


func _on_dinero(cantidad: int) -> void:
	if hud != null and is_instance_valid(hud):
		hud.dinero = cantidad


## Un punto de aparición lejos de `de`. Nacer al lado del jugador y que te
## maten antes de ver nada no es un juego, es una emboscada.
func _spawn_lejos(de: Vector3, minimo: float = 10.0) -> Vector3:
	var mejor := _punto_aleatorio()
	var mejor_d := -1.0
	for i in 12:
		var punto := _punto_aleatorio()
		var d := punto.distance_to(de)
		if d >= minimo:
			return punto
		if d > mejor_d:
			mejor = punto
			mejor_d = d
	return mejor


func _on_ronda_iniciada(numero: int) -> void:
	# Al morir se libera el raton; la ronda nueva lo vuelve a capturar salvo que
	# el menu de compra este abierto.
	if menu_compra == null or not menu_compra.abierto:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if hud != null and is_instance_valid(hud):
		hud.ronda = numero
	# Los bots vuelven a su sitio lejos del jugador y con el cargador lleno.
	for actor in _actores:
		if is_instance_valid(actor) and actor.vivo:
			actor.global_position = _spawn_lejos(jugador.global_position)
	for bot in _bots:
		if is_instance_valid(bot):
			bot.reiniciar()
	print("[papita] ronda ", numero, " | ", director.marcador())


func _on_ronda_terminada(ganador: String, motivo: String) -> void:
	print("[papita] gana ", ganador, " (", motivo, ") | ", director.marcador())


func _on_partida_terminada(resultado: String) -> void:
	print("[papita] fin de la partida: ", resultado)
	if hud != null and is_instance_valid(hud):
		hud.aviso("Fin de la partida · " + resultado, 10.0)


func _crear_hud() -> void:
	if hud == null or not is_instance_valid(hud):
		hud = Hud.new()
		hud.name = "hud"
		var capa := CanvasLayer.new()
		capa.name = "interfaz"
		add_child(capa)
		capa.add_child(hud)
	hud.arma = WeaponDB.nombre(jugador.arma_actual)
	jugador.arma_cambiada.connect(func(id: String) -> void:
		hud.arma = WeaponDB.nombre(id)
		hud.aviso("%s (%d$)" % [WeaponDB.nombre(id), int(WeaponDB.obtener(id).get("precio", 0))], 2.0))
	jugador.estado_actualizado.connect(func(v: int, c: int, ca: int, re: int) -> void:
		hud.vida = v
		hud.chaleco = c
		hud.cargador = ca
		hud.reserva = re)


func _crear_fondo() -> void:
	# R: reiniciar el mapa. Esto es lo minimo de "flujo de juego" por ahora.
	if not InputMap.has_action("reiniciar_mapa"):
		InputMap.add_action("reiniciar_mapa")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F5
		InputMap.action_add_event("reiniciar_mapa", ev)


func _unhandled_input(evento: InputEvent) -> void:
	if evento.is_action_pressed("comprar") and menu_compra != null:
		# BuyMenu se encarga del raton; el jugador sigue congelado por el director.
		menu_compra.alternar()
		return
	if evento.is_action_pressed("reiniciar_mapa"):
		cargar_mapa(mapa_actual)
	elif evento.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif evento is InputEventMouseButton and (evento as InputEventMouseButton).pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _crear_acciones() -> void:
	var mapa := {
		"adelante": [KEY_W],
		"atras": [KEY_S],
		"izquierda": [KEY_A],
		"derecha": [KEY_D],
		"saltar": [KEY_SPACE],
		"agacharse": [KEY_CTRL],
		"disparar": [KEY_NONE],
		# plantar/desactivar la C4 (el director consulta esta accion)
		"usar": [KEY_E],
		"comprar": [KEY_B],
	}
	for accion in mapa:
		if InputMap.has_action(accion):
			continue
		InputMap.add_action(accion)
		for tecla in mapa[accion]:
			if tecla == KEY_NONE:
				continue
			var ev := InputEventKey.new()
			ev.physical_keycode = tecla
			InputMap.action_add_event(accion, ev)
	# El boton izquierdo se anade siempre: "disparar" ya existe (creada arriba
	# sin teclas), asi que comprobar has_action() antes seria un no-op.
	var raton := InputEventMouseButton.new()
	raton.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("disparar", raton):
		InputMap.action_add_event("disparar", raton)
