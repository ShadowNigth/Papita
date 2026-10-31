class_name BotAI
extends Node
## IA de un actor enemigo: percibe, dispara y se mueve por el mapa.
##
## No es un `CharacterBody3D`: el actor es un `ActorModel` (Node3D) que ya sabe
## animarse, y este nodo lo mueve y le da vida de combate. La lógica está en
## cuatro estados, los mismos que usa cualquier shooter:
##
##   PATRULLA  va hacia un objetivo del mapa (sitio de bomba o punto aleatorio)
##   ALERTA    oyó disparos o perdió de vista al jugador y va a su última posición
##   COMBATE   ve al jugador: apunta, dispara en ráfagas y se mueve de lado
##   RECARGA   se queda sin balas y cambia el cargador
##
## Lo que **no** hace (ver `docs/PENDIENTE.md`): no usa granadas, no distingue
## cabeza del cuerpo y no oye pasos (solo disparos).

enum Estado { PATRULLA, ALERTA, COMBATE, RECARGA }

const ALTURA_OJOS := 1.55
const ALTURA_PECHO := 1.15
const RADIO_SEPARACION := 0.9

## Niveles de dificultad, con los nombres de los `bot_skill` del original.
const NIVELES := [
	{"nombre": "fácil", "reaccion": 0.65, "error": 3.2, "vision": 45.0, "cadencia": 0.65},
	{"nombre": "normal", "reaccion": 0.38, "error": 2.0, "vision": 60.0, "cadencia": 0.85},
	{"nombre": "difícil", "reaccion": 0.22, "error": 1.1, "vision": 80.0, "cadencia": 1.0},
]

var actor: ActorModel
var jugador: CsPlayer
var nav: NavGrid
var director: MatchDirector

var estado: int = Estado.PATRULLA
var dificultad: int = 1
var congelado: bool = false

var arma: String = "ak47"
var cargador: int = 30
var reserva: int = 90
var _cadencia: float = 600.0
var _danio: float = 30.0
var _dispersion: float = 1.0
var _tiempo_recarga: float = 2.4
var _sonido: String = "ak47-1.wav"

var objetivo: Vector3 = Vector3.ZERO
var _camino: PackedVector3Array = PackedVector3Array()
var _paso: int = 0
var _recalcular: float = 0.0
var _subiendo_escalera: bool = false
var _ve_al_jugador: bool = false
var _visto_hace: float = 99.0
var _ultima_pos: Vector3 = Vector3.ZERO
var _reaccion: float = 0.0
var _espera_disparo: float = 0.0
## Balas que quedan en la ráfaga actual. Un bot que dispara el cargador entero
## de golpe es una ametralladora, no un jugador: el original dispara a golpes
## de 3 a 6 balas y luego respira.
var _rafaga: int = 0
var _recarga_restante: float = 0.0
var _pausa: float = 0.0
var _lateral: float = 0.0
var _tiempo_lateral: float = 0.0
var _estaba_vivo: bool = true
var _audio: CsAudio
var _rng := RandomNumberGenerator.new()


func configurar(p_actor: ActorModel, p_jugador: CsPlayer, p_nav: NavGrid,
		p_equipo: String, p_dificultad: int = 1) -> void:
	actor = p_actor
	jugador = p_jugador
	nav = p_nav
	dificultad = clampi(p_dificultad, 0, NIVELES.size() - 1)
	_rng.randomize()

	# El arma depende del bando, como en el original: fusil de cada lado y,
	# si no existe el modelo, lo que haya.
	var preferidas := ["ak47", "m4a1"] if p_equipo == "t" else ["m4a1", "ak47"]
	var elegida := ""
	for id: String in preferidas:
		if WeaponDB.existe(id):
			elegida = id
			break
	if elegida.is_empty():
		elegida = "knife"
	if not elegida.is_empty():
		poner_arma(elegida)

	objetivo = actor.global_position
	_audio = CsAudio.new()
	_audio.name = "audio_bot"
	if actor.is_inside_tree():
		actor.add_child(_audio)


## Cambia el arma del bot, con sus estadísticas reales del `weapon_db`.
func poner_arma(id: String) -> void:
	if not WeaponDB.existe(id):
		return
	var datos := WeaponDB.obtener(id)
	arma = id
	_cadencia = float(datos.get("cadencia", 600))
	_danio = float(datos.get("danio", 30))
	_dispersion = float(datos.get("dispersion", 1.0))
	_sonido = String(datos.get("sonido", "ak47-1.wav"))
	cargador = int(datos.get("cargador", 30))
	reserva = int(datos.get("reserva", 90))
	_tiempo_recarga = 2.4
	if String(datos.get("tipo", "")) == "escopeta":
		_tiempo_recarga = 3.2


func nombre_dificultad() -> String:
	return String(NIVELES[dificultad]["nombre"])


## El director congela a los bots durante la congelación y el fin de ronda.
func congelar(si: bool) -> void:
	congelado = si
	if not si:
		_pausa = 0.0


func _process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if not actor.vivo:
		if _estaba_vivo:
			_estaba_vivo = false
			cargador = maxi(cargador, 0)
		return
	if not _estaba_vivo:
		# lo ha revivido el director al empezar la ronda
		_estaba_vivo = true
		_estado_reset()
	if congelado:
		actor.animar_por_velocidad(0.0)
		return
	if jugador == null or not is_instance_valid(jugador):
		return

	_reaccion = maxf(0.0, _reaccion - delta)
	_visto_hace += delta
	_espera_disparo = maxf(0.0, _espera_disparo - delta)
	_tiempo_lateral -= delta

	_percibir(delta)

	if estado == Estado.RECARGA:
		_recarga_restante -= delta
		actor.animar_por_velocidad(0.0)
		if _recarga_restante <= 0.0:
			_recargar()
		return

	if _ve_al_jugador:
		estado = Estado.COMBATE
		_combatir(delta)
	else:
		_mover_sin_ver(delta)


# ----------------------------------------------------------------- percepción
func _percibir(_delta: float) -> void:
	_ve_al_jugador = false
	if not jugador.vivo:
		return
	var ojo := _ojo()
	var pecho := jugador.global_position + Vector3(0, 1.1, 0)
	var distancia := ojo.distance_to(pecho)
	if distancia > float(NIVELES[dificultad]["vision"]):
		return
	# campo de visión: mirar por la espalda es no ver, salvo que te disparen
	var hacia := pecho - ojo
	if _visto_hace > 2.0:
		var adelante := actor.global_transform.basis.x   # los .mdl miran hacia +X
		var plano := Vector3(hacia.x, 0, hacia.z)
		if plano.length() > 0.1 and adelante.normalized().dot(plano.normalized()) < 0.1:
			return
	# línea de visión: ni paredes ni otros bots
	var espacio := actor.get_world_3d().direct_space_state
	if espacio == null:
		return
	var excluir: Array[RID] = []
	if actor.tiene_cuerpo():
		excluir.append(actor.cuerpo().get_rid())
	var consulta := PhysicsRayQueryParameters3D.create(ojo, pecho, 0xFFFFFFFF, excluir)
	var resultado := espacio.intersect_ray(consulta)
	if resultado.is_empty():
		_ve_al_jugador = true
	elif resultado.get("collider") == jugador:
		_ve_al_jugador = true
	elif resultado.get("collider") is Node and (resultado["collider"] as Node).get_meta("jugador", false):
		_ve_al_jugador = true

	if _ve_al_jugador:
		if _visto_hace > 0.4:
			_reaccion = float(NIVELES[dificultad]["reaccion"])
			_pausa = 0.0
		_visto_hace = 0.0
		_ultima_pos = jugador.global_position


# ------------------------------------------------------------------- combate
func _combatir(delta: float) -> void:
	var ojo := _ojo()
	var pecho := jugador.global_position + Vector3(0, 1.1, 0)
	var hacia := pecho - ojo
	var distancia := Vector2(hacia.x, hacia.z).length()

	# apuntar: girar en el plano y mirar arriba/abajo (el modelo solo gira en Y,
	# el ángulo vertical se usa para calcular el disparo)
	var plano := Vector3(hacia.x, 0, hacia.z)
	if plano.length() > 0.05:
		var objetivo_y := atan2(-plano.z, plano.x)
		actor.rotation.y = lerp_angle(actor.rotation.y, objetivo_y, minf(1.0, delta * 7.0))

	# moverse: de lado si está cerca, acercarse si está lejos
	if _tiempo_lateral <= 0.0:
		_tiempo_lateral = _rng.randf_range(0.4, 1.1)
		_lateral = _rng.randf_range(-1.0, 1.0)
	if _subiendo_escalera:
		_seguir_camino(delta, 3.2)
	elif distancia < 18.0:
		_moverse_lateral(delta, _lateral)
	elif _camino.is_empty() or _recalcular <= 0.0:
		_ir_a(jugador.global_position)
		_seguir_camino(delta, 3.2)
	else:
		_seguir_camino(delta, 3.2)

	# disparar
	if cargador <= 0:
		if reserva <= 0:
			return       # sin balas: solo puede mirar
		estado = Estado.RECARGA
		_recarga_restante = _tiempo_recarga
		return
	if _reaccion > 0.0 or _espera_disparo > 0.0:
		return
	_disparar(ojo, pecho, distancia)


func _disparar(ojo: Vector3, pecho: Vector3, distancia: float) -> void:
	var nivel: Dictionary = NIVELES[dificultad]
	# El error crece con la distancia y con el arma; se sortea un punto dentro de
	# un cono. Es lo que hace que a 30 m fallen y a 5 m no.
	var error_grados := float(nivel["error"]) * (0.6 + distancia / 25.0) \
		* (0.5 + _dispersion * 0.5)
	var hacia := (pecho - ojo).normalized()
	var error := Vector3(
		_rng.randfn(0.0, tan(deg_to_rad(error_grados)) * 0.5),
		_rng.randfn(0.0, tan(deg_to_rad(error_grados)) * 0.5), 0.0)
	hacia = (hacia + error).normalized()
	var hasta := ojo + hacia * 200.0

	var espacio := actor.get_world_3d().direct_space_state
	var excluir: Array[RID] = []
	if actor.tiene_cuerpo():
		excluir.append(actor.cuerpo().get_rid())
	var resultado: Dictionary = {}
	if espacio != null:
		var consulta := PhysicsRayQueryParameters3D.create(ojo, hasta, 0xFFFFFFFF, excluir)
		resultado = espacio.intersect_ray(consulta)

	cargador -= 1
	_espera_disparo = 60.0 / maxf(1.0, float(nivel["cadencia"]) * _cadencia)
	_rafaga -= 1
	if _rafaga <= 0:
		_rafaga = _rng.randi_range(3, 6)
		# el difícil respira menos entre ráfagas
		var respiro := _rng.randf_range(0.35, 1.1) * (1.3 - 0.25 * float(dificultad))
		_espera_disparo += respiro
	if _audio != null:
		_audio.reproducir("weapons/" + _sonido, -3.0)
	actor.animar_disparo()

	if resultado.is_empty():
		Fx.trazadora(actor.get_parent(), ojo, hasta)
		return
	var punto: Vector3 = resultado["position"]
	Fx.trazadora(actor.get_parent(), ojo, punto)
	if resultado.get("collider") == jugador:
		jugador.recibir_danio(_danio, ojo)
	elif resultado.get("collider") is Node and (resultado["collider"] as Node).get_meta("jugador", false):
		jugador.recibir_danio(_danio, ojo)
	else:
		Fx.impacto(actor.get_parent(), punto, resultado.get("normal", Vector3.UP), _danio)


func _recargar() -> void:
	var falta := cargador_max() - cargador
	var tomar := mini(falta, reserva)
	cargador += tomar
	reserva -= tomar
	estado = Estado.PATRULLA
	_espera_disparo = 0.3


func cargador_max() -> int:
	return maxi(1, int(WeaponDB.obtener(arma).get("cargador", 30)))


# ---------------------------------------------------------------- movimiento
func _mover_sin_ver(delta: float) -> void:
	if _visto_hace < 4.0 and _ultima_pos != Vector3.ZERO:
		estado = Estado.ALERTA
		_ir_a(_ultima_pos)
	else:
		estado = Estado.PATRULLA
		if not _subiendo_escalera and (_camino.is_empty() or _paso >= _camino.size() or _recalcular <= 0.0):
			_objetivo_de_patrulla()
	var rapidez := 3.2 if estado == Estado.ALERTA else 2.4
	_seguir_camino(delta, rapidez)


func _objetivo_de_patrulla() -> void:
	if _pausa > 0.0:
		_pausa -= get_process_delta_time()
		return
	# Si es terrorista y hay sitio de bomba, va hacia allí; si no, a un nodo
	# cualquiera del grafo, para que patrulle de verdad por el mapa.
	if director != null and is_instance_valid(director) and not director.zonas_bomba.is_empty() \
			and actor.equipo == "t":
		var zona: Dictionary = director.zonas_bomba[_rng.randi() % director.zonas_bomba.size()]
		var caja: AABB = zona["caja"]
		_ir_a(caja.get_center())
	elif nav != null and nav.valido():
		var idx := _rng.randi() % nav.posiciones.size()
		_ir_a(BspReader._a_godot(nav.posiciones[idx]))
	else:
		_ir_a(actor.global_position + Vector3(_rng.randf_range(-12, 12), 0,
			_rng.randf_range(-12, 12)))
	_pausa = _rng.randf_range(1.0, 3.0)


func _ir_a(destino: Vector3) -> void:
	if nav == null or not nav.valido():
		_camino = PackedVector3Array()
		return
	_camino = nav.camino(actor.global_position, destino)
	_subiendo_escalera = false
	if _camino.is_empty() and destino.distance_to(actor.global_position) > 1.0:
		# Sin ruta (el jugador se ha subido a un tejado, o el mapa no tiene
		# grafo): al menos se acerca en línea recta. Ver PENDIENTE.md.
		_camino.append(destino)
	_paso = 0
	_recalcular = 1.5


func _seguir_camino(delta: float, rapidez: float) -> void:
	_recalcular = maxf(0.0, _recalcular - delta)
	if _camino.is_empty():
		actor.animar_por_velocidad(0.0)
		if estado == Estado.PATRULLA:
			_objetivo_de_patrulla()
		return
	if _paso >= _camino.size():
		_camino = PackedVector3Array()
		actor.animar_por_velocidad(0.0)
		_pausa = _rng.randf_range(0.8, 2.0)
		return
	var destino := _camino[_paso]
	var dxz := Vector2(destino.x - actor.global_position.x, destino.z - actor.global_position.z)
	var distancia_horizontal := dxz.length()
	var diferencia_vertical := destino.y - actor.global_position.y

	# Los waypoints de una escalera están uno encima del otro. Primero se alinea
	# con la caja y luego se sube/baja a velocidad constante; no se interpola en
	# diagonal atravesando la pared. Se bloquea el recálculo hasta llegar arriba.
	if absf(diferencia_vertical) > 0.15 and distancia_horizontal < 1.2:
		_subiendo_escalera = true
		if distancia_horizontal > 0.12:
			var direccion_lateral := Vector3(dxz.x, 0.0, dxz.y).normalized()
			actor.global_position += direccion_lateral * rapidez * delta
			if estado != Estado.COMBATE:
				actor.rotation.y = atan2(-direccion_lateral.z, direccion_lateral.x)
			actor.animar_por_velocidad(rapidez)
			return
		var vel_escalera := 2.2
		actor.global_position.y = move_toward(actor.global_position.y, destino.y, vel_escalera * delta)
		actor.animar_por_velocidad(vel_escalera)
		if absf(destino.y - actor.global_position.y) < 0.08:
			_paso += 1
			_subiendo_escalera = false
		return

	_subiendo_escalera = false
	if distancia_horizontal < 0.7:
		_paso += 1
		return
	var direccion := Vector3(dxz.x, 0.0, dxz.y).normalized()
	actor.global_position += direccion * rapidez * delta
	# En las rampas normales se interpola la altura; no hay tirones.
	actor.global_position.y = lerpf(actor.global_position.y, destino.y, minf(1.0, delta * 8.0))
	if estado != Estado.COMBATE:
		actor.rotation.y = atan2(-direccion.z, direccion.x)
	actor.animar_por_velocidad(rapidez)


func _moverse_lateral(delta: float, sentido: float) -> void:
	if absf(sentido) < 0.15:
		actor.animar_por_velocidad(0.0)
		return
	var adelante := actor.global_transform.basis.x
	var derecha := Vector3(-adelante.z, 0.0, adelante.x).normalized()
	var destino := actor.global_position + derecha * signf(sentido) * 1.2
	# solo si hay hueco: no atravesar la pared de al lado
	if nav != null and nav.valido() and nav.bsp != null:
		var sonda := destino + Vector3(0, 0.6, 0)
		if nav.bsp.contenido(sonda) != -1:
			actor.animar_por_velocidad(0.0)
			return
	actor.global_position += derecha * signf(sentido) * 2.2 * delta
	actor.animar_por_velocidad(2.2)


func _ojo() -> Vector3:
	return actor.global_position + Vector3(0, ALTURA_OJOS, 0)


## Vuelve al estado inicial (lo llama el juego al empezar cada ronda).
func reiniciar() -> void:
	_estado_reset()


func _estado_reset() -> void:
	estado = Estado.PATRULLA
	_camino = PackedVector3Array()
	_paso = 0
	_recalcular = 0.0
	_subiendo_escalera = false
	_visto_hace = 99.0
	_reaccion = 0.0
	_espera_disparo = 0.0
	_rafaga = 0
	_pausa = 0.0
	var datos := WeaponDB.obtener(arma)
	cargador = int(datos.get("cargador", 30))
	reserva = int(datos.get("reserva", 90))
