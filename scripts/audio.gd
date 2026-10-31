class_name CsAudio
extends Node
## Reproduce los .wav originales de CS 1.5 directamente desde `assets/`.
##
## Godot no importa estos ficheros (no son recursos del proyecto), asi que se
## cargan en memoria con `AudioStreamWAV.load_from_file`, que entiende PCM de 8
## y 16 bits, que es justo lo que trae el juego (mono, 22050 Hz).

const RAIZ := "res://assets/sounds/cs15/"
const VOCES := 8

var _cache: Dictionary = {}
var _reproductores: Array[AudioStreamPlayer] = []
var _siguiente: int = 0
var volumen_db := 0.0


func _ready() -> void:
	for i in VOCES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_reproductores.append(p)


func reproducir(ruta_relativa: String, volumen: float = 0.0, tono: float = 1.0) -> void:
	var stream := _obtener(ruta_relativa)
	if stream == null:
		return
	var p := _reproductores[_siguiente]
	_siguiente = (_siguiente + 1) % _reproductores.size()
	p.stream = stream
	p.volume_db = volumen + volumen_db
	p.pitch_scale = tono
	p.play()


func _obtener(ruta_relativa: String) -> AudioStream:
	if _cache.has(ruta_relativa):
		return _cache[ruta_relativa] as AudioStream
	var ruta := RAIZ + ruta_relativa
	if not FileAccess.file_exists(ruta):
		return null
	var stream := AudioStreamWAV.load_from_file(ruta)
	_cache[ruta_relativa] = stream
	return stream


func precargar(rutas: Array[String]) -> void:
	for r in rutas:
		_obtener(r)
