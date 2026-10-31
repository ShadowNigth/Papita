extends SceneTree
## Comprueba lo que el smoke de carga no cubre: HUD/menu dentro del viewport,
## viewmodel en el semiespacio visible de la camara y movimiento con InputMap.

const ACCIONES_MOVIMIENTO := [
	["adelante", KEY_W], ["atras", KEY_S], ["izquierda", KEY_A], ["derecha", KEY_D],
]


func _initialize() -> void:
	call_deferred("_validar_juego")


func _validar_juego() -> void:
	var escena := load("res://scenes/main.tscn") as PackedScene
	if escena == null:
		_fallar("No se pudo cargar scenes/main.tscn")
		return
	var juego := escena.instantiate() as CsGame
	if juego == null:
		_fallar("La escena principal no instancia CsGame")
		return
	# Sin bots: esta prueba verifica el control del jugador, no la IA.
	juego.num_actores = 0
	root.add_child(juego)
	await process_frame

	if juego.hud == null or juego.hud.size.x <= 1.0 or juego.hud.size.y <= 1.0:
		_fallar("El HUD no ocupa el viewport: %s" % (juego.hud.size if juego.hud else "null"))
		return
	if juego.menu_compra == null or juego.menu_compra.size.x <= 1.0 or juego.menu_compra.size.y <= 1.0:
		_fallar("El menu de compra no ocupa el viewport: %s" % (juego.menu_compra.size if juego.menu_compra else "null"))
		return
	print("[godot jugabilidad] HUD y menu: %.0fx%.0f" % [juego.hud.size.x, juego.hud.size.y])

	var tecla_b := InputEventKey.new()
	tecla_b.keycode = KEY_B
	tecla_b.physical_keycode = KEY_B
	tecla_b.pressed = true
	Input.parse_input_event(tecla_b)
	await process_frame
	if not juego.menu_compra.abierto or not juego.menu_compra.visible:
		_fallar("La tecla B no abre el menu de compra")
		return
	print("[godot jugabilidad] la tecla B abre el menu")
	var soltar_b := InputEventKey.new()
	soltar_b.keycode = KEY_B
	soltar_b.physical_keycode = KEY_B
	Input.parse_input_event(soltar_b)
	juego.menu_compra.cerrar()

	var jugador := juego.jugador
	var vista := jugador.viewmodel
	var modelo := vista.modelo
	if modelo == null or modelo.mesh == null or modelo.mesh.get_surface_count() == 0:
		_fallar("El arma inicial no genero una malla visible")
		return
	if not modelo.get_layer_mask_value(20) or not jugador.camara.get_cull_mask_value(20):
		_fallar("La capa 20 del viewmodel no esta visible para la camara")
		return
	var transformacion := vista.transform * modelo.transform
	var caja_camara: AABB = transformacion * modelo.get_aabb()
	var mayor_dimension := maxf(caja_camara.size.x, maxf(caja_camara.size.y, caja_camara.size.z))
	if mayor_dimension < 0.05 or mayor_dimension > 2.5:
		_fallar("La escala del viewmodel no es razonable: %s" % caja_camara.size)
		return
	if caja_camara.position.z >= -0.02 or caja_camara.position.z + caja_camara.size.z >= -0.02:
		_fallar("El viewmodel queda detras del plano de la camara: %s" % caja_camara)
		return
	print("[godot jugabilidad] viewmodel: %d superficies, bounds en camara %s" % [
		modelo.mesh.get_surface_count(), caja_camara])

	for mapeo in ACCIONES_MOVIMIENTO:
		var accion := String(mapeo[0])
		var codigo := int(mapeo[1])
		if not InputMap.has_action(accion):
			_fallar("Falta la accion de movimiento '%s'" % accion)
			return
		var evento_tecla := InputEventKey.new()
		evento_tecla.keycode = codigo
		evento_tecla.physical_keycode = codigo
		evento_tecla.pressed = true
		if not evento_tecla.is_action_pressed(accion):
			_fallar("La tecla de movimiento no esta asignada a '%s'" % accion)
			return

	# Aisla esta prueba de una pared o del freezetime: recorre el _physics_process
	# real con acciones sinteticas, pero sin colision del mapa.
	juego.director.estado = MatchDirector.Estado.EN_JUEGO
	juego.director.tiempo_estado = 60.0
	jugador.congelado = false
	jugador.collision_mask = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var fallos_movimiento: Array[String] = []
	for mapeo in ACCIONES_MOVIMIENTO:
		var accion := String(mapeo[0])
		jugador.velocity = Vector3.ZERO
		var inicio := Vector2(jugador.global_position.x, jugador.global_position.z)
		Input.action_press(accion)
		if accion == "adelante":
			print("[godot jugabilidad debug] action=%s strength=%.2f congelado=%s vivo=%s physics=%s state=%d" % [
				accion, Input.get_action_strength(accion), jugador.congelado, jugador.vivo,
				jugador.is_physics_processing(), juego.director.estado])
		for _i in 16:
			await physics_frame
		Input.action_release(accion)
		var fin := Vector2(jugador.global_position.x, jugador.global_position.z)
		var desplazamiento := inicio.distance_to(fin)
		if accion == "adelante":
			print("[godot jugabilidad debug] pos %.3f,%.3f -> %.3f,%.3f; velocidad=%s congelado=%s" % [
				inicio.x, inicio.y, fin.x, fin.y, jugador.velocity, jugador.congelado])
		if desplazamiento > 0.05:
			print("[godot jugabilidad] %s movio %.2f m" % [accion, desplazamiento])
		else:
			fallos_movimiento.append(accion)
	if not fallos_movimiento.is_empty():
		_fallar("Estas acciones no desplazaron al jugador: " + ", ".join(fallos_movimiento))
		return

	juego.queue_free()
	await process_frame
	print("[godot jugabilidad] HUD, compra, viewmodel y movimiento correctos")
	quit()


func _fallar(mensaje: String) -> void:
	push_error(mensaje)
	quit(1)
