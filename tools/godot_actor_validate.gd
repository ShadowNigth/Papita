extends SceneTree

const FACCIONES := ["gign", "sas", "urban", "gsg9", "terror", "leet", "arctic", "guerilla"]
const ALTURA_MINIMA := 1.5
const ALTURA_MAXIMA := 1.95


func _initialize() -> void:
	call_deferred("_validar_modelos")


func _validar_modelos() -> void:
	var paleta := CsPalette.cargar()
	for faccion in FACCIONES:
		var actor := ActorModel.new()
		root.add_child(actor)
		var ruta := "player/%s/%s.mdl" % [faccion, faccion]
		if not actor.cargar(ruta, paleta):
			push_error("No se pudo cargar el modelo de prueba: " + ruta)
			quit(1)
			return
		if actor.instancia == null or actor.instancia.mesh == null or actor.instancia.mesh.get_surface_count() == 0:
			push_error("El modelo no creó superficies: " + ruta)
			quit(1)
			return
		if actor.lector.texturas.is_empty():
			push_error("El modelo no tiene texturas: " + ruta)
			quit(1)
			return
		for textura: Dictionary in actor.lector.texturas:
			var imagen: Image = textura.get("imagen") as Image
			if imagen == null or imagen.is_empty() or imagen.get_format() != Image.FORMAT_RGB8:
				push_error("Textura MDL sin imagen RGB decodificada: " + ruta)
				quit(1)
				return
		if not actor.reproducir("idle1"):
			push_error("El modelo no reproduce idle1: " + ruta)
			quit(1)
			return
		await process_frame
		var caja_local: AABB = actor.instancia.get_aabb()
		var caja_mundo: AABB = actor.instancia.global_transform * caja_local
		var altura: float = caja_mundo.size.y
		print("[godot mdl] %s: altura visual %.2f m" % [faccion, altura])
		if altura < ALTURA_MINIMA or altura > ALTURA_MAXIMA:
			push_error("Escala/ejes incorrectos en %s: altura %.2f m" % [faccion, altura])
			quit(1)
			return
		actor.queue_free()
		await process_frame
	print("[godot mdl] 8 modelos en rango de altura")
	quit()
