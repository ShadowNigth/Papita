extends RefCounted
## Registro central de acciones de entrada.
## Las acciones se crean en tiempo de ejecucion para poder reasignar teclas
## y guardarlas en user://settings.cfg sin tocar project.godot.

class_name InputSetup

const DEFAULT_KEYS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump": KEY_SPACE,
	"crouch": KEY_CTRL,
	"walk": KEY_SHIFT,
	"reload": KEY_R,
	"use": KEY_E,
	"buy": KEY_B,
	"drop": KEY_G,
	"last_weapon": KEY_Q,
	"slot1": KEY_1,
	"slot2": KEY_2,
	"slot3": KEY_3,
	"slot4": KEY_4,
	"slot5": KEY_5,
	"flashlight": KEY_F,
	"inspect": KEY_I,
	"scoreboard": KEY_TAB,
	"pause": KEY_ESCAPE,
	"console": KEY_QUOTELEFT,
	"toggle_help": KEY_F1,
}

## Acciones que usan botones del raton.
const DEFAULT_MOUSE := {
	"fire": MOUSE_BUTTON_LEFT,
	"alt_fire": MOUSE_BUTTON_RIGHT,
	"next_weapon": MOUSE_BUTTON_WHEEL_DOWN,
	"prev_weapon": MOUSE_BUTTON_WHEEL_UP,
}

## Acciones sin entrada asignable por el usuario.
const FIXED_MOUSE := {
	"fire": MOUSE_BUTTON_LEFT,
	"alt_fire": MOUSE_BUTTON_RIGHT,
	"next_weapon": MOUSE_BUTTON_WHEEL_DOWN,
	"prev_weapon": MOUSE_BUTTON_WHEEL_UP,
}

const LABELS := {
	"move_forward": "Avanzar",
	"move_back": "Retroceder",
	"move_left": "Izquierda",
	"move_right": "Derecha",
	"jump": "Saltar",
	"crouch": "Agacharse",
	"walk": "Caminar",
	"reload": "Recargar",
	"use": "Usar / Desactivar",
	"buy": "Menu de compra",
	"drop": "Soltar arma",
	"last_weapon": "Arma anterior",
	"slot1": "Arma primaria",
	"slot2": "Arma secundaria",
	"slot3": "Cuchillo",
	"slot4": "Granada",
	"slot5": "C4",
	"flashlight": "Linterna",
	"inspect": "Inspeccionar arma",
	"scoreboard": "Marcador",
	"pause": "Pausa",
	"console": "Consola",
	"toggle_help": "Ayuda",
}


static func ensure_actions() -> void:
	for action in DEFAULT_KEYS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	for action in DEFAULT_MOUSE.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	# Las acciones fijas se limpian y recrean para evitar duplicados.
	for action in DEFAULT_MOUSE.keys():
		InputMap.action_erase_events(action)
		var ev := InputEventMouseButton.new()
		ev.button_index = DEFAULT_MOUSE[action]
		InputMap.action_add_event(action, ev)


static func apply_bindings(bindings: Dictionary) -> void:
	ensure_actions()
	for action in DEFAULT_KEYS.keys():
		InputMap.action_erase_events(action)
		var key: int = int(bindings.get(action, DEFAULT_KEYS[action]))
		if key == 0:
			key = DEFAULT_KEYS[action]
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


static func default_bindings() -> Dictionary:
	var out := {}
	for action in DEFAULT_KEYS.keys():
		out[action] = DEFAULT_KEYS[action]
	return out


static func key_name(action: String, bindings: Dictionary) -> String:
	var code: int = int(bindings.get(action, DEFAULT_KEYS.get(action, 0)))
	if code == 0:
		return "-"
	return OS.get_keycode_string(code)


static func rebindable_actions() -> Array:
	return DEFAULT_KEYS.keys()
