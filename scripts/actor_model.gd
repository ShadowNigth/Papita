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
	return true


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


func morir() -> void:
	var vivos := ["death1", "death2", "death3"]
	var elegido := vivos[randi() % vivos.size()]
	for nombre in vivos:
		if lector.indice_secuencia(nombre) < 0:
			continue
		elegido = nombre
		break
	reproducir(elegido, 1.0, false)


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
