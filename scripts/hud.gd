class_name Hud
extends Control
## HUD al estilo CS 1.5: mira, vida, chaleco, municion, arma y FPS.

var vida: int = 100
var chaleco: int = 0
var cargador: int = 0
var reserva: int = 0
var arma: String = ""
var mensaje: String = ""
var mostrar_ayuda: bool = true

# --- estado de partida (lo rellena MatchDirector) ---
var dinero: int = 800
var ronda: int = 1
var marcador: String = "CT 0 — 0 T"
var fase: String = "Congelación"
var tiempo_ronda: float = 0.0
var tiempo_bomba: float = -1.0
var aviso_bomba: String = ""
## Enemigos que quedan vivos; -1 = no se sabe (sin partida).
var enemigos: int = -1

var _fuente: Font
var _tiempo_mensaje: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuente = ThemeDB.fallback_font


func aviso(texto: String, segundos: float = 3.0) -> void:
	mensaje = texto
	_tiempo_mensaje = segundos


func _process(delta: float) -> void:
	if _tiempo_mensaje > 0.0:
		_tiempo_mensaje -= delta
		if _tiempo_mensaje <= 0.0:
			mensaje = ""
	queue_redraw()


func _draw() -> void:
	var tam := size
	var centro := tam * 0.5

	# --- mira dinamica (se abre al moverse y al disparar) ---
	var jugador := _buscar_jugador()
	var abertura := 4.0
	if jugador != null:
		abertura += clampf(jugador.velocity.length() * 1.6, 0.0, 12.0)
		abertura += jugador._retroceso * 6.0
	var color_mira := Color(0.35, 1.0, 0.35, 0.95)
	draw_line(centro + Vector2(-abertura - 7, 0), centro + Vector2(-abertura, 0), color_mira, 1.5)
	draw_line(centro + Vector2(abertura, 0), centro + Vector2(abertura + 7, 0), color_mira, 1.5)
	draw_line(centro + Vector2(0, -abertura - 7), centro + Vector2(0, -abertura), color_mira, 1.5)
	draw_line(centro + Vector2(0, abertura), centro + Vector2(0, abertura + 7), color_mira, 1.5)

	# --- salud y chaleco, abajo a la izquierda ---
	var y := tam.y - 54.0
	_dibujar_texto(Vector2(28, y), "SALUD", 13, Color(0.75, 0.8, 0.85))
	_dibujar_texto(Vector2(28, y + 24), str(vida), 26,
		Color(1, 0.35, 0.3) if vida < 30 else Color(0.95, 0.95, 0.95))
	_dibujar_texto(Vector2(120, y), "CHALECO", 13, Color(0.75, 0.8, 0.85))
	_dibujar_texto(Vector2(120, y + 24), str(chaleco), 26, Color(0.6, 0.75, 1.0))

	# --- municion, abajo a la derecha ---
	var texto_municion := "%d / %d" % [cargador, reserva]
	var ancho := _fuente.get_string_size(texto_municion, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	_dibujar_texto(Vector2(tam.x - 28 - ancho, y + 24), texto_municion, 26, Color(0.95, 0.95, 0.95))
	var ancho_arma := _fuente.get_string_size(arma, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_dibujar_texto(Vector2(tam.x - 28 - ancho_arma, y), arma, 15, Color(0.75, 0.8, 0.85))

	# --- mensajes y ayuda ---
	if not mensaje.is_empty():
		var ancho_m := _fuente.get_string_size(mensaje, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_dibujar_texto(Vector2(centro.x - ancho_m * 0.5, tam.y * 0.28), mensaje, 18, Color(1, 0.9, 0.5))

	if mostrar_ayuda:
		var lineas := [
			"WASD mover   ESPACIO saltar   CTRL agachar   CLIC disparar   R recargar",
			"1-5 armas   RUEDA cambiar   B comprar   E plantar/desactivar   F1 ayuda",
			"Mapa y soldados leidos de los .bsp/.mdl originales, con sus animaciones",
		]
		var alto := tam.y - 132.0
		for i in lineas.size():
			_dibujar_texto(Vector2(28, alto + i * 18), lineas[i], 12, Color(0.8, 0.85, 0.9, 0.75))

	_dibujar_texto(Vector2(28, 28), "%d FPS" % Engine.get_frames_per_second(), 12, Color(0.7, 0.9, 0.7, 0.8))

	# --- marcador arriba al centro: CT / tiempo / T, como el original ---
	var reloj := _mmss(tiempo_ronda)
	var ancho_reloj := _fuente.get_string_size(reloj, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_texto_caja(Vector2(centro.x - 90, 14), 180, marcador, 15, Color(0.85, 0.9, 0.95))
	_dibujar_texto(Vector2(centro.x - ancho_reloj * 0.5, 46), reloj, 22,
		Color(1.0, 0.4, 0.35) if tiempo_ronda < 30.0 else Color(0.95, 0.95, 0.95))
	_dibujar_texto(Vector2(centro.x - _fuente.get_string_size(fase, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x * 0.5, 70),
		fase, 12, Color(0.65, 0.7, 0.75))
	if enemigos >= 0:
		var vivos := "quedan %d" % enemigos
		_dibujar_texto(Vector2(centro.x - _fuente.get_string_size(vivos, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x * 0.5, 86),
			vivos, 11, Color(0.8, 0.75, 0.55))

	# --- dinero, debajo de la salud ---
	_dibujar_texto(Vector2(28, tam.y - 92), "%d$" % dinero, 20, Color(0.65, 0.95, 0.65))

	# --- estado de la bomba, si la hay ---
	if tiempo_bomba >= 0.0:
		var txt := "BOMBA %s" % _mmss(tiempo_bomba)
		var ancho_b := _fuente.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_dibujar_texto(Vector2(centro.x - ancho_b * 0.5, 96), txt, 18,
			Color(1.0, 0.35, 0.25) if tiempo_bomba < 10.0 else Color(1.0, 0.7, 0.3))
	if not aviso_bomba.is_empty():
		var ancho_a := _fuente.get_string_size(aviso_bomba, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_dibujar_texto(Vector2(centro.x - ancho_a * 0.5, tam.y - 150), aviso_bomba, 14,
			Color(1.0, 0.9, 0.5))


func _dibujar_texto(pos: Vector2, texto: String, tam_fuente: int, color: Color) -> void:
	# sombra a 1 px para que se lea sobre cualquier textura, como en el original
	draw_string(_fuente, pos + Vector2(1, 1), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam_fuente, Color(0, 0, 0, color.a * 0.8))
	draw_string(_fuente, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam_fuente, color)


static func _mmss(segundos: float) -> String:
	var s := maxi(0, int(segundos))
	return "%d:%02d" % [int(s / 60.0), s % 60]


func _texto_caja(pos: Vector2, ancho: float, texto: String, tam: int, color: Color) -> void:
	draw_rect(Rect2(pos.x, pos.y - 2, ancho, 22), Color(0.05, 0.06, 0.08, 0.75))
	var w := _fuente.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	_dibujar_texto(Vector2(pos.x + (ancho - w) * 0.5, pos.y + 14), texto, tam, color)


func _buscar_jugador() -> CsPlayer:
	var jugadores := get_tree().get_nodes_in_group("jugador")
	if jugadores.is_empty():
		return null
	return jugadores[0] as CsPlayer


func _input(evento: InputEvent) -> void:
	if evento is InputEventKey and evento.is_pressed() and (evento as InputEventKey).physical_keycode == KEY_F1:
		mostrar_ayuda = not mostrar_ayuda
