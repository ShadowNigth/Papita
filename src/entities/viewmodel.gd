extends Node3D
## Viewmodel: arma en primera persona con sway, bob, retroceso y recarga.
##
## Los materiales usan `no_depth_test` para que el arma nunca se corte contra
## las paredes, y viven en la capa 19 para poder iluminarlas por separado.

class_name Viewmodel

const LAYER := 1 << 18

var camera: Camera3D
var def: Dictionary = {}
var model: Node3D
var muzzle: Node3D

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
var _base_pos := Vector3(0.24, -0.2, -0.42)
var _rng := RandomNumberGenerator.new()


func setup(cam: Camera3D) -> void:
	camera = cam
	name = "Viewmodel"
	_rng.randomize()
	_flash = Sprite3D.new()
	_flash.texture = MaterialLib.spark_texture(64)
	_flash.pixel_size = 0.0022
	_flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_flash.shaded = false
	_flash.no_depth_test = true
	_flash.top_level = true
	_flash.visible = false
	add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.78, 0.45)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 5.0
	_flash_light.shadow_enabled = false
	_flash_light.light_cull_mask = LAYER
	add_child(_flash_light)


func set_weapon(weapon_def: Dictionary) -> void:
	def = weapon_def
	if model and is_instance_valid(model):
		model.queue_free()
	model = WeaponModel.build(weapon_def)
	model.name = "Model"
	add_child(model)
	_prepare_materials(model)
	muzzle = WeaponModel.muzzle_of(model)
	_draw_t = 1.0
	_reload_t = 0.0
	_kick = 0.0
	_ads = false
	visible = true
	_base_pos = Vector3(0.24, -0.2, -0.42)
	if String(weapon_def.get("vm", {}).get("kind", "rifle")) == "knife":
		_base_pos = Vector3(0.28, -0.26, -0.4)


func _prepare_materials(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			mi.layers = LAYER
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := mi.material_override
			if mat is StandardMaterial3D:
				var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.no_depth_test = true
				dup.render_priority = 2
				mi.material_override = dup
		_prepare_materials(child)


func on_fire() -> void:
	var recoil: float = clampf(float(def.get("recoil", 1.0)) * 0.035, 0.012, 0.09)
	_kick = minf(_kick + recoil, 0.14)
	_kick_rot = minf(_kick_rot + recoil * 2.6, 0.22)
	_sway.x += _rng.randf_range(-0.02, 0.02)
	_sway.y += _rng.randf_range(-0.01, 0.02)
	if _flash:
		_flash.visible = true
		_flash.scale = Vector3.ONE * _rng.randf_range(0.5, 0.95)
		var tw := create_tween()
		tw.tween_interval(0.035)
		tw.tween_callback(func() -> void: _flash.visible = false)
	if _flash_light:
		_flash_light.light_energy = 3.5
		var tw2 := create_tween()
		tw2.tween_property(_flash_light, "light_energy", 0.0, 0.07)


func start_reload(time: float) -> void:
	_reload_time = maxf(time, 0.4)
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
	# Sway por movimiento del mouse.
	_sway.x = lerpf(_sway.x, clampf(-mouse_delta.x * 0.0008, -0.05, 0.05), delta * 8.0)
	_sway.y = lerpf(_sway.y, clampf(mouse_delta.y * 0.0008, -0.04, 0.04), delta * 8.0)
	# Bob al caminar.
	if grounded and speed > 0.6:
		_bob_phase += delta * (5.0 + speed * 1.4)
	var bob_amp := 0.012 * (1.0 if walking else 0.65) * (1.0 - (0.6 if _ads else 0.0))
	var bob := Vector3(sin(_bob_phase) * bob_amp, absf(cos(_bob_phase)) * bob_amp, 0)
	if not grounded:
		bob = Vector3(0, 0.01, 0)
	var crouch_off := Vector3(0, -0.035, 0.03) if crouch else Vector3.ZERO
	var ads_pos := Vector3(0.0, -0.075, -0.3)
	var target := _base_pos + crouch_off + bob + Vector3(_sway.x, _sway.y, 0)
	if _ads:
		target = target.lerp(ads_pos, 0.85)
	target.z += _kick
	target.y -= _kick * 0.25
	# Animacion de recarga.
	var reload_rot := 0.0
	var reload_dip := 0.0
	if _reload_t > 0.0:
		_reload_t = maxf(0.0, _reload_t - delta)
		var k := 1.0 - (_reload_t / _reload_time)
		reload_rot = sin(k * PI) * 0.55
		reload_dip = sin(k * PI) * 0.12
		target.y -= reload_dip
	# Animacion de inspeccion (giro del arma).
	if _inspect_t > 0.0:
		_inspect_t = maxf(0.0, _inspect_t - delta * 1.3)
		target.y -= sin(_inspect_t * PI) * 0.06
	# Animacion de desenfunde.
	if _draw_t > 0.0:
		_draw_t = maxf(0.0, _draw_t - delta * 3.2)
		target.y -= _draw_t * 0.32
		target.z -= _draw_t * 0.1
	position = position.lerp(target, clampf(delta * 16.0, 0.0, 1.0))
	var target_rot := Vector3(
		_kick_rot, _sway.x * 1.5 + sin((1.0 - _inspect_t) * PI) * 0.9, reload_rot
	)
	rotation = rotation.lerp(target_rot, clampf(delta * 18.0, 0.0, 1.0))
	_kick = lerpf(_kick, 0.0, delta * 10.0)
	_kick_rot = lerpf(_kick_rot, 0.0, delta * 10.0)
	if _flash and muzzle:
		_flash.global_position = muzzle.global_position
	if _flash_light and muzzle:
		_flash_light.global_position = muzzle.global_position
	visible = not _hide_for_scope
