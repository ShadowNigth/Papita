class_name MapDoor
extends AnimatableBody3D
## Puerta brush de GoldSrc, separada de la geometría estática del mundo.
##
## El modelo conserva sus caras/lightmaps originales. Las `func_door` se
## desplazan según angle/angles + lip; las `func_door_rotating` giran sobre el
## eje vertical. Para que el mapa sea jugable, todas abren al acercarse un
## jugador o un bot; los botones y las cadenas `target` quedan fuera de alcance.

enum Estado { CERRADA, ABRIENDO, ABIERTA, CERRANDO }

const ESCALA := 0.025
const MARGEN_ACTIVACION := Vector3(0.9, 0.9, 0.9)
const FLAG_START_OPEN := 1
const FLAG_REVERSE_DIRECTION := 2
const FLAG_PASSABLE := 8
const FLAG_NO_AUTO_RETURN := 32

var estado: Estado = Estado.CERRADA
var _rotatoria: bool = false
var _pos_cerrada: Vector3 = Vector3.ZERO
var _pos_abierta: Vector3 = Vector3.ZERO
var _rot_cerrada: Vector3 = Vector3.ZERO
var _rot_abierta: Vector3 = Vector3.ZERO
var _velocidad_lineal: float = 1.0
var _velocidad_angular: float = 1.0
var _espera: float = 4.0
var _temporizador: float = 0.0
var _ocupantes: Dictionary = {}
var _activacion: Area3D


## Configura el movimiento desde las claves reales del .bsp y crea el volumen
## invisible que detecta a jugadores y cuerpos de los bots.
func configurar(entidad: Dictionary, caja_goldsrc: AABB, caja_godot: AABB) -> void:
	var texto_origen := String(entidad.get("origin", "")).strip_edges()
	if not texto_origen.is_empty():
		position = BspReader.origin_de(entidad)

	var clase := String(entidad.get("classname", "func_door"))
	_rotatoria = clase == "func_door_rotating"
	var velocidad := maxf(1.0, float(entidad.get("speed", "100")))
	var flags := int(entidad.get("spawnflags", "0"))
	collision_layer = 0 if (flags & FLAG_PASSABLE) != 0 else 1
	collision_mask = 1
	_espera = float(entidad.get("wait", "4"))
	if _espera < 0.0 or (flags & FLAG_NO_AUTO_RETURN) != 0:
		_espera = -1.0

	_pos_cerrada = position
	_pos_abierta = position
	_rot_cerrada = rotation
	_rot_abierta = rotation
	if _rotatoria:
		var grados := float(entidad.get("distance", "90"))
		if (flags & FLAG_REVERSE_DIRECTION) != 0:
			grados = -grados
		_rot_abierta.y += deg_to_rad(grados)
		_velocidad_angular = deg_to_rad(velocidad)
	else:
		var direccion_goldsrc := _direccion_lineal(entidad)
		if (flags & FLAG_REVERSE_DIRECTION) != 0:
			direccion_goldsrc = -direccion_goldsrc
		var distancia := absf(direccion_goldsrc.x) * caja_goldsrc.size.x \
			+ absf(direccion_goldsrc.y) * caja_goldsrc.size.y \
			+ absf(direccion_goldsrc.z) * caja_goldsrc.size.z \
			- float(entidad.get("lip", "0"))
		var direccion_godot := BspReader._a_godot(direccion_goldsrc).normalized()
		_pos_abierta += direccion_godot * distancia * ESCALA
		_velocidad_lineal = velocidad * ESCALA

	_activacion = Area3D.new()
	_activacion.name = "activacion"
	_activacion.collision_layer = 0
	_activacion.collision_mask = 1
	_activacion.monitoring = true
	_activacion.monitorable = false
	var forma := CollisionShape3D.new()
	var caja := BoxShape3D.new()
	caja.size = caja_godot.size + MARGEN_ACTIVACION
	forma.shape = caja
	forma.position = caja_godot.position + caja_godot.size * 0.5
	_activacion.add_child(forma)
	add_child(_activacion)

	if (flags & FLAG_START_OPEN) != 0:
		position = _pos_abierta
		rotation = _rot_abierta
		estado = Estado.ABIERTA
		_temporizador = _espera


func _ready() -> void:
	add_to_group("map_doors")
	# AnimatableBody3D mantiene sincronizada la colisión móvil con el paso de
	# física; mover un StaticBody3D corriente puede dejar la forma desfasada.
	sync_to_physics = true
	if _activacion != null:
		_activacion.body_entered.connect(_al_entrar)
		_activacion.body_exited.connect(_al_salir)


func _physics_process(delta: float) -> void:
	match estado:
		Estado.ABRIENDO:
			if _rotatoria:
				rotation.y = move_toward(rotation.y, _rot_abierta.y, _velocidad_angular * delta)
				if absf(rotation.y - _rot_abierta.y) < 0.001:
					rotation = _rot_abierta
					_terminar_apertura()
			else:
				position = position.move_toward(_pos_abierta, _velocidad_lineal * delta)
				if position.distance_to(_pos_abierta) < 0.005:
					position = _pos_abierta
					_terminar_apertura()
		Estado.ABIERTA:
			if _espera >= 0.0:
				_temporizador -= delta
				if _temporizador <= 0.0 and _ocupantes.is_empty():
					estado = Estado.CERRANDO
		Estado.CERRANDO:
			if _rotatoria:
				rotation.y = move_toward(rotation.y, _rot_cerrada.y, _velocidad_angular * delta)
				if absf(rotation.y - _rot_cerrada.y) < 0.001:
					rotation = _rot_cerrada
					estado = Estado.CERRADA
			else:
				position = position.move_toward(_pos_cerrada, _velocidad_lineal * delta)
				if position.distance_to(_pos_cerrada) < 0.005:
					position = _pos_cerrada
					estado = Estado.CERRADA


## Puede llamarlo un botón o una entidad target cuando se implementen.
func activar() -> void:
	if estado == Estado.ABIERTA:
		_temporizador = _espera
	else:
		estado = Estado.ABRIENDO


func _terminar_apertura() -> void:
	estado = Estado.ABIERTA
	_temporizador = _espera


func _al_entrar(cuerpo: Node3D) -> void:
	if not _es_actor(cuerpo):
		return
	_ocupantes[cuerpo.get_instance_id()] = true
	activar()


func _al_salir(cuerpo: Node3D) -> void:
	_ocupantes.erase(cuerpo.get_instance_id())


func _es_actor(cuerpo: Node) -> bool:
	if cuerpo is CsPlayer:
		return true
	if cuerpo.has_meta("actor"):
		var actor: Variant = cuerpo.get_meta("actor")
		return actor is ActorModel and (actor as ActorModel).vivo
	return false


func _direccion_lineal(entidad: Dictionary) -> Vector3:
	if entidad.has("angle"):
		var angulo := float(entidad["angle"])
		if is_equal_approx(angulo, -1.0):
			return Vector3(0, 0, 1)
		if is_equal_approx(angulo, -2.0):
			return Vector3(0, 0, -1)
		var yaw := deg_to_rad(angulo)
		return Vector3(cos(yaw), sin(yaw), 0.0)

	if entidad.has("angles"):
		var partes := String(entidad["angles"]).split(" ", false)
		if partes.size() >= 3:
			var pitch := deg_to_rad(float(partes[0]))
			var yaw := deg_to_rad(float(partes[1]))
			return Vector3(cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), -sin(pitch))
	return Vector3.RIGHT
