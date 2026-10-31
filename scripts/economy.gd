class_name CsEconomy
extends RefCounted
## Reglas de dinero y compra de Counter-Strike 1.5.
##
## Todo el cálculo es puro (sin nodos ni estado de escena) para poder razonarlo y
## probarlo aparte. Los importes son los del 1.5; donde el 1.6 los cambió se
## indica en el comentario, porque la diferencia se nota al jugar.
##
## Fuentes: manual de CS 1.5 y la tabla de `mp_startmoney`, `mp_maxmoney` y los
## bonos de ronda que implementa el game dll del juego.

const DINERO_INICIAL := 800
const DINERO_MAX := 16000

# --- recompensas por ganar la ronda ---
const VICTORIA_ELIMINACION := 3250
const VICTORIA_BOMBA_EXPLOTA := 3500        # el equipo T
const VICTORIA_BOMBA_DESACTIVADA := 3500    # el equipo CT
const VICTORIA_TIEMPO := 3250               # se acaba el tiempo: ganan los CT
const VICTORIA_REHENES := 2000              # rescatados todos los rehenes
const RESCATE_REHEN := 1000                 # extra para quien rescata

# --- bonos por derrotar (bono de racha, sube con las derrotas seguidas) ---
const BONO_DERROTA := [1400, 1900, 2400, 2900]

# --- acciones ---
const BAJA := 300
const BAJA_CUCHILLO := 1500
const BAJA_AWP := 150                       # el AWP da menos, para desincentivarlo
const PLANTAR_BOMBA := 300                  # al que planta
const PLANTAR_EQUIPO := 800                 # a todo el equipo T al plantar
const DESACTIVAR_BOMBA := 300
const MULTA_TEAMKILL := 3300
const MULTA_SUICIDIO := 3300

# --- equipamiento que no es un arma ---
const EQUIPO := {
	"kevlar": {"nombre": "Chaleco Kevlar", "precio": 650, "tipo": "equipo"},
	"kevlar_casco": {"nombre": "Kevlar + Casco", "precio": 1000, "tipo": "equipo"},
	"kit": {"nombre": "Kit de desactivación", "precio": 200, "tipo": "equipo"},
	"hegrenade": {"nombre": "Granada HE", "precio": 300, "tipo": "granada"},
	"flashbang": {"nombre": "Flashbang", "precio": 200, "tipo": "granada"},
	"smokegrenade": {"nombre": "Granada de humo", "precio": 300, "tipo": "granada"},
}


## Precio de cualquier cosa comprable (arma o equipamiento).
static func precio(id: String) -> int:
	if EQUIPO.has(id):
		return int(EQUIPO[id]["precio"]) if EQUIPO[id].has("precio") else 0
	var arma := WeaponDB.obtener(id)
	return int(arma.get("precio", 0)) if not arma.is_empty() else 0


static func nombre(id: String) -> String:
	if EQUIPO.has(id):
		return String(EQUIPO[id].get("nombre", id))
	return WeaponDB.nombre(id)


## Bono de derrota segun las rondas perdidas seguidas (0, 1, 2, 3+).
static func bono_derrota(derrotas_seguidas: int) -> int:
	var i := clampi(derrotas_seguidas, 0, BONO_DERROTA.size() - 1)
	return int(BONO_DERROTA[i])


## Recompensa de fin de ronda para un equipo.
static func recompensa_victoria(motivo: String) -> int:
	match motivo:
		"bomba_explota":
			return VICTORIA_BOMBA_EXPLOTA
		"bomba_desactivada":
			return VICTORIA_BOMBA_DESACTIVADA
		"tiempo":
			return VICTORIA_TIEMPO
		"rehenes":
			return VICTORIA_REHENES
		_:
			return VICTORIA_ELIMINACION


## Recompensa por abatir a alguien segun el arma usada.
static func recompensa_baja(arma: String) -> int:
	match arma:
		"knife":
			return BAJA_CUCHILLO
		"awp":
			return BAJA_AWP
		_:
			return BAJA


static func limite(dinero: int) -> int:
	return clampi(dinero, 0, DINERO_MAX)


## Categorias del menu de compra, en el orden numerico del juego original.
static func categorias() -> Array[Dictionary]:
	return [
		{"clave": "1", "nombre": "Pistolas", "objetos": ["glock18", "usp45", "p228", "deagle", "elite"]},
		{"clave": "2", "nombre": "Subfusiles", "objetos": ["tmp", "mac10", "mp5", "ump45", "p90"]},
		{"clave": "3", "nombre": "Escopetas", "objetos": ["m3", "xm1014"]},
		{"clave": "4", "nombre": "Fusiles", "objetos": ["ak47", "m4a1", "sg552", "aug"]},
		{"clave": "5", "nombre": "Francotiradores", "objetos": ["scout", "awp", "g3sg1", "sg550"]},
		{"clave": "6", "nombre": "Ametralladora", "objetos": ["m249"]},
		{"clave": "7", "nombre": "Equipamiento", "objetos": ["kevlar", "kevlar_casco", "kit"]},
		{"clave": "8", "nombre": "Granadas", "objetos": ["hegrenade", "flashbang", "smokegrenade"]},
	]
