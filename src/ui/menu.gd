extends Node3D
## Menu: portada 3D animada + flujo completo de navegacion.
##
## Pantallas: principal, modo de juego, seleccion de mapa, bando,
## arsenal con vista previa 3D, estadisticas, creditos y opciones.

class_name Menu

signal start_requested(map_id: String, mode: String, team: int, bots: int, difficulty: int)

const SKY_SHADER := preload("res://shaders/sky.gdshader")

var _ui: CanvasLayer
var _root: Control
var _screens: Dictionary = {}
var _current := ""
var _camera: Camera3D
var _showcase: Node3D
var _showcase_model: Node3D
var _preview_viewport: SubViewport
var _preview_holder: Node3D
var _preview_time := 0.0
var _t := 0.0
var _selected_mode := "bomb"
var _selected_map := "de_dust2"
var _selected_team := Content.TEAM_CT
var _selected_map_label: Label
var _mode_buttons: Array[Button] = []
var _arsenal_preview_label: Label
var _title_glow: ColorRect
var _flash: ColorRect


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_world()
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_root)
	_flash = ColorRect.new()
	_flash.color = Color(0, 0, 0, 1)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_flash)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.8)
	_build_main()
	_build_modes()
	_build_maps()
	_build_team()
	_build_arsenal()
	_build_stats()
	_build_credits()
	_show_screen("main")
	AudioBank.set_music("menu_music", 2.5)
	AudioBank.set_ambience("night", 3.0)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	sm.set_shader_parameter("top_color", Color(0.03, 0.05, 0.09))
	sm.set_shader_parameter("horizon_color", Color(0.22, 0.19, 0.14))
	sm.set_shader_parameter("ground_color", Color(0.04, 0.04, 0.03))
	sm.set_shader_parameter("sun_color", Color(0.85, 0.7, 0.45))
	sm.set_shader_parameter("star_strength", 0.8)
	sm.set_shader_parameter("cloud_strength", 0.25)
	sm.set_shader_parameter("haze", 0.5)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.36
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.08
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.volumetric_fog_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.22, 0.2, 0.16)
	env.fog_density = 0.008
	env.set_meta("volumetric_density", 0.016)
	env.set_meta("volumetric_color", Color(0.5, 0.42, 0.3))
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	we.add_to_group("world_environment")
	add_child(we)
	Settings.apply_environment(env)

	var cam := Camera3D.new()
	cam.fov = 52.0
	cam.position = Vector3(0, 1.7, 4.6)
	cam.current = true
	add_child(cam)
	_camera = cam

	var spot := SpotLight3D.new()
	spot.position = Vector3(0.4, 4.2, 2.6)
	spot.light_color = Color(1.0, 0.86, 0.62)
	spot.light_energy = 9.5
	spot.spot_range = 14.0
	spot.spot_angle = 36.0
	spot.spot_angle_attenuation = 0.8
	spot.shadow_enabled = false
	add_child(spot)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.6, 2.2, -1.4)
	rim.light_color = Color(0.35, 0.55, 1.0)
	rim.light_energy = 3.5
	rim.omni_range = 9.0
	add_child(rim)
	var warm := OmniLight3D.new()
	warm.position = Vector3(3.0, 1.5, 1.0)
	warm.light_color = Color(1.0, 0.45, 0.2)
	warm.light_energy = 2.0
	warm.omni_range = 7.0
	add_child(warm)

	# Suelo y muros del "bunker".
	var floor_mat := MaterialLib.surface("concrete", "industrial", 0)
	var floor_mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(22, 0.4, 22)
	floor_mesh.mesh = cube
	floor_mesh.position = Vector3(0, -0.2, 0)
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)
	var wall_mat := MaterialLib.surface("brick", "industrial", 1)
	for i in 3:
		var wall := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(22, 6, 0.4)
		wall.mesh = bm
		wall.material_override = wall_mat
		wall.position = Vector3(0, 3.0, -3.0 - i * 0.01)
		add_child(wall)
	for side in [-1.0, 1.0]:
		var side_wall := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(0.4, 6, 16)
		side_wall.mesh = bm2
		side_wall.material_override = wall_mat
		side_wall.position = Vector3(side * 7.0, 3.0, 2.0)
		add_child(side_wall)
	# Cajas y props.
	var props := Node3D.new()
	props.position = Vector3(0, 0, -1.6)
	add_child(props)
	for i in 4:
		var crate := PropLib.crate("industrial", 0.9)
		crate.position = Vector3(-3.2 + i * 0.95, 0, 0.2 + (i % 2) * 0.6)
		crate.rotation_degrees.y = i * 17.0
		props.add_child(crate)
	var barrels := PropLib.barrels("industrial", 2)
	barrels.position = Vector3(2.7, 0, -0.4)
	props.add_child(barrels)
	var pallet := PropLib.pallet("industrial")
	pallet.position = Vector3(-1.2, 0, 1.6)
	props.add_child(pallet)
	var rubble := PropLib.rubble("industrial", 7)
	rubble.position = Vector3(3.6, 0, 1.2)
	props.add_child(rubble)

	# Pedestal con el arma girando.
	_showcase = Node3D.new()
	_showcase.position = Vector3(0.6, 0.0, 0.6)
	add_child(_showcase)
	var pedestal := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.9
	cyl.height = 0.55
	pedestal.mesh = cyl
	pedestal.position = Vector3(0, 0.27, 0)
	pedestal.material_override = MaterialLib.surface("metal", "industrial", 2)
	_showcase.add_child(pedestal)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.7
	torus.outer_radius = 0.78
	ring.mesh = torus
	ring.position = Vector3(0, 0.56, 0)
	ring.material_override = MaterialLib.emissive(Color(0.9, 0.72, 0.3), 2.4)
	_showcase.add_child(ring)
	_update_showcase("ak47")

	# Operadores originales de CS 1.5 escoltando el pedestal en el menu principal.
	var ct_guard := ActorModel.new()
	ct_guard.position = Vector3(-0.75, 0.0, 0.15)
	ct_guard.rotation_degrees = Vector3(0.0, 152.0, 0.0)
	add_child(ct_guard)
	ct_guard.setup(Content.TEAM_CT, false, Color.WHITE, 1.0, false, 0)
	ct_guard.equip(Content.get_weapon("m4a1"))

	var t_guard := ActorModel.new()
	t_guard.position = Vector3(2.05, 0.0, 0.05)
	t_guard.rotation_degrees = Vector3(0.0, -148.0, 0.0)
	add_child(t_guard)
	t_guard.setup(Content.TEAM_T, false, Color.WHITE, 1.0, false, 1)
	t_guard.equip(Content.get_weapon("ak47"))

	# Particulas de polvo ligeras.
	var dust := GPUParticles3D.new()
	dust.amount = 42
	dust.lifetime = 12.0
	dust.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))
	dust.position = Vector3(0, 2.5, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(6, 2.5, 5)
	pm.direction = Vector3(0, 0.2, 0)
	pm.spread = 60.0
	pm.gravity = Vector3(0, 0.03, 0)
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.28
	pm.scale_min = 0.01
	pm.scale_max = 0.045
	pm.color = Color(1.0, 0.9, 0.7, 0.8)
	dust.process_material = pm
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = MaterialLib.spark_texture(24)
	mat.albedo_color = Color(1.0, 0.9, 0.7)
	quad.material = mat
	dust.draw_pass_1 = quad
	add_child(dust)


func _update_showcase(id: String) -> void:
	if _showcase_model and is_instance_valid(_showcase_model):
		_showcase_model.queue_free()
	var def := Content.get_weapon(id)
	_showcase_model = WeaponModel.build(def)
	_showcase_model.scale = Vector3.ONE * 1.9
	_showcase_model.position = Vector3(0, 1.15, 0)
	_showcase_model.rotation_degrees = Vector3(0, 0, -8)
	_showcase.add_child(_showcase_model)


func _process(delta: float) -> void:
	_t += delta
	if _showcase:
		_showcase.rotation.y += delta * 0.45
		_showcase.position.y = sin(_t * 0.9) * 0.05
	if _camera:
		_camera.position.x = lerpf(_camera.position.x, sin(_t * 0.22) * 0.5, delta * 0.6)
		_camera.position.y = 1.7 + sin(_t * 0.35) * 0.06
		_camera.look_at(Vector3(0.3, 1.1, 0), Vector3.UP)
	if _preview_holder:
		_preview_holder.rotation.y += delta * 0.7
	if _title_glow:
		_title_glow.color.a = 0.06 + sin(_t * 1.4) * 0.03


# --- Infraestructura de pantallas ---------------------------------------------


func _new_screen(id: String) -> Control:
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	_root.add_child(screen)
	_screens[id] = screen
	return screen


func _show_screen(id: String) -> void:
	for key in _screens.keys():
		(_screens[key] as Control).visible = key == id
	_current = id
	if _preview_viewport:
		_preview_viewport.render_target_update_mode = (
			SubViewport.UPDATE_WHEN_VISIBLE if id == "arsenal" else SubViewport.UPDATE_DISABLED
		)
	AudioBank.play_ui("ui_click", -6.0)
	if id == "arsenal":
		_refresh_arsenal()
	if id == "stats":
		_refresh_stats()
	if id == "maps":
		_refresh_maps()


func _back_button(parent: Control, target: String = "main") -> void:
	var b := UITheme.button("< VOLVER", 150, 14)
	b.set_anchors_preset(Control.PRESET_TOP_LEFT)
	b.position = Vector2(36, 30)
	b.pressed.connect(func() -> void: _show_screen(target))
	parent.add_child(b)


func _vignette(parent: Control) -> void:
	_title_glow = ColorRect.new()
	_title_glow.color = Color(0.8, 0.65, 0.25, 0.07)
	_title_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_title_glow)


# --- Pantalla principal --------------------------------------------------------


func _build_main() -> void:
	var screen := _new_screen("main")
	_vignette(screen)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.01, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(shade)
	var left := VBoxContainer.new()
	left.position = Vector2(84, 90)
	left.custom_minimum_size = Vector2(620, 0)
	left.add_theme_constant_override("separation", 4)
	screen.add_child(left)
	var kicker := UITheme.label(
		"// PROYECTO PERSONAL - RECOMPILACION EN GODOT 4", 13, UITheme.ACCENT_DIM, true
	)
	left.add_child(kicker)
	var title := Label.new()
	title.text = "PAPITA"
	title.add_theme_font_override("font", UITheme.FONT_BOLD)
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	left.add_child(title)
	var sub := UITheme.label("COUNTER-STRIKE 1.5 REFORGED", 30, UITheme.TEXT, true)
	left.add_child(sub)
	var tag_text := "Armas, economia, rehenes, C4, bots, modo zombie, 10 mapas\n"
	tag_text += "y materiales PBR con iluminacion avanzada. Todo procedural."
	var tag := UITheme.label(tag_text, 14, UITheme.TEXT_DIM)
	left.add_child(tag)
	UITheme.spacer(left, 26)
	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size = Vector2(360, 0)
	buttons.add_theme_constant_override("separation", 8)
	left.add_child(buttons)
	_menu_button(buttons, "JUGAR", "main_play", func() -> void: _show_screen("modes"))
	_menu_button(
		buttons,
		"MODO ZOMBIE",
		"main_zombie",
		func() -> void:
			_selected_mode = "zombie"
			_show_screen("maps")
	)
	_menu_button(buttons, "ARSENAL", "main_arsenal", func() -> void: _show_screen("arsenal"))
	_menu_button(buttons, "OPCIONES", "main_options", _open_options)
	_menu_button(buttons, "ESTADISTICAS", "main_stats", func() -> void: _show_screen("stats"))
	_menu_button(buttons, "CREDITOS", "main_credits", func() -> void: _show_screen("credits"))
	_menu_button(
		buttons,
		"SALIR",
		"main_quit",
		func() -> void:
			Settings.flush()
			get_tree().quit()
	)
	var foot := UITheme.label(
		"Hecho para jugar sin conexion.  v1.0.0  -  Godot 4.4", 11, UITheme.TEXT_DIM, true
	)
	foot.position = Vector2(84, 0)
	screen.add_child(foot)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(84, -46)
	var profile := UITheme.label("", 12, UITheme.ACCENT_DIM, true)
	profile.name = "ProfileLabel"
	screen.add_child(profile)
	profile.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	profile.position = Vector2(-420, -46)
	profile.size = Vector2(380, 20)
	profile.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	profile.text = (
		"%s  //  %s  //  %d bajas"
		% [
			Settings.data.profile.get("name", "Papita"),
			Content.rank_for_kills(int(Settings.data.progress.get("kills", 0))),
			int(Settings.data.progress.get("kills", 0)),
		]
	)


func _menu_button(parent: VBoxContainer, text: String, id: String, action: Callable) -> Button:
	var b := UITheme.button(text, 340, 18)
	b.name = id
	b.pressed.connect(
		func() -> void:
			AudioBank.play_ui("ui_click")
			action.call()
	)
	b.mouse_entered.connect(func() -> void: AudioBank.play_ui("ui_hover", -14.0))
	parent.add_child(b)
	return b


# --- Seleccion de modo --------------------------------------------------------


func _build_modes() -> void:
	var screen := _new_screen("modes")
	_back_button(screen)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.01, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.position = Vector2(-680, -260)
	center.custom_minimum_size = Vector2(1360, 520)
	center.add_theme_constant_override("separation", 14)
	screen.add_child(center)
	var title := UITheme.title("SELECCIONA UN MODO DE JUEGO", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(row)
	var modes := [
		{
			"id": "bomb",
			"title": "BOMBEO",
			"sub": "C4 / OBJETIVOS",
			"desc":
			"Terroristas plantan el C4, CT lo desactiva.\nEconomia completa, rondas y compra de armas.",
			"maps": "6 mapas",
			"color": UITheme.ORANGE,
		},
		{
			"id": "hostage",
			"title": "REHENES",
			"sub": "RESCATE",
			"desc": "Los CT deben liberar y escoltar a los rehenes\nhasta la zona de rescate.",
			"maps": "2 mapas",
			"color": UITheme.CT,
		},
		{
			"id": "deathmatch",
			"title": "DEATHMATCH",
			"sub": "RESPAWNS DINAMICOS",
			"desc":
			"Accion continua sin rondas: cada vez que\nmueres reapareces en otro punto del mapa.",
			"maps": "8 mapas",
			"color": Color(0.95, 0.42, 0.32),
		},
		{
			"id": "zombie",
			"title": "ZOMBIE",
			"sub": "SUPERVIVENCIA",
			"desc": "Oleadas infinitas, puntos, perks y caja\nmisteriosa. Con bots aliados.",
			"maps": "2 mapas",
			"color": Color(0.62, 0.38, 0.85),
		},
	]
	_mode_buttons.clear()
	for m in modes:
		var card := Button.new()
		card.custom_minimum_size = Vector2(316, 330)
		card.add_theme_stylebox_override(
			"normal", _mode_style(Color(0.05, 0.06, 0.05, 0.94), Color(0.3, 0.28, 0.17))
		)
		card.add_theme_stylebox_override(
			"hover", _mode_style(Color(0.1, 0.12, 0.08, 0.98), m.color)
		)
		card.add_theme_stylebox_override(
			"pressed", _mode_style(Color(0.16, 0.16, 0.1, 1.0), m.color)
		)
		row.add_child(card)
		_mode_buttons.append(card)
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.position = Vector2(22, 22)
		vb.size = Vector2(276, 286)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 8)
		card.add_child(vb)
		var t := UITheme.label(String(m.title), 30, m.color, true)
		vb.add_child(t)
		vb.add_child(UITheme.label(String(m.sub), 13, UITheme.ACCENT_DIM, true))
		UITheme.hsep(vb, Color(0.35, 0.32, 0.2))
		var d := UITheme.label(String(m.desc), 13, UITheme.TEXT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(d)
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_child(sp)
		vb.add_child(UITheme.label(String(m.maps), 12, UITheme.TEXT_DIM, true))
		card.pressed.connect(
			func() -> void:
				_selected_mode = String(m.id)
				AudioBank.play_ui("ui_click")
				_show_screen("maps")
		)
	var note_text := "El modo zombie incluye 3 aliados bot. Los modos clasicos usan "
	note_text += "la cantidad de bots configurada."
	var note := UITheme.label(note_text, 12, UITheme.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(note)


func _mode_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = 4
	s.border_color = border
	s.content_margin_left = 8
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_right = 3
	return s


# --- Seleccion de mapa ---------------------------------------------------------


func _build_maps() -> void:
	var screen := _new_screen("maps")
	_back_button(screen, "modes")
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.01, 0.76)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
	var vb := VBoxContainer.new()
	vb.position = Vector2(70, 80)
	vb.custom_minimum_size = Vector2(1460, 760)
	vb.add_theme_constant_override("separation", 10)
	screen.add_child(vb)
	var head := HBoxContainer.new()
	head.add_child(UITheme.title("SELECCIONA UN MAPA", 30))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_selected_map_label = UITheme.label("", 14, UITheme.ACCENT, true)
	head.add_child(_selected_map_label)
	vb.add_child(head)
	var map_note := "Los mapas se reconstruyen proceduralmente con su ambiente, props y navegacion de bots."
	vb.add_child(UITheme.label(map_note, 12, UITheme.TEXT_DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(1440, 560)
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "MapGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	footer.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(footer)
	var next := UITheme.button("CONTINUAR >", 260, 18)
	next.pressed.connect(
		func() -> void:
			if _selected_mode == "zombie":
				_start(_selected_map, "zombie", Content.TEAM_CT)
			else:
				_show_screen("team")
	)
	footer.add_child(next)


func _refresh_maps() -> void:
	var grid := _screens.maps.find_child("MapGrid", true, false) as GridContainer
	if grid == null:
		return
	for c in grid.get_children():
		c.queue_free()
	var list := Content.maps_for_mode(_selected_mode)
	if list.is_empty():
		list = Content.MAPS
	for m in list:
		grid.add_child(_map_card(m))
	for m in list:
		if _selected_map == m.id:
			_selected_map_label.text = "SELECCIONADO: " + String(m.label).to_upper()
	if (
		_selected_map_label
		and not list.any(func(x): return x.id == _selected_map)
		and not list.is_empty()
	):
		_selected_map = String(list[0].id)
		_selected_map_label.text = "SELECCIONADO: " + String(list[0].label).to_upper()


func _map_card(m: Dictionary) -> Control:
	var selected := String(m.id) == _selected_map
	var card := Button.new()
	card.custom_minimum_size = Vector2(348, 210)
	var border: Color = UITheme.ACCENT if selected else Color(0.3, 0.28, 0.17)
	card.add_theme_stylebox_override(
		"normal",
		_mode_style(
			Color(0.05, 0.06, 0.05, 0.95) if not selected else Color(0.12, 0.13, 0.07, 0.98), border
		)
	)
	card.add_theme_stylebox_override(
		"hover", _mode_style(Color(0.1, 0.12, 0.08, 0.98), UITheme.ACCENT)
	)
	card.add_theme_stylebox_override(
		"pressed", _mode_style(Color(0.16, 0.16, 0.1, 1.0), UITheme.ACCENT)
	)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.position = Vector2(16, 14)
	vb.size = Vector2(316, 182)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	var top := HBoxContainer.new()
	top.add_child(
		UITheme.label(
			String(m.label).to_upper(), 22, UITheme.ACCENT if selected else UITheme.TEXT, true
		)
	)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var mode_label := "C4" if m.mode == "bomb" else ("REHENES" if m.mode == "hostage" else "ZOMBIE")
	var badge := UITheme.label(mode_label, 11, UITheme.TEXT_DIM, true)
	top.add_child(badge)
	vb.add_child(top)
	var desc := UITheme.label(String(m.desc), 12, UITheme.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)
	var tags := ""
	for t in m.get("tags", []):
		tags += "#%s  " % t
	vb.add_child(UITheme.label(tags, 11, UITheme.ACCENT_DIM, true))
	card.pressed.connect(
		func() -> void:
			_selected_map = String(m.id)
			AudioBank.play_ui("ui_click")
			_refresh_maps()
	)
	return card


# --- Seleccion de bando -------------------------------------------------------


func _build_team() -> void:
	var screen := _new_screen("team")
	_back_button(screen, "maps")
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.01, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.position = Vector2(-480, -280)
	center.custom_minimum_size = Vector2(960, 560)
	center.add_theme_constant_override("separation", 14)
	screen.add_child(center)
	var title := UITheme.title("ELIGE TU BANDO", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(row)
	for team_info in [
		{
			"team": Content.TEAM_CT,
			"name": "ANTITERRORISTAS",
			"color": UITheme.CT,
			"desc": "Desactiva el C4 o rescata rehenes.\nUSP, M4A1, AWP, kit de desactivacion.",
		},
		{
			"team": Content.TEAM_T,
			"name": "TERRORISTAS",
			"color": UITheme.T,
			"desc": "Planta el C4 y defiende los sitios.\nGlock, AK-47, cuchillo rapido.",
		},
	]:
		var card := Button.new()
		card.custom_minimum_size = Vector2(360, 250)
		card.add_theme_stylebox_override(
			"normal", _mode_style(Color(0.05, 0.06, 0.05, 0.95), Color(0.3, 0.28, 0.17))
		)
		card.add_theme_stylebox_override(
			"hover", _mode_style(Color(0.1, 0.12, 0.1, 0.98), team_info.color)
		)
		card.add_theme_stylebox_override(
			"pressed", _mode_style(Color(0.16, 0.17, 0.12, 1.0), team_info.color)
		)
		row.add_child(card)
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.position = Vector2(22, 20)
		vb.size = Vector2(316, 210)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 8)
		card.add_child(vb)
		var t := UITheme.label(String(team_info.name), 24, team_info.color, true)
		vb.add_child(t)
		UITheme.hsep(vb, Color(0.35, 0.32, 0.2))
		var d := UITheme.label(String(team_info.desc), 13, UITheme.TEXT)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(d)
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_child(sp)
		vb.add_child(UITheme.label("CLIC PARA ELEGIR", 11, UITheme.TEXT_DIM, true))
		card.pressed.connect(
			func() -> void:
				_selected_team = int(team_info.team)
				AudioBank.play_ui("ui_click")
				_start(_selected_map, _selected_mode, _selected_team)
		)
	var summary := UITheme.label("", 13, UITheme.TEXT_DIM, true)
	summary.name = "Summary"
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(summary)
	var random := UITheme.button("BANDO ALEATORIO", 300, 15)
	random.pressed.connect(
		func() -> void:
			_selected_team = [Content.TEAM_CT, Content.TEAM_T][randi() % 2]
			_start(_selected_map, _selected_mode, _selected_team)
	)
	var rrow := HBoxContainer.new()
	rrow.alignment = BoxContainer.ALIGNMENT_CENTER
	rrow.add_child(random)
	center.add_child(rrow)


func _refresh_team_summary() -> void:
	var summary := _screens.team.find_child("Summary", true, false) as Label
	if summary == null:
		return
	summary.text = (
		"%s  -  %d bots  -  dificultad %s"
		% [
			Content.map_by_id(_selected_map).get("label", _selected_map),
			int(Settings.data.gameplay.get("bots", 7)),
			Content.difficulty(int(Settings.data.gameplay.get("difficulty", 2))).name,
		]
	)


# --- Arsenal -------------------------------------------------------------------


func _build_arsenal() -> void:
	var screen := _new_screen("arsenal")
	_back_button(screen)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.01, 0.8)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
	var root := HBoxContainer.new()
	root.position = Vector2(60, 90)
	root.custom_minimum_size = Vector2(1480, 760)
	root.add_theme_constant_override("separation", 26)
	screen.add_child(root)
	# Lista de armas.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)
	left.add_child(UITheme.title("ARSENAL", 30))
	left.add_child(
		UITheme.label(
			"Todas las armas del juego, con estadisticas reales del codigo.", 12, UITheme.TEXT_DIM
		)
	)
	UITheme.hsep(left)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "WeaponList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	# Vista previa 3D y detalle.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	var preview := SubViewportContainer.new()
	preview.custom_minimum_size = Vector2(0, 380)
	preview.stretch = true
	right.add_child(preview)
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	preview.add_child(vp)
	_preview_viewport = vp
	_build_preview_world(vp)
	var info := VBoxContainer.new()
	info.name = "WeaponInfo"
	info.add_theme_constant_override("separation", 6)
	right.add_child(info)
	_arsenal_preview_label = UITheme.label("", 12, UITheme.TEXT_DIM, true)
	right.add_child(_arsenal_preview_label)


func _build_preview_world(vp: SubViewport) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.5)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = false
	env.ssao_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.2, 2.2)
	cam.fov = 42.0
	cam.current = true
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.0, 0), Vector3.UP)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.0
	key.light_color = Color(1.0, 0.94, 0.86)
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.shadow_enabled = false
	vp.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.4, 0.8, 1.4)
	fill.light_color = Color(0.45, 0.6, 1.0)
	fill.light_energy = 2.4
	fill.omni_range = 6.0
	vp.add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.2, -0.4, -1.6)
	rim.light_color = Color(1.0, 0.55, 0.25)
	rim.light_energy = 3.0
	rim.omni_range = 6.0
	vp.add_child(rim)
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	plane.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.08, 0.07)
	mat.roughness = 0.35
	mat.metallic = 0.2
	plane.material_override = mat
	plane.position = Vector3(0, -0.7, 0)
	vp.add_child(plane)
	_preview_holder = Node3D.new()
	vp.add_child(_preview_holder)


func _refresh_arsenal() -> void:
	var list := _screens.arsenal.find_child("WeaponList", true, false) as VBoxContainer
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	var classes := ["pistol", "smg", "rifle", "sniper", "shotgun", "lmg", "grenade", "knife", "c4"]
	var titles := {
		"pistol": "PISTOLAS",
		"smg": "SUBFUSILES",
		"rifle": "FUSILES",
		"sniper": "FRANCOTIRADORES",
		"shotgun": "ESCOPETAS",
		"lmg": "AMETRALLADORAS",
		"grenade": "GRANADAS",
		"knife": "CUERPO A CUERPO",
		"c4": "EXPLOSIVOS",
	}
	for cls in classes:
		var header := UITheme.label(String(titles[cls]), 13, UITheme.ACCENT_DIM, true)
		list.add_child(header)
		for id in Content.WEAPONS.keys():
			var w: Dictionary = Content.WEAPONS[id]
			if String(w.cls) != cls:
				continue
			var b := UITheme.button("%s   $%d" % [String(w.name), int(w.price)], 0, 14)
			b.custom_minimum_size = Vector2(0, 32)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(func() -> void: _select_weapon(id))
			list.add_child(b)
	_select_weapon("ak47")


func _select_weapon(id: String) -> void:
	var def := Content.get_weapon(id)
	if def.is_empty():
		return
	if _preview_holder:
		for c in _preview_holder.get_children():
			c.queue_free()
		var model := WeaponModel.build(def)
		model.scale = Vector3.ONE * 2.4
		model.position = Vector3(0, 0.0, 0)
		_preview_holder.add_child(model)
		_update_showcase(id)
	var info := _screens.arsenal.find_child("WeaponInfo", true, false) as VBoxContainer
	if info == null:
		return
	for c in info.get_children():
		c.queue_free()
	var title := HBoxContainer.new()
	var name_label := UITheme.label(String(def.name).to_upper(), 26, UITheme.ACCENT, true)
	title.add_child(name_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(sp)
	title.add_child(UITheme.label(UITheme.weapon_icon(def), 12, UITheme.TEXT_DIM, true))
	info.add_child(title)
	var desc := UITheme.label(String(def.get("desc", "")), 13, UITheme.TEXT_DIM)
	info.add_child(desc)
	UITheme.hsep(info)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	info.add_child(grid)
	var stats := [
		["DANO", float(def.get("damage", 0)) * float(def.get("pellets", 1))],
		["CADENCIA", float(def.get("rpm", 0))],
		["CARGADOR", float(def.get("mag", 1))],
		["RETROCESO", float(def.get("recoil", 0)) * 2.0],
		["PRECISION", 100.0 - float(def.get("spread", 0.5)) * 40.0],
		["ALCANCE", float(def.get("range", 40.0))],
		["PENETRACION", float(def.get("penetration", 1))],
		["PRECIO", float(def.get("price", 0))],
	]
	for s in stats:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(210, 0)
		col.add_child(UITheme.label(String(s[0]), 10, UITheme.TEXT_DIM, true))
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = _stat_max(String(s[0]))
		bar.value = minf(float(s[1]), bar.max_value)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(200, 10)
		col.add_child(bar)
		var val := UITheme.label(_stat_text(String(s[0]), float(s[1])), 12, UITheme.TEXT, true)
		col.add_child(val)
		grid.add_child(col)
	var extra := ""
	if def.has("pellets"):
		extra += "Peregrinos: %d balas por disparo.  " % int(def.pellets)
	if def.get("auto", false):
		extra += "Automatica.  "
	if int(def.get("burst", 0)) > 0:
		extra += "Rafaga de %d.  " % int(def.burst)
	if float(def.get("zoom", 0.0)) > 0.0:
		extra += "Zoom %.1fx.  " % float(def.zoom)
	if def.get("silencer", false):
		extra += "Silenciador disponible.  "
	info.add_child(UITheme.label(extra, 12, UITheme.ACCENT_DIM))
	_arsenal_preview_label.text = (
		"Vista previa 3D generada proceduralmente - %d armas en total" % Content.WEAPONS.size()
	)


func _stat_max(stat: String) -> float:
	match stat:
		"DANO":
			return 120.0
		"CADENCIA":
			return 900.0
		"CARGADOR":
			return 100.0
		"RETROCESO":
			return 8.0
		"PRECISION":
			return 100.0
		"ALCANCE":
			return 150.0
		"PENETRACION":
			return 4.0
		"PRECIO":
			return 6000.0
	return 100.0


func _stat_text(stat: String, value: float) -> String:
	match stat:
		"CADENCIA":
			return "%d RPM" % int(value)
		"PRECIO":
			return "$%d" % int(value)
		"ALCANCE":
			return "%d m" % int(value)
		"RETROCESO":
			return "%0.1f" % (value / 2.0)
	return "%d" % int(value)


# --- Estadisticas -------------------------------------------------------------


func _build_stats() -> void:
	var screen := _new_screen("stats")
	_back_button(screen)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.01, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
	var panel := UITheme.panel()
	panel.position = Vector2(120, 80)
	panel.custom_minimum_size = Vector2(1360, 760)
	screen.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	head.add_child(UITheme.title("ESTADISTICAS DEL PERFIL", 28))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var name_edit := LineEdit.new()
	name_edit.text = String(Settings.data.profile.get("name", "Papita"))
	name_edit.custom_minimum_size = Vector2(240, 36)
	name_edit.placeholder_text = "Nombre de jugador"
	head.add_child(name_edit)
	var save := UITheme.button("GUARDAR", 130, 14)
	save.pressed.connect(
		func() -> void:
			Settings.set_value("profile", "name", name_edit.text.strip_edges())
			Settings.flush()
			_toast_refresh()
			AudioBank.play_ui("buy")
	)
	head.add_child(save)
	vb.add_child(head)
	UITheme.hsep(vb)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	vb.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	var progress: Dictionary = Settings.data.progress
	var rows := [
		["Rango", Content.rank_for_kills(int(progress.get("kills", 0)))],
		["Bajas totales", "%d" % int(progress.get("kills", 0))],
		["Tiros a la cabeza", "%d" % int(progress.get("headshots", 0))],
		["Partidas jugadas", "%d" % int(progress.get("matches", 0))],
		["Rondas ganadas", "%d" % int(progress.get("wins", 0))],
		["Precision global", "%.1f%%" % _accuracy(progress)],
		["Record de oleadas", "%d" % int(progress.get("zombie_best_wave", 0))],
		["Zombies eliminados", "%d" % int(progress.get("zombie_kills", 0))],
		["Tiempo jugado", _playtime(float(progress.get("play_time", 0.0)))],
	]
	for r in rows:
		var row := HBoxContainer.new()
		var a := UITheme.label(String(r[0]), 15, UITheme.TEXT_DIM)
		a.custom_minimum_size = Vector2(320, 0)
		row.add_child(a)
		row.add_child(UITheme.label(String(r[1]), 16, UITheme.ACCENT, true))
		left.add_child(row)
	UITheme.hsep(left)
	left.add_child(UITheme.label("LOGROS", 14, UITheme.ACCENT_DIM, true))
	var unlocked: Array = progress.get("achievements", [])
	for id in Content.ACHIEVEMENTS.keys():
		var info: Dictionary = Content.ACHIEVEMENTS[id]
		var got := unlocked.has(id)
		var row := HBoxContainer.new()
		var mark := UITheme.label(
			" [X] " if got else " [ ] ", 14, UITheme.GREEN if got else UITheme.TEXT_DIM, true
		)
		row.add_child(mark)
		var t := UITheme.label(
			"%s - %s" % [String(info.name), String(info.desc)],
			13,
			UITheme.TEXT if got else UITheme.TEXT_DIM
		)
		row.add_child(t)
		left.add_child(row)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	cols.add_child(right)
	right.add_child(UITheme.label("PROGRESO DE RANGO", 13, UITheme.ACCENT_DIM, true))
	var kills := int(progress.get("kills", 0))
	var next_rank := 1
	for entry in Content.RANKS:
		if kills < int(entry[0]):
			next_rank = int(entry[0])
			break
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = maxf(float(next_rank), 1.0)
	bar.value = float(kills)
	bar.custom_minimum_size = Vector2(0, 26)
	bar.show_percentage = false
	right.add_child(bar)
	right.add_child(
		UITheme.label(
			"%d / %d bajas para el siguiente rango" % [kills, next_rank], 12, UITheme.TEXT_DIM
		)
	)
	UITheme.spacer(right, 10)
	right.add_child(UITheme.label("PERFIL", 13, UITheme.ACCENT_DIM, true))
	var profile_group := VBoxContainer.new()
	right.add_child(profile_group)
	var name_row := HBoxContainer.new()
	name_row.add_child(UITheme.label("Nombre:", 13, UITheme.TEXT_DIM))
	name_row.add_child(
		UITheme.label(String(Settings.data.profile.get("name", "Papita")), 14, UITheme.TEXT, true)
	)
	profile_group.add_child(name_row)
	profile_group.add_child(
		UITheme.label(
			"Los logros y el progreso se guardan en user://settings.cfg", 11, UITheme.TEXT_DIM
		)
	)
	var reset := UITheme.button("BORRAR PROGRESO", 260, 13)
	reset.pressed.connect(
		func() -> void:
			Settings.reset_section("progress")
			_refresh_stats()
			_toast_refresh()
	)
	right.add_child(reset)


func _accuracy(progress: Dictionary) -> float:
	var shots := float(progress.get("accuracy_shots", 0))
	var hits := float(progress.get("accuracy_hits", 0))
	if shots <= 0.0:
		return 0.0
	return clampf(hits / shots * 100.0, 0.0, 100.0)


func _playtime(seconds: float) -> String:
	var s := int(seconds)
	return "%dh %02dm" % [s / 3600, (s % 3600) / 60]


func _refresh_stats() -> void:
	# Reconstruye la pantalla para reflejar cambios.
	if _screens.has("stats"):
		var old: Control = _screens.stats
		_screens.erase("stats")
		old.queue_free()
		_build_stats()
		(_screens.stats as Control).visible = true


func _toast_refresh() -> void:
	var profile := _screens.main.find_child("ProfileLabel", true, false) as Label
	if profile:
		profile.text = (
			"%s  //  %s  //  %d bajas"
			% [
				Settings.data.profile.get("name", "Papita"),
				Content.rank_for_kills(int(Settings.data.progress.get("kills", 0))),
				int(Settings.data.progress.get("kills", 0)),
			]
		)


# --- Creditos y opciones ------------------------------------------------------


func _build_credits() -> void:
	var screen := _new_screen("credits")
	_back_button(screen)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.01, 0.8)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
	var panel := UITheme.panel()
	panel.position = Vector2(240, 110)
	panel.custom_minimum_size = Vector2(1120, 680)
	screen.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(UITheme.title("CREDITOS", 32))
	vb.add_child(UITheme.label("PAPITA: COUNTER-STRIKE 1.5 REFORGED", 18, UITheme.TEXT, true))
	UITheme.hsep(vb)
	var lines := [
		[
			"Proyecto personal",
			"Recreacion jugable del clasico Counter-Strike 1.5 en Godot 4.4. Sin distribucion publica."
		],
		[
			"Codigo y diseno",
			"Reimplementacion original: movimiento, balistica, economia, IA, objetivos y modo zombie."
		],
		[
			"Arte",
			"Todo el arte 3D es procedural: no se usan modelos, texturas ni sonidos de terceros."
		],
		[
			"Texturas PBR",
			"Generadas en tiempo de ejecucion (albedo + normal + ORM) con ruido celular y Worley."
		],
		[
			"Sonido",
			"Sintesis DSP propia para disparos, recargas, pasos, explosiones, zombies y musica."
		],
		["Iluminacion", "Sky shader, SSAO, SSIL, SSR, niebla volumetrica, bloom y sombras suaves."],
		[
			"Mapas",
			"Layouts originales inspirados en los clasicos: Dust II, Inferno, Aztec, Nuke, Train, Office, Italy, Dust."
		],
		[
			"Agradecimientos",
			"A Valve y al equipo original de Counter-Strike. Este proyecto es un homenaje privado."
		],
		["Aviso", "Counter-Strike es una marca de Valve. Este juego no se distribuye ni se vende."],
	]
	for l in lines:
		var row := VBoxContainer.new()
		row.add_child(UITheme.label(String(l[0]), 13, UITheme.ACCENT, true))
		var body := UITheme.label(String(l[1]), 14, UITheme.TEXT)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(1040, 0)
		row.add_child(body)
		vb.add_child(row)
	UITheme.hsep(vb)
	vb.add_child(UITheme.label("Godot 4.4  -  Forward+  -  v1.0.0", 12, UITheme.TEXT_DIM, true))


func _open_options() -> void:
	var opts := OptionsPanel.new()
	_root.add_child(opts)
	opts.setup()
	opts.closed.connect(
		func() -> void:
			AudioBank.play_ui("ui_hover")
			_update_showcase_visibility(false)
	)
	_update_showcase_visibility(true)


func _update_showcase_visibility(hidden: bool) -> void:
	# Las opciones tapan el fondo; apagamos el brillo para que no distraiga.
	if _ui:
		_ui.visible = true


# --- Flujo de inicio ----------------------------------------------------------


func _start(map_id: String, mode: String, team: int) -> void:
	var bots := int(Settings.data.gameplay.get("bots", 7))
	var diff := int(Settings.data.gameplay.get("difficulty", 2))
	AudioBank.play_ui("buy", 0.0)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 1.0, 0.35)
	tw.tween_callback(func() -> void: start_requested.emit(map_id, mode, team, bots, diff))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Settings.flush()
