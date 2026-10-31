class_name Fx
extends RefCounted
## Efectos de impacto y trazadoras. Sencillos a proposito: el juego original
## resolvia esto con sprites de 8 bits; aqui con mallas minimas y una luz breve.

static var _material_chispa: StandardMaterial3D
static var _material_humo: StandardMaterial3D


static func impacto(padre: Node, punto: Vector3, normal: Vector3, _danio: float) -> void:
	if padre == null or not padre.is_inside_tree():
		return
	var nodo := Node3D.new()
	nodo.position = punto
	padre.add_child(nodo)

	# chispa: cuadro pequeno que mira a la normal y se apaga
	var chispa := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	chispa.mesh = quad
	chispa.material_override = _mat_chispa()
	chispa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nodo.add_child(chispa)
	if normal.length() > 0.01:
		nodo.look_at(punto + normal, Vector3.UP)

	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.8, 0.45)
	luz.light_energy = 1.2
	luz.omni_range = 1.2
	nodo.add_child(luz)

	var tween := nodo.create_tween()
	tween.set_parallel(true)
	tween.tween_property(chispa, "scale", Vector3(1.6, 1.6, 1.6), 0.12)
	tween.tween_property(luz, "light_energy", 0.0, 0.12)
	tween.chain().tween_callback(nodo.queue_free)


## Trazadora: linea fina entre el canon y el punto de impacto.
static func trazadora(padre: Node, desde: Vector3, hasta: Vector3, duracion: float = 0.06) -> void:
	if padre == null:
		return
	var malla := ImmediateMesh.new()
	var instancia := MeshInstance3D.new()
	instancia.mesh = malla
	instancia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instancia.material_override = _mat_chispa()
	padre.add_child(instancia)
	malla.surface_begin(Mesh.PRIMITIVE_LINES)
	malla.surface_add_vertex(desde)
	malla.surface_add_vertex(hasta)
	malla.surface_end()
	var tween := instancia.create_tween()
	tween.tween_interval(duracion)
	tween.tween_callback(instancia.queue_free)


static func _mat_chispa() -> StandardMaterial3D:
	if _material_chispa == null:
		_material_chispa = StandardMaterial3D.new()
		_material_chispa.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material_chispa.albedo_color = Color(1.0, 0.92, 0.7)
		_material_chispa.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material_chispa.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_material_chispa.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material_chispa
