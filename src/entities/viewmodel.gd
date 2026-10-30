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
	_kick = 0.0
	_kick_rot = 0.0
	_ads = false
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
	var recoil: float = clampf(float(def.get("recoil", 1.0)) * 0.012, 0.004, 0.032)
	_kick = minf(_kick + recoil, 0.045)
	_kick_rot = minf(_kick_rot + recoil * 1.4, 0.08)
	_sway.x += _rng.randf_range(-0.006, 0.006)
	_sway.y += _rng.randf_range(-0.004, 0.006)
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


func on_knife(hit: bool = false) -> void:
	if _using_mdl:
		if hit:
			_play_action(["stab", "midslash1", "slash1"])
		else:
			_shot_idx = (_shot_idx + 1) % 2
			_play_action(["slash1" if _shot_idx == 0 else "slash2", "midslash1"])
	else:
		_kick = 0.06


func on_grenade_throw() -> void:
	if _using_mdl:
		_play_action(["throw", "pullpin"])


func on_c4_plant() -> void:
	if _using_mdl:
		_play_action(["pressbutton"])


func start_reload(time: float) -> void:
	_reload_time = maxf(time, 0.4)
	if _using_mdl:
		if bool(def.get("reload_shell", false)):
			_play_action(["insert", "start_reload", "reload"], 0.55)
		else:
			_play_action(["reload"], _reload_time)
	else:
		_reload_t = _reload_time


func inspect() -> void:
	_inspect_t = 1.0


func set_ads(enabled: bool, hide_for_scope: bool = false) -> void:
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
		_sway.x, clampf(-mouse_delta.x * 0.00045 * sway_scale, -0.02, 0.02), delta * 10.0
	)
	_sway.y = lerpf(
		_sway.y, clampf(mouse_delta.y * 0.00045 * sway_scale, -0.016, 0.016), delta * 10.0
	)
	if grounded and speed > 0.6:
		_bob_phase += delta * (5.2 + speed * 1.35)
	var bob_amp := 0.0045 * bob_scale * (0.75 if walking else 1.0) * (0.45 if _ads else 1.0)
	var bob := Vector3(sin(_bob_phase) * bob_amp, -absf(cos(_bob_phase)) * bob_amp * 0.85, 0.0)
	if not grounded:
		bob = Vector3(0.0, 0.004, 0.0)
	var crouch_off := Vector3(0.0, -0.008, 0.008) if crouch else Vector3.ZERO
	var ads_off := Vector3(-0.028, 0.012, 0.025) if _ads else Vector3.ZERO
	var target := _base_pos + crouch_off + ads_off + bob + Vector3(_sway.x, _sway.y, 0.0)
	target.z += _kick
	target.y -= _kick * 0.2

	var reload_rot := 0.0
	if not _using_mdl and _reload_t > 0.0:
		_reload_t = maxf(0.0, _reload_t - delta)
		var k := 1.0 - (_reload_t / maxf(_reload_time, 0.01))
		reload_rot = sin(k * PI) * 0.55
		target.y -= sin(k * PI) * 0.12

	var inspect_yaw := 0.0
	var inspect_roll := 0.0
	if _inspect_t > 0.0:
		_inspect_t = maxf(0.0, _inspect_t - delta * 1.1)
		var ik := sin(_inspect_t * PI)
		inspect_yaw = ik * 0.28
		inspect_roll = ik * 0.22

	if not _using_mdl and _draw_t > 0.0:
		_draw_t = maxf(0.0, _draw_t - delta * 3.2)
		target.y -= _draw_t * 0.32
		target.z -= _draw_t * 0.1

	position = position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))
	var target_rot := Vector3(_kick_rot, _sway.x * 1.1 + inspect_yaw, reload_rot + inspect_roll)
	rotation = rotation.lerp(target_rot, clampf(delta * 18.0, 0.0, 1.0))
	_kick = lerpf(_kick, 0.0, delta * 14.0)
	_kick_rot = lerpf(_kick_rot, 0.0, delta * 14.0)
	if _flash and muzzle:
		_flash.global_position = muzzle.global_position
	if _flash_light and muzzle:
		_flash_light.global_position = muzzle.global_position
	visible = not _hide_for_scope
