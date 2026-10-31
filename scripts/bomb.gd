class_name CsBomb
extends Node3D
## C4 plantado: cuenta atrás de 35 s (CS 1.5, no los 40 del 1.6), pitidos cada
## vez más rápidos y explosión con daño en área.
##
## El modelo que se ve es el original (`w_c4.mdl`), colocado en el sitio de
## bomba donde se plantó.

signal explotada(posicion: Vector3)
signal desactivada

const TIEMPO := 35.0            # mp_c4timer del 1.5
const RADIO_DANIO := 500.0 * 0.025   # ~12.5 m
const DANIO_MAX := 200.0

var restante: float = TIEMPO
var activa: bool = false
## Segundos que lleva el jugador desactivando sin soltar. No lo toca `_process`:
## solo avanza mientras `progreso_desactivar()` se llama cada cuadro.
var desactivando: float = 0.0
var tiempo_desactivar: float = 10.0   # con kit son 5 s
var _pitido: float = 0.0
var _audio: CsAudio
var _modelo: MeshInstance3D
var _luz: OmniLight3D


func plantar(pos: Vector3, paleta: CsPalette) -> void:
	position = pos
	activa = true
	restante = TIEMPO
	_pitido = 0.0
	_audio = CsAudio.new()
	add_child(_audio)
	_crear_visual(paleta)
	_audio.reproducir("weapons/c4_plant.wav", 0.0)


func _crear_visual(paleta: CsPalette) -> void:
	var ruta := "res://assets/models/cs15/w_c4.mdl"
	if FileAccess.file_exists(ruta):
		var lector := MdlReader.cargar(ruta, paleta)
		if lector != null and lector.errores.is_empty():
			_modelo = MeshInstance3D.new()
			_modelo.mesh = lector.construir_malla()
			# los modelos de arma del suelo estan en unidades grandes
			_modelo.scale = Vector3.ONE * 0.03
			add_child(_modelo)
	_luz = OmniLight3D.new()
	_luz.light_color = Color(1.0, 0.15, 0.1)
	_luz.light_energy = 0.0
	_luz.omni_range = 2.0
	add_child(_luz)


func _process(delta: float) -> void:
	if not activa:
		return
	restante -= delta
	if restante <= 0.0:
		_explotar()
		return

	# pitido: la frecuencia sube segun se acerca el final
	var intervalo := clampf(restante / 35.0, 0.06, 1.0) * 1.1
	_pitido += delta
	if _pitido >= intervalo:
		_pitido = 0.0
		if _audio:
			_audio.reproducir("weapons/c4_beep1.wav", -6.0)
		if _luz:
			_luz.light_energy = 2.0

	if _luz:
		_luz.light_energy = lerpf(_luz.light_energy, 0.0, delta * 10.0)


## El jugador mantiene pulsado "usar" sobre la bomba. Devuelve el progreso 0..1.
func progreso_desactivar(delta: float, tiene_kit: bool) -> float:
	if not activa:
		return 0.0
	var total := 5.0 if tiene_kit else 10.0
	tiempo_desactivar = total
	if desactivando <= 0.0 and _audio:
		_audio.reproducir("weapons/c4_disarm.wav", -4.0)
	desactivando = minf(total, desactivando + delta)
	if desactivando >= total:
		_desactivar()
		return 1.0
	return desactivando / total


func cancelar_desactivar() -> void:
	if activa and desactivando > 0.0:
		desactivando = 0.0


func _desactivar() -> void:
	activa = false
	desactivada.emit()
	if _audio:
		_audio.reproducir("weapons/c4_disarmed.wav", 0.0)
	queue_free()


func _explotar() -> void:
	activa = false
	if _audio:
		_audio.reproducir("weapons/c4_explode1.wav", 3.0)
	explotada.emit(global_position)
	_danio_en_area()
	queue_free()


func _danio_en_area() -> void:
	var padre := get_parent()
	if padre == null:
		return
	var candidatos := padre.get_children()
	for nodo in candidatos:
		if not (nodo is Node3D):
			continue
		var n3 := nodo as Node3D
		if n3 == self:
			continue
		var distancia := global_position.distance_to(n3.global_position)
		if distancia > RADIO_DANIO:
			continue
		var factor := 1.0 - distancia / RADIO_DANIO
		var danio := DANIO_MAX * factor * factor
		if n3.has_method("recibir_danio"):
			n3.call("recibir_danio", danio, global_position)
		elif n3.has_method("aplicar_danio_bomba"):
			n3.call("aplicar_danio_bomba", danio)
