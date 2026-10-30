extends Node3D
## Viewmodel: brazos y arma en primera persona originales de Counter-Strike 1.5 (.mdl)
## con esqueleto real (draw, shoot, reload, silencer, cuchillo, C4 y granadas),
## bob clasico de CS 1.5, sway suave y fogonazo en la boca del canon.

class_name Viewmodel

const LAYER := 1 << 18

var camera: Camera3D
var def: Dictionary = {}
var model: Node3D
var muzzle: Node3D

var _anim_player: AnimationPlayer
var _seqs := PackedStringArray()
var _has_unsil := false
var _silenced := false
var _using_mdl := false
var _dual_toggle := false
var _shot_idx := 0

var _sway := Vector2.ZERO
var _bob_phase := 0.0
var _kick := 0.0
var _kick_rot := 0.0
var _reload_t := 0.0
var _reload_time := 0.0
var _draw_t := 0.0
var _ads := false
var _hide_for_scope := false
var _inspect_t := 0.0
var _inspect_dur := 3.2
var _inspect_variant := 0
var _wick_light: OmniLight3D
var _flash: Sprite3D
var _flash_light: OmniLight3D
var _base_pos := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func setup(cam: Camera3D) -> void:
	camera = cam
	name = "Viewmodel"
	_rng.randomize()
	_flash = Sprite3D.new()
	_flash.texture = MaterialLib.spark_texture(64)
	_flash.pixel_size = 0.0014
	_flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_flash.shaded = false
	_flash.no_depth_test = true
	_flash.top_level = true
	_flash.visible = false
	add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.78, 0.45)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 4.5
	_flash_light.shadow_enabled = false
	add_child(_flash_light)
	_wick_light = OmniLight3D.new()
	_wick_light.light_color = Color(1.0, 0.56, 0.16)
	_wick_light.light_energy = 0.0
	_wick_light.omni_range = 2.6
	_wick_light.shadow_enabled = false
	_wick_light.position = Vector3(0.22, -0.08, -0.36)
	add_child(_wick_light)


func set_weapon(weapon_def: Dictionary, silenced: bool = false) -> void:
	def = weapon_def
	_silenced = silenced
	if model and is_instance_valid(model):
		model.queue_free()
	model = null
	_anim_player = null
	_seqs = PackedStringArray()
	_has_unsil = false
	_using_mdl = false

	var wid := String(weapon_def.get("id", "knife"))
	var built := MdlLoader.build_viewmodel(wid)
	if not built.is_empty():
		_using_mdl = true
		model = built["root"]
		model.name = "Model"
		add_child(model)
		_anim_player = built["anim_player"]
		_seqs = built["seqs"]
		muzzle = built["muzzle"]
		for s in _seqs:
			if s.ends_with("_unsil"):
				_has_unsil = true
				break
		if _anim_player:
			_anim_player.animation_finished.connect(_on_anim_finished)
		_base_pos = Vector3.ZERO
		position = Vector3.ZERO
		rotation = Vector3.ZERO
		_play_action(["draw", "deploy"], 1.0)
	else:
		model = WeaponModel.build(weapon_def, false)
		model.name = "Model"
		add_child(model)
		muzzle = WeaponModel.muzzle_of(model)
		_base_pos = Vector3(0.24, -0.2, -0.42)
		_draw_t = 1.0

	_reload_t = 0.0
	_inspect_t = 0.0
	_kick = 0.0
	_kick_rot = 0.0
	_ads = false
	if _wick_light:
		_wick_light.light_energy = 1.15 if wid == "molotov" else 0.0
	visible = true


func _resolve_seq(candidates: Array[String]) -> String:
	if _seqs.is_empty():
		return ""
	if _has_unsil and not _silenced:
		for c in candidates:
			var u := c + "_unsil"
			if _seqs.has(u):
				return u
	for c in candidates:
		if _seqs.has(c):
			return c
	for c in candidates:
		for s in _seqs:
			if s.begins_with(c):
				if _has_unsil and _silenced and s.ends_with("_unsil"):
					continue
				return s
	return _seqs[0]


func _play_idle() -> void:
	if _anim_player == null:
		return
	var idle_name := _resolve_seq(["idle", "idle1", "idle3"])
	if idle_name != "":
		_anim_player.speed_scale = 1.0
		_anim_player.play(idle_name, 0.08)


func _play_action(candidates: Array[String], target_duration: float = 0.0) -> void:
	if _anim_player == null:
		return
	var seq_name := _resolve_seq(candidates)
	if seq_name == "" or not _anim_player.has_animation(seq_name):
		return
	_anim_player.stop()
	var spd := 1.0
	if target_duration > 0.05:
		var anim := _anim_player.get_animation(seq_name)
		if anim != null and anim.length > 0.05:
			spd = clampf(anim.length / target_duration, 0.45, 3.2)
	_anim_player.speed_scale = spd
	_anim_player.play(seq_name)


func _on_anim_finished(_anim_name: StringName) -> void:
	_play_idle()


func set_silenced(enabled: bool, animate_toggle: bool = false) -> void:
	if _silenced == enabled and not animate_toggle:
		return
	_silenced = enabled
	if _using_mdl and animate_toggle:
		if enabled:
			_play_action(["add_silencer"])
		else:
			_play_action(["detach_silencer"])
	elif _using_mdl:
		_play_idle()


func on_fire() -> void:
	_inspect_t = 0.0
	var recoil: float = clampf(float(def.get("recoil", 1.0)) * 0.008, 0.003, 0.020)
	_kick = minf(_kick + recoil, 0.024)
	_kick_rot = minf(_kick_rot + recoil * 1.8, 0.075)
	_sway.x += _rng.randf_range(-0.004, 0.004)
	_sway.y += _rng.randf_range(-0.003, 0.004)
	if _using_mdl:
		_shot_idx = (_shot_idx + 1) % 3
		if String(def.get("id", "")) == "elite":
			_dual_toggle = not _dual_toggle
			if _dual_toggle:
				_play_action(["shoot_left1", "shoot_left2"])
			else:
				_play_action(["shoot_right1", "shoot_right2"])
		else:
			var shot_cands: Array[String] = ["shoot" + str(_shot_idx + 1), "shoot1", "shoot"]
			_play_action(shot_cands)

	var slot: int = int(def.get("slot", Content.SLOT_PRIMARY))
	var show_flash := (
		(slot == Content.SLOT_PRIMARY or slot == Content.SLOT_SECONDARY)
		and not (_silenced and bool(def.get("silencer", false)))
	)
	if _flash and show_flash:
		_flash.visible = true
		_flash.scale = Vector3.ONE * _rng.randf_range(0.35, 0.65)
		var tw := create_tween()
		tw.tween_interval(0.032)
		tw.tween_callback(func() -> void: _flash.visible = false)
	if _flash_light and show_flash:
		_flash_light.light_energy = 2.4
		var tw2 := create_tween()
		tw2.tween_property(_flash_light, "light_energy", 0.0, 0.06)


func on_knife(hit: bool = false, heavy: bool = false) -> void:
	_inspect_t = 0.0
	if _using_mdl:
		if heavy:
			if hit:
				_play_action(["stab", "midslash1", "slash1"])
			else:
				_play_action(["stab_miss", "stab", "midslash1"])
		else:
			_shot_idx = (_shot_idx + 1) % 2
			_play_action(["midslash1", "slash1"] if _shot_idx == 0 else ["midslash2", "slash2"])
	else:
		_kick = 0.09 if heavy else 0.06


func on_grenade_throw() -> void:
	_inspect_t = 0.0
	if _using_mdl:
		_play_action(["throw", "pullpin"])


func on_c4_plant() -> void:
	_inspect_t = 0.0
	if _using_mdl:
		_play_action(["pressbutton"])


func start_reload(time: float) -> void:
	_inspect_t = 0.0
	_reload_time = maxf(time, 0.4)
	if _using_mdl:
		if bool(def.get("reload_shell", false)):
			_play_action(["insert", "start_reload", "reload"], 0.55)
		else:
			_play_action(["reload"], _reload_time)
	else:
		_reload_t = _reload_time


func inspect() -> void:
	if _reload_t > 0.05 or _ads or _hide_for_scope:
		return
	var cls := String(def.get("cls", "rifle"))
	var wid := String(def.get("id", ""))
	_inspect_variant = (_inspect_variant + 1) % 3
	match cls:
		"knife":
			_inspect_dur = 2.85
			AudioBank.play_2d("knife_deploy", -10.0, _rng.randf_range(0.96, 1.06))
		"pistol":
			_inspect_dur = 2.65 if (wid == "deagle" and _inspect_variant == 2) else 2.55
			AudioBank.play_2d("inspect_foley", -13.0, _rng.randf_range(1.04, 1.14))
		"grenade", "c4":
			_inspect_dur = 2.45
			AudioBank.play_2d("inspect_foley", -14.0, _rng.randf_range(1.08, 1.18))
		_:
			_inspect_dur = 3.45
			AudioBank.play_2d("inspect_foley", -12.0, _rng.randf_range(0.95, 1.05))
	_inspect_t = _inspect_dur
	if _using_mdl:
		_play_idle()


func _compute_inspect_pose(progress: float) -> Dictionary:
	# progress va de 0.0 (inicio) a 1.0 (fin). Envolvente suave de entrada y salida.
	var env := sin(clampf(progress / 0.16, 0.0, 1.0) * PI * 0.5)
	if progress > 0.82:
		env *= cos(clampf((progress - 0.82) / 0.18, 0.0, 1.0) * PI * 0.5)
	var cls := String(def.get("cls", "rifle"))
	var wid := String(def.get("id", ""))
	var pos_off := Vector3.ZERO
	var rot_off := Vector3.ZERO
	match cls:
		"knife":
			if _inspect_variant == 0:
				# Giro de muneca + exhibicion de ambos lados de la hoja (estilo CS2).
				var flip := sin(progress * PI * 2.0)
				pos_off = Vector3(-0.045, 0.032, -0.025) * env
				rot_off = Vector3(0.26 * env, 0.58 * flip * env, 0.82 * sin(progress * PI) * env)
			elif _inspect_variant == 1:
				# Flourish / pirueta completa de 360 grados sobre el eje de la hoja.
				var spin := smoothstep(0.08, 0.72, progress) * TAU
				pos_off = Vector3(-0.035, 0.048 * sin(progress * PI), -0.02) * env
				rot_off = Vector3(spin, 0.34 * env, 0.42 * sin(progress * PI) * env)
			else:
				# Inspeccion tactica del filo a contraluz.
				var wave := sin(progress * PI * 1.5)
				pos_off = Vector3(-0.052, 0.024, -0.03) * env
				rot_off = Vector3(-0.32 * env, -0.62 * wave * env, -0.68 * env)
		"pistol":
			if wid == "deagle" and _inspect_variant == 2:
				# Inspeccion rara de Desert Eagle girando en el dedo indice (CS2).
				var dspin := smoothstep(0.06, 0.84, progress) * TAU * 2.0
				pos_off = Vector3(-0.03, 0.035, -0.015) * env
				rot_off = Vector3(dspin, 0.22 * env, 0.18 * sin(progress * PI * 2.0) * env)
			else:
				var p_side := sin(progress * PI * 2.0)
				pos_off = Vector3(-0.042, 0.026, -0.018) * env
				rot_off = Vector3(0.18 * env, 0.52 * p_side * env, 0.66 * p_side * env)
		"grenade":
			if wid == "molotov":
				# Agita suavemente la botella incendiaria e inspecciona la mecha encendida.
				var swirl := sin(progress * PI * 3.0)
				pos_off = Vector3(-0.05, 0.03 + 0.012 * swirl, -0.04) * env
				rot_off = Vector3(
					0.28 * env, 0.45 * swirl * env, 0.52 * sin(progress * PI * 2.0) * env
				)
			else:
				# Rueda la granada en la mano mostrando espoleta y anilla.
				var g_turn := sin(progress * PI * 2.0)
				pos_off = Vector3(-0.04, 0.032, -0.025) * env
				rot_off = Vector3(0.32 * sin(progress * PI) * env, 0.68 * g_turn * env, 0.48 * env)
		"c4":
			# Eleva e inclina el bloque de C4 hacia la vista para leer el teclado y pantalla.
			var c_tilt := sin(progress * PI)
			pos_off = Vector3(-0.055, 0.042, -0.035) * env
			rot_off = Vector3(
				0.46 * c_tilt * env, 0.28 * sin(progress * PI * 2.0) * env, -0.24 * env
			)
		_:
			# Fusiles, subfusiles, escopetas, francotiradores y M249:
			# Fase 1 muestra costado izquierdo (cajon de mecanismos / cargador),
			# Fase 2 gira hacia el otro lado mostrando ventana de expulsion y canon (CS2).
			var phase1 := (
				smoothstep(0.05, 0.28, progress) * (1.0 - smoothstep(0.46, 0.62, progress))
			)
			var phase2 := (
				smoothstep(0.48, 0.66, progress) * (1.0 - smoothstep(0.84, 0.98, progress))
			)
			pos_off = (
				Vector3(-0.052, 0.026, -0.022) * phase1 + Vector3(-0.028, 0.018, -0.016) * phase2
			)
			rot_off = (Vector3(0.14, 0.48, 0.62) * phase1 + Vector3(-0.10, -0.36, -0.54) * phase2)
	return {"pos": pos_off, "rot": rot_off}


func set_ads(enabled: bool, hide_for_scope: bool = false) -> void:
	if enabled or hide_for_scope:
		_inspect_t = 0.0
	_ads = enabled
	_hide_for_scope = hide_for_scope


func update(
	delta: float,
	velocity: Vector3,
	grounded: bool,
	crouch: bool,
	mouse_delta: Vector2,
	walking: bool
) -> void:
	if model == null:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var sway_scale: float = float(Settings.data.gameplay.get("viewmodel_sway", 1.0))
	var bob_scale: float = float(Settings.data.gameplay.get("bob", 1.0))
	_sway.x = lerpf(
		_sway.x, clampf(-mouse_delta.x * 0.0003 * sway_scale, -0.014, 0.014), delta * 10.0
	)
	_sway.y = lerpf(
		_sway.y, clampf(mouse_delta.y * 0.0003 * sway_scale, -0.011, 0.011), delta * 10.0
	)
	if grounded and speed > 0.6:
		_bob_phase += delta * (5.2 + speed * 1.35)
	var bob_amp := 0.003 * bob_scale * (0.75 if walking else 1.0) * (0.45 if _ads else 1.0)
	var bob := Vector3(sin(_bob_phase) * bob_amp, -absf(cos(_bob_phase)) * bob_amp * 0.85, 0.0)
	if not grounded:
		bob = Vector3(0.0, 0.0028, 0.0)
	var crouch_off := Vector3(0.0, -0.005, 0.004) if crouch else Vector3.ZERO
	var ads_off := Vector3(-0.018, 0.008, 0.012) if _ads else Vector3.ZERO
	var target := _base_pos + crouch_off + ads_off + bob + Vector3(_sway.x, _sway.y, 0.0)
	target.z = minf(target.z + _kick, 0.016)
	target.y -= _kick * 0.2

	var reload_rot := 0.0
	if not _using_mdl and _reload_t > 0.0:
		_reload_t = maxf(0.0, _reload_t - delta)
		var k := 1.0 - (_reload_t / maxf(_reload_time, 0.01))
		reload_rot = sin(k * PI) * 0.55
		target.y -= sin(k * PI) * 0.12

	var inspect_pos := Vector3.ZERO
	var inspect_rot := Vector3.ZERO
	if _inspect_t > 0.0:
		_inspect_t = maxf(0.0, _inspect_t - delta)
		var prog := 1.0 - (_inspect_t / maxf(_inspect_dur, 0.1))
		var pose := _compute_inspect_pose(prog)
		inspect_pos = pose["pos"]
		inspect_rot = pose["rot"]
		target += inspect_pos

	if _wick_light and String(def.get("id", "")) == "molotov":
		_wick_light.light_energy = 1.05 + sin(float(Time.get_ticks_msec()) * 0.024) * 0.25

	if not _using_mdl and _draw_t > 0.0:
		_draw_t = maxf(0.0, _draw_t - delta * 3.2)
		target.y -= _draw_t * 0.32
		target.z -= _draw_t * 0.1

	position = position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))
	var target_rot := Vector3(_kick_rot, _sway.x * 1.1, reload_rot) + inspect_rot
	rotation = rotation.lerp(target_rot, clampf(delta * 16.0, 0.0, 1.0))
	_kick = lerpf(_kick, 0.0, delta * 14.0)
	_kick_rot = lerpf(_kick_rot, 0.0, delta * 14.0)
	if _flash and muzzle:
		_flash.global_position = muzzle.global_position
	if _flash_light and muzzle:
		_flash_light.global_position = muzzle.global_position
	visible = not _hide_for_scope
