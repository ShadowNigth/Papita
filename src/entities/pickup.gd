extends Area3D
## Arma tirada en el suelo que puede recogerse caminando sobre ella.

class_name WeaponPickup

var weapon_id := ""
var mag := 0
var reserve := 0
var _model: Node3D
var _t := 0.0


func setup(id: String, ammo_mag: int, ammo_reserve: int) -> void:
	weapon_id = id
	mag = ammo_mag
	reserve = ammo_reserve


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	shape.shape = sphere
	shape.position = Vector3(0, 0.4, 0)
	add_child(shape)
	var def := Content.get_weapon(weapon_id)
	_model = WeaponModel.build(def)
	_model.scale = Vector3.ONE * 1.4
	_model.position = Vector3(0, 0.25, 0)
	add_child(_model)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.4)
	light.light_energy = 0.7
	light.omni_range = 2.5
	light.position = Vector3(0, 0.5, 0)
	add_child(light)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	if _model:
		_model.rotation.y += delta * 1.4
		_model.position.y = 0.25 + sin(_t * 2.0) * 0.05


func _on_body_entered(body: Node) -> void:
	if not body is Combatant:
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
			_consume()
			return
		c.give_weapon(weapon_id, c.primary_id == "")
		c._set_ammo(weapon_id, mag, reserve)
	elif slot == Content.SLOT_SECONDARY:
		c.give_weapon(weapon_id, c.secondary_id == "")
		c._set_ammo(weapon_id, mag, reserve)
	AudioBank.play_at("draw", self, global_position, -6.0, 1.0, 15.0)
	_consume()


func _consume() -> void:
	set_deferred("monitoring", false)
	queue_free()
