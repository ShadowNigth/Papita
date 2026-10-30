extends RefCounted
## UITheme: tema visual unificado (olivo/dorado, aire CS 1.5 modernizado).

class_name UITheme

const FONT_MONO := preload("res://assets/fonts/DejaVuSansMono.ttf")
const FONT_BOLD := preload("res://assets/fonts/DejaVuSans-Bold.ttf")
const FONT_BODY := preload("res://assets/fonts/DejaVuSans.ttf")

const BG := Color(0.045, 0.055, 0.04, 0.94)
const BG_DARK := Color(0.025, 0.032, 0.024, 0.96)
const ACCENT := Color(0.86, 0.76, 0.35)
const ACCENT_DIM := Color(0.54, 0.48, 0.24)
const TEXT := Color(0.87, 0.86, 0.79)
const TEXT_DIM := Color(0.62, 0.62, 0.55)
const CT := Color(0.48, 0.7, 0.95)
const T := Color(0.95, 0.68, 0.38)
const GREEN := Color(0.55, 0.82, 0.46)
const RED := Color(0.87, 0.3, 0.26)
const ORANGE := Color(0.95, 0.58, 0.22)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = FONT_BODY
	theme.default_font_size = 16
	# Etiquetas.
	theme.set_font("font", "Label", FONT_BODY)
	theme.set_font_size("font_size", "Label", 16)
	theme.set_color("font_color", "Label", TEXT)
	# Botones.
	theme.set_font("font", "Button", FONT_MONO)
	theme.set_font_size("font_size", "Button", 16)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color(1.0, 0.98, 0.86))
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_focus_color", "Button", Color(1.0, 0.98, 0.86))
	theme.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.4))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.095, 0.07, 0.92)
	normal.border_width_left = 3
	normal.border_color = Color(0.4, 0.36, 0.16)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 9
	normal.content_margin_bottom = 9
	normal.corner_radius_top_right = 2
	normal.corner_radius_bottom_right = 2
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.18, 0.12, 0.95)
	hover.border_color = ACCENT
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.22, 0.22, 0.12, 0.98)
	pressed.border_color = ACCENT
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.05, 0.055, 0.045, 0.8)
	disabled.border_color = Color(0.2, 0.2, 0.17)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", hover)
	theme.set_stylebox("disabled", "Button", disabled)
	# Paneles.
	var panel := StyleBoxFlat.new()
	panel.bg_color = BG
	panel.border_width_left = 1
	panel.border_width_top = 1
	panel.border_width_right = 1
	panel.border_width_bottom = 1
	panel.border_color = Color(0.32, 0.3, 0.18, 0.85)
	panel.content_margin_left = 18
	panel.content_margin_right = 18
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	panel.corner_radius_top_left = 3
	panel.corner_radius_top_right = 3
	panel.corner_radius_bottom_left = 3
	panel.corner_radius_bottom_right = 3
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	var inner := StyleBoxFlat.new()
	inner.bg_color = Color(0.06, 0.07, 0.055, 0.9)
	inner.border_width_left = 1
	inner.border_color = Color(0.25, 0.24, 0.16, 0.9)
	inner.content_margin_left = 10
	inner.content_margin_right = 10
	inner.content_margin_top = 8
	inner.content_margin_bottom = 8
	theme.set_stylebox("panel", "ItemList", inner)
	# Sliders.
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(0.1, 0.11, 0.09)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = ACCENT
	var grabber_hi := StyleBoxFlat.new()
	grabber_hi.bg_color = Color(1.0, 0.9, 0.55)
	theme.set_stylebox("slider", "HSlider", slider)
	theme.set_stylebox("grabber_area", "HSlider", grabber)
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabber_hi)
	# Checkbox / OptionButton / ProgressBar / LineEdit.
	theme.set_color("font_color", "CheckButton", TEXT)
	theme.set_color("font_color", "OptionButton", TEXT)
	theme.set_font("font", "OptionButton", FONT_MONO)
	theme.set_stylebox("normal", "LineEdit", inner)
	theme.set_stylebox("focus", "LineEdit", inner)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_font("font", "LineEdit", FONT_MONO)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.09, 0.07)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = ACCENT
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)
	theme.set_color("font_color", "ProgressBar", TEXT)
	# Tabs.
	theme.set_stylebox("tab_selected", "TabContainer", panel)
	theme.set_stylebox("panel", "TabContainer", panel)
	theme.set_color("font_selected_color", "TabContainer", ACCENT)
	theme.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	# Scroll.
	var scroll := StyleBoxFlat.new()
	scroll.bg_color = Color(0.06, 0.065, 0.055, 0.6)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.38, 0.36, 0.24)
	theme.set_stylebox("scroll", "VScrollBar", scroll)
	theme.set_stylebox("grabber", "VScrollBar", grab)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_hi)
	return theme


static func label(text: String, size: int = 16, color: Color = TEXT, mono: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if mono:
		l.add_theme_font_override("font", FONT_MONO)
	return l


static func title(text: String, size: int = 42) -> Label:
	var l := label(text, size, ACCENT)
	l.add_theme_font_override("font", FONT_BOLD)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


static func button(text: String, min_width: float = 0.0, size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 40)
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


static func panel(margin: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", build().get_stylebox("panel", "PanelContainer"))
	return p


static func hsep(parent: Node, color: Color = Color(0.3, 0.28, 0.18, 0.8)) -> void:
	var line := ColorRect.new()
	line.color = color
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(line)


static func spacer(parent: Node, height: float = 10) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)


static func weapon_icon(def: Dictionary) -> String:
	var cls := String(def.get("cls", "rifle"))
	match cls:
		"pistol":
			return "PISTOLA"
		"smg":
			return "SUBFUSIL"
		"rifle":
			return "FUSIL"
		"sniper":
			return "FRANCO"
		"shotgun":
			return "ESCOPETA"
		"lmg":
			return "AMETRALLADORA"
		"knife":
			return "CUCHILLO"
		"grenade":
			return "GRANADA"
	return "ARMA"
