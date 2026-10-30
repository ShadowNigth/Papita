extends RefCounted
## MaterialLib: texturas PBR y materiales generados en tiempo de ejecucion.
##
## Cada material produce tres mapas (albedo, normal y ORM) dibujados con ruido
## y patrones procedurales, y usa el shader `surface.gdshader` para triplanar,
## desgaste y humedad. Resultado: look "realista" sin depender de archivos.

class_name MaterialLib

const SIZE := 128
const SHADER := preload("res://shaders/surface.gdshader")

const PALETTES := {
	"desert":
	{
		"plaster": Color(0.78, 0.66, 0.45),
		"stone": Color(0.63, 0.55, 0.41),
		"brick": Color(0.62, 0.44, 0.3),
		"wood": Color(0.46, 0.3, 0.16),
		"metal": Color(0.42, 0.42, 0.38),
		"sand": Color(0.72, 0.61, 0.42),
		"roof": Color(0.55, 0.36, 0.24),
		"cloth": Color(0.62, 0.52, 0.34),
	},
	"mediterranean":
	{
		"plaster": Color(0.82, 0.7, 0.52),
		"stone": Color(0.6, 0.55, 0.45),
		"brick": Color(0.58, 0.34, 0.23),
		"wood": Color(0.4, 0.27, 0.15),
		"metal": Color(0.38, 0.38, 0.36),
		"sand": Color(0.68, 0.58, 0.42),
		"roof": Color(0.62, 0.32, 0.2),
		"cloth": Color(0.74, 0.62, 0.4),
	},
	"jungle":
	{
		"plaster": Color(0.55, 0.55, 0.47),
		"stone": Color(0.44, 0.47, 0.4),
		"brick": Color(0.42, 0.36, 0.28),
		"wood": Color(0.35, 0.25, 0.15),
		"metal": Color(0.34, 0.36, 0.33),
		"sand": Color(0.42, 0.4, 0.3),
		"roof": Color(0.36, 0.4, 0.3),
		"cloth": Color(0.5, 0.44, 0.3),
	},
	"industrial":
	{
		"plaster": Color(0.6, 0.61, 0.58),
		"stone": Color(0.48, 0.5, 0.48),
		"brick": Color(0.5, 0.38, 0.3),
		"wood": Color(0.4, 0.29, 0.18),
		"metal": Color(0.4, 0.43, 0.44),
		"sand": Color(0.5, 0.48, 0.4),
		"roof": Color(0.35, 0.37, 0.36),
		"cloth": Color(0.42, 0.44, 0.38),
	},
	"railyard":
	{
		"plaster": Color(0.55, 0.56, 0.55),
		"stone": Color(0.45, 0.46, 0.44),
		"brick": Color(0.48, 0.4, 0.34),
		"wood": Color(0.36, 0.28, 0.2),
		"metal": Color(0.36, 0.39, 0.4),
		"sand": Color(0.7, 0.72, 0.74),
		"roof": Color(0.4, 0.42, 0.4),
		"cloth": Color(0.55, 0.57, 0.55),
	},
	"office":
	{
		"plaster": Color(0.78, 0.78, 0.73),
		"stone": Color(0.55, 0.55, 0.52),
		"brick": Color(0.45, 0.42, 0.38),
		"wood": Color(0.34, 0.24, 0.16),
		"metal": Color(0.35, 0.36, 0.37),
		"sand": Color(0.54, 0.52, 0.48),
		"roof": Color(0.4, 0.4, 0.4),
		"cloth": Color(0.26, 0.29, 0.34),
	},
	"italy":
	{
		"plaster": Color(0.8, 0.68, 0.48),
		"stone": Color(0.6, 0.54, 0.44),
		"brick": Color(0.6, 0.36, 0.24),
		"wood": Color(0.42, 0.28, 0.16),
		"metal": Color(0.36, 0.36, 0.33),
		"sand": Color(0.64, 0.56, 0.42),
		"roof": Color(0.58, 0.32, 0.22),
		"cloth": Color(0.7, 0.6, 0.42),
	},
	"mansion":
	{
		"plaster": Color(0.46, 0.36, 0.28),
		"stone": Color(0.4, 0.36, 0.3),
		"brick": Color(0.4, 0.28, 0.22),
		"wood": Color(0.28, 0.18, 0.11),
		"metal": Color(0.3, 0.28, 0.24),
		"sand": Color(0.4, 0.36, 0.3),
		"roof": Color(0.28, 0.22, 0.18),
		"cloth": Color(0.35, 0.2, 0.2),
	},
	"desert_night":
	{
		"plaster": Color(0.4, 0.36, 0.28),
		"stone": Color(0.33, 0.3, 0.25),
		"brick": Color(0.34, 0.26, 0.2),
		"wood": Color(0.24, 0.17, 0.1),
		"metal": Color(0.25, 0.26, 0.24),
		"sand": Color(0.38, 0.34, 0.26),
		"roof": Color(0.3, 0.22, 0.17),
		"cloth": Color(0.34, 0.3, 0.22),
	},
}

static var _cache: Dictionary = {}

# --- API -----------------------------------------------------------------------


static func surface(
	kind: String, theme: String = "desert", variant: int = 0, wetness: float = 0.0
) -> ShaderMaterial:
	var key := "%s|%s|%d|%.2f" % [kind, theme, variant, wetness]
	if _cache.has(key):
		return _cache[key]
	var pal: Dictionary = PALETTES.get(theme, PALETTES.desert)
	var base: Color = pal.get(_palette_key(kind), pal.plaster)
	base = base.lightened((variant % 3) * 0.04 - 0.04)
	var maps := _generate(kind, base, variant)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("albedo_tex", maps.albedo)
	mat.set_shader_parameter("normal_tex", maps.normal)
	mat.set_shader_parameter("orm_tex", maps.orm)
	mat.set_shader_parameter("tint", Color(1, 1, 1))
	mat.set_shader_parameter("uv_scale", maps.uv)
	mat.set_shader_parameter("normal_strength", maps.normal_strength)
	mat.set_shader_parameter("roughness_scale", maps.roughness)
	mat.set_shader_parameter("metallic_scale", maps.metallic)
	mat.set_shader_parameter("wear", maps.wear)
	mat.set_shader_parameter("wetness", wetness)
	mat.set_shader_parameter("moss", maps.moss)
	mat.set_shader_parameter("detail_scale", maps.detail)
	_cache[key] = mat
	return mat


static func _palette_key(kind: String) -> String:
	match kind:
		"brick", "cobble", "carpet", "sandbag", "tile":
			return "brick" if kind == "brick" else "stone"
		"wood", "plank", "crate", "door":
			return "wood"
		"metal", "rust", "pipe", "container", "roof_metal":
			return "metal"
		"sand", "dirt", "gravel", "asphalt":
			return "sand"
		"roof", "terracotta":
			return "roof"
		"cloth", "canvas", "bed":
			return "cloth"
		_:
			return "plaster"


static func _generate(kind: String, base: Color, variant: int) -> Dictionary:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var height := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	var rough := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	var metal := 0.0
	var metallic_val := 0.05
	var uv := 1.0
	var normal_strength := 0.9
	var rough_mult := 1.0
	var wear := 0.3
	var moss := 0.0
	var detail := 2.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + variant * 131 + kind.length() * 17
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.03
	noise.fractal_octaves = 4
	var noise2 := FastNoiseLite.new()
	noise2.seed = rng.randi()
	noise2.frequency = 0.11
	noise2.fractal_octaves = 3
	var cellular := FastNoiseLite.new()
	cellular.seed = rng.randi()
	cellular.frequency = 0.06
	cellular.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cellular.noise_type = FastNoiseLite.TYPE_CELLULAR

	for y in SIZE:
		for x in SIZE:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var n2 := noise2.get_noise_2d(x, y) * 0.5 + 0.5
			var col := base
			var h := n * 0.6 + n2 * 0.4
			var r := 0.7
			match kind:
				"plaster", "stucco":
					col = base.darkened(0.05 + n * 0.22)
					h = n * 0.5 + n2 * 0.12
					r = 0.82 + n2 * 0.12
					wear = 0.45
				"sand":
					col = base.lightened(n * 0.12).darkened(n2 * 0.1)
					h = n * 0.35 + sin(float(x) * 0.35) * 0.12
					r = 0.95
					uv = 0.7
					detail = 5.0
				"dirt", "gravel":
					col = base.darkened(0.1 + n * 0.25)
					h = n * 0.7 + n2 * 0.3
					r = 1.0
					uv = 0.8
					detail = 4.0
				"brick":
					var row := int(y / 12.0)
					var offset := 0 if row % 2 == 0 else 8
					var bx := (x + offset) % 16
					var by := y % 12
					var mortar := bx < 1 or by < 1
					col = (base.darkened(0.05) if not mortar else base.lightened(0.3))
					col = col.darkened(rng.randf() * 0.02 + n * 0.16)
					h = 0.15 if mortar else 0.8 + n2 * 0.2
					r = 0.95 if mortar else 0.85
					uv = 1.2
					normal_strength = 1.2
					wear = 0.35
				"cobble", "stone":
					var cell := cellular.get_noise_2d(x, y) * 0.5 + 0.5
					var seam := smoothstep(0.42, 0.5, cell)
					col = base.darkened(0.12 + seam * 0.35 + n * 0.12)
					h = (1.0 - seam) * 0.8 + n2 * 0.2
					r = 0.9
					uv = 1.1
					normal_strength = 1.25
				"tile":
					var tx := x % 16
					var ty := y % 16
					var grout := tx < 1 or ty < 1
					col = (base if not grout else base.lightened(0.22)).darkened(n * 0.1)
					h = 0.1 if grout else 0.9
					r = 0.45 if not grout else 0.9
					uv = 1.4
					metallic_val = 0.05
				"wood", "plank", "crate", "door":
					var plank := int(x / 22.0)
					var grain := sin((y + plank * 13) * 0.5 + n * 6.0) * 0.5 + 0.5
					var seam := 0.0 if x % 22 < 1 else 1.0
					col = base.darkened(0.12 + grain * 0.22 + (1.0 - seam) * 0.18)
					col = col.lightened(n2 * 0.06)
					h = grain * 0.5 * seam + 0.2
					r = 0.72
					uv = 1.0
					wear = 0.4
					normal_strength = 0.7
				"metal", "pipe", "container":
					col = base.darkened(n * 0.16)
					col = col.lerp(base.lightened(0.18), n2 * 0.35)
					h = n * 0.3 + sin(float(y) * 0.9) * 0.05
					r = 0.35 + n2 * 0.18
					metallic_val = 0.85
					uv = 1.6
					wear = 0.55
					normal_strength = 0.5
				"rust":
					col = base.lerp(Color(0.45, 0.24, 0.12), smoothstep(0.35, 0.75, n))
					h = n * 0.7
					r = 0.85
					metallic_val = 0.35
					wear = 0.8
					normal_strength = 1.1
				"roof", "terracotta":
					var rh := int(y / 10.0)
					var rx := x % 10
					col = base.darkened(0.1 + n * 0.2 + (1.0 if rx < 2 else 0.0) * 0.15)
					h = sin(float(rx) / 10.0 * PI) * 0.7 + n2 * 0.2
					r = 0.85
					uv = 1.3
					normal_strength = 1.15
				"cloth", "sandbag", "canvas":
					var weave := (int(x / 2.0) + int(y / 2.0)) % 2
					col = base.darkened(0.1 + n * 0.18 + weave * 0.06)
					h = weave * 0.4 + n2 * 0.4
					r = 0.98
					uv = 2.0
					normal_strength = 1.0
					detail = 6.0
				"carpet":
					col = base.darkened(n * 0.18 + n2 * 0.12)
					h = n2 * 0.8
					r = 1.0
					uv = 3.0
					detail = 7.0
				"concrete":
					col = base.darkened(0.08 + n * 0.16)
					if n2 > 0.78:
						col = col.darkened(0.25)
					h = n * 0.4 + n2 * 0.3
					r = 0.88
					uv = 1.2
					wear = 0.5
					normal_strength = 0.85
				"asphalt":
					col = base.darkened(0.3 + n * 0.2)
					if n2 > 0.7:
						col = col.lightened(0.15)
					h = n2 * 0.6
					r = 0.95
					uv = 0.9
					detail = 4.0
				"snow":
					col = base.lightened(n * 0.1).darkened(n2 * 0.08)
					h = n2 * 0.3
					r = 0.55 + n * 0.2
					uv = 1.0
					detail = 3.0
				"grass", "moss":
					col = base.lerp(Color(0.2, 0.3, 0.13), n * 0.6)
					h = n2 * 0.6
					r = 0.98
					moss = 0.5
					uv = 2.0
				"marble":
					var vein := absf(sin((x + n * 40.0) * 0.08)) * 0.5
					col = base.darkened(vein * 0.25 + n * 0.06)
					h = 0.4 + vein * 0.2
					r = 0.35
					uv = 1.0
					normal_strength = 0.5
				"wallpaper":
					var stripe := 0.06 if int(x / 8.0) % 2 == 0 else 0.0
					col = base.darkened(0.08 + stripe + n * 0.18)
					h = n * 0.3
					r = 0.85
					moss = 0.15
				"glass":
					col = base.lightened(0.15)
					h = 0.1
					r = 0.08
					metallic_val = 0.9
					uv = 1.0
				_:
					col = base.darkened(n * 0.16)
					h = n * 0.5
			img.set_pixel(x, y, col)
			height.set_pixel(x, y, Color(h, h, h))
			var rr := clampf(r + (n2 - 0.5) * 0.1, 0.05, 1.0)
			rough.set_pixel(x, y, Color(rr, rr, rr))

	# Normal map por derivadas del height.
	var normal := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var strength := 2.4 * normal_strength
	for y in SIZE:
		for x in SIZE:
			var hl := height.get_pixel((x - 1 + SIZE) % SIZE, y).r
			var hr := height.get_pixel((x + 1) % SIZE, y).r
			var hu := height.get_pixel(x, (y - 1 + SIZE) % SIZE).r
			var hd := height.get_pixel(x, (y + 1) % SIZE).r
			var n := Vector3((hl - hr) * strength, (hd - hu) * strength, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))

	# ORM: R=AO aproximada, G=rugosidad, B=metalico.
	var orm := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var ao := 0.75 + height.get_pixel(x, y).r * 0.25
			var rr := rough.get_pixel(x, y).r
			orm.set_pixel(x, y, Color(ao, rr, metallic_val))

	return {
		"albedo": ImageTexture.create_from_image(img),
		"normal": ImageTexture.create_from_image(normal),
		"orm": ImageTexture.create_from_image(orm),
		"uv": uv,
		"normal_strength": normal_strength,
		"roughness": rough_mult,
		"metallic": 1.0,
		"wear": wear,
		"moss": moss,
		"detail": detail,
	}


# --- Utilidades para Fx / props -------------------------------------------------


static func flat_texture(color: Color, size: int = 8) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## Textura radial suave, usada por particulas, humo y flashes.
static func radial_texture(softness: float = 2.5, size: int = 96) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c) / (size * 0.5)
			var a := clampf(pow(clampf(1.0 - d, 0.0, 1.0), softness), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func spark_texture(size: int = 24) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


## Material simple para props chicos (no triplanar, mas barato).
static func simple(
	color: Color, roughness: float = 0.75, metallic: float = 0.0
) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


static func emissive(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
		if energy > 4.0
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)
	return mat
