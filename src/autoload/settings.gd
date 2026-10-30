extends Node
## Settings: ajustes persistentes (video, audio, controles, juego, perfil, progreso).
##
## Todo se guarda en user://settings.cfg. Los cambios emiten `settings_changed`
## para que el mundo/HUD reaccionen en caliente.

signal settings_changed(section: String)
signal progress_changed

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"video":
	{
		"mode": 0,  # 0 ventana, 1 pantalla completa, 2 sin bordes
		"width": 1600,
		"height": 900,
		"msaa": 2,
		"ssao": true,
		"ssil": true,
		"glow": true,
		"vol_fog": true,
		"shadows": 1,
		"brightness": 1.0,
		"fov": 90.0,
		"view_fov": 60.0,
		"vsync": true,
		"motion_blur": 0.0,
		"film_grain": 0.35,
	},
	"audio":
	{
		"master": 0.85,
		"sfx": 1.0,
		"music": 0.55,
		"ui": 0.8,
		"voice": 0.9,
		"mute": false,
	},
	"gameplay":
	{
		"sensitivity": 1.6,
		"invert_y": false,
		"difficulty": 2,
		"bots": 7,
		"zombies": 16,
		"friendly_fire": false,
		"round_time": 300,
		"buy_time": 45,
		"respawn": false,
		"crosshair_color": "4ade80",
		"crosshair_dynamic": true,
		"hud_scale": 1.0,
		"hitmarker": true,
		"headshot_sound": true,
		"blood": 1.0,
		"auto_reload": false,
		"show_fps": false,
		"language": "es",
		"viewmodel_sway": 1.0,
		"bob": 1.0,
		"start_money": 800,
	},
	"controls": {},
	"profile":
	{
		"name": "Papita",
		"avatar": "ct",
		"loadout_prime": "ak47",
		"loadout_secondary": "deagle",
	},
	"progress":
	{
		"kills": 0,
		"headshots": 0,
		"matches": 0,
		"wins": 0,
		"zombie_best_wave": 0,
		"zombie_kills": 0,
		"accuracy_shots": 0,
		"accuracy_hits": 0,
		"play_time": 0.0,
		"unlocked": [],
		"achievements": [],
	},
}

var data: Dictionary = {}

var _save_timer := 0.0
var _loaded := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	load_settings()
	apply_all()
	# Ajusta el nivel del mapa cuando el jugador cambia de escena.
	get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	if _save_timer > 0.0:
		_save_timer -= delta
		if _save_timer <= 0.0:
			flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		flush()


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment and node.environment != null:
		apply_environment(node.environment)


# --- API publica ---------------------------------------------------------------


func get_value(section: String, key: String, fallback: Variant = null) -> Variant:
	if data.has(section) and data[section].has(key):
		return data[section][key]
	return fallback


func set_value(section: String, key: String, value: Variant) -> void:
	if not data.has(section):
		data[section] = {}
	if data[section].get(key) == value:
		return
	data[section][key] = value
	_apply_section(section)
	settings_changed.emit(section)
	queue_save()


func reset_section(section: String) -> void:
	if DEFAULTS.has(section):
		data[section] = DEFAULTS[section].duplicate(true)
	_apply_section(section)
	settings_changed.emit(section)
	queue_save()


func add_progress(key: String, amount: float = 1.0) -> void:
	var current: float = float(data.progress.get(key, 0))
	data.progress[key] = current + amount
	progress_changed.emit()
	queue_save()


func unlock_weapon(id: String) -> void:
	var unlocked: Array = data.progress.get("unlocked", [])
	if not unlocked.has(id):
		unlocked.append(id)
		data.progress.unlocked = unlocked
		progress_changed.emit()
		queue_save()


func is_weapon_unlocked(id: String) -> bool:
	var unlocked: Array = data.progress.get("unlocked", [])
	return unlocked.has(id)


func grant_achievement(id: String) -> bool:
	var list: Array = data.progress.get("achievements", [])
	if list.has(id):
		return false
	list.append(id)
	data.progress.achievements = list
	progress_changed.emit()
	queue_save()
	return true


func save_settings() -> void:
	flush()


func flush() -> void:
	_save_timer = 0.0
	if not _loaded:
		return
	var cfg := ConfigFile.new()
	for section in data.keys():
		for key in data[section].keys():
			cfg.set_value(section, key, data[section][key])
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("No se pudo guardar la configuracion: %s" % err)


func queue_save() -> void:
	_save_timer = 0.8


func load_settings() -> void:
	data = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for section in cfg.get_sections():
			if not data.has(section):
				data[section] = {}
			for key in cfg.get_section_keys(section):
				if section == "controls":
					data.controls[key] = int(cfg.get_value(section, key))
				elif data.get(section, {}).has(key):
					data[section][key] = cfg.get_value(section, key)
	# Normaliza secciones que crecieron en versiones nuevas.
	for section in DEFAULTS.keys():
		for key in DEFAULTS[section].keys():
			if not data[section].has(key):
				data[section][key] = DEFAULTS[section][key]
	_loaded = true


func apply_all() -> void:
	for section in data.keys():
		_apply_section(section)
	settings_changed.emit("all")


func apply_controls() -> void:
	var bindings := {}
	for action in InputSetup.DEFAULT_KEYS.keys():
		bindings[action] = data.controls.get(action, InputSetup.DEFAULT_KEYS[action])
	InputSetup.apply_bindings(bindings)


# --- Aplicacion tecnica --------------------------------------------------------


func _apply_section(section: String) -> void:
	match section:
		"video":
			_apply_video()
		"audio":
			_apply_audio()
		"controls":
			apply_controls()
		"gameplay":
			_apply_gameplay()
		"profile", "progress", "all":
			pass


func _apply_video() -> void:
	var mode := int(data.video.get("mode", 0))
	match mode:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(Vector2i(int(data.video.width), int(data.video.height)))
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(DisplayServer.screen_get_size())
	if mode != 2:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_vsync_mode(
		(
			DisplayServer.VSYNC_ENABLED
			if data.video.get("vsync", true)
			else DisplayServer.VSYNC_DISABLED
		)
	)
	# Recentra si es ventana pequena.
	if mode == 0:
		var size := Vector2i(int(data.video.width), int(data.video.height))
		var screen := DisplayServer.screen_get_size()
		if size.x < screen.x and size.y < screen.y:
			DisplayServer.window_set_position((screen - size) / 2)


func _apply_audio() -> void:
	var mute: bool = data.audio.get("mute", false)
	AudioServer.set_bus_mute(0, mute)
	_set_bus_volume("Master", data.audio.get("master", 0.85))
	_set_bus_volume("SFX", data.audio.get("sfx", 1.0))
	_set_bus_volume("Music", data.audio.get("music", 0.55))
	_set_bus_volume("UI", data.audio.get("ui", 0.8))
	_set_bus_volume("Voice", data.audio.get("voice", 0.9))


func _apply_gameplay() -> void:
	Engine.time_scale = 1.0
	TranslationServer.set_locale("es" if data.gameplay.get("language", "es") == "es" else "en")


func _setup_buses() -> void:
	for bus_name in ["SFX", "Music", "UI", "Voice"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))


## Aplica el perfil de calidad del usuario a un Environment ya creado.
func apply_environment(env: Environment) -> void:
	if env == null:
		return
	var ssao: bool = data.video.get("ssao", true)
	var ssil: bool = data.video.get("ssil", true)
	var glow: bool = data.video.get("glow", true)
	var fog: bool = data.video.get("vol_fog", true)
	env.ssao_enabled = ssao
	env.ssil_enabled = ssil
	env.glow_enabled = glow
	env.volumetric_fog_enabled = fog
	env.fog_enabled = false
	env.tonemap_exposure = float(data.video.get("brightness", 1.0))
	env.adjustment_enabled = true
	env.adjustment_brightness = float(data.video.get("brightness", 1.0))
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.06
	var viewport := get_viewport()
	if viewport:
		var scale: int = int(data.video.get("msaa", 2))
		viewport.msaa_3d = scale
		viewport.screen_space_aa = (
			Viewport.SCREEN_SPACE_AA_FXAA if scale >= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
		)
	var shadows: int = int(data.video.get("shadows", 1))
	var sizes := [2048, 4096, 8192]
	if env.ssao_enabled:
		env.ssao_radius = 1.6
		env.ssao_intensity = 2.4
		env.ssao_power = 1.6
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_albedo = Color(0.82, 0.86, 0.78)
		env.volumetric_fog_length = 80.0
		env.volumetric_fog_detail_spread = 1.6
	RenderingServer.directional_shadow_atlas_set_size(sizes[clampi(shadows, 0, 2)], true)


## Volcado legible para la consola / pantalla de opciones.
func describe(section: String) -> Array:
	var lines: Array = []
	if not data.has(section):
		return lines
	for key in data[section].keys():
		lines.append("%s.%s = %s" % [section, key, str(data[section][key])])
	return lines
