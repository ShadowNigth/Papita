class_name CsViewmodel
extends Node3D
## Arma en primera persona: carga el viewmodel original (`v_*.mdl`) y lo mueve
## con balanceo, retroceso y retardo de camara, como el juego de 1999.

const RAIZ := "res://assets/models/cs15/"
const ESCALA_VISTA := 1.0 / 45.0     # los viewmodels se modelan en unidades grandes

var modelo: MeshInstance3D
var luz_boquilla: OmniLight3D
var arma_actual: String = ""

var _cache: Dictionary = {}
var _balanceo: float = 0.0
var _retroceso: float = 0.0
var _pos_base := Vector3(0.18, -0.16, -0.32)
var _flash: float = 0.0


func _ready() -> void:
	modelo = MeshInstance3D.new()
	add_child(modelo)
	luz_boquilla = OmniLight3D.new()
	luz_boquilla.light_color = Color(1.0, 0.85, 0.55)
	luz_boquilla.light_energy = 0.0
	luz_boquilla.omni_range = 3.0
	luz_boquilla.position = Vector3(0.18, -0.1, -0.65)
	add_child(luz_boquilla)
	position = _pos_base


func precargar(arma_id: String) -> void:
	var datos := WeaponDB.obtener(arma_id)
	var fichero := String(datos.get("viewmodel", ""))
	if fichero.is_empty() or _cache.has(fichero):
		return
	var ruta := RAIZ + fichero
	if not FileAccess.file_exists(ruta):
		return
	var lector := MdlReader.cargar(ruta, CsPalette.cargar())
	_cache[fichero] = lector


func equipar(fichero: String) -> void:
	if fichero.is_empty():
		return
	arma_actual = fichero
	if not _cache.has(fichero):
		precargar_por_fichero(fichero)
	var lector: MdlReader = _cache.get(fichero)
	if lector == null:
		modelo.mesh = null
		return
	modelo.mesh = lector.construir_malla()
	# Los v_*.mdl llevan la profundidad en -Y. Primero se convierte el StudioModel
	# Z-up a la camara Y-up y luego se gira 180 grados para que -Y mire por -Z,
	# hacia delante; sin esa orientacion el arma queda detras de la camara.
	modelo.quaternion = Quaternion(Vector3.UP, PI) * Quaternion(Vector3.RIGHT, -PI * 0.5)
	modelo.scale = Vector3.ONE * ESCALA_VISTA
	modelo.position = Vector3.ZERO
	# El viewmodel se dibuja por delante del mundo (como en GoldSrc).
	modelo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	modelo.set_layer_mask_value(1, false)
	modelo.set_layer_mask_value(20, true)


func precargar_por_fichero(fichero: String) -> void:
	var ruta := RAIZ + fichero
	if not FileAccess.file_exists(ruta):
		return
	_cache[fichero] = MdlReader.cargar(ruta, CsPalette.cargar())


func disparar(retroceso: float) -> void:
	_retroceso = clampf(_retroceso + retroceso * 0.06, 0.0, 0.5)
	_flash = 0.05
	if luz_boquilla:
		luz_boquilla.light_energy = 3.0 * clampf(retroceso, 0.4, 2.0)


func actualizar(delta: float, velocidad: float, retroceso_padre: float, agachado: bool) -> void:
	_retroceso = lerpf(_retroceso, 0.0, delta * 8.0)
	_flash = maxf(0.0, _flash - delta)
	if luz_boquilla:
		luz_boquilla.light_energy = lerpf(luz_boquilla.light_energy, 0.0, delta * 18.0)

	# balanceo al andar (dos senos desfasados, como el "bob" de GoldSrc)
	_balanceo += delta * velocidad * 1.6
	var bob := Vector3(sin(_balanceo) * 0.012, absf(cos(_balanceo)) * 0.010, 0.0)
	var caida := -0.02 if agachado else 0.0

	position = position.lerp(_pos_base + bob + Vector3(0, caida, 0), delta * 12.0)
	rotation_degrees.z = lerpf(rotation_degrees.z, sin(_balanceo * 0.5) * 1.5, delta * 10.0)
	rotation_degrees.x = lerpf(rotation_degrees.x, _retroceso * 45.0, delta * 14.0)
	position.z = _pos_base.z + _retroceso * 0.12
