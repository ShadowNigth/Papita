extends Area3D
## Arma tirada en el suelo con fisica balistica estilo CS2 (rebote, giro y onda expansiva).

class_name WeaponPickup

var weapon_id := ""
var mag := 0
var reserve := 0
var velocity := Vector3.ZERO
var _spin := Vector3.ZERO
var _settled := false
var _pickup_delay := 0.32
var _model: Node3D


func setup(
	id: String, ammo_mag: int, ammo_reserve: int, initial_vel: Vector3 = Vector3.ZERO
) -> void:
	weapon_id = id
	mag = ammo_mag
	reserve = ammo_reserve
	velocity = initial_vel
	if velocity.length_squared() > 0.05:
		_spin = Vector3(randf_range(-5.0, 5.0), randf_range(-8.0, 8.0), randf_range(-4.0, 4.0))


func _ready() -> void:
	add_to_group("weapon_pickup")
	collision_layer = 0
	collision_mask = 4
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.05
	shape.shape = sphere
	shape.position = Vector3(0, 0.35, 0)
	add_child(shape)
	var def := Content.get_weapon(weapon_id)
	_model = WeaponModel.build(def, false)
	_model.scale = Vector3.ONE * 1.08
	_model.position = Vector3(0, 0.06, 0)
	_model.rotation.y = randf_range(0.0, TAU)
	add_child(_model)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _pickup_delay > 0.0:
		_pickup_delay = maxf(0.0, _pickup_delay - delta)
	if _settled:
		return
	velocity.y -= 17.5 * delta
	var step := velocity * delta
	if step.length_squared() > 0.00001:
		var space := get_world_3d().direct_space_state
		var rq := PhysicsRayQueryParameters3D.new()
		rq.from = global_position + Vector3(0.0, 0.14, 0.0)
		rq.to = rq.from + step + Vector3(0.0, -0.14 if velocity.y <= 0.0 else 0.08, 0.0)
		rq.collision_mask = 1
		var hit := space.intersect_ray(rq)
		if not hit.is_empty():
			var n: Vector3 = hit.normal
			global_position = hit.position + n * 0.04
			if n.y >= 0.65:
				if absf(velocity.y) > 2.2:
					velocity.y = -velocity.y * 0.28
					velocity.x *= 0.58
					velocity.z *= 0.58
					_spin *= 0.45
					AudioBank.play_at(
						"weapon_drop", get_parent(), global_position, -8.0, 1.05, 18.0
					)
				else:
					velocity.y = 0.0
					velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
					velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
					if Vector2(velocity.x, velocity.z).length() < 0.08:
						velocity = Vector3.ZERO
						_spin = Vector3.ZERO
						_settled = true
						if _model:
							_model.rotation.x = 0.0
							_model.rotation.z = 0.0
			else:
				velocity = velocity.bounce(n) * 0.45
		else:
			global_position += step
	if _model and not _settled:
		_model.rotation += _spin * delta
		_model.rotation.x = lerpf(_model.rotation.x, 0.0, delta * 3.0)
		_model.rotation.z = lerpf(_model.rotation.z, 0.0, delta * 3.0)
	if global_position.y < -75.0:
		queue_free()


## Impulso por onda expansiva de granada HE/C4 (como en CS2, las armas vuelan hacia ti).
func apply_blast(center: Vector3, radius: float, force: float = 16.0) -> void:
	var dist := global_position.distance_to(center)
	if dist > radius or dist < 0.01:
		return
	var falloff := clampf(1.0 - dist / radius, 0.15, 1.0)
	var dir := (global_position - center).normalized()
	velocity += (dir + Vector3(0.0, 0.72, 0.0)).normalized() * (force * falloff)
	_spin = Vector3(randf_range(-9.0, 9.0), randf_range(-11.0, 11.0), randf_range(-7.0, 7.0))
	_settled = false


func _on_body_entered(body: Node) -> void:
	if _pickup_delay > 0.0:
		return
	if not (body is Combatant):
		return
	var c := body as Combatant
	if not c.alive or c.is_hostage or c.is_zombie:
		return
	var def := Content.get_weapon(weapon_id)
	if def.is_empty():
		return
	var slot: int = int(def.get("slot", 1))
	if slot == Content.SLOT_GRENADE:
		if c.grenades.size() >= 4:
			return
		c.give_weapon(weapon_id, false)
		c.select_slot(Content.SLOT_GRENADE)
	elif slot == Content.SLOT_PRIMARY:
		if c.primary_id == weapon_id:
			c._set_ammo(weapon_id, mini(int(def.mag), mag + c.current_ammo().x), reserve)
			AudioBank.play_at("ammo", c, global_position, -4.0, 1.0, 16.0)
			_consume()
			return
		if c.primary_id != "":
			return
		c.give_weapon(weapon_id, true)
		c._set_ammo(weapon_id, mag, reserve)
	elif slot == Content.SLOT_SECONDARY:
		if c.secondary_id != "" and c.secondary_id != weapon_id:
			return
		c.give_weapon(weapon_id, c.primary_id == "")
		c._set_ammo(weapon_id, mag, reserve)
	AudioBank.play_at("pickup", c, global_position, -4.0, 1.0, 18.0)
	_consume()


func _consume() -> void:
	set_deferred("monitoring", false)
	queue_free()
