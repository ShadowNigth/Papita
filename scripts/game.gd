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
var _actores_meta: Array[Dictionary] = []

## Cuantos soldados animados se colocan (0 = ninguno). Se puede cambiar con
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
			"--actores":
				if i + 1 < args.size():
					num_actores = int(args[i + 1])
			"--secuencia":
				if i + 1 < args.size():
					set_meta("secuencia_forzada", args[i + 1])


func cargar_mapa(id: String) -> void:
	if not MAPAS.has(id):
		push_warning("mapa desconocido '%s', uso de_dust2" % id)
		id = "de_dust2"
	mapa_actual = id

	if _nodo_mapa != null and is_instance_valid(_nodo_mapa):
		_nodo_mapa.queue_free()

	bsp = BspReader.cargar(RAIZ_MAPAS + String(MAPAS[id]), paleta)
	if not bsp.errores.is_empty():
		push_error("BSP: " + ", ".join(bsp.errores))
	print("[papita] ", bsp.resumen())

	var t0 := Time.get_ticks_msec()
	info_mapa = MapBuilder.construir(bsp)
	var t1 := Time.get_ticks_msec()
	print("[papita] mapa construido en %d ms: %d superficies, %d triangulos" % [
		t1 - t0, int(info_mapa.get("superficies", 0)), int(info_mapa.get("triangulos", 0))])

	_nodo_mapa = info_mapa["nodo"] as Node3D
	add_child(_nodo_mapa)

	_colocar_jugador()
	_colocar_actores()
	_crear_hud()
	_crear_fondo()


func _colocar_jugador() -> void:
	if jugador != null and is_instance_valid(jugador):
		jugador.queue_free()
	var spawns: Array[Vector3] = info_mapa.get("spawns", [])
	var origen := Vector3(0, 2, 0)
	if not spawns.is_empty():
		origen = spawns[randi() % spawns.size()] + Vector3(0, 0.4, 0)
	jugador = CsPlayer.new()
	jugador.name = "jugador"
	jugador.add_to_group("jugador")
	jugador.position = origen
	add_child(jugador)

	var arma_inicial := String(get_meta("arma_inicial", ""))
	if not arma_inicial.is_empty():
		jugador.armas.append(arma_inicial)
		jugador.equipar(arma_inicial)
	else:
		jugador.equipar("glock18")


## Coloca soldados animados de las facciones originales. Se mueven en linea
## recta entre puntos aleatorios del mapa (no hay navegacion todavia), asi que
## pueden atravesar paredes: es una demo de animacion, no IA.
func _colocar_actores() -> void:
	for a in _actores:
		if is_instance_valid(a):
			a.queue_free()
	_actores.clear()
	_actores_meta.clear()
	if num_actores <= 0:
		return

	var spawns: Array[Vector3] = info_mapa.get("spawns", [])
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
		var destino := spawns[randi() % spawns.size()]
		actor.position = destino + Vector3(0, 0.1, 0)
		add_child(actor)
		var forzada := String(get_meta("secuencia_forzada", ""))
		if not forzada.is_empty():
			actor.reproducir(forzada)
		else:
			actor.reproducir("idle1")
		_actores.append(actor)
		_actores_meta.append({
			"objetivo": spawns[randi() % spawns.size()],
			"pausa": randf_range(0.5, 3.0),
		})
	print("[papita] %d actores animados (%s)" % [
		_actores.size(), ", ".join(a.secuencias_disponibles().slice(0, 6))])


func _process(delta: float) -> void:
	_mover_actores(delta)


func _mover_actores(delta: float) -> void:
	for i in _actores.size():
		var actor := _actores[i]
		if not is_instance_valid(actor) or actor.lector == null:
			continue
		var meta: Dictionary = _actores_meta[i]
		var pausa: float = float(meta.get("pausa", 0.0))
		if pausa > 0.0:
			meta["pausa"] = pausa - delta
			actor.animar_por_velocidad(0.0)
			continue
		var objetivo: Vector3 = meta["objetivo"]
		var plano := Vector3(objetivo.x, actor.position.y, objetivo.z)
		var distancia := actor.position.distance_to(plano)
		if distancia < 0.6:
			# destino alcanzado: descansa y elige otro
			meta["objetivo"] = _punto_aleatorio()
			meta["pausa"] = randf_range(0.4, 2.0)
			continue
		var direccion := (plano - actor.position).normalized()
		var rapidez := 3.4
		actor.position += direccion * rapidez * delta
		# Los modelos de GoldSrc estan modelados mirando hacia +X. `look_at`
		# orientaria -Z hacia el objetivo, asi que se calcula el giro a mano:
		# rotation.y = t lleva el +X local a (cos t, 0, -sin t).
		actor.rotation.y = atan2(-direccion.z, direccion.x)
		actor.animar_por_velocidad(rapidez)


func _punto_aleatorio() -> Vector3:
	var spawns: Array[Vector3] = info_mapa.get("spawns", [])
	if spawns.is_empty():
		return Vector3.ZERO
	return spawns[randi() % spawns.size()]


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
