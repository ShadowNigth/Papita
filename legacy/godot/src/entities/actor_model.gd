extends Node3D
## ActorModel: soldados CT/T, rehenes y zombies con modelos .mdl originales de
## Counter-Strike 1.5 (urban, gsg9, sas, gign, terror, leet, arctic, guerilla, hostage),
## skinning en GPU, AnimationPlayer nativo en C++ y armas p_*.mdl en las manos.

class_name ActorModel

var team := 1
var is_zombie := false
var is_hostage_actor := false
var zombie_color := Color(0.4, 0.5, 0.35)
var body_scale := 1.0
var alive := true

var _mdl_root: Node3D
var _skeleton: Skeleton3D
var _anim_player: AnimationPlayer
var _r_hand: BoneAttachment3D
var _l_hand: BoneAttachment3D
var _r_weapon_mi: MeshInstance3D
var _l_weapon_mi: MeshInstance3D
var _label: Label3D
var _stand_y := 1.01
var _crouch_y := 0.50
var _cur_anim := ""
var _weapon_stance := "rifle"
var _variant_seed := 0


func setup(
	team_id: int,
	zombie: bool = false,
	z_color: Color = Color(0.4, 0.5, 0.35),
	s: float = 1.0,
	hostage_mode: bool = false,
	variant_seed: int = -1
) -> void:
	for child in get_children():
		child.queue_free()
	_mdl_root = null
	_skeleton = null
	_anim_player = null
	_r_hand = null
	_l_hand = null
	_r_weapon_mi = null
	_l_weapon_mi = null
	_cur_anim = ""

	team = team_id
	is_zombie = zombie
	is_hostage_actor = hostage_mode
	zombie_color = z_color
	body_scale = s
	alive = true
	scale = Vector3.ONE * s
	_variant_seed = absi(get_instance_id()) if variant_seed < 0 else variant_seed
	_build()


func _build() -> void:
	var built := MdlLoader.build_actor(
		team, is_zombie, is_hostage_actor, zombie_color, _variant_seed
	)
	if not built.is_empty():
		_mdl_root = built["root"]
		add_child(_mdl_root)
		_skeleton = built["skeleton"]
		_anim_player = built["anim_player"]
		_r_hand = built["r_hand"]
		_l_hand = built["l_hand"]
		_stand_y = float(built["stand_y"])
		_crouch_y = float(built["crouch_y"])
		if _r_hand != null:
			_r_weapon_mi = MeshInstance3D.new()
			_r_weapon_mi.name = "HeldWeaponR"
			_r_weapon_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_r_hand.add_child(_r_weapon_mi)
		if _l_hand != null:
			_l_weapon_mi = MeshInstance3D.new()
			_l_weapon_mi.name = "HeldWeaponL"
			_l_weapon_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_l_hand.add_child(_l_weapon_mi)
		_play_anim(_initial_anim_name())

	_label = Label3D.new()
	_label.text = ""
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.position = Vector3(0.0, 2.02, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.outline_size = 7
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	_label.visibility_range_end = 26.0
	_label.modulate = (Color(0.6, 0.85, 1.0) if team == Content.TEAM_CT else Color(1.0, 0.75, 0.4))
	if is_hostage_actor:
		_label.modulate = Color(0.55, 1.0, 0.65)
	if is_zombie:
		_label.visible = false
	add_child(_label)


func _initial_anim_name() -> String:
	if is_hostage_actor:
		return "idle"
	if is_zombie:
		return "zombie_idle"
	return "idle_rifle"


func _play_anim(anim_name: String, speed: float = 1.0) -> void:
	if _anim_player == null:
		return
	if not _anim_player.has_animation(anim_name):
		return
	if _cur_anim != anim_name:
		_cur_anim = anim_name
		_anim_player.play(anim_name, 0.12)
	if absf(_anim_player.speed_scale - speed) > 0.04:
		_anim_player.speed_scale = speed


func set_name_tag(text: String) -> void:
	if _label == null:
		return
	if is_zombie:
		_label.visible = false
		return
	_label.text = text


func equip(def: Dictionary) -> void:
	if is_zombie or is_hostage_actor:
		hide_weapon()
		return
	var wid := String(def.get("id", "knife"))
	var grp := MdlLoader.aim_group_for(wid)
	match grp:
		"onehanded", "grenade", "c4":
			_weapon_stance = "pistol"
		"knife":
			_weapon_stance = "knife"
		"dualpistols":
			_weapon_stance = "dual"
		_:
			_weapon_stance = "rifle"

	var held := MdlLoader.get_held_weapon_meshes(wid)
	if _r_weapon_mi != null:
		var rm: ArrayMesh = held.get("r_mesh", null)
		_r_weapon_mi.mesh = rm
		_r_weapon_mi.visible = rm != null
	if _l_weapon_mi != null:
		var lm: ArrayMesh = held.get("l_mesh", null)
		_l_weapon_mi.mesh = lm
		_l_weapon_mi.visible = lm != null


func hide_weapon() -> void:
	if _r_weapon_mi != null:
		_r_weapon_mi.visible = false
	if _l_weapon_mi != null:
		_l_weapon_mi.visible = false


func animate(velocity: Vector3, grounded: bool, _pitch: float, crouch: bool, delta: float) -> void:
	if not alive or _anim_player == null:
		return
	var planar := Vector2(velocity.x, velocity.z).length()

	if _skeleton != null and not is_hostage_actor:
		var target_y := _crouch_y if crouch else _stand_y
		_skeleton.position.y = lerpf(_skeleton.position.y, target_y, clampf(delta * 14.0, 0.0, 1.0))

	if is_hostage_actor:
		if crouch:
			_play_anim("crouch_idle", 1.0)
		elif planar > 3.2:
			_play_anim("run", clampf(planar / 4.8, 0.85, 1.35))
		elif planar > 0.4:
			_play_anim("walk", clampf(planar / 2.6, 0.8, 1.3))
		else:
			_play_anim("idle", 1.0)
		return

	if is_zombie:
		if planar > 3.0:
			_play_anim("zombie_run", clampf(planar / 5.0, 0.85, 1.45))
		elif planar > 0.35:
			_play_anim("zombie_walk", clampf(planar / 2.5, 0.85, 1.35))
		else:
			_play_anim("zombie_idle", 1.0)
		return

	if not grounded:
		_play_anim("jump", 1.0)
		return

	var stance_suffix := "_" + _weapon_stance
	if crouch:
		var c_suffix := "_pistol" if _weapon_stance == "pistol" else "_rifle"
		if planar > 0.5:
			_play_anim("crouch_run" + c_suffix, clampf(planar / 2.6, 0.8, 1.3))
		else:
			_play_anim("crouch_idle" + c_suffix, 1.0)
		return

	if planar > 3.2:
		_play_anim("run" + stance_suffix, clampf(planar / 5.2, 0.85, 1.3))
	elif planar > 0.45:
		var w_name := "walk" + stance_suffix
		if not _anim_player.has_animation(w_name):
			w_name = "run" + stance_suffix
		_play_anim(w_name, clampf(planar / 2.8, 0.75, 1.2))
	else:
		_play_anim("idle" + stance_suffix, 1.0)


func play_death(headshot: bool = false) -> void:
	alive = false
	hide_weapon()
	if _skeleton != null and not is_hostage_actor:
		_skeleton.position.y = _stand_y
	if _anim_player != null:
		var d_anim := "head" if (headshot and _anim_player.has_animation("head")) else "death1"
		if _anim_player.has_animation(d_anim):
			_cur_anim = d_anim
			_anim_player.speed_scale = 1.0
			_anim_player.play(d_anim, 0.06)
	if _label != null:
		_label.visible = false


func revive() -> void:
	alive = true
	if _skeleton != null and not is_hostage_actor:
		_skeleton.position.y = _stand_y
	if _label != null and not is_zombie:
		_label.visible = true
	_cur_anim = ""
	_play_anim(_initial_anim_name(), 1.0)
