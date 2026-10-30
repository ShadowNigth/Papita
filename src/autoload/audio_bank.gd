extends Node
## AudioBank: cargador y cache de sonidos originales de Counter-Strike 1.5 (.wav)
## + reproductores 2D/3D/UI. La musica del menu y del modo zombie permanece
## 100 % procedural (Synth), sin incluir musica original de CS.

const CS15_DIR := "res://assets/sounds/cs15/"
const MAX_3D := 48

## Pools de variantes .wav originales de Counter-Strike 1.5 / Half-Life 1.
const SOUND_POOLS := {
	"draw": ["common/wpn_select.wav", "weapons/slideback1.wav"],
	"pickup": ["items/gunpickup2.wav"],
	"ammo": ["items/9mmclip1.wav", "items/ammopickup2.wav"],
	"kevlar": ["items/kevlar.wav"],
	"flashlight": ["items/flashlight1.wav"],
	"zoom": ["weapons/zoom.wav"],
	"weapon_drop": ["items/weapondrop1.wav"],
	"reload_out": ["weapons/clipout1.wav"],
	"reload_in": ["weapons/clipin1.wav"],
	"reload_bolt": ["weapons/boltpull1.wav", "weapons/sliderelease1.wav"],
	"pump": ["weapons/m3_pump.wav"],
	"empty": ["weapons/dryfire_rifle.wav"],
	"empty_pistol": ["weapons/dryfire_pistol.wav"],
	"knife_deploy": ["weapons/knife_deploy1.wav"],
	"knife_swing": ["weapons/knife_slash1.wav", "weapons/knife_slash2.wav"],
	"knife_hit":
	[
		"weapons/knife_hit1.wav",
		"weapons/knife_hit2.wav",
		"weapons/knife_hit3.wav",
		"weapons/knife_hit4.wav",
	],
	"knife_stab": ["weapons/knife_stab.wav"],
	"knife_wall": ["weapons/knife_hitwall1.wav"],
	"flesh_hit": ["player/bhit_flesh-1.wav", "player/bhit_flesh-2.wav", "player/bhit_flesh-3.wav"],
	"kevlar_hit": ["player/bhit_kevlar-1.wav"],
	"helmet_hit": ["player/bhit_helmet-1.wav"],
	"headshot": ["player/headshot1.wav", "player/headshot2.wav", "player/headshot3.wav"],
	"wall_hit":
	[
		"weapons/ric_conc-1.wav",
		"weapons/ric_conc-2.wav",
		"weapons/bullet_hit1.wav",
		"weapons/bullet_hit2.wav",
	],
	"ricochet":
	[
		"weapons/ric1.wav",
		"weapons/ric2.wav",
		"weapons/ric3.wav",
		"weapons/ric4.wav",
		"weapons/ric5.wav",
		"weapons/ric_metal-1.wav",
		"weapons/ric_metal-2.wav",
	],
	"whiz": ["weapons/ric1.wav", "weapons/ric2.wav", "weapons/ric4.wav"],
	"shell": ["player/pl_shell1.wav", "player/pl_shell2.wav", "player/pl_shell3.wav"],
	"jump": ["player/pl_jump1.wav", "player/pl_jump2.wav"],
	"land": ["player/pl_jumpland2.wav"],
	"fall_pain": ["player/pl_fallpain1.wav", "player/pl_fallpain2.wav", "player/pl_fallpain3.wav"],
	"pain":
	[
		"player/pl_pain2.wav",
		"player/pl_pain4.wav",
		"player/pl_pain5.wav",
		"player/pl_pain6.wav",
		"player/pl_pain7.wav",
	],
	"explosion":
	[
		"weapons/hegrenade-1.wav",
		"weapons/hegrenade-2.wav",
		"weapons/explode3.wav",
		"weapons/explode4.wav",
		"weapons/explode5.wav",
	],
	"c4_explode": ["weapons/c4_explode1.wav"],
	"grenade_bounce":
	[
		"weapons/grenade_hit1.wav",
		"weapons/grenade_hit2.wav",
		"weapons/grenade_hit3.wav",
	],
	"he_bounce": ["weapons/he_bounce-1.wav"],
	"grenade_throw": ["weapons/pinpull.wav"],
	"fire_in_hole": ["radio/ct_fireinhole.wav"],
	"flashbang": ["weapons/flashbang-1.wav", "weapons/flashbang-2.wav"],
	"smoke": ["weapons/sg_explode.wav"],
	"beep": ["weapons/c4_beep1.wav"],
	"plant": ["weapons/c4_plant.wav"],
	"bomb_planted_voice": ["radio/bombpl.wav"],
	"defuse_start": ["weapons/c4_disarm.wav"],
	"defuse": ["weapons/c4_disarmed.wav"],
	"bomb_defused_voice": ["radio/bombdef.wav"],
	"body_fall":
	[
		"common/bodydrop1.wav",
		"common/bodydrop2.wav",
		"common/bodydrop3.wav",
		"common/bodydrop4.wav",
	],
	"death_cry":
	[
		"player/die1.wav",
		"player/die2.wav",
		"player/die3.wav",
		"player/death6.wav",
		"player/pl_die1.wav",
	],
	"zombie_attack":
	[
		"zombie/zo_attack1.wav",
		"zombie/zo_attack2.wav",
		"zombie/claw_strike1.wav",
		"zombie/claw_strike2.wav",
		"zombie/claw_strike3.wav",
	],
	"zombie_death": ["zombie/zo_pain1.wav", "zombie/zo_pain2.wav"],
	"zombie_spawn": ["zombie/zo_alert10.wav", "zombie/zo_alert20.wav", "zombie/zo_alert30.wav"],
	"wave_start": ["ambience/wolfhowl01.wav", "zombie/zo_alert20.wav"],
	"perk": ["items/suitchargeok1.wav", "items/medshot4.wav"],
	"ui_click": ["ui/launch_select1.wav", "ui/launch_select2.wav"],
	"ui_hover": ["ui/launch_glow1.wav"],
	"buy": ["items/gunpickup2.wav"],
	"error": ["common/wpn_denyselect.wav", "ui/launch_deny1.wav"],
	"hitmarker": ["common/wpn_moveselect.wav"],
	"round_start": ["radio/letsgo.wav", "radio/locknload.wav", "radio/moveout.wav", "radio/go.wav"],
	"ct_win": ["radio/ctwin.wav"],
	"t_win": ["radio/terwin.wav"],
	"round_draw": ["radio/rounddraw.wav"],
	"win_good": ["radio/ctwin.wav"],
	"win_bad": ["radio/terwin.wav"],
	"money": ["items/9mmclip1.wav"],
	"radio": ["radio/roger.wav", "radio/ct_affirm.wav", "radio/enemydown.wav", "radio/clear.wav"],
	"hostage_use":
	[
		"hostage/hos1.wav",
		"hostage/hos2.wav",
		"hostage/hos3.wav",
		"hostage/hos4.wav",
		"hostage/hos5.wav",
	],
	"hostage_rescued": ["radio/rescued.wav"],
	"hostage_pain": ["radio/hosdown.wav"],
	"footstep_default":
	[
		"player/pl_step1.wav",
		"player/pl_step2.wav",
		"player/pl_step3.wav",
		"player/pl_step4.wav",
	],
	"footstep_dirt":
	[
		"player/pl_dirt1.wav",
		"player/pl_dirt2.wav",
		"player/pl_dirt3.wav",
		"player/pl_dirt4.wav",
	],
	"footstep_metal":
	[
		"player/pl_metal1.wav",
		"player/pl_metal2.wav",
		"player/pl_metal3.wav",
		"player/pl_metal4.wav",
	],
	"footstep_tile":
	[
		"player/pl_tile1.wav",
		"player/pl_tile2.wav",
		"player/pl_tile3.wav",
		"player/pl_tile4.wav",
		"player/pl_tile5.wav",
	],
	"growl":
	[
		"zombie/zo_idle1.wav",
		"zombie/zo_idle2.wav",
		"zombie/zo_idle3.wav",
		"zombie/zo_idle4.wav",
	],
}

const C4_BEEPS: Array[String] = [
	"weapons/c4_beep1.wav",
	"weapons/c4_beep2.wav",
	"weapons/c4_beep3.wav",
	"weapons/c4_beep4.wav",
	"weapons/c4_beep5.wav",
]

## Disparos individuales originales por arma de Counter-Strike 1.5.
const WEAPON_FIRE_WAVS := {
	"glock18": ["weapons/glock18-1.wav", "weapons/glock18-2.wav"],
	"usp45": ["weapons/usp_unsil-1.wav"],
	"usp45_sil": ["weapons/usp1.wav", "weapons/usp2.wav"],
	"p228": ["weapons/p228-1.wav"],
	"deagle": ["weapons/deagle-1.wav", "weapons/deagle-2.wav"],
	"fiveseven": ["weapons/fiveseven-1.wav"],
	"elite": ["weapons/elite_fire.wav"],
	"m3": ["weapons/m3-1.wav"],
	"xm1014": ["weapons/xm1014-1.wav"],
	"tmp": ["weapons/tmp-1.wav", "weapons/tmp-2.wav"],
	"mac10": ["weapons/mac10-1.wav"],
	"mp5": ["weapons/mp5-1.wav", "weapons/mp5-2.wav"],
	"ump45": ["weapons/ump45-1.wav"],
	"p90": ["weapons/p90-1.wav"],
	"famas": ["weapons/aug-1.wav"],
	"galil": ["weapons/ak47-1.wav", "weapons/ak47-2.wav"],
	"ak47": ["weapons/ak47-1.wav", "weapons/ak47-2.wav"],
	"m4a1": ["weapons/m4a1_unsil-1.wav", "weapons/m4a1_unsil-2.wav"],
	"m4a1_sil": ["weapons/m4a1-1.wav"],
	"sg552": ["weapons/sg552-1.wav", "weapons/sg552-2.wav"],
	"aug": ["weapons/aug-1.wav"],
	"scout": ["weapons/scout_fire-1.wav"],
	"awp": ["weapons/awp1.wav"],
	"g3sg1": ["weapons/g3sg1-1.wav"],
	"sg550": ["weapons/sg550-1.wav"],
	"m249": ["weapons/m249-1.wav", "weapons/m249-2.wav"],
}

## Recargas y cerrojos originales por arma (out, in, bolt, deploy).
const WEAPON_RELOAD_WAVS := {
	"glock18": ["weapons/clipout1.wav", "weapons/clipin1.wav", "weapons/sliderelease1.wav"],
	"usp45": ["weapons/usp_clipout.wav", "weapons/usp_clipin.wav", "weapons/usp_sliderelease.wav"],
	"p228":
	["weapons/p228_clipout.wav", "weapons/p228_clipin.wav", "weapons/p228_sliderelease.wav"],
	"deagle": ["weapons/de_clipout.wav", "weapons/de_clipin.wav", "weapons/de_deploy.wav"],
	"fiveseven":
	[
		"weapons/fiveseven_clipout.wav",
		"weapons/fiveseven_clipin.wav",
		"weapons/fiveseven_sliderelease.wav",
	],
	"elite":
	[
		"weapons/elite_clipout.wav",
		"weapons/elite_leftclipin.wav",
		"weapons/elite_sliderelease.wav",
	],
	"m3": ["weapons/m3_insertshell.wav", "weapons/m3_insertshell.wav", "weapons/m3_pump.wav"],
	"xm1014": ["weapons/m3_insertshell.wav", "weapons/m3_insertshell.wav", "weapons/m3_pump.wav"],
	"tmp": ["weapons/clipout1.wav", "weapons/clipin1.wav", "weapons/slideback1.wav"],
	"mac10":
	["weapons/mac10_clipout.wav", "weapons/mac10_clipin.wav", "weapons/mac10_boltpull.wav"],
	"mp5": ["weapons/mp5_clipout.wav", "weapons/mp5_clipin.wav", "weapons/mp5_slideback.wav"],
	"ump45":
	["weapons/ump45_clipout.wav", "weapons/ump45_clipin.wav", "weapons/ump45_boltslap.wav"],
	"p90": ["weapons/p90_clipout.wav", "weapons/p90_clipin.wav", "weapons/p90_boltpull.wav"],
	"famas": ["weapons/aug_clipout.wav", "weapons/aug_clipin.wav", "weapons/aug_boltslap.wav"],
	"galil": ["weapons/ak47_clipout.wav", "weapons/ak47_clipin.wav", "weapons/ak47_boltpull.wav"],
	"ak47": ["weapons/ak47_clipout.wav", "weapons/ak47_clipin.wav", "weapons/ak47_boltpull.wav"],
	"m4a1": ["weapons/m4a1_clipout.wav", "weapons/m4a1_clipin.wav", "weapons/m4a1_boltpull.wav"],
	"sg552":
	["weapons/sg552_clipout.wav", "weapons/sg552_clipin.wav", "weapons/sg552_boltpull.wav"],
	"aug": ["weapons/aug_clipout.wav", "weapons/aug_clipin.wav", "weapons/aug_boltpull.wav"],
	"scout": ["weapons/scout_clipout.wav", "weapons/scout_clipin.wav", "weapons/scout_bolt.wav"],
	"awp": ["weapons/awp_clipout.wav", "weapons/awp_clipin.wav", "weapons/boltpull1.wav"],
	"g3sg1": ["weapons/g3sg1_clipout.wav", "weapons/g3sg1_clipin.wav", "weapons/g3sg1_slide.wav"],
	"sg550":
	["weapons/sg550_clipout.wav", "weapons/sg550_clipin.wav", "weapons/sg550_boltpull.wav"],
	"m249": ["weapons/m249_boxout.wav", "weapons/m249_boxin.wav", "weapons/m249_chain.wav"],
}

const WEAPON_DEPLOY_WAVS := {
	"knife": "weapons/knife_deploy1.wav",
	"awp": "weapons/awp_deploy.wav",
	"deagle": "weapons/de_deploy.wav",
	"elite": "weapons/elite_deploy.wav",
	"m4a1": "weapons/m4a1_deploy.wav",
	"aug": "weapons/aug_forearm.wav",
	"famas": "weapons/aug_forearm.wav",
	"m3": "weapons/m3_pump.wav",
	"xm1014": "weapons/m3_pump.wav",
	"c4": "weapons/c4_click.wav",
}

## Ambientes ambientales puros de mapa (sin musica).
const AMBIENCE_WAVS := {
	"dust": "ambience/tk_windstreet.wav",
	"night": "ambience/cicada3.wav",
	"industrial": "ambience/tk_steam.wav",
	"zombie": "ambience/torn_templewind.wav",
}

const FAMILY_FALLBACK_WEAPON := {
	"pistol": "glock18",
	"pistol_heavy": "deagle",
	"smg": "mp5",
	"rifle": "m4a1",
	"rifle_heavy": "ak47",
	"sniper": "awp",
	"shotgun": "m3",
	"lmg": "m249",
	"silenced": "m4a1_sil",
}

var _wav_cache: Dictionary = {}
var _synth_cache: Dictionary = {}
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
var _bg_thread: Thread
var _bg_key := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_setup_players()
	_preload_hot_sounds()


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


func _preload_hot_sounds() -> void:
	var hot: Array[String] = [
		"ui/launch_select1.wav",
		"ui/launch_glow1.wav",
		"player/pl_step1.wav",
		"player/pl_step2.wav",
		"player/pl_step3.wav",
		"player/pl_step4.wav",
		"player/bhit_flesh-1.wav",
		"player/headshot1.wav",
		"player/pl_shell1.wav",
		"weapons/ric1.wav",
		"weapons/ric2.wav",
		"weapons/ak47-1.wav",
		"weapons/m4a1_unsil-1.wav",
		"weapons/m4a1-1.wav",
		"weapons/awp1.wav",
		"weapons/glock18-1.wav",
		"weapons/usp_unsil-1.wav",
		"weapons/usp1.wav",
		"weapons/deagle-1.wav",
		"weapons/mp5-1.wav",
		"weapons/knife_slash1.wav",
	]
	for rel in hot:
		_load_wav(rel, false)


func _load_wav(rel_path: String, looped: bool = false) -> AudioStreamWAV:
	var cache_key := rel_path + ("|L" if looped else "")
	if _wav_cache.has(cache_key):
		var cached: AudioStreamWAV = _wav_cache[cache_key]
		return cached
	var full_path := CS15_DIR + rel_path
	var wav: AudioStreamWAV = null
	if FileAccess.file_exists(full_path):
		var opts: Dictionary = {"edit/loop_mode": 1}
		if looped:
			opts = {"edit/loop_mode": 2, "edit/loop_begin": 0, "edit/loop_end": -1}
		wav = AudioStreamWAV.load_from_file(full_path, opts)
	elif ResourceLoader.exists(full_path):
		var res := ResourceLoader.load(full_path)
		if res is AudioStreamWAV:
			wav = res as AudioStreamWAV
	if wav != null:
		_wav_cache[cache_key] = wav
	return wav


func _pick_wav(list_any: Array, looped: bool = false) -> AudioStreamWAV:
	if list_any.is_empty():
		return null
	var idx := _rng.randi_range(0, list_any.size() - 1)
	return _load_wav(String(list_any[idx]), looped)


func _process(_delta: float) -> void:
	if _bg_thread != null and not _bg_thread.is_alive():
		var result = _bg_thread.wait_to_finish()
		_bg_thread = null
		var key := _bg_key
		_bg_key = ""
		if result is AudioStreamWAV:
			_synth_cache[key] = result
			if _music_wanted == key:
				_play_music_stream(key)
	if _music_wanted != "" and _bg_thread == null:
		if _synth_cache.has(_music_wanted):
			_play_music_stream(_music_wanted)
		else:
			_request_music_synth(_music_wanted)


func _request_music_synth(name: String) -> void:
	if _bg_thread != null:
		return
	_bg_key = name
	_bg_thread = Thread.new()
	_bg_thread.start(_synth_music_only.bind(name))


func _synth_music_only(name: String) -> AudioStreamWAV:
	if name == "menu_music":
		return Synth.menu_music()
	if name == "zombie_music":
		return Synth.zombie_music()
	return null


## Devuelve un AudioStreamWAV para el identificador pedido.
## Todos los efectos usan los .wav originales de CS 1.5; la musica sigue en Synth.
func stream(name: String) -> AudioStreamWAV:
	if name == "menu_music" or name == "zombie_music":
		if _synth_cache.has(name):
			var ms: AudioStreamWAV = _synth_cache[name]
			return ms
		var gen := _synth_music_only(name)
		if gen != null:
			_synth_cache[name] = gen
		return gen

	if name == "flash_ring":
		if not _synth_cache.has("flash_ring"):
			_synth_cache["flash_ring"] = Synth.flash_ring()
		var fr: AudioStreamWAV = _synth_cache["flash_ring"]
		return fr

	if name.begins_with("amb_"):
		var akind := name.substr(4)
		var arel := String(AMBIENCE_WAVS.get(akind, "ambience/tk_windstreet.wav"))
		var awav := _load_wav(arel, true)
		if awav != null:
			return awav
		return Synth.ambience(akind)

	if SOUND_POOLS.has(name):
		var pool: Array = SOUND_POOLS[name]
		var s := _pick_wav(pool, false)
		if s != null:
			return s

	if name.begins_with("footstep_"):
		var fs_pool: Array = SOUND_POOLS["footstep_default"]
		var fs := _pick_wav(fs_pool, false)
		if fs != null:
			return fs

	if name.begins_with("growl_"):
		var gr_pool: Array = SOUND_POOLS["growl"]
		var gr := _pick_wav(gr_pool, false)
		if gr != null:
			return gr

	if name.begins_with("fire_"):
		var parts := name.split("_")
		var family := "_".join(parts.slice(1, parts.size() - 1))
		var wid := String(FAMILY_FALLBACK_WEAPON.get(family, "ak47"))
		if WEAPON_FIRE_WAVS.has(wid):
			var wf_pool: Array = WEAPON_FIRE_WAVS[wid]
			var wf := _pick_wav(wf_pool, false)
			if wf != null:
				return wf

	if name.ends_with(".wav"):
		return _load_wav(name, false)

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
	_play_stream_2d(s, volume_db, pitch, bus)


func _play_stream_2d(
	s: AudioStreamWAV, volume_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX"
) -> void:
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


## Sonido posicional 3D. Se cuelga de `parent` para liberarse con la escena.
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
	if _active_3d > MAX_3D:
		return
	var s := stream(name)
	if s == null:
		return
	_play_stream_3d(s, parent, position, volume_db, pitch, max_distance)


func _play_stream_3d(
	s: AudioStreamWAV,
	parent: Node,
	position: Vector3,
	volume_db: float,
	pitch: float,
	max_distance: float
) -> void:
	if s == null or parent == null or not is_instance_valid(parent):
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


## Disparo autentico de CS 1.5 por ID de arma (con soporte de silenciador M4A1/USP).
func weapon_fire_id(
	weapon_id: String,
	silenced: bool,
	parent: Node,
	pos: Vector3,
	is_local_player: bool = false,
	max_distance: float = 95.0
) -> void:
	var key := weapon_id
	if silenced and (weapon_id == "m4a1" or weapon_id == "usp45"):
		key = weapon_id + "_sil"
	var wav: AudioStreamWAV = null
	if WEAPON_FIRE_WAVS.has(key):
		var pool: Array = WEAPON_FIRE_WAVS[key]
		wav = _pick_wav(pool, false)
	if wav == null:
		wav = _load_wav("weapons/ak47-1.wav", false)
	var pitch := _rng.randf_range(0.98, 1.03)
	if weapon_id == "galil" or weapon_id == "famas":
		pitch = _rng.randf_range(1.04, 1.08)
	if is_local_player:
		_play_stream_2d(wav, -3.5 if not silenced else -6.0, pitch)
	else:
		_play_stream_3d(wav, parent, pos, -1.5 if not silenced else -5.0, pitch, max_distance)


func weapon_fire(family: String, parent: Node, pos: Vector3, max_distance: float = 90.0) -> void:
	var wid := String(FAMILY_FALLBACK_WEAPON.get(family, "ak47"))
	var sil := family == "silenced"
	if sil:
		wid = "m4a1"
	weapon_fire_id(wid, sil, parent, pos, false, max_distance)


func weapon_deploy(weapon_id: String, is_local_player: bool = true) -> void:
	if not is_local_player:
		return
	var rel := String(WEAPON_DEPLOY_WAVS.get(weapon_id, "common/wpn_select.wav"))
	var wav := _load_wav(rel, false)
	_play_stream_2d(wav, -6.0, 1.0)


func weapon_reload_step(
	weapon_id: String, step_idx: int, is_local_player: bool, parent: Node, pos: Vector3
) -> void:
	var rel := "weapons/clipout1.wav"
	if step_idx == 1:
		rel = "weapons/clipin1.wav"
	elif step_idx >= 2:
		rel = "weapons/boltpull1.wav"
	if WEAPON_RELOAD_WAVS.has(weapon_id):
		var steps: Array = WEAPON_RELOAD_WAVS[weapon_id]
		var clamped := clampi(step_idx, 0, steps.size() - 1)
		rel = String(steps[clamped])
	var wav := _load_wav(rel, false)
	if is_local_player:
		_play_stream_2d(wav, -4.5, 1.0)
	else:
		_play_stream_3d(wav, parent, pos, -5.0, 1.0, 22.0)


func weapon_silencer(weapon_id: String, attach: bool) -> void:
	var rel := "weapons/m4a1_silencer_on.wav" if attach else "weapons/m4a1_silencer_off.wav"
	if weapon_id == "usp45":
		rel = "weapons/usp_silencer_on.wav" if attach else "weapons/usp_silencer_off.wav"
	_play_stream_2d(_load_wav(rel, false), -4.0, 1.0)


func c4_beep(urgency: float, parent: Node, pos: Vector3) -> void:
	var idx := clampi(int(urgency * float(C4_BEEPS.size())), 0, C4_BEEPS.size() - 1)
	var wav := _load_wav(C4_BEEPS[idx], false)
	_play_stream_3d(wav, parent, pos, 1.0, 1.0, 65.0)


func play_win_voice(winner_team: int) -> void:
	if winner_team == Content.TEAM_CT:
		play_2d("ct_win", -1.5)
	elif winner_team == Content.TEAM_T:
		play_2d("t_win", -1.5)
	else:
		play_2d("round_draw", -1.5)


func footstep(
	parent: Node, pos: Vector3, quiet: bool = false, surface_kind: String = "default"
) -> void:
	var pool_key := "footstep_default"
	match surface_kind:
		"sand", "dirt", "grass":
			pool_key = "footstep_dirt"
		"metal":
			pool_key = "footstep_metal"
		"tile", "marble":
			pool_key = "footstep_tile"
	var pool: Array = SOUND_POOLS[pool_key]
	var wav := _pick_wav(pool, false)
	var db := -11.0 if quiet else -3.5
	_play_stream_3d(wav, parent, pos, db, _rng.randf_range(0.95, 1.06), 28.0)


func random_pitch(center: float = 1.0, spread: float = 0.06) -> float:
	return center + _rng.randf_range(-spread, spread)


# --- Ambiente (sonido ambiental CS 1.5 sin musica) y musica procedural ---------


func set_ambience(kind: String, fade: float = 2.0) -> void:
	if kind == _ambience_name:
		return
	_ambience_name = kind
	if kind == "":
		var tw := create_tween()
		tw.tween_property(_ambience_player, "volume_db", -60.0, fade)
		tw.tween_callback(_ambience_player.stop)
		return
	var s := stream("amb_" + kind)
	if s != null:
		_ambience_player.stream = s
		_ambience_player.volume_db = -40.0
		_ambience_player.play()
		var tw2 := create_tween()
		tw2.tween_property(_ambience_player, "volume_db", -16.0, 2.0)


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
	if _synth_cache.has(kind):
		_play_music_stream(kind)
	elif _bg_thread == null:
		_request_music_synth(kind)


func _play_music_stream(key: String) -> void:
	if _music_player.stream == _synth_cache[key] and _music_player.playing:
		return
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", -45.0, _music_fade * 0.4)
	tw.tween_callback(
		func() -> void:
			_music_player.stream = _synth_cache[key]
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
	if _bg_thread != null and _bg_thread.is_alive():
		_bg_thread.wait_to_finish()
