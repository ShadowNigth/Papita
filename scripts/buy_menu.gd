class_name BuyMenu
extends Control
## Menú de compra numérico, como el de CS 1.5: `B` abre, números para elegir,
## `0` o `B` para volver/salir. Sin ratón, igual que el original.
##
## Dos niveles: categorías (1-8) y objetos dentro de la categoría.

signal compra_solicitada(id: String)

const ANCHO := 420.0
const ALTO := 460.0

var abierto: bool = false
var categoria: int = -1
var dinero: int = 0
var director: MatchDirector

var _fuente: Font
var _aviso: String = ""
var _aviso_tiempo: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuente = ThemeDB.fallback_font
	visible = false
	_ajustar_a_viewport()
	get_viewport().size_changed.connect(_ajustar_a_viewport)


## El menu tambien cuelga de un CanvasLayer, no de otro Control. Sin un tamano
## explicito, el panel se dibuja centrado en (0, 0), fuera de la pantalla.
func _ajustar_a_viewport() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	queue_redraw()


func alternar() -> void:
	abierto = not abierto
	visible = abierto
	categoria = -1
	if abierto:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_redraw()


func cerrar() -> void:
	if abierto:
		alternar()


func mostrar_aviso(texto: String) -> void:
	_aviso = texto
	_aviso_tiempo = 2.5


func _process(delta: float) -> void:
	if _aviso_tiempo > 0.0:
		_aviso_tiempo -= delta
		if _aviso_tiempo <= 0.0:
			_aviso = ""
	if abierto:
		if director != null and is_instance_valid(director):
			dinero = director.dinero
		queue_redraw()


func _input(evento: InputEvent) -> void:
	if not abierto:
		return
	if not (evento is InputEventKey) or not evento.is_pressed():
		return
	var tecla := (evento as InputEventKey).physical_keycode
	if tecla == KEY_B or tecla == KEY_ESCAPE:
		alternar()
		get_viewport().set_input_as_handled()
		return
	if tecla >= KEY_0 and tecla <= KEY_9:
		var numero := tecla - KEY_0
		get_viewport().set_input_as_handled()
		_elegir(numero)


func _elegir(numero: int) -> void:
	var categorias := CsEconomy.categorias()
	if categoria < 0:
		# nivel 1: categoria (1-8), 0 = salir
		if numero == 0:
			alternar()
			return
		var i := numero - 1
		if i < 0 or i >= categorias.size():
			return
		categoria = i
		queue_redraw()
		return
	# nivel 2: objeto dentro de la categoria, 0 = volver
	if numero == 0:
		categoria = -1
		queue_redraw()
		return
	var objetos: Array = categorias[categoria]["objetos"]
	var j := numero - 1
	if j < 0 or j >= objetos.size():
		return
	var id := String(objetos[j])
	compra_solicitada.emit(id)
	if director != null and is_instance_valid(director):
		var error := director.comprar(id, director.esta_en_zona_compra(director.jugador.global_position))
		mostrar_aviso(error if not error.is_empty() else "Comprado: " + CsEconomy.nombre(id))
	queue_redraw()


func _draw() -> void:
	if not abierto:
		return
	var tam := size
	var x := (tam.x - ANCHO) * 0.5
	var y := (tam.y - ALTO) * 0.5

	draw_rect(Rect2(x, y, ANCHO, ALTO), Color(0.05, 0.06, 0.08, 0.94))
	draw_rect(Rect2(x, y, ANCHO, ALTO), Color(0.35, 0.55, 0.35, 0.9), false, 2.0)

	var categorias := CsEconomy.categorias()
	_texto(Vector2(x + 18, y + 30), "COMPRAR", 20, Color(0.85, 1.0, 0.85))
	var dinero_txt := "%d$" % dinero
	_texto(Vector2(x + ANCHO - 18 - _fuente.get_string_size(dinero_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x,
		y + 30), dinero_txt, 18, Color(0.7, 1.0, 0.7))

	if categoria < 0:
		_texto(Vector2(x + 18, y + 54), "Elige categoría (0 para salir)", 12, Color(0.6, 0.65, 0.7))
		var fila := 0
		for i in categorias.size():
			var cat: Dictionary = categorias[i]
			var objetos: Array = cat["objetos"]
			_texto(Vector2(x + 18, y + 84 + fila * 40),
				"%s.  %s" % [cat["clave"], cat["nombre"]], 16, Color(0.9, 0.9, 0.9))
			var resumen := ""
			for o in objetos:
				resumen += "%s %d$   " % [WeaponDB.nombre(String(o)), CsEconomy.precio(String(o))]
			_texto(Vector2(x + 54, y + 104 + fila * 40), resumen, 10, Color(0.55, 0.6, 0.65))
			fila += 1
	else:
		var cat: Dictionary = categorias[categoria]
		_texto(Vector2(x + 18, y + 54), "%s  (0 para volver)" % cat["nombre"], 13, Color(0.6, 0.65, 0.7))
		var objetos: Array = cat["objetos"]
		for j in objetos.size():
			var id := String(objetos[j])
			var precio := CsEconomy.precio(id)
			var alcanza := dinero >= precio
			var color := Color(0.9, 0.9, 0.9) if alcanza else Color(0.55, 0.45, 0.45)
			_texto(Vector2(x + 18, y + 88 + j * 38),
				"%d.  %s" % [j + 1, CsEconomy.nombre(id)], 16, color)
			var p := "%d$" % precio
			_texto(Vector2(x + ANCHO - 18 - _fuente.get_string_size(p, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x,
				y + 88 + j * 38), p, 16, color)

	if not _aviso.is_empty():
		_texto(Vector2(x + 18, y + ALTO - 18), _aviso, 13, Color(1.0, 0.85, 0.45))


func _texto(pos: Vector2, texto: String, tam: int, color: Color) -> void:
	draw_string(_fuente, pos + Vector2(1, 1), texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam,
		Color(0, 0, 0, color.a * 0.8))
	draw_string(_fuente, pos, texto, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, color)
