extends Combatant
## Rehen rescatable: sigue al CT que lo libera y debe llegar a la zona segura.

class_name Hostage

var following: Combatant = null
var rescued := false
var follow_offset := Vector3.ZERO
var _think := 0.0


func _ready() -> void:
	super._ready()
	is_hostage = true
	is_bot = true
	team = 0
	display_name = "Rehen"
	max_health = 100.0
	health = 100.0
	armor = 0.0
	invulnerable = true
	_rng.randomize()
	add_to_group("hostage")
	if model_container == null:
		model_container = Node3D.new()
		model_container.name = "Model"
		add_child(model_container)
		actor_model = ActorModel.new()
		actor_model.name = "Actor"
		model_container.add_child(actor_model)
	actor_model.setup(Content.TEAM_T, false, Color(0.72, 0.56, 0.42), 1.0, true)
	actor_model.set_name_tag("REHEN")
	actor_model.hide_weapon()


func setup_hostage(pos: Vector3) -> void:
	global_position = pos + Vector3(0, 0.15, 0)
	_spawn_position = global_position
	follow_offset = Vector3(_rng.randf_range(-0.7, 0.7), 0, _rng.randf_range(-0.7, 0.7))


func start_follow(leader: Combatant) -> void:
	following = leader
	AudioBank.play_at("hostage_use", self, global_position, -2.0, 1.0, 24.0)


func stop_follow() -> void:
	following = null
	wish_dir = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if not alive:
		super._physics_process(delta)
		return
	_think -= delta
	if following and is_instance_valid(following) and following.alive:
		var goal := following.global_position + follow_offset
		var d := goal - global_position
		d.y = 0
		if d.length() > 1.2:
			wish_dir = Vector2(d.x, d.z).normalized()
			want_jump = false
			if _think <= 0.0:
				_think = 0.5
				face_towards(following.global_position)
		else:
			wish_dir = Vector2.ZERO
		if global_position.distance_to(following.global_position) > 14.0:
			global_position = (
				following.global_position
				+ following.get_fire_direction() * -1.5
				+ Vector3(0, 0.2, 0)
			)
	else:
		wish_dir = Vector2.ZERO
	super._physics_process(delta)


func take_damage(
	_amount: float, _attacker: Node, _hitbox: String, _weapon_id: String, _penetrated: bool = false
) -> void:
	# Los rehenes no mueren: se pueden recuperar siempre.
	AudioBank.play_at("hostage_pain", self, global_position, -3.0, 1.0, 20.0)
