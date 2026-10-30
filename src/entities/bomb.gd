extends Node3D
## C4: bomba plantada con cuenta atras, pitidos y desactivacion.

class_name Bomb

signal exploded
signal defused
signal defuse_progress(progress: float)

const FUSE_TIME := 40.0
const DEFUSE_TIME := 10.0
const DEFUSE_TIME_KIT := 5.0

var time_left := FUSE_TIME
var planted := false
var defuse_amount := 0.0
var defusing_by: Combatant = null

var _beep_timer := 0.0
var _light: OmniLight3D
var _led: MeshInstance3D
var _label: Label3D
var _red_mat: StandardMaterial3D


func plant(position: Vector3) -> void:
	global_position = position + Vector3(0, 0.06, 0)
	planted = true
	time_left = FUSE_TIME
	AudioBank.play_at("plant", self, global_position, 0.0, 1.0, 40.0)
	if _label:
		_label.text = "C4"


func _ready() -> void:
	_build()


func _build() -> void:
	var c4_model := MdlLoader.build_world_weapon("c4", false)
	if c4_model != null:
		c4_model.scale = Vector3.ONE * 1.15
		add_child(c4_model)
	else:
		var body := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.34, 0.12, 0.24)
		body.mesh = mesh
		body.material_override = MaterialLib.simple(Color(0.28, 0.22, 0.12), 0.8)
		add_child(body)
	var panel := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.02
	pm.height = 0.04
	panel.mesh = pm
	panel.position = Vector3(0.02, 0.14, 0.0)
	_red_mat = MaterialLib.emissive(Color(1.0, 0.1, 0.05), 4.0)
	panel.material_override = _red_mat
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_led = panel
	add_child(panel)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.1, 0.05)
	_light.light_energy = 0.0
	_light.omni_range = 4.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.22, 0)
	add_child(_light)
	_label = Label3D.new()
	_label.text = "C4"
	_label.font_size = 56
	_label.pixel_size = 0.003
	_label.position = Vector3(0, 0.35, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1.0, 0.25, 0.2)
	_label.outline_size = 8
	_label.visibility_range_end = 28.0
	add_child(_label)


func _process(delta: float) -> void:
	if not planted:
		return
	time_left -= delta
	if time_left <= 0.0:
		explode()
		return
	var urgency := clampf(1.0 - time_left / FUSE_TIME, 0.0, 1.0)
	_beep_timer -= delta
	if _beep_timer <= 0.0:
		_beep_timer = lerpf(1.0, 0.09, urgency)
		AudioBank.play_at("beep", self, global_position, 0.0, 1.0 + urgency * 0.8, 60.0)
		if _light:
			_light.light_energy = 2.2
	if _light:
		_light.light_energy = maxf(0.0, _light.light_energy - delta * 8.0)
	if _led:
		_led.visible = fmod(time_left, 0.5) < 0.25
	# Progreso de desactivacion.
	if defusing_by and is_instance_valid(defusing_by) and defusing_by.alive:
		if defusing_by.global_position.distance_to(global_position) < 2.4:
			var speed := 1.0 / (DEFUSE_TIME_KIT if defusing_by.defusekit else DEFUSE_TIME)
			defuse_amount += delta * speed
			defuse_progress.emit(clampf(defuse_amount, 0.0, 1.0))
			if defuse_amount >= 1.0:
				_defused()
		else:
			defusing_by = null
			defuse_progress.emit(0.0)
	if _label:
		_label.text = "%0.1f" % maxf(time_left, 0.0)


func begin_defuse(combatant: Combatant) -> void:
	if not planted:
		return
	defusing_by = combatant


func stop_defuse() -> void:
	defusing_by = null
	defuse_progress.emit(0.0)


func _defused() -> void:
	planted = false
	AudioBank.play_at("defuse", self, global_position, 0.0, 1.0, 50.0)
	defused.emit()
	queue_free()


func explode() -> void:
	if not planted:
		return
	planted = false
	Fx.explosion(get_parent(), global_position + Vector3(0, 0.3, 0), true)
	exploded.emit()
	queue_free()
