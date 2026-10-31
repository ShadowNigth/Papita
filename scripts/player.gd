class_name CsPlayer
extends CharacterBody3D
## Jugador en primera persona con el movimiento de GoldSrc.
##
## Las constantes son las del motor original (en unidades GoldSrc, ~0.025 m) y se
## convierten a metros. No es una imitacion a ojo: `sv_accelerate 10`,
## `sv_friction 4`, `sv_airaccelerate 10`, `sv_stopspeed 75`, salto 270 u/s y
## velocidad maxima 250 u/s son los valores reales de CS 1.5.

signal arma_cambiada(id: String)
signal disparo(impacto: Vector3, impacto_valido: bool)
signal estado_actualizado(vida: int, chaleco: int, cargador: int, reserva: int)

const UNIDAD := 0.025
const VEL_CAMINAR := 250.0 * UNIDAD        # 6.25 m/s
const VEL_AGACHADO := 100.0 * UNIDAD
const ACELERACION := 10.0
const ACELERACION_AIRE := 10.0
const FRICCION := 4.0
const VEL_FRENADO := 75.0 * UNIDAD
const SALTO := 270.0 * UNIDAD
const GRAVEDAD := 800.0 * UNIDAD
const ALTURA_OJOS := 64.0 * UNIDAD
const ALTURA_OJOS_AGACHADO := 28.0 * UNIDAD
const ALTURA_CAPSULA := 72.0 * UNIDAD
const ALTURA_CAPSULA_AGACHADO := 36.0 * UNIDAD

var vida: int = 100
var chaleco: int = 0
var velocidad_mira := 2.2

var camara: Camera3D
var viewmodel: CsViewmodel

var armas: Array[String] = []
var arma_actual: String = ""
var cargador: int = 0
var reserva: int = 0

var _pitch: float = 0.0
var _tiempo_disparo: float = 0.0
var _retroceso: float = 0.0
var _agachado: bool = false
var _altura_ojos: float = ALTURA_OJOS
var _recargando: bool = false
var _tiempo_recarga: float = 0.0
var _ruido: CsAudio


func _ready() -> void:
	var forma := CollisionShape3D.new()
	var capsula := CapsuleShape3D.new()
	capsula.height = ALTURA_CAPSULA
	capsula.radius = 16.0 * UNIDAD
	forma.shape = capsula
	# El nodo esta a la altura de los pies; la capsula se centra a media altura.
	forma.position.y = ALTURA_CAPSULA * 0.5
	add_child(forma)

	camara = Camera3D.new()
	camara.name = "camara"
	camara.position = Vector3(0, ALTURA_OJOS, 0)
	camara.fov = 90.0
	camara.near = 0.02
	add_child(camara)

	viewmodel = CsViewmodel.new()
	viewmodel.name = "viewmodel"
	camara.add_child(viewmodel)

	_ruido = CsAudio.new()
	add_child(_ruido)

	if armas.is_empty():
		armas = WeaponDB.EQUIPO_INICIAL.duplicate()
	for a in armas:
		viewmodel.precargar(a)
	equipar(arma_actual if not arma_actual.is_empty() else armas[-1])


func _unhandled_input(evento: InputEvent) -> void:
	if evento is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mov := (evento as InputEventMouseMotion).relative
		rotate_y(-mov.x * 0.0022 * velocidad_mira)
		_pitch = clampf(_pitch - mov.y * 0.0022 * velocidad_mira, -89.0, 89.0)
		if camara:
			camara.rotation_degrees.x = _pitch
	elif evento.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif evento is InputEventMouseButton:
		var mb := evento as InputEventMouseButton
		if mb.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_ciclar_arma(1)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_ciclar_arma(-1)
	elif evento is InputEventKey and (evento as InputEventKey).pressed:
		var tecla := (evento as InputEventKey).physical_keycode
		if tecla >= KEY_1 and tecla <= KEY_5:
			var slot := tecla - KEY_0
			_arma_de_slot(slot)
		elif tecla == KEY_R:
			_recargar()


func _physics_process(delta: float) -> void:
	_tiempo_disparo = maxf(0.0, _tiempo_disparo - delta)
	_retroceso = maxf(0.0, _retroceso - delta * 6.0)
	if _recargando:
		_tiempo_recarga -= delta
		if _tiempo_recarga <= 0.0:
			_terminar_recarga()

	_agachado = Input.is_action_pressed("agacharse")
	var altura_objetivo := ALTURA_OJOS_AGACHADO if _agachado else ALTURA_OJOS
	_altura_ojos = lerpf(_altura_ojos, altura_objetivo, delta * 12.0)
	camara.position.y = _altura_ojos

	_mover(delta)

	if Input.is_action_pressed("disparar"):
		_intentar_disparar()
	if Input.is_action_just_pressed("saltar") and is_on_floor() and not _agachado:
		velocity.y = SALTO
		_ruido.reproducir("player/pl_jump1.wav", -12.0)

	viewmodel.actualizar(delta, velocity.length(), _retroceso, _agachado)
	_actualizar_estado()


func _mover(delta: float) -> void:
	var entrada := Vector2(
		Input.get_action_strength("derecha") - Input.get_action_strength("izquierda"),
		Input.get_action_strength("atras") - Input.get_action_strength("adelante")
	)
	var deseo := (transform.basis * Vector3(entrada.x, 0, entrada.y)).normalized()

	var maxima := VEL_AGACHADO if _agachado else VEL_CAMINAR
	var en_suelo := is_on_floor()
	var horizontal := Vector3(velocity.x, 0, velocity.z)

	if en_suelo:
		# friccion del motor: solo frena si no hay entrada
		if deseo.length() < 0.01:
			var vel := horizontal.length()
			if vel > 0.0:
				var control := maxf(vel, VEL_FRENADO)
				var nueva := maxf(0.0, vel - control * FRICCION * delta)
				if vel > 0.0:
					horizontal *= nueva / vel
		# aceleracion de suelo
		_acelerar(horizontal, deseo, maxima, ACELERACION, delta)
	else:
		_acelerar(horizontal, deseo, 30.0 * UNIDAD, ACELERACION_AIRE, delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y -= GRAVEDAD * delta
	move_and_slide()


func _acelerar(velocidad: Vector3, deseo: Vector3, maxima: float, acel: float, delta: float) -> void:
	if deseo.length() < 0.01:
		return
	var objetivo := deseo * maxima
	var actual := velocidad.dot(deseo)
	var sumar := maxima - actual
	if sumar <= 0.0:
		return
	var paso := minf(acel * maxima * delta, sumar)
	velocidad.x += deseo.x * paso
	velocidad.z += deseo.z * paso


# ------------------------------------------------------------------ armas
func equipar(id: String) -> void:
	if not WeaponDB.existe(id):
		return
	if not armas.has(id):
		armas.append(id)
		viewmodel.precargar(id)
	arma_actual = id
	var datos := WeaponDB.obtener(id)
	cargador = int(datos.get("cargador", 0))
	reserva = int(datos.get("reserva", 0))
	_recargando = false
	viewmodel.equipar(datos.get("viewmodel", ""))
	arma_cambiada.emit(id)


func _ciclar_arma(direccion: int) -> void:
	if armas.size() <= 1:
		return
	var i := armas.find(arma_actual)
	i = wrapi(i + direccion, 0, armas.size())
	equipar(armas[i])


func _arma_de_slot(slot: int) -> void:
	var tipo := String(WeaponDB.SLOTS.get(slot, ""))
	if tipo.is_empty():
		return
	for id in armas:
		var datos := WeaponDB.obtener(id)
		var es_primaria: bool = String(datos.get("tipo", "")) in ["fusil", "subfusil", "escopeta", "francotirador", "ametralladora"]
		var coincide := false
		if tipo == "primaria" and es_primaria:
			coincide = true
		elif tipo == "pistola" and String(datos.get("tipo", "")) == "pistola":
			coincide = true
		elif tipo == "cuchillo" and String(datos.get("tipo", "")) == "cuchillo":
			coincide = true
		elif tipo == "granada" and String(datos.get("tipo", "")) == "granada":
			coincide = true
		if coincide:
			equipar(id)
			return


func _intentar_disparar() -> void:
	if _recargando or _tiempo_disparo > 0.0:
		return
	var datos := WeaponDB.obtener(arma_actual)
	if datos.is_empty():
		return
	var tipo := String(datos.get("tipo", ""))
	var cadencia := float(datos.get("cadencia", 600))
	_tiempo_disparo = 60.0 / maxf(1.0, cadencia)

	if tipo == "cuchillo":
		_danio_cuerpo_a_cuerpo(datos)
		return
	if tipo == "granada":
		# TODO: fisica de granada (ver docs/PENDIENTE.md)
		return
	if cargador <= 0:
		_ruido.reproducir("common/wpn_denyselect.wav", -6.0)
		_recargar()
		return
	cargador -= 1
	viewmodel.disparar(float(datos.get("retroceso", 1.0)))
	_retroceso = float(datos.get("retroceso", 1.0))
	_ruido.reproducir("weapons/" + String(datos.get("sonido", "ak47-1.wav")), -4.0)

	var perdigones := int(datos.get("perdigones", 1))
	var dispersion := float(datos.get("dispersion", 0.5))
	if velocity.length() > VEL_CAMINAR * 0.5:
		dispersion *= 2.2
	if not is_on_floor():
		dispersion *= 3.0
	for i in perdigones:
		_disparar_rayo(float(datos.get("danio", 25)), dispersion)
	disparo.emit(Vector3.ZERO, false)


func _disparar_rayo(danio: float, dispersion: float) -> void:
	var espacio := get_world_3d().direct_space_state
	var desde := camara.global_position
	var dir := -camara.global_transform.basis.z
	if dispersion > 0.0:
		dir = (dir + _aleatorio_cono(deg_to_rad(dispersion))).normalized()
	var hasta := desde + dir * 300.0
	var consulta := PhysicsRayQueryParameters3D.create(desde, hasta)
	consulta.collide_with_areas = false
	var resultado := espacio.intersect_ray(consulta)
	if resultado.is_empty():
		return
	var punto: Vector3 = resultado["position"]
	var normal: Vector3 = resultado["normal"]
	Fx.impacto(get_parent(), punto, normal, danio)
	disparo.emit(punto, true)


func _aleatorio_cono(angulo: float) -> Vector3:
	var yaw := randf_range(-angulo, angulo)
	var pitch := randf_range(-angulo, angulo)
	return Vector3(tan(yaw), tan(pitch), 0.0)


func _danio_cuerpo_a_cuerpo(datos: Dictionary) -> void:
	var alcance := float(datos.get("alcance", 1.2))
	_ruido.reproducir("weapons/" + String(datos.get("sonido", "knife_slash1.wav")), -6.0)
	var espacio := get_world_3d().direct_space_state
	var desde := camara.global_position
	var consulta := PhysicsRayQueryParameters3D.create(desde, desde - camara.global_transform.basis.z * alcance)
	var resultado := espacio.intersect_ray(consulta)
	if not resultado.is_empty():
		Fx.impacto(get_parent(), resultado["position"], resultado["normal"], float(datos.get("danio", 15)))


func _recargar() -> void:
	var datos := WeaponDB.obtener(arma_actual)
	if datos.is_empty() or int(datos.get("cargador", 0)) <= 0:
		return
	if _recargando or cargador == int(datos.get("cargador", 0)):
		return
	_recargando = true
	_tiempo_recarga = 2.4
	var sonido := String(datos.get("tipo", ""))
	_ruido.reproducir("weapons/357_reload1.wav" if sonido == "pistola" else "weapons/ak47_clipout.wav", -10.0)


func _terminar_recarga() -> void:
	_recargando = false
	var datos := WeaponDB.obtener(arma_actual)
	var capacidad := int(datos.get("cargador", 0))
	var falta := capacidad - cargador
	var tomar := mini(falta, reserva if reserva > 0 else falta)
	cargador += tomar
	if reserva > 0:
		reserva -= tomar


func _actualizar_estado() -> void:
	estado_actualizado.emit(vida, chaleco, cargador, reserva)
