extends Control
## OptionsPanel: opciones completas (video, audio, controles, gameplay).
## Se usa tanto en el menu principal como en el menu de pausa.

class_name OptionsPanel

signal closed

var _tabs: TabContainer
var _rebind_action := ""
var _rebind_button: Button
var _rows: Dictionary = {}
var _close_btn: Button


func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP
	build()


func build() -> void:
	for c in get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.01, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := UITheme.panel()
	var panel_size := Vector2(minf(940, size.x - 40), minf(650, size.y - 40))
	panel.custom_minimum_size = panel_size
	panel.position = (size - panel_size) * 0.5
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_child(UITheme.title("OPCIONES", 26))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var defaults := UITheme.button("RESTABLECER", 150)
	defaults.pressed.connect(_on_defaults)
	header.add_child(defaults)
	_close_btn = UITheme.button("CERRAR", 130)
	_close_btn.pressed.connect(_on_close)
	header.add_child(_close_btn)
	vbox.add_child(header)
	UITheme.hsep(vbox)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_tabs)

	_build_video()
	_build_audio()
	_build_gameplay()
	_build_controls()

	var footer := UITheme.label(
		"Los cambios se aplican al instante y se guardan en user://settings.cfg",
		12,
		UITheme.TEXT_DIM
	)
	vbox.add_child(footer)


func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)
	scroll.add_child(inner)
	_tabs.add_child(scroll)
	return inner


func _row_label(parent: VBoxContainer, text: String, hint: String = "") -> void:
	var l := UITheme.label(text, 15, UITheme.TEXT)
	parent.add_child(l)
	if hint != "":
		var h := UITheme.label(hint, 11, UITheme.TEXT_DIM)
		parent.add_child(h)


func _slider_row(
	parent: VBoxContainer,
	label: String,
	min_v: float,
	max_v: float,
	step: float,
	value: float,
	setter: Callable,
	suffix: String = ""
) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := UITheme.label(label, 14, UITheme.TEXT)
	l.custom_minimum_size = Vector2(280, 0)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(340, 24)
	row.add_child(slider)
	var value_label := UITheme.label(_fmt(value, step) + suffix, 14, UITheme.ACCENT, true)
	value_label.custom_minimum_size = Vector2(86, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	slider.value_changed.connect(
		func(v: float) -> void:
			value_label.text = _fmt(v, step) + suffix
			setter.call(v)
	)
	parent.add_child(row)
	return slider


func _fmt(v: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % int(v)
	return "%0.2f" % v


func _toggle_row(
	parent: VBoxContainer, label: String, value: bool, setter: Callable
) -> CheckButton:
	var row := HBoxContainer.new()
	var l := UITheme.label(label, 14, UITheme.TEXT)
	l.custom_minimum_size = Vector2(280, 0)
	row.add_child(l)
	var check := CheckButton.new()
	check.button_pressed = value
	check.text = "SI" if value else "NO"
	check.toggled.connect(
		func(on: bool) -> void:
			check.text = "SI" if on else "NO"
			setter.call(on)
	)
	row.add_child(check)
	parent.add_child(row)
	return check


func _option_row(
	parent: VBoxContainer, label: String, options: Array, selected: int, setter: Callable
) -> OptionButton:
	var row := HBoxContainer.new()
	var l := UITheme.label(label, 14, UITheme.TEXT)
	l.custom_minimum_size = Vector2(280, 0)
	row.add_child(l)
	var opt := OptionButton.new()
	for o in options:
		opt.add_item(String(o))
	opt.selected = clampi(selected, 0, options.size() - 1)
	opt.custom_minimum_size = Vector2(260, 30)
	opt.item_selected.connect(func(idx: int) -> void: setter.call(idx))
	row.add_child(opt)
	parent.add_child(row)
	return opt


func _build_video() -> void:
	var page := _page("VIDEO")
	_option_row(
		page,
		"Modo de pantalla",
		["VENTANA", "PANTALLA COMPLETA", "SIN BORDES"],
		int(Settings.data.video.mode),
		func(i: int) -> void: Settings.set_value("video", "mode", i)
	)
	var res_index := 1
	var resolutions := [
		Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)
	]
	var current := Vector2i(int(Settings.data.video.width), int(Settings.data.video.height))
	for i in resolutions.size():
		if resolutions[i] == current:
			res_index = i
	_option_row(
		page,
		"Resolucion",
		["1280x720", "1600x900", "1920x1080", "2560x1440"],
		res_index,
		func(i: int) -> void:
			Settings.set_value("video", "width", resolutions[i].x)
			Settings.set_value("video", "height", resolutions[i].y)
	)
	_slider_row(
		page,
		"Campo de vision (FOV)",
		70.0,
		110.0,
		1.0,
		float(Settings.data.video.fov),
		func(v: float) -> void: Settings.set_value("video", "fov", v)
	)
	_slider_row(
		page,
		"Brillo / exposicion",
		0.6,
		1.6,
		0.02,
		float(Settings.data.video.brightness),
		func(v: float) -> void:
			Settings.set_value("video", "brightness", v)
			var env := _environment()
			if env:
				Settings.apply_environment(env)
	)
	_toggle_row(
		page,
		"Antialiasing MSAA 2x",
		int(Settings.data.video.msaa) >= 2,
		func(on: bool) -> void: Settings.set_value("video", "msaa", 2 if on else 0)
	)
	_option_row(
		page,
		"Calidad de sombras",
		["BAJA", "MEDIA", "ALTA"],
		int(Settings.data.video.shadows),
		func(i: int) -> void: Settings.set_value("video", "shadows", i)
	)
	_toggle_row(
		page,
		"Oclusion ambiental (SSAO)",
		bool(Settings.data.video.ssao),
		func(on: bool) -> void: Settings.set_value("video", "ssao", on)
	)
	_toggle_row(
		page,
		"Iluminacion indirecta (SSIL)",
		bool(Settings.data.video.ssil),
		func(on: bool) -> void: Settings.set_value("video", "ssil", on)
	)
	_toggle_row(
		page,
		"Bloom / Glow",
		bool(Settings.data.video.glow),
		func(on: bool) -> void: Settings.set_value("video", "glow", on)
	)
	_toggle_row(
		page,
		"Niebla volumetrica",
		bool(Settings.data.video.vol_fog),
		func(on: bool) -> void: Settings.set_value("video", "vol_fog", on)
	)
	_toggle_row(
		page,
		"V-Sync",
		bool(Settings.data.video.vsync),
		func(on: bool) -> void: Settings.set_value("video", "vsync", on)
	)


func _environment() -> Environment:
	var nodes := get_tree().get_nodes_in_group("world_environment")
	if nodes.is_empty():
		var we := get_tree().root.find_child("WorldEnvironment", true, false)
		if we is WorldEnvironment:
			return (we as WorldEnvironment).environment
		return null
	return (nodes[0] as WorldEnvironment).environment


func _build_audio() -> void:
	var page := _page("AUDIO")
	_slider_row(
		page,
		"Volumen general",
		0.0,
		1.0,
		0.01,
		float(Settings.data.audio.master),
		func(v: float) -> void: Settings.set_value("audio", "master", v)
	)
	_slider_row(
		page,
		"Efectos de sonido",
		0.0,
		1.0,
		0.01,
		float(Settings.data.audio.sfx),
		func(v: float) -> void: Settings.set_value("audio", "sfx", v)
	)
	_slider_row(
		page,
		"Musica",
		0.0,
		1.0,
		0.01,
		float(Settings.data.audio.music),
		func(v: float) -> void: Settings.set_value("audio", "music", v)
	)
	_slider_row(
		page,
		"Interfaz",
		0.0,
		1.0,
		0.01,
		float(Settings.data.audio.ui),
		func(v: float) -> void: Settings.set_value("audio", "ui", v)
	)
	_slider_row(
		page,
		"Voces / radio",
		0.0,
		1.0,
		0.01,
		float(Settings.data.audio.voice),
		func(v: float) -> void: Settings.set_value("audio", "voice", v)
	)
	_toggle_row(
		page,
		"Silenciar todo",
		bool(Settings.data.audio.mute),
		func(on: bool) -> void: Settings.set_value("audio", "mute", on)
	)
	var note_text := "Todo el audio del juego (disparos, pasos, ambientes y musica) se sintetiza en tiempo real."
	var note := UITheme.label(note_text, 12, UITheme.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(note)


func _build_gameplay() -> void:
	var page := _page("JUEGO")
	_slider_row(
		page,
		"Sensibilidad del mouse",
		0.2,
		5.0,
		0.05,
		float(Settings.data.gameplay.sensitivity),
		func(v: float) -> void: Settings.set_value("gameplay", "sensitivity", v)
	)
	_toggle_row(
		page,
		"Invertir eje Y",
		bool(Settings.data.gameplay.invert_y),
		func(on: bool) -> void: Settings.set_value("gameplay", "invert_y", on)
	)
	_slider_row(
		page,
		"Bots por partida",
		1.0,
		15.0,
		1.0,
		float(Settings.data.gameplay.bots),
		func(v: float) -> void: Settings.set_value("gameplay", "bots", int(v))
	)
	_option_row(
		page,
		"Dificultad de los bots",
		["RECLUTA", "REGULAR", "VETERANO", "EXPERTO", "LEYENDA"],
		int(Settings.data.gameplay.difficulty),
		func(i: int) -> void: Settings.set_value("gameplay", "difficulty", i)
	)
	_slider_row(
		page,
		"Duracion de ronda (seg)",
		60.0,
		600.0,
		15.0,
		float(Settings.data.gameplay.round_time),
		func(v: float) -> void: Settings.set_value("gameplay", "round_time", int(v))
	)
	_slider_row(
		page,
		"Tiempo de compra (seg)",
		10.0,
		60.0,
		5.0,
		float(Settings.data.gameplay.buy_time),
		func(v: float) -> void: Settings.set_value("gameplay", "buy_time", int(v))
	)
	_toggle_row(
		page,
		"Fuego amigo",
		bool(Settings.data.gameplay.friendly_fire),
		func(on: bool) -> void: Settings.set_value("gameplay", "friendly_fire", on)
	)
	_toggle_row(
		page,
		"Recarga automatica",
		bool(Settings.data.gameplay.auto_reload),
		func(on: bool) -> void: Settings.set_value("gameplay", "auto_reload", on)
	)
	_toggle_row(
		page,
		"Mostrar FPS",
		bool(Settings.data.gameplay.show_fps),
		func(on: bool) -> void: Settings.set_value("gameplay", "show_fps", on)
	)
	_toggle_row(
		page,
		"Hitmarker sonoro",
		bool(Settings.data.gameplay.hitmarker),
		func(on: bool) -> void: Settings.set_value("gameplay", "hitmarker", on)
	)
	_slider_row(
		page,
		"Cantidad de sangre",
		0.0,
		1.0,
		0.1,
		float(Settings.data.gameplay.blood),
		func(v: float) -> void: Settings.set_value("gameplay", "blood", v)
	)
	_slider_row(
		page,
		"Escala del HUD",
		0.7,
		1.4,
		0.05,
		float(Settings.data.gameplay.hud_scale),
		func(v: float) -> void: Settings.set_value("gameplay", "hud_scale", v)
	)
	_option_row(
		page,
		"Idioma",
		["ESPANOL", "ENGLISH"],
		0 if String(Settings.data.gameplay.language) == "es" else 1,
		func(i: int) -> void: Settings.set_value("gameplay", "language", "es" if i == 0 else "en")
	)
	_option_row(
		page,
		"Color de mira",
		["VERDE", "CIAN", "AMARILLO", "MAGENTA", "BLANCO"],
		_crosshair_index(),
		func(i: int) -> void:
			var colors := ["4ade80", "38e5e5", "f2d64b", "d96bf0", "ffffff"]
			Settings.set_value("gameplay", "crosshair_color", colors[i])
	)


func _crosshair_index() -> int:
	var colors := ["4ade80", "38e5e5", "f2d64b", "d96bf0", "ffffff"]
	return maxi(0, colors.find(String(Settings.data.gameplay.crosshair_color)))


func _build_controls() -> void:
	var page := _page("CONTROLES")
	var note := UITheme.label(
		"Haz clic en una tecla y luego pulsa la nueva. ESC cancela la asignacion.",
		12,
		UITheme.TEXT_DIM
	)
	page.add_child(note)
	UITheme.spacer(page, 4)
	var current_cat := ""
	for action in InputSetup.rebindable_actions():
		var label := String(InputSetup.LABELS.get(action, action))
		var row := HBoxContainer.new()
		var l := UITheme.label(label, 14, UITheme.TEXT)
		l.custom_minimum_size = Vector2(280, 0)
		row.add_child(l)
		var b := UITheme.button(InputSetup.key_name(action, Settings.data.controls), 150, 14)
		b.custom_minimum_size = Vector2(180, 32)
		b.pressed.connect(func() -> void: _start_rebind(action, b))
		row.add_child(b)
		page.add_child(row)


func _start_rebind(action: String, button: Button) -> void:
	_rebind_action = action
	_rebind_button = button
	button.text = "Pulsa una tecla..."


func _unhandled_input(event: InputEvent) -> void:
	if _rebind_action == "":
		return
	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_ESCAPE:
			_rebind_action = ""
			if _rebind_button:
				_rebind_button.text = InputSetup.key_name(_rebind_action, Settings.data.controls)
			return
		Settings.data.controls[_rebind_action] = key_event.physical_keycode
		Settings.queue_save()
		Settings.apply_controls()
		if _rebind_button:
			_rebind_button.text = OS.get_keycode_string(key_event.physical_keycode)
		AudioBank.play_ui("ui_click")
		_rebind_action = ""
		get_viewport().set_input_as_handled()


func _on_defaults() -> void:
	for section in Settings.DEFAULTS.keys():
		Settings.reset_section(section)
	build()
	AudioBank.play_ui("ui_click")


func _on_close() -> void:
	if _rebind_action != "":
		_rebind_action = ""
	AudioBank.play_ui("ui_click")
	closed.emit()
	queue_free()
