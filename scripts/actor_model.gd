class_name ActorModel
extends Node3D
## Soldado o rehén animado a partir de un `.mdl` original de CS 1.5.
##
## El skinning lo hace la GPU: `Skeleton3D` con la jerarquía del modelo y un
## `Skin` calculado con `create_skin_from_rest_transforms()`. Cada cuadro se
## calcula la pose con `MdlReader.pose()` (el mismo algoritmo del motor) y se
## aplica hueso a hueso con `set_bone_pose()`.
##
## Ventaja frente a reconstruir la malla por cuadro: la geometría se sube a la
## GPU una sola vez y animar cuesta 53 transformaciones, no 800 vértices.

const RAIZ_MODELOS := "res://assets/models/cs15/"

var lector: MdlReader
var esqueleto: Skeleton3D
var instancia: MeshInstance3D

var secuencia: int = -1
var nombre_actual: String = ""
var tiempo: float = 0.0
var velocidad: float = 1.0
var bucle: bool = true
var errores: Array[String] = []

## Vida y estado de combate. El actor es un blanco simple: no dispara.
var vida: int = 100
var vivo: bool = true
var equipo: String = "t"
var _golpe: StaticBody3D


func cargar(fichero: String, paleta: CsPalette) -> bool:
	var ruta := RAIZ_MODELOS + fichero
	if not FileAccess.file_exists(ruta):
		errores.append("no existe " + ruta)
		return false
	lector = MdlReader.cargar(ruta, paleta)
	if lector == null or not lector.errores.is_empty():
		errores.append_array(lector.errores if lector != null else ["no se pudo leer"])
		return false

	esqueleto = lector.construir_esqueleto()
	esqueleto.name = "esqueleto"
	add_child(esqueleto)

	instancia = MeshInstance3D.new()
	instancia.name = "malla"
	instancia.mesh = lector.construir_malla_animada()
	esqueleto.add_child(instancia)

	# El Skin hace falta para que la malla siga a los huesos. Los binds se
	# calculan desde las poses de reposo del propio esqueleto.
	instancia.skin = esqueleto.create_skin_from_rest_transforms()
	_enganchar_esqueleto()
	_crear_caja_de_golpe()
	return true


## Caja invisible para que los rayos del jugador acierten al soldado. Se marca
## con `actor` en los metadatos para que `player.gd` sepa a quien hirio.
func _crear_caja_de_golpe() -> void:
	_golpe = StaticBody3D.new()
	_golpe.name = "golpe"
	_golpe.set_meta("actor", self)
	var forma := CollisionShape3D.new()
	var capsula := CapsuleShape3D.new()
	capsula.height = 1.7
	capsula.radius = 0.35
	forma.shape = capsula
	forma.position.y = 0.85
	_golpe.add_child(forma)
	add_child(_golpe)


func _enganchar_esqueleto() -> void:
	if instancia == null or esqueleto == null:
		return
	if not is_inside_tree():
		# `get_path_to` necesita estar en el arbol: se reintenta al entrar.
		call_deferred("_enganchar_esqueleto")
		return
	instancia.skeleton = instancia.get_path_to(esqueleto)


func _ready() -> void:
	_enganchar_esqueleto()


## Reproduce una secuencia por nombre ("walk", "run", "idle1", "death1"...).
func reproducir(nombre: String, vel: float = 1.0, repetir: bool = true) -> bool:
	if lector == null:
		return false
	var i := lector.indice_secuencia(nombre)
	if i < 0:
		return false
	if i == secuencia and nombre == nombre_actual:
		velocidad = vel
		return true
	secuencia = i
	nombre_actual = nombre
	tiempo = 0.0
	velocidad = vel
	bucle = repetir
	_aplicar_cuadro(0.0)
	return true


## Elige animación según lo rápido que se mueva el actor (m/s).
func animar_por_velocidad(metros_por_segundo: float, agachado: bool = false) -> void:
	if lector == null:
		return
	if agachado:
		if metros_por_segundo < 0.2:
			reproducir("crouch_idle")
		else:
			reproducir("crouchrun")
	elif metros_por_segundo < 0.25:
		reproducir("idle1")
	elif metros_por_segundo < 3.2:
		reproducir("walk", clampf(metros_por_segundo / 2.0, 0.6, 1.6))
	else:
		reproducir("run", clampf(metros_por_segundo / 5.0, 0.8, 1.5))


## Daño recibido del jugador.
func recibir_danio(cantidad: float, _punto: Vector3 = Vector3.ZERO) -> void:
	if not vivo:
		return
	# los headshots no se distinguen: la caja es una capsula entera
	vida -= int(maxf(1.0, cantidad * 1.6))
	if vida <= 0:
		vida = 0
		vivo = false
		if _golpe != null:
			_golpe.collision_layer = 0
			_golpe.collision_mask = 0
		morir()
		var temporizador := get_tree().create_timer(6.0)
		temporizador.timeout.connect(_ocultar_cadaver)


func _ocultar_cadaver() -> void:
	visible = false


## Vuelve a estar vivo al empezar la ronda.
func revivir() -> void:
	vivo = true
	vida = 100
	visible = true
	if _golpe != null:
		_golpe.collision_layer = 1
		_golpe.collision_mask = 1
	reproducir("idle1")


func morir() -> void:
	if lector == null:
		return
	# Las tres muertes del original; se elige una al azar de las que existan.
	var disponibles: Array[String] = []
	for nombre in ["death1", "death2", "death3", "crouch_die"]:
		if lector.indice_secuencia(nombre) >= 0:
			disponibles.append(nombre)
	if disponibles.is_empty():
		return
	reproducir(disponibles[randi() % disponibles.size()], 1.0, false)


func secuencias_disponibles() -> PackedStringArray:
	return lector.lista_secuencias() if lector != null else PackedStringArray()


func _process(delta: float) -> void:
	if lector == null or secuencia < 0 or esqueleto == null:
		return
	var desc: Dictionary = lector.secuencias[secuencia]
	var fps: float = maxf(1.0, float(desc["fps"]))
	var total := maxf(1.0, float(desc["cuadros"]) - 1.0)

	tiempo += delta * velocidad
	var cuadro := tiempo * fps
	if cuadro >= total:
		if bucle:
			cuadro = fmod(cuadro, total)
			tiempo = cuadro / fps
		else:
			cuadro = total
			tiempo = total / fps
	_aplicar_cuadro(cuadro)


func _aplicar_cuadro(cuadro: float) -> void:
	if lector == null or esqueleto == null or secuencia < 0:
		return
	var poses := lector.pose(secuencia, cuadro)
	var n := mini(poses.size(), esqueleto.get_bone_count())
	for i in n:
		esqueleto.set_bone_pose(i, poses[i])
