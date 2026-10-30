extends Node
## AudioBank: cache de audio sintetizado + reproductores 2D/3D/UI.
##
## El banco de efectos se construye en un hilo aparte para no congelar el
## menu. La musica y los ambientes se sintetizan de forma diferida y tambien
## en segundo plano.

const ESSENTIAL := [
	"draw",
	"reload_out",
	"reload_in",
	"reload_bolt",
	"pump",
	"empty",
	"knife_swing",
	"knife_hit",
	"flesh_hit",
	"headshot",
	"wall_hit",
	"ricochet",
	"whiz",
	"shell",
	"jump",
	"land",
	"explosion",
	"grenade_bounce",
	"grenade_throw",
	"flashbang",
	"smoke",
	"beep",
	"plant",
	"defuse",
	"body_fall",
	"death_cry",
	"zombie_attack",
	"zombie_death",
	"zombie_spawn",
	"wave_start",
	"perk",
	"ui_click",
	"ui_hover",
	"buy",
	"error",
	"hitmarker",
	"round_start",
	"win_good",
	"win_bad",
	"money",
	"radio",
	"flash_ring",
]

const FIRE_FAMILIES := [
	"pistol", "pistol_heavy", "smg", "rifle", "rifle_heavy", "sniper", "shotgun", "lmg"
]
const MAX_3D := 48

var _cache: Dictionary = {}
var _generating: Dictionary = {}
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_index := 0
var _active_3d := 0
var _ambience_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _ambience_name := ""
var _music_name := ""
var _music_wanted := ""
var _music_fade := 2.5
var _rng := RandomNumberGenerator.new()
var _bank_thread: Thread
var _bank_busy := false
var _bg_thread: Thread
var _bg_key := ""
var _bg_kind := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_setup_players()
	_start_bank_build()


func _setup_players() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_ui_players.append(p)
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.bus = "SFX"
	_ambience_player.volume_db = -60.0
	add_child(_ambience_player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.volume_db = -60.0
	add_child(_music_player)


func _start_bank_build() -> void:
	_bank_busy = true
	_bank_thread = Thread.new()
	_bank_thread.start(_build_bank_worker)


## Se ejecuta en un hilo: devuelve un diccionario nuevo con los streams.
func _build_bank_worker() -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var bank := {}
	for name in ESSENTIAL:
		var s := _generate(name)
		if s:
			bank[name] = s
	for family in FIRE_FAMILIES:
		for v in 2:
			var key := "fire_%s_%d" % [family, v]
			var s2 := _generate(key)
			if s2:
				bank[key] = s2
	for i in 4:
		var key := "footstep_%d" % i
		var s3 := _generate(key)
		if s3:
			bank[key] = s3
	for i in 3:
		var key := "growl_%d" % i
		var s4 := _generate(key)
		if s4:
			bank[key] = s4
	print(
		"[AudioBank] %d efectos sintetizados en %d ms" % [bank.size(), Time.get_ticks_msec() - t0]
	)
	return bank


func _process(_delta: float) -> void:
	if _bank_thread != null and not _bank_thread.is_alive():
		var bank: Dictionary = _bank_thread.wait_to_finish()
		_bank_thread = null
		_bank_busy = false
		if bank is Dictionary:
			for key in bank.keys():
				_cache[key] = bank[key]
		_try_start_music()
	if _bg_thread != null and not _bg_thread.is_alive():
		var result = _bg_thread.wait_to_finish()
		_bg_thread = null
		var key := _bg_key
		var kind := _bg_kind
		_bg_key = ""
		_bg_kind = ""
		if result is AudioStreamWAV:
			_cache[key] = result
			if kind == "music" and _music_wanted == key:
				_play_music_stream(key)
			elif kind == "ambience" and _ambience_name == key.substr(4):
				_play_ambience_stream(key)
	if _music_wanted != "" and _bg_thread == null:
		if _cache.has(_music_wanted):
			_play_music_stream(_music_wanted)
		else:
			_request_stream(_music_wanted, "music")


func _try_start_music() -> void:
	if _music_wanted != "":
		if _cache.has(_music_wanted):
			_play_music_stream(_music_wanted)
		elif _bg_thread == null:
			_request_stream(_music_wanted, "music")


func _request_stream(name: String, kind: String) -> void:
	if _bg_thread != null:
		return
	_bg_key = name
	_bg_kind = kind
	_bg_thread = Thread.new()
	_bg_thread.start(_generate.bind(name))


## Devuelve (y sintetiza si hace falta) un AudioStreamWAV por nombre.
func stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	if _generating.has(name):
		return null
	_generating[name] = true
	var s: AudioStreamWAV = _generate(name)
	_generating.erase(name)
	if s:
		_cache[name] = s
	return s


func _generate(name: String) -> AudioStreamWAV:
	if name.begins_with("fire_"):
		var parts := name.split("_")
		var variant := int(parts[-1])
		var family := "_".join(parts.slice(1, parts.size() - 1))
		if family == "shotgun":
			return Synth.shotgun_fire(variant)
		if family == "silenced":
			return Synth.silent_shot()
		return Synth.weapon_fire(family, variant)
	if name.begins_with("footstep_"):
		return Synth.footstep(int(name.get_slice("_", 1)))
	if name.begins_with("growl_"):
		return Synth.zombie_growl(int(name.get_slice("_", 1)))
	if name.begins_with("amb_"):
		return Synth.ambience(name.substr(4))
	if name == "menu_music":
		return Synth.menu_music()
	if name == "zombie_music":
		return Synth.zombie_music()
	match name:
		"draw":
			return Synth.draw_weapon()
		"reload_out":
			return Synth.reload_mag_out()
		"reload_in":
			return Synth.reload_mag_in()
		"reload_bolt":
			return Synth.reload_bolt()
		"pump":
			return Synth.pump_shotgun()
		"empty":
			return Synth.empty_click()
		"knife_swing":
			return Synth.knife_swing()
		"knife_hit":
			return Synth.knife_hit()
		"flesh_hit":
			return Synth.flesh_hit()
		"headshot":
			return Synth.headshot_ding()
		"wall_hit":
			return Synth.wall_hit()
		"ricochet":
			return Synth.ricochet()
		"whiz":
			return Synth.bullet_whiz()
		"shell":
			return Synth.shell_drop()
		"jump":
			return Synth.jump()
		"land":
			return Synth.land()
		"explosion":
			return Synth.explosion()
		"grenade_bounce":
			return Synth.grenade_bounce()
		"grenade_throw":
			return Synth.grenade_throw()
		"flashbang":
			return Synth.flashbang()
		"flash_ring":
			return Synth.flash_ring()
		"smoke":
			return Synth.smoke_pop()
		"beep":
			return Synth.bomb_beep()
		"plant":
			return Synth.bomb_plant()
		"defuse":
			return Synth.defuse()
		"body_fall":
			return Synth.body_fall()
		"death_cry":
			return Synth.death_cry()
		"zombie_attack":
			return Synth.zombie_attack()
		"zombie_death":
			return Synth.zombie_death()
		"zombie_spawn":
			return Synth.zombie_spawn()
		"wave_start":
			return Synth.wave_start()
		"perk":
			return Synth.perk()
		"ui_click":
			return Synth.ui_click()
		"ui_hover":
			return Synth.ui_hover()
		"buy":
			return Synth.buy()
		"error":
			return Synth.error()
		"hitmarker":
			return Synth.hitmarker()
		"round_start":
			return Synth.round_start()
		"win_good":
			return Synth.round_win(true)
		"win_bad":
			return Synth.round_win(false)
		"money":
			return Synth.money()
		"radio":
			return Synth.radio_beep()
	push_warning("[AudioBank] sonido desconocido: %s" % name)
	return null


# --- Reproduccion --------------------------------------------------------------


func play_ui(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := stream(name)
	if s == null:
		return
	var p := _ui_players[_ui_index]
	_ui_index = (_ui_index + 1) % _ui_players.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch, 0.3, 3.0)
	p.play()


func play_2d(name: String, volume_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX") -> void:
	var s := stream(name)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch, 0.3, 3.0)
	p.bus = bus
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Sonido posicional. Se cuelga de `parent` para liberarse con la escena.
func play_at(
	name: String,
	parent: Node,
	position: Vector3,
	volume_db: float = 0.0,
	pitch: float = 1.0,
	max_distance: float = 90.0
) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var s := stream(name)
	if s == null:
		return
	if _active_3d > MAX_3D:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.unit_size = 12.0
	p.max_db = 12.0
	p.max_distance = max_distance
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch, 0.3, 3.0)
	p.bus = "SFX"
	p.position = position
	parent.add_child(p)
	_active_3d += 1
	p.tree_exited.connect(func() -> void: _active_3d = maxi(0, _active_3d - 1))
	p.finished.connect(p.queue_free)
	p.play()


func weapon_fire(family: String, parent: Node, pos: Vector3, max_distance: float = 90.0) -> void:
	var variant := _rng.randi_range(0, 1)
	var pitch := _rng.randf_range(0.96, 1.05)
	var key := "fire_%s_%d" % [family, variant]
	if not _cache.has(key):
		key = "fire_%s_0" % family
	play_at(key, parent, pos, -2.0, pitch, max_distance)


func footstep(parent: Node, pos: Vector3, surface_loud: bool = false) -> void:
	var variant := _rng.randi_range(0, 3)
	var db := 2.0 if surface_loud else -4.0
	play_at("footstep_%d" % variant, parent, pos, db, _rng.randf_range(0.9, 1.1), 28.0)


func random_pitch(center: float = 1.0, spread: float = 0.06) -> float:
	return center + _rng.randf_range(-spread, spread)


# --- Ambiente y musica ---------------------------------------------------------


func set_ambience(kind: String, fade: float = 2.0) -> void:
	if kind == _ambience_name:
		return
	_ambience_name = kind
	var key := "amb_" + kind
	if kind == "":
		var tw := create_tween()
		tw.tween_property(_ambience_player, "volume_db", -60.0, fade)
		tw.tween_callback(_ambience_player.stop)
		return
	if _cache.has(key):
		_play_ambience_stream(key)
	elif _bg_thread == null:
		_request_stream(key, "ambience")


func _play_ambience_stream(key: String) -> void:
	_ambience_player.stream = _cache[key]
	_ambience_player.volume_db = -40.0
	_ambience_player.play()
	var tw := create_tween()
	tw.tween_property(_ambience_player, "volume_db", -14.0, 2.0)


func set_music(kind: String, fade: float = 2.5) -> void:
	_music_fade = fade
	if kind == _music_name and kind != "":
		return
	_music_name = kind
	_music_wanted = kind
	if kind == "":
		var tw := create_tween()
		tw.tween_property(_music_player, "volume_db", -60.0, fade)
		tw.tween_callback(_music_player.stop)
		return
	if _cache.has(kind):
		_play_music_stream(kind)
	elif _bg_thread == null:
		_request_stream(kind, "music")


func _play_music_stream(key: String) -> void:
	if _music_player.stream == _cache[key] and _music_player.playing:
		return
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", -45.0, _music_fade * 0.4)
	tw.tween_callback(
		func() -> void:
			_music_player.stream = _cache[key]
			_music_player.play()
	)
	tw.tween_property(_music_player, "volume_db", -10.0, _music_fade)


func stop_all() -> void:
	_ambience_name = ""
	_music_name = ""
	_music_wanted = ""
	_ambience_player.stop()
	_music_player.stop()


func _exit_tree() -> void:
	if _bank_thread != null and _bank_thread.is_alive():
		_bank_thread.wait_to_finish()
	if _bg_thread != null and _bg_thread.is_alive():
		_bg_thread.wait_to_finish()
