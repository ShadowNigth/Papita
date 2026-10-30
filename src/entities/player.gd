extends Combatant
## Player: control en primera persona con camara, viewmodel y entrada CS-like.

class_name Player

signal buy_requested
signal pause_requested
signal console_requested
signal help_requested
signal scoreboard_changed(visible: bool)

var camera_rig: Node3D
var camera: Camera3D
var viewmodel: Viewmodel
var flashlight: SpotLight3D
var input_enabled := true
var interaction_hint := ""
var mouse_sensitivity := 1.6

var _pitch := 0.0
var _target_fov := 90.0
var _base_fov := 90.0
var _shake := 0.0
var _bob_t := 0.0
var _use_hold := 0.0
var _scoped := false
var _ads := false
var _dead_time := 0.0
var _last_health := 100.0
var _last_vm_id := ""
var _mouse_accum := Vector2.ZERO


func _ready() -> void:
	is_player = true
	is_bot = false
	super._ready()
	add_to_group("player")
	mouse_sensitivity = float(Settings.data.gameplay.get("sensitivity", 1.6))
	_base_fov = float(Settings.data.video.get("fov", 90.0))
	_target_fov = _base_fov
	_build_view()
	Settings.settings_changed.connect(_on_settings_changed)


func _build_view() -> void:
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	camera_rig.position = Vector3(0, 1.62, 0)
	add_child(camera_rig)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = _base_fov
	camera.near = 0.008
	camera.far = 650.0
	camera.current = true
	camera.position = Vector3.ZERO
	camera_rig.add_child(camera)
	viewmodel = Viewmodel.new()
	viewmodel.setup(camera)
	camera.add_child(viewmodel)
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1.0, 0.95, 0.82)
	flashlight.light_energy = 2.6
	flashlight.spot_range = 22.0
	flashlight.spot_angle = 28.0
	flashlight.spot_angle_attenuation = 1.2
	flashlight.shadow_enabled = false
	flashlight.visible = false
	flashlight.position = Vector3(0.18, -0.1, 0.12)
	camera.add_child(flashlight)
	set_meta("camera", camera)
	if actor_model:
		actor_model.visible = false
	if model_container:
		model_container.visible = false


func setup_player(team_id: int, pname: String) -> void:
	is_player = true
	is_bot = false
	configure(pname, team_id, false)
	if actor_model:
		actor_model.visible = false
	if model_container:
		model_container.visible = false
	if primary_id == "":
		give_weapon("glock18" if team_id == Content.TEAM_T else "usp45")
		give_weapon("knife")
		select_slot(Content.SLOT_SECONDARY)


func _on_settings_changed(section: String) -> void:
	if section == "video" or section == "all":
		_base_fov = float(Settings.data.video.get("fov", 90.0))
		if not _scoped:
			_target_fov = _base_fov
	if section == "gameplay" or section == "all":
		mouse_sensitivity = float(Settings.data.gameplay.get("sensitivity", 1.6))


func _unhandled_input(event: InputEvent) -> void:
	if not alive:
		if event is InputEventMouseButton and event.is_pressed():
			pass
		return
	if event is InputEventMouseMotion and input_enabled:
		var mm := event as InputEventMouseMotion
		_look(mm.relative)
	if event is InputEventMouseButton and event.is_pressed() and input_enabled:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				cycle_weapon(1)
			MOUSE_BUTTON_WHEEL_UP:
				cycle_weapon(-1)
	if event.is_action_pressed("pause"):
		pause_requested.emit()
		return
	if not input_enabled:
		return
	if event.is_action_pressed("buy"):
		buy_requested.emit()
	elif event.is_action_pressed("console"):
		console_requested.emit()
	elif event.is_action_pressed("toggle_help"):
		help_requested.emit()
	elif event.is_action_pressed("reload"):
		reload()
	elif event.is_action_pressed("last_weapon"):
		cycle_weapon(1)
	elif event.is_action_pressed("slot1"):
		select_slot(Content.SLOT_PRIMARY)
	elif event.is_action_pressed("slot2"):
		select_slot(Content.SLOT_SECONDARY)
	elif event.is_action_pressed("slot3"):
		select_slot(Content.SLOT_KNIFE)
	elif event.is_action_pressed("slot4"):
		if Input.is_key_pressed(KEY_CTRL):
			cycle_grenade()
		else:
			select_slot(Content.SLOT_GRENADE)
	elif event.is_action_pressed("slot5"):
		select_slot(Content.SLOT_C4)
	elif event.is_action_pressed("drop"):
		_drop_current()
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
		AudioBank.play_2d("ui_click", -12.0)
	elif event.is_action_pressed("inspect"):
		if viewmodel:
			viewmodel.inspect()
	elif event.is_action_pressed("alt_fire"):
		_alt_fire()
	elif event.is_action_pressed("scoreboard"):
		scoreboard_changed.emit(true)
	elif event.is_action_released("scoreboard"):
		scoreboard_changed.emit(false)


func _alt_fire() -> void:
	var def := current_def()
	var zoom: float = float(def.get("zoom", 0.0))
	if zoom > 0.0:
		toggle_zoom()
		_scoped = zoom_level > 0
		if viewmodel:
			viewmodel.set_ads(_scoped, true)
		if not _scoped:
			_target_fov = _base_fov
	elif bool(def.get("silencer", false)):
		toggle_silencer()
	else:
		_ads = not _ads


func _look(relative: Vector2) -> void:
	var factor := mouse_sensitivity * 0.0022
	if _scoped:
		factor *= 0.42
	elif _ads:
		factor *= 0.8
	var invert: float = -1.0 if bool(Settings.data.gameplay.get("invert_y", false)) else 1.0
	_mouse_accum += relative
	rotate_y(-relative.x * factor)
	_pitch = clampf(_pitch - relative.y * factor * invert, -1.45, 1.35)
	_apply_camera_rotation()


func _apply_camera_rotation() -> void:
	if camera_rig == null:
		return
	camera_rig.rotation.x = _pitch
	camera_rig.rotation.y = recoil_yaw
	camera_rig.position.x = sin(recoil_yaw * 3.0) * 0.02


func apply_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.2)


func _apply_player_recoil(r: float, _def: Dictionary) -> void:
	var kick := r * 0.011
	if _scoped:
		kick *= 0.5
	_pitch = clampf(_pitch + kick, -1.45, 1.4)
	_apply_camera_rotation()
	_shake = minf(_shake + r * 0.035, 0.7)
	if viewmodel:
		viewmodel.on_fire()


func _physics_process(delta: float) -> void:
	if not alive:
		_dead_time += delta
		_update_camera_dead(delta)
		super._physics_process(delta)
		return
	_gather_input(delta)
	super._physics_process(delta)
	_sync_viewmodel()
	_update_camera(delta)
	if input_enabled and wants_fire and current_id != "":
		pass


func _sync_viewmodel() -> void:
	if viewmodel == null:
		return
	var wanted := current_id if current_id != "" else "knife"
	if wanted == _last_vm_id and viewmodel.model != null:
		return
	_last_vm_id = wanted
	viewmodel.set_weapon(current_def(), silencer_on)


func _on_reload_started(duration: float) -> void:
	if viewmodel:
		viewmodel.start_reload(duration)


func _on_melee_attacked(hit: bool) -> void:
	if viewmodel:
		viewmodel.on_knife(hit)


func _on_grenade_thrown() -> void:
	if viewmodel:
		viewmodel.on_grenade_throw()


func _on_silencer_toggled(enabled: bool) -> void:
	if viewmodel:
		viewmodel.set_silenced(enabled, true)


func _gather_input(_delta: float) -> void:
	if not input_enabled:
		wish_dir = Vector2.ZERO
		want_jump = false
		wants_fire = false
		want_crouch = false
		want_walk = false
		return
	var axis := Vector2(
		Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back")
	)
	if axis.length() > 1.0:
		axis = axis.normalized()
	var basis_yaw := global_transform.basis
	var forward := -basis_yaw.z
	var right := basis_yaw.x
	var world := right * axis.x + forward * (-axis.y)
	wish_dir = Vector2(world.x, world.z)
	want_crouch = Input.is_action_pressed("crouch")
	want_walk = Input.is_action_pressed("walk")
	if Input.is_action_just_pressed("jump"):
		want_jump = true
	wants_fire = Input.is_action_pressed("fire")
	if Input.is_action_pressed("use"):
		_use_hold += _delta_safe()
		var game := get_tree().get_first_node_in_group("game")
		if game and game.has_method("interact_hold"):
			game.call("interact_hold", self, _use_hold)
	else:
		if _use_hold > 0.0:
			var game := get_tree().get_first_node_in_group("game")
			if game and game.has_method("interact_release"):
				game.call("interact_release", self)
		_use_hold = 0.0
	if Input.is_action_just_pressed("use"):
		var game := get_tree().get_first_node_in_group("game")
		if game and game.has_method("interact_press"):
			game.call("interact_press", self)


func _delta_safe() -> float:
	return get_physics_process_delta_time()


func _update_camera(delta: float) -> void:
	if camera_rig == null:
		return
	var target_y := 1.62
	if crouching:
		target_y = 1.02
	if not is_on_floor():
		target_y += 0.03
	camera_rig.position.y = lerpf(camera_rig.position.y, target_y, clampf(delta * 12.0, 0.0, 1.0))
	# Bob de cabeza.
	var planar := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and planar > 0.8:
		_bob_t += delta * (6.0 + planar * 1.3)
	var amp := 0.016 * clampf(planar / BASE_SPEED, 0.0, 1.0)
	camera.position.y = sin(_bob_t) * amp
	camera.position.x = cos(_bob_t * 0.5) * amp * 0.6
	# Shake.
	if _shake > 0.001:
		_shake = maxf(0.0, _shake - delta * 2.2)
		camera_rig.rotation.z = randf_range(-1, 1) * _shake * 0.02
		camera_rig.position.x += randf_range(-1, 1) * _shake * 0.01
	else:
		camera_rig.rotation.z = lerpf(camera_rig.rotation.z, 0.0, delta * 8.0)
	_apply_camera_rotation()
	# Zoom / ADS / FOV.
	var def := current_def()
	var zoom: float = float(def.get("zoom", 0.0))
	if zoom_level > 0 and zoom > 0.0:
		_target_fov = _base_fov / zoom
	else:
		_target_fov = _base_fov * (0.86 if _ads else 1.0)
	camera.fov = lerpf(camera.fov, _target_fov, clampf(delta * 12.0, 0.0, 1.0))
	if viewmodel:
		viewmodel.set_ads(_scoped or _ads, _scoped and zoom > 0.0)
		var mouse_rel := _mouse_accum
		_mouse_accum = Vector2.ZERO
		viewmodel.update(delta, velocity, is_on_floor(), crouching, mouse_rel, want_walk)


func _update_camera_dead(delta: float) -> void:
	if camera_rig:
		camera_rig.position.y = lerpf(camera_rig.position.y, 0.35, clampf(delta * 3.0, 0.0, 1.0))
		camera_rig.rotation.z = lerpf(camera_rig.rotation.z, 1.2, clampf(delta * 2.0, 0.0, 1.0))
	if viewmodel:
		viewmodel.visible = false


func _drop_current() -> void:
	if current_slot != Content.SLOT_PRIMARY and current_slot != Content.SLOT_SECONDARY:
		return
	var id := primary_id if current_slot == Content.SLOT_PRIMARY else secondary_id
	if id == "":
		return
	var a: Vector2i = ammo.get(id, Vector2i(0, 0))
	if current_slot == Content.SLOT_PRIMARY:
		primary_id = ""
	else:
		secondary_id = ""
	var game := get_tree().get_first_node_in_group("game")
	if game and game.has_method("spawn_pickup"):
		game.call(
			"spawn_pickup",
			id,
			global_position + get_fire_direction() * 1.2 + Vector3(0, 0.3, 0),
			id,
			a.x,
			a.y
		)
	current_id = ""
	current_slot = Content.SLOT_KNIFE
	select_slot(Content.SLOT_KNIFE)


func on_respawn(pos: Vector3) -> void:
	respawn(pos)
	if actor_model:
		actor_model.visible = false
	if model_container:
		model_container.visible = false
	_dead_time = 0.0
	_pitch = 0.0
	_shake = 0.0
	_scoped = false
	_ads = false
	zoom_level = 0
	if camera_rig:
		camera_rig.position = Vector3(0, 1.62, 0)
		camera_rig.rotation = Vector3.ZERO
	if viewmodel:
		viewmodel.visible = true
	input_enabled = true
	capture_mouse(true)
	select_slot(Content.SLOT_PRIMARY if primary_id != "" else Content.SLOT_SECONDARY)


func capture_mouse(capture: bool) -> void:
	if capture and not alive:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			pause_requested.emit()
