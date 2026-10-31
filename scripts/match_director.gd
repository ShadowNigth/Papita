class_name MatchDirector
extends Node
## Director de partida: rondas, economía, objetivos y condiciones de victoria.
##
## Máquina de estados:
##
##   CONGELACION --(fin del tiempo de compra)--> EN_JUEGO
##        ^                                        │
##        │                                ┌───────┴────────┐
##        │                                ▼                ▼
##        │                          BOMBA_PLANTADA     FIN_RONDA
##        │                                │                ▲
##        └──────────── FIN_RONDA <────────┴────────────────┘
##
## Condiciones de victoria implementadas:
##   * eliminación (no queda nadie vivo en un bando)
##   * tiempo agotado (ganan los CT)
##   * la bomba explota (ganan los T)
##   * la bomba se desactiva (ganan los CT)
##   * rehenes rescatados (ganan los CT)

signal ronda_iniciada(numero: int)
signal ronda_terminada(ganador: String, motivo: String)
signal estado_cambiado(estado: int, tiempo_restante: float)
signal dinero_cambiado(cantidad: int)
signal mensaje(texto: String)
signal partida_terminada(ganador: String)

enum Estado { CONGELACION, EN_JUEGO, BOMBA_PLANTADA, FIN_RONDA }

# Tiempos (los del 1.5 con los .cfg por defecto)
const TIEMPO_CONGELACION := 6.0
const TIEMPO_RONDA := 300.0        # mp_roundtime 5
const TIEMPO_FIN_RONDA := 5.0      # mp_chattime
const TIEMPO_PLANTAR := 3.0

var estado: int = Estado.CONGELACION
var numero_ronda: int = 1
var tiempo_estado: float = TIEMPO_CONGELACION

var puntos_ct: int = 0
var puntos_t: int = 0
var equipo_jugador: String = "ct"      # "ct" o "t"
var dinero: int = CsEconomy.DINERO_INICIAL
var derrotas_seguidas: int = 0
var bajas: int = 0
var muertes: int = 0
## mp_maxrounds: 0 = partida sin limite (util para probar un mapa suelto).
var max_rondas: int = 0
var _progreso_mensaje: int = -1

var jugador: CsPlayer
var actores: Array[ActorModel] = []
var zonas_bomba: Array[Dictionary] = []
var zonas_compra: Array[Dictionary] = []

var bomba: CsBomb
var _progreso_plantar: float = 0.0
var _ronda_plantada: bool = false
var _spawn: Vector3 = Vector3.ZERO


func configurar(p_jugador: CsPlayer, p_actores: Array[ActorModel],
		p_zonas_bomba: Array[Dictionary], p_zonas_compra: Array[Dictionary],
		p_equipo: String) -> void:
	jugador = p_jugador
	actores = p_actores
	zonas_bomba = p_zonas_bomba
	zonas_compra = p_zonas_compra
	equipo_jugador = p_equipo
	reiniciar_partida()


func reiniciar_partida() -> void:
	numero_ronda = 1
	puntos_ct = 0
	puntos_t = 0
	dinero = CsEconomy.DINERO_INICIAL
	derrotas_seguidas = 0
	bajas = 0
	muertes = 0
	_iniciar_ronda()
	dinero_cambiado.emit(dinero)


# ------------------------------------------------------------------ rondas
func _iniciar_ronda() -> void:
	estado = Estado.CONGELACION
	tiempo_estado = TIEMPO_CONGELACION
	_ronda_plantada = false
	_progreso_plantar = 0.0
	_progreso_mensaje = -1
	if bomba != null and is_instance_valid(bomba):
		bomba.queue_free()
	bomba = null
	# respawn de todos
	if jugador != null and is_instance_valid(jugador):
		# Sobrevivir la ronda conserva el equipo; morir lo pierde todo.
		var sobrevivio := jugador.vivo
		jugador.reaparecer(_punto_de_aparicion(), sobrevivio)
	for actor in actores:
		if is_instance_valid(actor):
			actor.revivir()
	ronda_iniciada.emit(numero_ronda)
	mensaje.emit("Ronda %d · compra libre (B)" % numero_ronda)


func _terminar_ronda(ganador: String, motivo: String) -> void:
	if estado == Estado.FIN_RONDA:
		return
	estado = Estado.FIN_RONDA
	tiempo_estado = TIEMPO_FIN_RONDA

	var gana_jugador := (ganador == "ct" and equipo_jugador == "ct") or \
		(ganador == "t" and equipo_jugador == "t")

	if gana_jugador:
		_pagar(CsEconomy.recompensa_victoria(motivo))
		derrotas_seguidas = 0
	else:
		_pagar(CsEconomy.bono_derrota(derrotas_seguidas))
		derrotas_seguidas += 1

	if ganador == "ct":
		puntos_ct += 1
	else:
		puntos_t += 1

	ronda_terminada.emit(ganador, motivo)
	mensaje.emit("%s gana la ronda (%s)" % [
		"CT" if ganador == "ct" else "T", _texto_motivo(motivo)])


func _texto_motivo(motivo: String) -> String:
	match motivo:
		"eliminacion":
			return "eliminación"
		"bomba_explota":
			return "la bomba explotó"
		"bomba_desactivada":
			return "bomba desactivada"
		"tiempo":
			return "tiempo agotado"
		"rehenes":
			return "rehenes rescatados"
		_:
			return motivo


func _punto_de_aparicion() -> Vector3:
	# Se guarda el primer punto del mapa y se reaparece siempre ahi: los .bsp
	# no distinguen spawn por equipo (info_player_start es generico), asi que
	# separar CT y T de verdad exige leer los `info_player_*` por equipo.
	if _spawn == Vector3.ZERO and jugador != null:
		_spawn = jugador.global_position + Vector3(0, 0.3, 0)
	return _spawn


# ------------------------------------------------------------------ bucle
func _process(delta: float) -> void:
	if jugador == null or not is_instance_valid(jugador):
		return

	tiempo_estado = maxf(0.0, tiempo_estado - delta)
	estado_cambiado.emit(estado, tiempo_estado)

	match estado:
		Estado.CONGELACION:
			jugador.congelado = true
			if tiempo_estado <= 0.0:
				estado = Estado.EN_JUEGO
				tiempo_estado = TIEMPO_RONDA
				jugador.congelado = false
				mensaje.emit("¡A por ellos!")

		Estado.EN_JUEGO:
			jugador.congelado = false
			_comprobar_objetivos(delta)
			if tiempo_estado <= 0.0:
				_terminar_ronda("ct", "tiempo")
			elif _enemigos_vivos() == 0 and not actores.is_empty():
				_terminar_ronda("ct" if equipo_jugador == "ct" else "t", "eliminacion")
			elif not jugador.vivo:
				_terminar_ronda("t" if equipo_jugador == "ct" else "ct", "eliminacion")

		Estado.BOMBA_PLANTADA:
			jugador.congelado = false
			_comprobar_desactivar(delta)
			# la ronda acaba por las senales de la bomba (explotada/desactivada)

		Estado.FIN_RONDA:
			jugador.congelado = true
			if tiempo_estado <= 0.0:
				if max_rondas > 0 and numero_ronda >= max_rondas:
					partida_terminada.emit(marcador())
					tiempo_estado = 0.0
					return
				numero_ronda += 1
				_iniciar_ronda()


func _comprobar_objetivos(delta: float) -> void:
	# plantar solo si eres T y estas dentro de un sitio de bomba
	if equipo_jugador != "t" or _ronda_plantada:
		return
	var dentro := BspReader.posicion_en_zona(jugador.global_position, zonas_bomba)
	if dentro < 0:
		_progreso_plantar = 0.0
		return
	if not Input.is_action_pressed("usar"):
		_progreso_plantar = 0.0
		_progreso_mensaje = -1
		return
	_progreso_plantar += delta
	if _progreso_plantar < TIEMPO_PLANTAR:
		var pct := int(_progreso_plantar / TIEMPO_PLANTAR * 100.0)
		if pct != _progreso_mensaje:
			_progreso_mensaje = pct
			mensaje.emit("Plantando... %d%%" % pct)
		return
	_plantar()


func _plantar() -> void:
	_ronda_plantada = true
	bomba = CsBomb.new()
	bomba.name = "c4"
	get_parent().add_child(bomba)
	var paleta := CsPalette.cargar()
	bomba.plantar(jugador.global_position, paleta)
	bomba.explotada.connect(_on_bomba_explotada)
	bomba.desactivada.connect(_on_bomba_desactivada)
	estado = Estado.BOMBA_PLANTADA
	tiempo_estado = CsBomb.TIEMPO
	_pagar(CsEconomy.PLANTAR_BOMBA)
	mensaje.emit("¡Bomba plantada! %d segundos" % int(CsBomb.TIEMPO))


func _comprobar_desactivar(delta: float) -> void:
	if bomba == null or not is_instance_valid(bomba):
		return
	if equipo_jugador != "ct":
		return
	var cerca := jugador.global_position.distance_to(bomba.global_position) < 2.0
	if cerca and Input.is_action_pressed("usar") and jugador.vivo:
		var progreso := bomba.progreso_desactivar(delta, jugador.tiene_kit)
		if progreso > 0.0:
			mensaje.emit("Desactivando... %d%%" % int(progreso * 100.0))
	else:
		bomba.cancelar_desactivar()


func _on_bomba_desactivada() -> void:
	bomba = null
	_terminar_ronda("ct", "bomba_desactivada")


func _on_bomba_explotada(_pos: Vector3) -> void:
	bomba = null
	_terminar_ronda("t", "bomba_explota")


## Cuántos enemigos siguen en pie (lo enseña el HUD).
func enemigos_vivos() -> int:
	return _enemigos_vivos()


func _enemigos_vivos() -> int:
	var n := 0
	for a in actores:
		if is_instance_valid(a) and a.vivo:
			n += 1
	return n


# ------------------------------------------------------------------ economía
func _pagar(cantidad: int) -> void:
	dinero = CsEconomy.limite(dinero + cantidad)
	dinero_cambiado.emit(dinero)
	if jugador != null and is_instance_valid(jugador):
		jugador.dinero = dinero


func registrar_baja(arma: String) -> void:
	bajas += 1
	_pagar(CsEconomy.recompensa_baja(arma))
	mensaje.emit("+%d$ por la baja" % CsEconomy.recompensa_baja(arma))


## Devuelve "" si la compra fue bien, o el motivo del fallo.
func comprar(id: String, en_zona: bool) -> String:
	if estado != Estado.CONGELACION:
		return "Solo puedes comprar durante el tiempo de compra"
	if not en_zona:
		return "No estás en la zona de compra"
	var precio := CsEconomy.precio(id)
	if precio <= 0:
		return "Ese objeto no existe"
	if precio > dinero:
		return "No tienes dinero (%d$ de %d$)" % [dinero, precio]

	if not jugador.comprar(id):
		return "No se pudo comprar %s" % CsEconomy.nombre(id)

	_pagar(-precio)
	mensaje.emit("Compraste %s (-%d$)" % [CsEconomy.nombre(id), precio])
	return ""


func esta_en_zona_compra(pos: Vector3) -> bool:
	if zonas_compra.is_empty():
		return true   # mapas sin buyzone: se permite comprar igualmente
	for z in zonas_compra:
		if (z["caja"] as AABB).has_point(pos):
			return true
	return false


func tiempo_restante() -> float:
	return tiempo_estado


func marcador() -> String:
	return "CT %d — %d T" % [puntos_ct, puntos_t]
