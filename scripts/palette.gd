class_name CsPalette
extends RefCounted
## Paleta de 256 colores (.lmp) para las texturas indexadas de los .bsp y .mdl.
##
## Los assets no traen paleta: los .bsp guardan los pixeles como indices y la
## paleta vivia en gfx/palette.lmp del Half-Life base. Si no esta, se genera una
## aproximacion (cubo 6x6x6 + rampa de grises) y se avisa por consola.

const RUTAS_PALETA: Array[String] = [
	"res://assets/valve/gfx/palette.lmp",
	"res://assets/gfx/palette.lmp",
	"res://game/valve/gfx/palette.lmp",
]

var colores: PackedColorArray = PackedColorArray()
var origen: String = ""


static func cargar() -> CsPalette:
	var p := CsPalette.new()
	p._cargar()
	return p


func _cargar() -> void:
	for ruta in RUTAS_PALETA:
		if not FileAccess.file_exists(ruta):
			continue
		var datos := FileAccess.get_file_as_bytes(ruta)
		if datos.size() < 768:
			continue
		_colores_desde_bytes(datos)
		origen = ruta
		return
	_generar()
	origen = "generada (aproximada)"


func _colores_desde_bytes(datos: PackedByteArray) -> void:
	colores.resize(256)
	for i in 256:
		colores[i] = Color8(datos[i * 3], datos[i * 3 + 1], datos[i * 3 + 2])


func _generar() -> void:
	colores.resize(256)
	var i := 0
	for r in 6:
		for g in 6:
			for b in 6:
				colores[i] = Color8(r * 51, g * 51, b * 51)
				i += 1
	for k in 40:
		var v := mini(255, k * 255 / 39)
		colores[i] = Color8(v, v, v)
		i += 1


## Convierte un buffer de indices en una Image RGB8.
func indices_a_imagen(indices: PackedByteArray, ancho: int, alto: int) -> Image:
	var total := mini(indices.size(), ancho * alto)
	var pixeles := PackedByteArray()
	pixeles.resize(total * 3)
	for i in total:
		var c := colores[indices[i]]
		pixeles[i * 3] = int(c.r * 255.0)
		pixeles[i * 3 + 1] = int(c.g * 255.0)
		pixeles[i * 3 + 2] = int(c.b * 255.0)
	var img := Image.create_from_data(ancho, alto, false, Image.FORMAT_RGB8, pixeles)
	img.generate_mipmaps()
	return img
