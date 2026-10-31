class_name MapBuilder
extends RefCounted
## Convierte un `BspReader` en un nodo 3D jugable de Godot.
##
##  * Geometria: una superficie por textura, con UV de la textura original.
##  * Iluminacion: los lightmaps de radiosidad del .bsp se empaquetan en un
##    unico atlas de luz y se aplican por UV2 (asi el mapa se ve como en 1999,
##    sin necesidad de luces dinamicas ni de hornear nada).
##  * Colision: malla concava a partir de las mismas caras.
##  * Entidades: puntos de aparicion, objetivos y ambiente.

const ESCALA := 0.025
const SHADER_BRUSH := "res://shaders/brush.gdshader"

const CARAS_IGNORADAS := ["sky", "trigger", "clip", "origin", "aaatrigger", "hint", "skip"]


class Superficie:
	var texinfo: int = -1
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uvs_luz := PackedVector2Array()
	var colores := PackedColorArray()


static func construir(bsp: BspReader) -> Dictionary:
	var raiz := Node3D.new()
	raiz.name = bsp.ruta.get_file().get_basename()

	# El atlas de luz se construye ANTES de la geometria: las UV2 de cada cara
	# se calculan a partir del hueco que ocupa en el atlas.
	var atlas := _construir_atlas(bsp)
	var material := _material_luz(atlas)
	var superficies := _agrupar_por_textura(bsp)

	var malla := ArrayMesh.new()
	var triangulos_colision := PackedVector3Array()

	for clave in superficies:
		var sup: Superficie = superficies[clave]
		if sup.vertices.size() < 3:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in sup.vertices.size():
			st.set_uv(sup.uvs[i])
			st.set_uv2(sup.uvs_luz[i])
			st.add_vertex(sup.vertices[i])
		st.generate_normals()
		malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())

		var idx := malla.get_surface_count() - 1
		var mat := material.duplicate() as ShaderMaterial
		var tex: Dictionary = bsp.texturas[clampi(clave, 0, bsp.texturas.size() - 1)]
		if tex.get("imagen") != null:
			mat.set_shader_parameter("albedo_tex", ImageTexture.create_from_image(tex["imagen"] as Image))
		else:
			mat.set_shader_parameter("albedo_tex", _textura_plana(tex.get("color_medio", Color.GRAY)))
		malla.surface_set_material(idx, mat)

		triangulos_colision.append_array(_triangulos_de(sup.vertices))

	var instancia := MeshInstance3D.new()
	instancia.mesh = malla
	instancia.name = "geometria"
	raiz.add_child(instancia)

	var cuerpo := StaticBody3D.new()
	cuerpo.name = "colision"
	var forma := CollisionShape3D.new()
	var convexa := ConcavePolygonShape3D.new()
	convexa.set_faces(triangulos_colision)
	forma.shape = convexa
	cuerpo.add_child(forma)
	raiz.add_child(cuerpo)

	raiz.add_child(_ambiente(bsp))
	return {
		"nodo": raiz,
		"spawns": bsp.puntos_de_aparicion(),
		"bomb_targets": _origenes(bsp, "func_bomb_target"),
		"rehenes": _origenes(bsp, "hostage_entity"),
		"superficies": superficies.size(),
		"triangulos": triangulos_colision.size() / 3,
	}


# ---------------------------------------------------------------- geometria
static func _agrupar_por_textura(bsp: BspReader) -> Dictionary:
	var grupos := {}
	for cara in bsp.cara_texinfo.size():
		var n := bsp.cara_numedges[cara]
		if n < 3:
			continue
		var ti := bsp.cara_texinfo[cara]
		if ti < 0 or ti >= bsp.texinfo_miptex.size():
			continue
		var tex_idx := bsp.texinfo_miptex[ti]
		if tex_idx < 0 or tex_idx >= bsp.texturas.size():
			continue
		var tex: Dictionary = bsp.texturas[tex_idx]
		var nombre := String(tex["nombre"]).to_lower()
		var ignorar := false
		for prefijo in CARAS_IGNORADAS:
			if nombre.begins_with(prefijo):
				ignorar = true
				break
		if ignorar:
			continue

		var idx := bsp.indices_cara(cara)
		if idx.size() < 3:
			continue
		if not grupos.has(tex_idx):
			grupos[tex_idx] = Superficie.new()
			(grupos[tex_idx] as Superficie).texinfo = tex_idx
		var sup: Superficie = grupos[tex_idx]
		var caja := bsp.caja_lightmap(cara)

		# abanico: las caras de GoldSrc son convexas
		for k in range(1, idx.size() - 1):
			for v in [idx[0], idx[k], idx[k + 1]]:
				var pos := bsp.vertices[v]
				sup.vertices.append(pos)
				sup.uvs.append(bsp.uv_de(cara, pos))
				sup.uvs_luz.append(_uv_atlas(bsp, cara, pos, caja))
	return grupos


## Convierte las coordenadas de luxel de la cara a UV del atlas global.
static func _uv_atlas(bsp: BspReader, cara: int, vertice: Vector3, caja: Rect2i) -> Vector2:
	if caja.size.x <= 0 or caja.size.y <= 0:
		return Vector2(0.5, 0.5)
	var u := bsp.uv_lightmap(cara, vertice, caja)
	if not bsp.has_meta("atlas"):
		return Vector2(0.5, 0.5)
	var atlas: Dictionary = bsp.get_meta("atlas")
	var hueco: Rect2i = atlas["huecos"].get(cara, Rect2i())
	if hueco.size == Vector2i.ZERO:
		return Vector2(0.5, 0.5)
	var tam: Vector2 = atlas["tamano"]
	return Vector2((hueco.position.x + u.x * hueco.size.x) / tam.x,
		(hueco.position.y + u.y * hueco.size.y) / tam.y)


static func _triangulos_de(vertices: PackedVector3Array) -> PackedVector3Array:
	var salida := PackedVector3Array()
	salida.resize(vertices.size())
	salida = vertices.duplicate()
	return salida


# ---------------------------------------------------------------- lightmaps
## Empaqueta el lightmap de cada cara en un unico atlas (shelf packing).
static func _construir_atlas(bsp: BspReader) -> ImageTexture:
	var piezas: Array[Dictionary] = []
	for cara in bsp.cara_texinfo.size():
		var n := bsp.cara_numedges[cara]
		if n < 3:
			continue
		var ti := bsp.cara_texinfo[cara]
		if ti < 0 or ti >= bsp.texinfo_miptex.size():
			continue
		var caja := bsp.caja_lightmap(cara)
		var pixeles := bsp.luz_cara(cara, caja)
		if pixeles.is_empty():
			continue
		piezas.append({"cara": cara, "caja": caja, "pixeles": pixeles})

	# tamano del atlas: potencia de dos que quepa con margen
	var area := 0
	for p in piezas:
		area += p["caja"].size.x * p["caja"].size.y
	var lado := 256
	while lado * lado < area * 3 and lado < 4096:
		lado *= 2
	var atlas := Image.create(lado, lado, false, Image.FORMAT_RGB8)
	atlas.fill(Color(1, 1, 1))   # sin lightmap = luz plena

	var x := 0
	var y := 0
	var alto_fila := 0
	var huecos := {}
	for p in piezas:
		var caja: Rect2i = p["caja"]
		if x + caja.size.x >= lado:
			x = 0
			y += alto_fila
			alto_fila = 0
		if y + caja.size.y >= lado:
			break   # se acabo el sitio: esas caras quedan a luz plena
		var pixeles: PackedByteArray = p["pixeles"]
		for fy in caja.size.y:
			for fx in caja.size.x:
				var o := (fy * caja.size.x + fx) * 3
				if o + 2 >= pixeles.size():
					continue
				# el lightmap de GoldSrc ya viene en sRGB 0..255
				atlas.set_pixel(x + fx, y + fy, Color8(pixeles[o], pixeles[o + 1], pixeles[o + 2]))
		huecos[p["cara"]] = Rect2i(Vector2i(x, y), caja.size)
		x += caja.size.x
		alto_fila = maxi(alto_fila, caja.size.y)

	bsp.set_meta("atlas", {"huecos": huecos, "tamano": Vector2(lado, lado)})
	return ImageTexture.create_from_image(atlas)


static func _material_luz(atlas: ImageTexture) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var shader: Shader = load(SHADER_BRUSH)
	if shader != null:
		mat.shader = shader
	mat.set_shader_parameter("lightmap_tex", atlas)
	return mat


static func _textura_plana(color: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- ambiente
static func _origenes(bsp: BspReader, clase: String) -> Array[Vector3]:
	var salida: Array[Vector3] = []
	for e in bsp.entidades_de(clase):
		salida.append(BspReader.origin_de(e))
	return salida


## Luz de entorno y cielo segun lo que declare el propio .bsp.
static func _ambiente(bsp: BspReader) -> Node3D:
	var nodo := Node3D.new()
	nodo.name = "ambiente"

	var ent := Environment.new()
	ent.background_mode = Environment.BG_SKY
	var cielo := Sky.new()
	var material_cielo := ProceduralSkyMaterial.new()

	var brillo := 1.0
	for e in bsp.entidades_de("light_environment"):
		var luz := String(e.get("_light", "255 255 255 200")).split(" ", false)
		if luz.size() >= 3:
			var c := Color8(int(luz[0]), int(luz[1]), int(luz[2]))
			material_cielo.sky_top_color = c
			material_cielo.sky_horizon_color = c.lerp(Color(0.8, 0.85, 0.9), 0.45)
			material_cielo.ground_horizon_color = c.lerp(Color(0.55, 0.5, 0.45), 0.5)
			material_cielo.ground_bottom_color = c.lerp(Color(0.3, 0.28, 0.26), 0.7)
			brillo = clampf(float(luz[3]) / 200.0, 0.5, 1.6) if luz.size() > 3 else 1.0
		break

	material_cielo.sky_energy_multiplier = brillo
	cielo.sky_material = material_cielo
	ent.sky = cielo
	ent.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	ent.ambient_light_energy = 0.6
	ent.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	ent.fog_enabled = false
	ent.ssao_enabled = false

	var world := WorldEnvironment.new()
	world.environment = ent
	nodo.add_child(world)

	# Las caras usan el lightmap horneado, asi que la luz del mundo solo
	# afecta a los modelos (jugador y armas).
	var sol := DirectionalLight3D.new()
	sol.light_energy = 0.9
	sol.rotation_degrees = Vector3(-55, 40, 0)
	sol.shadow_enabled = true
	nodo.add_child(sol)
	return nodo
