class_name WeaponDB
extends RefCounted
## Arsenal de Counter-Strike 1.5 con las estadisticas del juego original.
##
## Solo armas de 1.5: FAMAS, Galil, Five-SeveN y el escudo son de 1.6 y no se
## incluyen aunque sus modelos esten en assets/ (los viewmodels son mixtos).
##
## `danio`, `cadencia` (disparos por minuto), `precio` y `cargador` son los del
## CS 1.5. La dispersion es la del `.txt` de armas de Valve, expresada en grados
## para Godot (1 unidad GoldSrc ~ 0.025 m).

const ARMAS := {
	# --- pistolas ---
	"glock18": {"nombre": "Glock 18", "tipo": "pistola", "precio": 400, "danio": 25,
		"cadencia": 400, "cargador": 20, "reserva": 120, "dispersion": 0.9,
		"retroceso": 1.2, "penetracion": 0.5, "sonido": "glock18-1.wav", "slot": 2,
		"viewmodel": "v_glock18_r.mdl", "automatica": false},
	"usp45": {"nombre": "USP .45", "tipo": "pistola", "precio": 500, "danio": 34,
		"cadencia": 352, "cargador": 12, "reserva": 100, "dispersion": 0.55,
		"retroceso": 1.4, "penetracion": 0.6, "sonido": "usp45-1.wav", "slot": 2,
		"viewmodel": "v_usp_r.mdl", "automatica": false},
	"p228": {"nombre": "P228", "tipo": "pistola", "precio": 600, "danio": 32,
		"cadencia": 400, "cargador": 13, "reserva": 52, "dispersion": 0.6,
		"retroceso": 1.3, "penetracion": 0.6, "sonido": "p228-1.wav", "slot": 2,
		"viewmodel": "v_p228_r.mdl", "automatica": false},
	"deagle": {"nombre": "Desert Eagle", "tipo": "pistola", "precio": 650, "danio": 54,
		"cadencia": 267, "cargador": 7, "reserva": 35, "dispersion": 0.9,
		"retroceso": 3.6, "penetracion": 0.8, "sonido": "deagle-1.wav", "slot": 2,
		"viewmodel": "v_deagle_r.mdl", "automatica": false},
	"elite": {"nombre": "Dual Berettas", "tipo": "pistola", "precio": 800, "danio": 26,
		"cadencia": 500, "cargador": 30, "reserva": 120, "dispersion": 1.1,
		"retroceso": 1.0, "penetracion": 0.5, "sonido": "elite-1.wav", "slot": 2,
		"viewmodel": "v_elite.mdl", "automatica": false},
	# --- subfusiles ---
	"tmp": {"nombre": "TMP", "tipo": "subfusil", "precio": 1250, "danio": 20,
		"cadencia": 857, "cargador": 30, "reserva": 120, "dispersion": 0.85,
		"retroceso": 1.1, "penetracion": 0.55, "sonido": "tmp-1.wav", "slot": 1,
		"viewmodel": "v_tmp_r.mdl", "automatica": true},
	"mac10": {"nombre": "MAC-10", "tipo": "subfusil", "precio": 1400, "danio": 29,
		"cadencia": 857, "cargador": 30, "reserva": 90, "dispersion": 1.0,
		"retroceso": 1.4, "penetracion": 0.5, "sonido": "mac10-1.wav", "slot": 1,
		"viewmodel": "v_mac10_r.mdl", "automatica": true},
	"mp5": {"nombre": "MP5 Navy", "tipo": "subfusil", "precio": 1500, "danio": 27,
		"cadencia": 750, "cargador": 30, "reserva": 120, "dispersion": 0.7,
		"retroceso": 1.2, "penetracion": 0.6, "sonido": "mp5-1.wav", "slot": 1,
		"viewmodel": "v_mp5_r.mdl", "automatica": true},
	"ump45": {"nombre": "UMP 45", "tipo": "subfusil", "precio": 1700, "danio": 30,
		"cadencia": 666, "cargador": 25, "reserva": 100, "dispersion": 0.75,
		"retroceso": 1.3, "penetracion": 0.6, "sonido": "ump45-1.wav", "slot": 1,
		"viewmodel": "v_ump45_r.mdl", "automatica": true},
	"p90": {"nombre": "P90", "tipo": "subfusil", "precio": 2350, "danio": 21,
		"cadencia": 857, "cargador": 50, "reserva": 100, "dispersion": 0.8,
		"retroceso": 1.1, "penetracion": 0.65, "sonido": "p90-1.wav", "slot": 1,
		"viewmodel": "v_p90_r.mdl", "automatica": true},
	# --- escopetas ---
	"m3": {"nombre": "M3 Super 90", "tipo": "escopeta", "precio": 1700, "danio": 8,
		"cadencia": 76, "cargador": 8, "reserva": 32, "dispersion": 0.0,
		"retroceso": 4.0, "penetracion": 0.4, "sonido": "m3-1.wav", "slot": 1,
		"viewmodel": "v_m3_r.mdl", "automatica": false, "perdigones": 9},
	"xm1014": {"nombre": "XM1014", "tipo": "escopeta", "precio": 3000, "danio": 5,
		"cadencia": 240, "cargador": 7, "reserva": 32, "dispersion": 0.0,
		"retroceso": 3.4, "penetracion": 0.4, "sonido": "xm1014-1.wav", "slot": 1,
		"viewmodel": "v_xm1014_r.mdl", "automatica": false, "perdigones": 6},
	# --- fusiles ---
	"ak47": {"nombre": "AK-47", "tipo": "fusil", "precio": 2500, "danio": 36,
		"cadencia": 600, "cargador": 30, "reserva": 90, "dispersion": 0.4,
		"retroceso": 3.0, "penetracion": 0.77, "sonido": "ak47-1.wav", "slot": 1,
		"viewmodel": "v_ak47_r.mdl", "automatica": true},
	"m4a1": {"nombre": "M4A1", "tipo": "fusil", "precio": 3100, "danio": 32,
		"cadencia": 685, "cargador": 30, "reserva": 90, "dispersion": 0.4,
		"retroceso": 2.6, "penetracion": 0.7, "sonido": "m4a1-1.wav", "slot": 1,
		"viewmodel": "v_m4a1_r.mdl", "automatica": true},
	"sg552": {"nombre": "SG 552", "tipo": "fusil", "precio": 3500, "danio": 33,
		"cadencia": 727, "cargador": 30, "reserva": 90, "dispersion": 0.42,
		"retroceso": 2.5, "penetracion": 0.7, "sonido": "sg552-1.wav", "slot": 1,
		"viewmodel": "v_sg552_r.mdl", "automatica": true, "zoom": 2.0},
	"aug": {"nombre": "Steyr AUG", "tipo": "fusil", "precio": 3500, "danio": 32,
		"cadencia": 666, "cargador": 30, "reserva": 90, "dispersion": 0.42,
		"retroceso": 2.5, "penetracion": 0.7, "sonido": "aug-1.wav", "slot": 1,
		"viewmodel": "v_aug_r.mdl", "automatica": true, "zoom": 1.8},
	# --- francotiradores ---
	"scout": {"nombre": "Steyr Scout", "tipo": "francotirador", "precio": 2750,
		"danio": 75, "cadencia": 100, "cargador": 10, "reserva": 90, "dispersion": 0.0,
		"retroceso": 3.0, "penetracion": 0.85, "sonido": "scout_fire1.wav", "slot": 1,
		"viewmodel": "v_scout_r.mdl", "automatica": false, "zoom": 4.0},
	"awp": {"nombre": "AWP", "tipo": "francotirador", "precio": 4750, "danio": 115,
		"cadencia": 41, "cargador": 10, "reserva": 30, "dispersion": 0.0,
		"retroceso": 5.0, "penetracion": 0.95, "sonido": "awp1.wav", "slot": 1,
		"viewmodel": "v_awp_r.mdl", "automatica": false, "zoom": 3.5},
	"g3sg1": {"nombre": "G3SG1", "tipo": "francotirador", "precio": 5000, "danio": 80,
		"cadencia": 240, "cargador": 20, "reserva": 90, "dispersion": 0.15,
		"retroceso": 3.5, "penetracion": 0.85, "sonido": "g3sg1-1.wav", "slot": 1,
		"viewmodel": "v_g3sg1_r.mdl", "automatica": false, "zoom": 3.0},
	"sg550": {"nombre": "SG 550", "tipo": "francotirador", "precio": 4200, "danio": 70,
		"cadencia": 240, "cargador": 20, "reserva": 90, "dispersion": 0.15,
		"retroceso": 3.2, "penetracion": 0.85, "sonido": "sg550-1.wav", "slot": 1,
		"viewmodel": "v_sg550_r.mdl", "automatica": false, "zoom": 3.0},
	# --- ametralladora ---
	"m249": {"nombre": "M249 Para", "tipo": "ametralladora", "precio": 5750, "danio": 32,
		"cadencia": 750, "cargador": 100, "reserva": 200, "dispersion": 0.6,
		"retroceso": 3.0, "penetracion": 0.8, "sonido": "m249-1.wav", "slot": 1,
		"viewmodel": "v_m249_r.mdl", "automatica": true},
	# --- cuerpo a cuerpo y granadas ---
	"knife": {"nombre": "Cuchillo", "tipo": "cuchillo", "precio": 0, "danio": 15,
		"cadencia": 120, "cargador": 0, "reserva": 0, "dispersion": 0.0,
		"retroceso": 0.0, "penetracion": 0.0, "sonido": "knife_slash1.wav", "slot": 3,
		"viewmodel": "v_knife_r.mdl", "automatica": false, "alcance": 1.2},
	"hegrenade": {"nombre": "Granada HE", "tipo": "granada", "precio": 300,
		"danio": 98, "cadencia": 60, "cargador": 1, "reserva": 1, "dispersion": 0.0,
		"retroceso": 0.0, "penetracion": 0.0, "sonido": "he_bounce1.wav", "slot": 4,
		"viewmodel": "v_hegrenade_r.mdl", "automatica": false},
	"flashbang": {"nombre": "Flashbang", "tipo": "granada", "precio": 200,
		"danio": 0, "cadencia": 60, "cargador": 1, "reserva": 1, "dispersion": 0.0,
		"retroceso": 0.0, "penetracion": 0.0, "sonido": "flashbang_explode1.wav",
		"slot": 4, "viewmodel": "v_flashbang_r.mdl", "automatica": false},
	"smokegrenade": {"nombre": "Granada de humo", "tipo": "granada", "precio": 300,
		"danio": 0, "cadencia": 60, "cargador": 1, "reserva": 1, "dispersion": 0.0,
		"retroceso": 0.0, "penetracion": 0.0, "sonido": "flashbang_explode1.wav",
		"slot": 4, "viewmodel": "v_smokegrenade_r.mdl", "automatica": false},
}

## Equipamiento por defecto al aparecer (como en CS 1.5: solo pistola y cuchillo).
const EQUIPO_INICIAL: Array[String] = ["knife", "glock18"]

## Orden de los slots del HUD (1..5 en el teclado).
const SLOTS := {1: "primaria", 2: "pistola", 3: "cuchillo", 4: "granada", 5: "c4"}


static func obtener(id: String) -> Dictionary:
	return ARMAS.get(id, {}) as Dictionary


static func existe(id: String) -> bool:
	return ARMAS.has(id)


static func de_tipo(tipo: String) -> Array[String]:
	var salida: Array[String] = []
	for id in ARMAS:
		if String(ARMAS[id]["tipo"]) == tipo:
			salida.append(id)
	return salida


static func nombre(id: String) -> String:
	var a := obtener(id)
	return String(a.get("nombre", id))
