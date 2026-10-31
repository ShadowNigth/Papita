extends Node
## Content: base de datos del juego (armas, economia, mapas, zombies, bots).
##
## Todos los valores estan inspirados en Counter-Strike 1.5 y reajustados para
## una jugabilidad moderna en Godot 4. Es una reimplementacion propia.

const TEAM_BOTH := 0
const TEAM_CT := 1
const TEAM_T := 2

const SLOT_PRIMARY := 1
const SLOT_SECONDARY := 2
const SLOT_KNIFE := 3
const SLOT_GRENADE := 4
const SLOT_C4 := 5

const START_MONEY := 800
const MAX_MONEY := 16000
const WIN_REWARD := 3250
const WIN_BOMB_REWARD := 3500
const LOSS_BONUS := [1400, 1900, 2400, 2900, 3400]
const PLANT_REWARD := 800
const DEFUSE_REWARD := 800
const RESCUE_REWARD := 1000
const TEAMKILL_PENALTY := 3300
const MAX_HEALTH := 100
const MAX_ARMOR := 100

const ZOMBIE_START_POINTS := 500
const ZOMBIE_POINTS_PER_HIT := 10
const ZOMBIE_POINTS_KILL_BONUS := 1
const PERK_PRICES := {"jugg": 2500, "speed": 2000, "double": 2000, "revive": 2500, "mule": 4000}
const MYSTERY_BOX_PRICE := 950
const ZOMBIE_AMMO_PRICE := 450

const DIFFICULTY := [
	{
		"id": "recruit",
		"name": "RECLUTA",
		"reaction": 0.65,
		"aim_error": 4.2,
		"accuracy": 0.5,
		"burst": 0.5,
		"fov": 75.0,
		"hearing": 14.0,
		"hp": 90,
	},
	{
		"id": "regular",
		"name": "REGULAR",
		"reaction": 0.42,
		"aim_error": 2.6,
		"accuracy": 0.66,
		"burst": 0.35,
		"fov": 95.0,
		"hearing": 20.0,
		"hp": 100,
	},
	{
		"id": "veteran",
		"name": "VETERANO",
		"reaction": 0.27,
		"aim_error": 1.7,
		"accuracy": 0.78,
		"burst": 0.24,
		"fov": 110.0,
		"hearing": 26.0,
		"hp": 100,
	},
	{
		"id": "expert",
		"name": "EXPERTO",
		"reaction": 0.16,
		"aim_error": 1.0,
		"accuracy": 0.87,
		"burst": 0.16,
		"fov": 120.0,
		"hearing": 32.0,
		"hp": 110,
	},
	{
		"id": "legend",
		"name": "LEYENDA",
		"reaction": 0.09,
		"aim_error": 0.55,
		"accuracy": 0.94,
		"burst": 0.1,
		"fov": 130.0,
		"hearing": 40.0,
		"hp": 120,
	},
]

const BOT_NAMES := [
	"Papita",
	"Mate",
	"Truco",
	"Che",
	"Gaucho",
	"Asado",
	"Chimichurri",
	"Emi",
	"Fede",
	"Sofi",
	"Nico",
	"Cami",
	"Leo",
	"Mica",
	"Tano",
	"Bocha",
	"Pampa",
	"Zorro",
	"Cordoba",
	"Serrano",
	"Nube",
	"Pulga",
	"Rulo",
	"Chino",
	"Loco",
	"Cuervo",
	"Tigre",
	"Lobo",
	"Falcon",
	"Viper",
	"Rocco",
	"Dante",
	"Bruno",
	"Kali",
	"Reaper",
	"Nova",
	"Ghost",
	"Boris",
	"Yuki",
	"Axel",
]

const RANKS := [
	[0, "Aspirante"],
	[5, "Cabo"],
	[15, "Sargento"],
	[30, "Teniente"],
	[60, "Capitan"],
	[100, "Mayor"],
	[160, "Coronel"],
	[240, "Comando"],
	[350, "Elite"],
	[500, "Leyenda"],
]

const ACHIEVEMENTS := {
	"first_blood": {"name": "Primera sangre", "desc": "Consigue tu primera baja."},
	"headhunter": {"name": "Cazacabezas", "desc": "50 tiros a la cabeza."},
	"ace": {"name": "ACE", "desc": "Elimina a 5 enemigos en una ronda."},
	"bombhero": {"name": "Heroe del C4", "desc": "Desactiva una bomba."},
	"survivor": {"name": "Superviviente", "desc": "Alcanza la oleada 10 en Zombie."},
	"slayer": {"name": "Exterminador", "desc": "500 zombies eliminados."},
	"rich": {"name": "Millonario", "desc": "Acumula 16000 en una partida."},
	"knife": {"name": "Silencioso", "desc": "Consigue una baja con cuchillo."},
	"wallbang": {"name": "Perforador", "desc": "Consigue una baja atravesando una pared."},
	"untouchable": {"name": "Intocable", "desc": "Gana una ronda sin recibir dano."},
}

const WEAPONS := {
	"knife":
	{
		"id": "knife",
		"name": "Cuchillo",
		"cls": "knife",
		"slot": 3,
		"team": 0,
		"price": 0,
		"damage": 40,
		"back_damage": 90,
		"stab_damage": 65,
		"stab_back_damage": 180,
		"rpm": 120,
		"stab_rpm": 60,
		"mag": 0,
		"reserve": 0,
		"reload": 0.0,
		"draw": 0.4,
		"spread": 0.0,
		"range": 2.0,
		"recoil": 0.0,
		"speed_mult": 1.12,
		"award": 1500,
		"sound": "knife",
		"desc": "Silencioso y letal: click derecho apunala con fuerza.",
		"vm": {"len": 0.22, "color": Color(0.7, 0.72, 0.75), "kind": "knife"},
	},
	"glock18":
	{
		"id": "glock18",
		"name": "Glock 18",
		"cls": "pistol",
		"slot": 2,
		"team": 2,
		"price": 400,
		"damage": 25,
		"armor_pen": 0.55,
		"rpm": 400,
		"mag": 20,
		"reserve": 120,
		"reload": 2.2,
		"draw": 0.45,
		"spread": 0.55,
		"move_spread": 1.8,
		"air_spread": 4.0,
		"recoil": 0.9,
		"range": 45.0,
		"falloff": 22.0,
		"min_mult": 0.55,
		"auto": false,
		"burst": 3,
		"burst_toggle": true,
		"burst_rpm": 1100,
		"burst_cooldown": 0.42,
		"penetration": 1,
		"speed_mult": 1.02,
		"award": 300,
		"sound": "pistol",
		"silencer": false,
		"desc": "Click derecho alterna semiautomatica y rafaga de 3 tiros.",
		"vm": {"len": 0.3, "color": Color(0.22, 0.23, 0.25), "kind": "pistol"},
	},
	"usp45":
	{
		"id": "usp45",
		"name": "USP .45",
		"cls": "pistol",
		"slot": 2,
		"team": 1,
		"price": 500,
		"damage": 34,
		"armor_pen": 0.6,
		"rpm": 400,
		"mag": 12,
		"reserve": 100,
		"reload": 2.2,
		"draw": 0.45,
		"spread": 0.42,
		"move_spread": 1.6,
		"air_spread": 3.6,
		"recoil": 1.15,
		"range": 55.0,
		"falloff": 25.0,
		"min_mult": 0.6,
		"auto": false,
		"burst": 0,
		"penetration": 1,
		"speed_mult": 1.02,
		"award": 300,
		"sound": "pistol",
		"silencer": true,
		"desc": "Silenciable, precisa y contundente. Estandar CT.",
		"vm": {"len": 0.34, "color": Color(0.18, 0.19, 0.21), "kind": "pistol", "silencer": true},
	},
	"p228":
	{
		"id": "p228",
		"name": "P228",
		"cls": "pistol",
		"slot": 2,
		"team": 0,
		"price": 600,
		"damage": 32,
		"armor_pen": 0.6,
		"rpm": 400,
		"mag": 13,
		"reserve": 52,
		"reload": 2.1,
		"draw": 0.45,
		"spread": 0.4,
		"move_spread": 1.5,
		"air_spread": 3.4,
		"recoil": 1.05,
		"range": 50.0,
		"falloff": 24.0,
		"min_mult": 0.6,
		"auto": false,
		"burst": 0,
		"penetration": 1,
		"speed_mult": 1.02,
		"award": 300,
		"sound": "pistol",
		"silencer": false,
		"desc": "Compacta, rapida y equilibrada.",
		"vm": {"len": 0.29, "color": Color(0.2, 0.21, 0.23), "kind": "pistol"},
	},
	"deagle":
	{
		"id": "deagle",
		"name": "Desert Eagle",
		"cls": "pistol",
		"slot": 2,
		"team": 0,
		"price": 650,
		"damage": 54,
		"armor_pen": 0.75,
		"rpm": 267,
		"mag": 7,
		"reserve": 35,
		"reload": 2.4,
		"draw": 0.6,
		"spread": 0.5,
		"move_spread": 2.6,
		"air_spread": 6.0,
		"recoil": 2.4,
		"range": 80.0,
		"falloff": 35.0,
		"min_mult": 0.7,
		"auto": false,
		"burst": 0,
		"penetration": 2,
		"speed_mult": 0.98,
		"award": 300,
		"sound": "pistol_heavy",
		"silencer": false,
		"desc": "Un canon en el bolsillo. Headshot casi seguro.",
		"vm": {"len": 0.36, "color": Color(0.42, 0.38, 0.32), "kind": "pistol", "big": true},
	},
	"fiveseven":
	{
		"id": "fiveseven",
		"name": "Five-SeveN",
		"cls": "pistol",
		"slot": 2,
		"team": 1,
		"price": 750,
		"damage": 25,
		"armor_pen": 0.72,
		"rpm": 400,
		"mag": 20,
		"reserve": 100,
		"reload": 2.2,
		"draw": 0.45,
		"spread": 0.36,
		"move_spread": 1.4,
		"air_spread": 3.2,
		"recoil": 0.85,
		"range": 55.0,
		"falloff": 26.0,
		"min_mult": 0.65,
		"auto": false,
		"burst": 0,
		"penetration": 2,
		"speed_mult": 1.04,
		"award": 300,
		"sound": "pistol",
		"silencer": false,
		"desc": "Perfora chalecos con 20 balas de alto poder.",
		"vm": {"len": 0.31, "color": Color(0.24, 0.26, 0.24), "kind": "pistol"},
	},
	"elite":
	{
		"id": "elite",
		"name": "Dual Berettas",
		"cls": "pistol",
		"slot": 2,
		"team": 2,
		"price": 800,
		"damage": 36,
		"armor_pen": 0.55,
		"rpm": 600,
		"mag": 30,
		"reserve": 120,
		"reload": 2.8,
		"draw": 0.7,
		"spread": 0.75,
		"move_spread": 2.0,
		"air_spread": 4.5,
		"recoil": 1.0,
		"range": 40.0,
		"falloff": 20.0,
		"min_mult": 0.5,
		"auto": true,
		"burst": 0,
		"penetration": 1,
		"speed_mult": 1.0,
		"award": 300,
		"sound": "pistol",
		"silencer": false,
		"dual": true,
		"desc": "Dos pistolas, 30 balas de puro ruido.",
		"vm": {"len": 0.3, "color": Color(0.26, 0.25, 0.23), "kind": "pistol", "dual": true},
	},
	"m3":
	{
		"id": "m3",
		"name": "M3 Super 90",
		"cls": "shotgun",
		"slot": 1,
		"team": 0,
		"price": 1700,
		"damage": 9,
		"pellets": 9,
		"armor_pen": 0.5,
		"rpm": 80,
		"mag": 8,
		"reserve": 32,
		"reload": 0.55,
		"reload_shell": true,
		"draw": 0.8,
		"spread": 3.2,
		"move_spread": 1.0,
		"air_spread": 2.0,
		"recoil": 3.0,
		"range": 20.0,
		"falloff": 8.0,
		"min_mult": 0.2,
		"auto": false,
		"penetration": 0,
		"speed_mult": 0.98,
		"award": 900,
		"sound": "shotgun",
		"pump": true,
		"desc": "Bomba de corredera. Devastadora de cerca.",
		"vm": {"len": 0.78, "color": Color(0.2, 0.2, 0.22), "kind": "shotgun", "wood": true},
	},
	"xm1014":
	{
		"id": "xm1014",
		"name": "XM1014",
		"cls": "shotgun",
		"slot": 1,
		"team": 0,
		"price": 3000,
		"damage": 8,
		"pellets": 8,
		"armor_pen": 0.55,
		"rpm": 171,
		"mag": 7,
		"reserve": 32,
		"reload": 2.6,
		"draw": 0.85,
		"spread": 3.6,
		"move_spread": 1.1,
		"air_spread": 2.2,
		"recoil": 2.2,
		"range": 22.0,
		"falloff": 9.0,
		"min_mult": 0.22,
		"auto": true,
		"penetration": 0,
		"speed_mult": 0.98,
		"award": 900,
		"sound": "shotgun",
		"desc": "Semiautomatica: limpia habitaciones enteras.",
		"vm": {"len": 0.72, "color": Color(0.15, 0.16, 0.17), "kind": "shotgun"},
	},
	"tmp":
	{
		"id": "tmp",
		"name": "TMP",
		"cls": "smg",
		"slot": 1,
		"team": 1,
		"price": 1250,
		"damage": 20,
		"armor_pen": 0.6,
		"rpm": 857,
		"mag": 30,
		"reserve": 120,
		"reload": 2.2,
		"draw": 0.55,
		"spread": 0.55,
		"move_spread": 0.9,
		"air_spread": 2.6,
		"recoil": 0.8,
		"range": 32.0,
		"falloff": 16.0,
		"min_mult": 0.5,
		"auto": true,
		"penetration": 1,
		"speed_mult": 1.06,
		"award": 600,
		"sound": "smg",
		"desc": "Subfusil silencioso de CT, control absoluto.",
		"vm": {"len": 0.42, "color": Color(0.17, 0.18, 0.2), "kind": "smg", "silencer": true},
	},
	"mac10":
	{
		"id": "mac10",
		"name": "MAC-10",
		"cls": "smg",
		"slot": 1,
		"team": 2,
		"price": 1400,
		"damage": 29,
		"armor_pen": 0.6,
		"rpm": 800,
		"mag": 30,
		"reserve": 100,
		"reload": 2.3,
		"draw": 0.55,
		"spread": 0.8,
		"move_spread": 1.0,
		"air_spread": 2.8,
		"recoil": 1.25,
		"range": 30.0,
		"falloff": 15.0,
		"min_mult": 0.5,
		"auto": true,
		"penetration": 1,
		"speed_mult": 1.05,
		"award": 600,
		"sound": "smg",
		"desc": "Pequeno, barato y brutalmente rapido.",
		"vm": {"len": 0.34, "color": Color(0.16, 0.17, 0.16), "kind": "smg"},
	},
	"mp5":
	{
		"id": "mp5",
		"name": "MP5 Navy",
		"cls": "smg",
		"slot": 1,
		"team": 0,
		"price": 1500,
		"damage": 27,
		"armor_pen": 0.62,
		"rpm": 750,
		"mag": 30,
		"reserve": 120,
		"reload": 2.3,
		"draw": 0.55,
		"spread": 0.45,
		"move_spread": 0.75,
		"air_spread": 2.4,
		"recoil": 0.95,
		"range": 38.0,
		"falloff": 18.0,
		"min_mult": 0.55,
		"auto": true,
		"penetration": 1,
		"speed_mult": 1.06,
		"award": 600,
		"sound": "smg",
		"desc": "El clasico. Precision de fusil en cuerpo de subfusil.",
		"vm": {"len": 0.46, "color": Color(0.14, 0.15, 0.17), "kind": "smg"},
	},
	"ump45":
	{
		"id": "ump45",
		"name": "UMP 45",
		"cls": "smg",
		"slot": 1,
		"team": 0,
		"price": 1700,
		"damage": 34,
		"armor_pen": 0.65,
		"rpm": 600,
		"mag": 25,
		"reserve": 100,
		"reload": 2.4,
		"draw": 0.6,
		"spread": 0.5,
		"move_spread": 0.85,
		"air_spread": 2.6,
		"recoil": 1.15,
		"range": 40.0,
		"falloff": 19.0,
		"min_mult": 0.6,
		"auto": true,
		"penetration": 1,
		"speed_mult": 1.04,
		"award": 600,
		"sound": "smg",
		"desc": "Balas .45 con cadencia lenta y mucho dano.",
		"vm": {"len": 0.45, "color": Color(0.18, 0.17, 0.15), "kind": "smg"},
	},
	"p90":
	{
		"id": "p90",
		"name": "P90",
		"cls": "smg",
		"slot": 1,
		"team": 0,
		"price": 2350,
		"damage": 21,
		"armor_pen": 0.65,
		"rpm": 857,
		"mag": 50,
		"reserve": 100,
		"reload": 3.0,
		"draw": 0.65,
		"spread": 0.55,
		"move_spread": 0.7,
		"air_spread": 2.2,
		"recoil": 0.85,
		"range": 36.0,
		"falloff": 17.0,
		"min_mult": 0.55,
		"auto": true,
		"penetration": 1,
		"speed_mult": 1.06,
		"award": 600,
		"sound": "smg",
		"desc": "50 balas, retroceso minimo. Perfecta para rushes.",
		"vm": {"len": 0.5, "color": Color(0.24, 0.25, 0.2), "kind": "smg", "bullpup": true},
	},
	"famas":
	{
		"id": "famas",
		"name": "FAMAS",
		"cls": "rifle",
		"slot": 1,
		"team": 1,
		"price": 2250,
		"damage": 30,
		"armor_pen": 0.7,
		"rpm": 750,
		"mag": 25,
		"reserve": 90,
		"reload": 2.6,
		"draw": 0.7,
		"spread": 0.35,
		"move_spread": 1.8,
		"air_spread": 5.0,
		"recoil": 1.35,
		"range": 70.0,
		"falloff": 30.0,
		"min_mult": 0.65,
		"auto": true,
		"burst": 3,
		"burst_toggle": true,
		"burst_rpm": 1050,
		"burst_cooldown": 0.4,
		"penetration": 2,
		"speed_mult": 1.0,
		"award": 300,
		"sound": "rifle",
		"desc": "Click derecho alterna fuego automatico y rafaga de 3 tiros.",
		"vm": {"len": 0.75, "color": Color(0.16, 0.17, 0.18), "kind": "rifle", "bullpup": true},
	},
	"galil":
	{
		"id": "galil",
		"name": "Galil AR",
		"cls": "rifle",
		"slot": 1,
		"team": 2,
		"price": 2000,
		"damage": 30,
		"armor_pen": 0.72,
		"rpm": 666,
		"mag": 35,
		"reserve": 90,
		"reload": 2.7,
		"draw": 0.7,
		"spread": 0.45,
		"move_spread": 1.9,
		"air_spread": 5.2,
		"recoil": 1.5,
		"range": 75.0,
		"falloff": 32.0,
		"min_mult": 0.68,
		"auto": true,
		"penetration": 2,
		"speed_mult": 1.0,
		"award": 300,
		"sound": "rifle",
		"desc": "El fusil barato de los T: 35 balas y buen control.",
		"vm": {"len": 0.78, "color": Color(0.17, 0.16, 0.14), "kind": "rifle"},
	},
	"ak47":
	{
		"id": "ak47",
		"name": "AK-47",
		"cls": "rifle",
		"slot": 1,
		"team": 2,
		"price": 2500,
		"damage": 36,
		"armor_pen": 0.78,
		"rpm": 600,
		"mag": 30,
		"reserve": 90,
		"reload": 2.5,
		"draw": 0.75,
		"spread": 0.32,
		"move_spread": 2.2,
		"air_spread": 6.0,
		"recoil": 2.1,
		"range": 85.0,
		"falloff": 35.0,
		"min_mult": 0.7,
		"auto": true,
		"penetration": 3,
		"speed_mult": 0.99,
		"award": 300,
		"sound": "rifle_heavy",
		"desc": "Un disparo a la cabeza y no hay casco que salve.",
		"vm": {"len": 0.82, "color": Color(0.32, 0.22, 0.14), "kind": "rifle", "wood": true},
	},
	"m4a1":
	{
		"id": "m4a1",
		"name": "M4A1",
		"cls": "rifle",
		"slot": 1,
		"team": 1,
		"price": 3100,
		"damage": 33,
		"armor_pen": 0.73,
		"rpm": 666,
		"mag": 30,
		"reserve": 90,
		"reload": 2.6,
		"draw": 0.75,
		"spread": 0.3,
		"move_spread": 1.9,
		"air_spread": 5.5,
		"recoil": 1.6,
		"range": 85.0,
		"falloff": 34.0,
		"min_mult": 0.7,
		"auto": true,
		"penetration": 2,
		"speed_mult": 1.0,
		"award": 300,
		"sound": "rifle",
		"silencer": true,
		"desc": "Silenciable y estable: la columna vertebral de CT.",
		"vm": {"len": 0.8, "color": Color(0.18, 0.19, 0.2), "kind": "rifle", "silencer": true},
	},
	"sg552":
	{
		"id": "sg552",
		"name": "SG 552",
		"cls": "rifle",
		"slot": 1,
		"team": 2,
		"price": 3500,
		"damage": 33,
		"armor_pen": 0.75,
		"rpm": 727,
		"mag": 30,
		"reserve": 90,
		"reload": 2.8,
		"draw": 0.8,
		"spread": 0.3,
		"move_spread": 2.0,
		"air_spread": 5.6,
		"recoil": 1.7,
		"range": 88.0,
		"falloff": 34.0,
		"min_mult": 0.72,
		"auto": true,
		"penetration": 2,
		"speed_mult": 0.98,
		"award": 300,
		"sound": "rifle",
		"zoom": 2.0,
		"desc": "Fusil de asalto con mira de 2x.",
		"vm": {"len": 0.74, "color": Color(0.15, 0.16, 0.15), "kind": "rifle", "scope": true},
	},
	"aug":
	{
		"id": "aug",
		"name": "Steyr AUG",
		"cls": "rifle",
		"slot": 1,
		"team": 1,
		"price": 3500,
		"damage": 32,
		"armor_pen": 0.74,
		"rpm": 727,
		"mag": 30,
		"reserve": 90,
		"reload": 2.8,
		"draw": 0.8,
		"spread": 0.28,
		"move_spread": 1.9,
		"air_spread": 5.4,
		"recoil": 1.55,
		"range": 88.0,
		"falloff": 34.0,
		"min_mult": 0.72,
		"auto": true,
		"penetration": 2,
		"speed_mult": 0.98,
		"award": 300,
		"sound": "rifle",
		"zoom": 1.8,
		"desc": "Bullpup con mira integrada de 1.8x.",
		"vm":
		{
			"len": 0.76,
			"color": Color(0.28, 0.27, 0.22),
			"kind": "rifle",
			"scope": true,
			"bullpup": true
		},
	},
	"scout":
	{
		"id": "scout",
		"name": "Steyr Scout",
		"cls": "sniper",
		"slot": 1,
		"team": 0,
		"price": 2750,
		"damage": 75,
		"armor_pen": 0.8,
		"rpm": 100,
		"mag": 10,
		"reserve": 90,
		"reload": 2.8,
		"draw": 0.9,
		"spread": 0.1,
		"move_spread": 6.0,
		"air_spread": 12.0,
		"recoil": 2.0,
		"range": 120.0,
		"falloff": 60.0,
		"min_mult": 0.85,
		"auto": false,
		"penetration": 2,
		"speed_mult": 1.04,
		"award": 300,
		"sound": "sniper",
		"zoom": 4.0,
		"desc": "Ligero, rapido y preciso. El fusil de los valientes.",
		"vm": {"len": 0.85, "color": Color(0.2, 0.24, 0.2), "kind": "sniper", "scope": true},
	},
	"awp":
	{
		"id": "awp",
		"name": "AWP",
		"cls": "sniper",
		"slot": 1,
		"team": 0,
		"price": 4750,
		"damage": 115,
		"armor_pen": 0.95,
		"rpm": 41,
		"mag": 10,
		"reserve": 30,
		"reload": 3.6,
		"draw": 1.1,
		"spread": 0.05,
		"move_spread": 9.0,
		"air_spread": 16.0,
		"recoil": 3.6,
		"range": 150.0,
		"falloff": 80.0,
		"min_mult": 0.9,
		"auto": false,
		"penetration": 4,
		"speed_mult": 0.92,
		"award": 100,
		"sound": "sniper",
		"zoom": 5.0,
		"desc": "Un tiro, una baja. El arma mas temida del juego.",
		"vm":
		{
			"len": 0.95,
			"color": Color(0.16, 0.2, 0.16),
			"kind": "sniper",
			"scope": true,
			"bipod": true
		},
	},
	"g3sg1":
	{
		"id": "g3sg1",
		"name": "G3SG1",
		"cls": "sniper",
		"slot": 1,
		"team": 2,
		"price": 5000,
		"damage": 80,
		"armor_pen": 0.82,
		"rpm": 240,
		"mag": 20,
		"reserve": 90,
		"reload": 3.2,
		"draw": 1.0,
		"spread": 0.08,
		"move_spread": 7.0,
		"air_spread": 14.0,
		"recoil": 2.8,
		"range": 130.0,
		"falloff": 65.0,
		"min_mult": 0.85,
		"auto": true,
		"penetration": 3,
		"speed_mult": 0.94,
		"award": 300,
		"sound": "sniper",
		"zoom": 3.5,
		"desc": "Semiautomatico de precision, ideal para cubrir sitios.",
		"vm": {"len": 0.9, "color": Color(0.17, 0.17, 0.16), "kind": "sniper", "scope": true},
	},
	"sg550":
	{
		"id": "sg550",
		"name": "SG 550",
		"cls": "sniper",
		"slot": 1,
		"team": 1,
		"price": 4200,
		"damage": 70,
		"armor_pen": 0.8,
		"rpm": 240,
		"mag": 20,
		"reserve": 90,
		"reload": 3.1,
		"draw": 1.0,
		"spread": 0.08,
		"move_spread": 6.5,
		"air_spread": 13.0,
		"recoil": 2.4,
		"range": 130.0,
		"falloff": 65.0,
		"min_mult": 0.85,
		"auto": true,
		"penetration": 3,
		"speed_mult": 0.96,
		"award": 300,
		"sound": "sniper",
		"zoom": 3.5,
		"desc": "Precision suiza con cargador de 20.",
		"vm": {"len": 0.9, "color": Color(0.2, 0.21, 0.2), "kind": "sniper", "scope": true},
	},
	"m249":
	{
		"id": "m249",
		"name": "M249 Para",
		"cls": "lmg",
		"slot": 1,
		"team": 0,
		"price": 5750,
		"damage": 35,
		"armor_pen": 0.8,
		"rpm": 600,
		"mag": 100,
		"reserve": 200,
		"reload": 5.6,
		"draw": 1.4,
		"spread": 0.6,
		"move_spread": 3.0,
		"air_spread": 7.0,
		"recoil": 1.8,
		"range": 90.0,
		"falloff": 40.0,
		"min_mult": 0.7,
		"auto": true,
		"penetration": 3,
		"speed_mult": 0.86,
		"award": 300,
		"sound": "lmg",
		"desc": "100 balas de supresion. No hace falta apuntar mucho.",
		"vm": {"len": 0.9, "color": Color(0.15, 0.16, 0.15), "kind": "lmg", "bipod": true},
	},
	"hegrenade":
	{
		"id": "hegrenade",
		"name": "Granada HE",
		"cls": "grenade",
		"slot": 4,
		"team": 0,
		"price": 300,
		"damage": 98,
		"radius": 7.0,
		"rpm": 60,
		"mag": 1,
		"reserve": 1,
		"reload": 0.0,
		"draw": 0.6,
		"speed_mult": 1.02,
		"award": 300,
		"sound": "grenade",
		"desc": "Dano en area, ideal para forzar posiciones.",
		"vm": {"len": 0.16, "color": Color(0.22, 0.28, 0.16), "kind": "grenade"},
	},
	"flashbang":
	{
		"id": "flashbang",
		"name": "Flashbang",
		"cls": "grenade",
		"slot": 4,
		"team": 0,
		"price": 200,
		"damage": 35,
		"radius": 9.0,
		"rpm": 60,
		"mag": 1,
		"reserve": 1,
		"reload": 0.0,
		"draw": 0.6,
		"speed_mult": 1.02,
		"award": 300,
		"sound": "grenade",
		"desc": "Ciega a todo el que mire. Cuidado con tu equipo.",
		"vm": {"len": 0.16, "color": Color(0.32, 0.32, 0.3), "kind": "grenade"},
	},
	"smokegrenade":
	{
		"id": "smokegrenade",
		"name": "Granada de humo",
		"cls": "grenade",
		"slot": 4,
		"team": 0,
		"price": 300,
		"damage": 0,
		"radius": 4.5,
		"rpm": 60,
		"mag": 1,
		"reserve": 1,
		"reload": 0.0,
		"draw": 0.6,
		"speed_mult": 1.02,
		"award": 300,
		"sound": "grenade",
		"desc": "Corta la vision y apaga las llamas de Molotov al contacto.",
		"vm": {"len": 0.16, "color": Color(0.28, 0.3, 0.28), "kind": "grenade"},
	},
	"molotov":
	{
		"id": "molotov",
		"name": "Molotov",
		"cls": "grenade",
		"slot": 4,
		"team": 0,
		"price": 400,
		"damage": 40,
		"radius": 3.8,
		"rpm": 60,
		"mag": 1,
		"reserve": 1,
		"reload": 0.0,
		"draw": 0.62,
		"speed_mult": 1.02,
		"award": 300,
		"sound": "grenade",
		"desc": "Botella incendiaria estilo CS2: propaga fuego en el suelo y se apaga con humo.",
		"vm": {"len": 0.22, "color": Color(0.75, 0.36, 0.08), "kind": "molotov"},
	},
	"c4":
	{
		"id": "c4",
		"name": "C4",
		"cls": "c4",
		"slot": 5,
		"team": 2,
		"price": 0,
		"damage": 500,
		"radius": 22.0,
		"rpm": 60,
		"mag": 1,
		"reserve": 1,
		"reload": 0.0,
		"draw": 0.6,
		"speed_mult": 1.02,
		"award": 0,
		"sound": "c4",
		"desc": "Planta la bomba en el sitio A o B y defiende 40 segundos.",
		"vm": {"len": 0.2, "color": Color(0.35, 0.24, 0.1), "kind": "c4"},
	},
}

const EQUIPMENT := {
	"kevlar": {"id": "kevlar", "name": "Chaleco Kevlar", "price": 650, "desc": "+100 de armadura."},
	"helmet":
	{"id": "helmet", "name": "Casco", "price": 350, "desc": "Reduce el dano en la cabeza."},
	"defusekit":
	{
		"id": "defusekit",
		"name": "Kit de desactivacion",
		"price": 200,
		"desc": "Desactiva el C4 en 5 s."
	},
}

const BUY_MENU := [
	{
		"key": "1",
		"title": "PISTOLAS",
		"items": ["glock18", "usp45", "p228", "deagle", "fiveseven", "elite"],
		"team": 0,
	},
	{"key": "2", "title": "ESCOPETAS", "items": ["m3", "xm1014"], "team": 0},
	{
		"key": "3",
		"title": "SUBFUSILES",
		"items": ["tmp", "mac10", "mp5", "ump45", "p90"],
		"team": 0
	},
	{
		"key": "4",
		"title": "FUSILES",
		"items": ["famas", "galil", "ak47", "m4a1", "sg552", "aug"],
		"team": 0,
	},
	{
		"key": "5",
		"title": "FRANCOTIRADORES",
		"items": ["scout", "awp", "g3sg1", "sg550"],
		"team": 0
	},
	{"key": "6", "title": "AMETRALLADORAS", "items": ["m249"], "team": 0},
	{
		"key": "7",
		"title": "GRANADAS",
		"items": ["molotov", "hegrenade", "flashbang", "smokegrenade"],
		"team": 0
	},
	{"key": "8", "title": "EQUIPAMIENTO", "items": ["kevlar", "helmet", "defusekit"], "team": 0},
]

const GRENADE_LIMITS := {"molotov": 1, "hegrenade": 1, "flashbang": 2, "smokegrenade": 1}

const ZOMBIE_TYPES := {
	"walker":
	{
		"name": "Caminante",
		"hp": 110,
		"speed": 2.1,
		"damage": 18,
		"attack_rate": 1.1,
		"points": 60,
		"scale": 1.0,
		"color": Color(0.42, 0.5, 0.36),
		"armor": 0.0,
	},
	"runner":
	{
		"name": "Corredor",
		"hp": 75,
		"speed": 4.6,
		"damage": 14,
		"attack_rate": 0.85,
		"points": 90,
		"scale": 0.94,
		"color": Color(0.5, 0.42, 0.32),
		"armor": 0.0,
	},
	"brute":
	{
		"name": "Bruto",
		"hp": 480,
		"speed": 1.7,
		"damage": 42,
		"attack_rate": 1.5,
		"points": 220,
		"scale": 1.35,
		"color": Color(0.34, 0.4, 0.3),
		"armor": 0.25,
	},
	"spitter":
	{
		"name": "Escupidor",
		"hp": 140,
		"speed": 2.6,
		"damage": 12,
		"attack_rate": 2.4,
		"points": 150,
		"scale": 1.05,
		"color": Color(0.55, 0.55, 0.28),
		"armor": 0.0,
		"ranged": true,
		"range": 14.0,
	},
	"boss":
	{
		"name": "Devorador",
		"hp": 2800,
		"speed": 2.2,
		"damage": 65,
		"attack_rate": 1.8,
		"points": 1200,
		"scale": 1.9,
		"color": Color(0.3, 0.34, 0.22),
		"armor": 0.35,
		"boss": true,
	},
}

const PERKS := {
	"jugg":
	{
		"name": "Juggernog",
		"desc": "+100 de vida maxima y regeneracion lenta.",
		"color": Color(0.72, 0.2, 0.18),
		"icon": "J",
	},
	"speed":
	{
		"name": "Speed Cola",
		"desc": "Recarga y cambio de arma un 45% mas rapidos.",
		"color": Color(0.25, 0.55, 0.25),
		"icon": "S",
	},
	"double":
	{
		"name": "Double Tap",
		"desc": "Doble de puntos y 15% mas de cadencia.",
		"color": Color(0.85, 0.65, 0.18),
		"icon": "D",
	},
	"revive":
	{
		"name": "Quick Revive",
		"desc": "Revive una vez al morir con 50 de vida.",
		"color": Color(0.22, 0.45, 0.75),
		"icon": "R",
	},
	"mule":
	{
		"name": "Mule Kick",
		"desc": "Municion de reserva infinita para todas las armas.",
		"color": Color(0.5, 0.3, 0.6),
		"icon": "M",
	},
}

## Mapas jugables originales de Counter-Strike 1.5 (.bsp) con texturas PBR realistas.
const MAPS := [
	{
		"id": "de_dust2",
		"name": "de_dust2",
		"bsp": "de_dust2",
		"label": "Dust II",
		"mode": "bomb",
		"theme": "desert",
		"size": "media",
		"ambience": "dust",
		"desc": "El mapa original de CS 1.5: Larga A, Catwalk, tunel B y medio.",
		"tags": ["cs 1.5", "bomb", "equilibrado"],
	},
	{
		"id": "de_inferno",
		"name": "de_inferno",
		"bsp": "de_inferno",
		"label": "Inferno",
		"mode": "bomb",
		"theme": "mediterranean",
		"size": "media",
		"ambience": "dust",
		"desc": "El Inferno original de CS 1.5: banana, apartamentos y balcones.",
		"tags": ["cs 1.5", "bomb", "corto alcance"],
	},
	{
		"id": "de_aztec",
		"name": "de_aztec",
		"bsp": "de_aztec",
		"label": "Aztec",
		"mode": "bomb",
		"theme": "jungle",
		"size": "grande",
		"ambience": "night",
		"desc": "El Aztec original de CS 1.5: puente colgante, puertas dobles y rio.",
		"tags": ["cs 1.5", "bomb", "awp"],
	},
	{
		"id": "de_nuke",
		"name": "de_nuke",
		"bsp": "de_nuke",
		"label": "Nuke",
		"mode": "bomb",
		"theme": "industrial",
		"size": "chica",
		"ambience": "industrial",
		"desc": "Planta nuclear original de CS 1.5: rampa, ductos y sitios superpuestos.",
		"tags": ["cs 1.5", "bomb", "tactico"],
	},
	{
		"id": "de_train",
		"name": "de_train",
		"bsp": "de_train",
		"label": "Train",
		"mode": "bomb",
		"theme": "railyard",
		"size": "media",
		"ambience": "industrial",
		"desc": "Estacion ferroviaria original de CS 1.5: vagones, escaleras y pasarelas.",
		"tags": ["cs 1.5", "bomb", "precision"],
	},
	{
		"id": "de_dust",
		"name": "de_dust",
		"bsp": "de_dust",
		"label": "Dust",
		"mode": "bomb",
		"theme": "desert",
		"size": "chica",
		"ambience": "dust",
		"desc": "El Dust original de CS 1.5: el paso subterraneo y los dos patios.",
		"tags": ["cs 1.5", "clasico", "bomb"],
	},
	{
		"id": "cs_office",
		"name": "cs_office",
		"bsp": "cs_office",
		"label": "Office",
		"mode": "hostage",
		"theme": "office",
		"size": "media",
		"ambience": "industrial",
		"desc": "Complejo nevado original de CS 1.5 con ventanas rompibles y rehenes.",
		"tags": ["cs 1.5", "rehenes", "interior"],
	},
	{
		"id": "cs_italy",
		"name": "cs_italy",
		"bsp": "cs_italy",
		"label": "Italy",
		"mode": "hostage",
		"theme": "italy",
		"size": "media",
		"ambience": "dust",
		"desc": "Pueblo italiano original de CS 1.5: mercado, bodega y callejones.",
		"tags": ["cs 1.5", "rehenes", "urbano"],
	},
	{
		"id": "cs_assault",
		"name": "cs_assault",
		"bsp": "cs_assault",
		"label": "Assault",
		"mode": "hostage",
		"theme": "industrial",
		"size": "chica",
		"ambience": "industrial",
		"desc": "El galpon clasico de CS 1.5 con puente, conductos y rescate de rehenes.",
		"tags": ["cs 1.5", "rehenes", "clasico"],
	},
	{
		"id": "zm_mansion",
		"name": "zm_mansion",
		"bsp": "cs_estate",
		"label": "Estate Mansion",
		"mode": "zombie",
		"theme": "mansion",
		"size": "chica",
		"ambience": "zombie",
		"desc": "La mansion cs_estate original de CS 1.5 de noche contra oleadas zombies.",
		"tags": ["cs 1.5", "zombie", "nocturno"],
	},
	{
		"id": "zm_dust_night",
		"name": "zm_dust_night",
		"bsp": "de_dust",
		"label": "Dust Night",
		"mode": "zombie",
		"theme": "desert_night",
		"size": "media",
		"ambience": "zombie",
		"desc": "El de_dust original de CS 1.5 en plena noche contra la horda sin fin.",
		"tags": ["cs 1.5", "zombie", "abierto"],
	},
]


func get_weapon(id: String) -> Dictionary:
	return WEAPONS.get(id, {})


func is_equipment(id: String) -> bool:
	return EQUIPMENT.has(id)


func item_name(id: String) -> String:
	if WEAPONS.has(id):
		return WEAPONS[id].name
	if EQUIPMENT.has(id):
		return EQUIPMENT[id].name
	if PERKS.has(id):
		return PERKS[id].name
	return id


func item_price(id: String) -> int:
	if WEAPONS.has(id):
		return int(WEAPONS[id].price)
	if EQUIPMENT.has(id):
		return int(EQUIPMENT[id].price)
	if PERKS.has(id):
		return int(PERK_PRICES.get(id, 0))
	return 0


func can_buy(id: String, team: int, money: int) -> bool:
	var w := get_weapon(id)
	if w.is_empty():
		return money >= item_price(id)
	var wteam: int = w.get("team", 0)
	if wteam != 0 and wteam != team:
		return false
	return money >= int(w.price)


func weapons_for_team(team: int, slot: int = -1) -> Array:
	var out: Array = []
	for id in WEAPONS.keys():
		var w: Dictionary = WEAPONS[id]
		if int(w.team) != 0 and int(w.team) != team:
			continue
		if slot >= 0 and int(w.slot) != slot:
			continue
		out.append(id)
	return out


func buy_menu_for_team(team: int) -> Array:
	var out: Array = []
	for cat in BUY_MENU:
		var items: Array = []
		for id in cat.items:
			if id == "defusekit" and team != TEAM_CT:
				continue
			var w := get_weapon(id)
			if not w.is_empty() and int(w.team) != 0 and int(w.team) != team:
				continue
			items.append(id)
		out.append({"key": cat.key, "title": cat.title, "items": items})
	return out


func map_by_id(id: String) -> Dictionary:
	for m in MAPS:
		if m.id == id:
			return m
	return {}


func maps_for_mode(mode: String) -> Array:
	var out: Array = []
	for m in MAPS:
		if mode == "deathmatch":
			if m.mode == "bomb" or m.mode == "hostage":
				out.append(m)
		elif m.mode == mode:
			out.append(m)
	return out


func zombie_type(id: String) -> Dictionary:
	return ZOMBIE_TYPES.get(id, ZOMBIE_TYPES.walker)


func difficulty(index: int) -> Dictionary:
	return DIFFICULTY[clampi(index, 0, DIFFICULTY.size() - 1)]


func rank_for_kills(kills: int) -> String:
	var rank := String(RANKS[0][1])
	for entry in RANKS:
		if kills >= int(entry[0]):
			rank = entry[1]
	return rank


func random_bot_names(count: int, avoid: Array = []) -> Array:
	var pool: Array = []
	for n in BOT_NAMES:
		if not avoid.has(n):
			pool.append(n)
	pool.shuffle()
	return pool.slice(0, mini(count, pool.size()))


## Escala de una oleada zombie.
func wave_config(wave: int) -> Dictionary:
	var w := maxi(1, wave)
	var count := mini(10 + w * 4, 70)
	var hp := 1.0 + float(w - 1) * 0.13
	var speed := 1.0 + minf(float(w - 1) * 0.018, 0.4)
	var special := clampf(0.08 + float(w) * 0.035, 0.0, 0.55)
	return {
		"count": count,
		"hp_mult": hp,
		"speed_mult": speed,
		"special_chance": special,
		"spawn_interval": maxf(0.35, 1.6 - float(w) * 0.07),
		"boss": w % 5 == 0,
		"max_alive": mini(12 + w * 2, 36),
	}


## Elige el tipo de zombie de una oleada respetando la dificultad progresiva.
func pick_zombie_type(wave: int, rng: RandomNumberGenerator) -> String:
	var special: float = wave_config(wave).special_chance
	var r := rng.randf()
	if wave >= 4 and r < special * 0.35:
		return "spitter"
	if wave >= 3 and r < special * 0.7:
		return "brute"
	if wave >= 2 and r < special:
		return "runner"
	return "walker"


func weapons_for_mystery_box() -> Array:
	return [
		"ak47",
		"m4a1",
		"awp",
		"deagle",
		"mp5",
		"p90",
		"m249",
		"xm1014",
		"sg552",
		"aug",
		"scout",
		"galil",
		"famas",
		"g3sg1",
		"sg550",
	]
