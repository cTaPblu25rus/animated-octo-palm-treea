## Экран паузы и настроек: стиль графики, громкость, вибрация.
## Открывается кнопкой-шестерёнкой справа сверху; пока открыт, игра на паузе.
## Стиль меняется сразу, за полупрозрачной панелью видно результат.
extends CanvasLayer

const Settings := preload("res://scripts/settings.gd")
const GOLD := Color(0.96, 0.78, 0.36)
const GOLD_DARK := Color(0.45, 0.3, 0.12)
const INK := Color(0.07, 0.06, 0.09)
const PARCHMENT := Color(0.96, 0.92, 0.82)

var game: Node

var _gear: Button
var _dim: ColorRect
var _panel: PanelContainer
var _style_buttons := {}
var _volume: HSlider
var _vibro: Button


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_refresh()


func is_open() -> bool:
	return _panel.visible


func set_open(open: bool) -> void:
	_panel.visible = open
	_dim.visible = open
	_gear.visible = not open
	game.gestures.enabled = not open
	get_tree().paused = open
	if not open:
		Settings.save()
	_refresh()


func set_style(id: String) -> void:
	Settings.style = id
	game.apply_style()
	_refresh()


func _build() -> void:
	_gear = Button.new()
	_gear.text = "II"
	_gear.custom_minimum_size = Vector2(62, 34)
	_gear.add_theme_font_size_override("font_size", 16)
	_gear.add_theme_color_override("font_color", PARCHMENT)
	for st in ["normal", "hover", "pressed", "focus"]:
		_gear.add_theme_stylebox_override(st, _box(Color(INK, 0.8), GOLD_DARK, 1, 12))
	_gear.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_gear.position = Vector2(-72, 44)
	_gear.pressed.connect(set_open.bind(true))
	add_child(_gear)

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.01, 0.04, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(440, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bg := _box(Color(0.12, 0.09, 0.13, 0.9), GOLD, 3, 18)
	bg.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", bg)
	_panel.visible = false
	add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	v.add_child(_label("ПАУЗА", 34, GOLD, true))
	v.add_child(_label("Графика", 17, Color(PARCHMENT, 0.7), false))
	for id: String in Settings.STYLE_ORDER:
		var st: Dictionary = Settings.STYLES[id]
		var b := _button("%s\n%s" % [st.name, st.hint], 74)
		b.pressed.connect(set_style.bind(id))
		v.add_child(b)
		_style_buttons[id] = b

	v.add_child(_label("Громкость", 17, Color(PARCHMENT, 0.7), false))
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.value = Settings.volume
	_volume.custom_minimum_size = Vector2(0, 44)
	_volume.value_changed.connect(func(val: float) -> void:
		Settings.volume = val
		Settings.apply_volume())
	v.add_child(_volume)

	_vibro = _button("", 56)
	_vibro.pressed.connect(func() -> void:
		Settings.vibration = not Settings.vibration
		if Settings.vibration:
			Input.vibrate_handheld(40)
		_refresh())
	v.add_child(_vibro)

	var resume := _button("Продолжить", 66)
	resume.add_theme_font_size_override("font_size", 22)
	resume.pressed.connect(set_open.bind(false))
	v.add_child(resume)
	var restart := _button("Новый забег", 52)
	restart.pressed.connect(func() -> void:
		Settings.save()
		get_tree().paused = false
		get_tree().reload_current_scene())
	v.add_child(restart)


func _refresh() -> void:
	for id: String in _style_buttons:
		var b: Button = _style_buttons[id]
		var on := id == Settings.style
		var border := GOLD if on else GOLD_DARK
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, _box(Color(0.25, 0.18, 0.1, 0.95) if on else Color(INK, 0.85), border, 3 if on else 1, 12))
		b.add_theme_color_override("font_color", GOLD if on else PARCHMENT)
	_vibro.text = "Вибрация: %s" % ("вкл" if Settings.vibration else "выкл")


func _label(text: String, size: int, color: Color, center: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _button(text: String, height: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", PARCHMENT)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, _box(Color(INK, 0.85), GOLD_DARK, 1, 12))
	return b


func _box(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	return sb
