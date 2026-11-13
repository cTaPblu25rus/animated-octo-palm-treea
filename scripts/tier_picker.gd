## Выбор Ступени Пепла: стрелки по бокам, посередине номер, имя и правило ступени.
## Стоит на заставке и в паузе; выбор действует со следующего забега.
extends HBoxContainer

const Difficulty := preload("res://scripts/difficulty.gd")
const GOLD := Color(0.96, 0.78, 0.36)
const GOLD_DARK := Color(0.45, 0.3, 0.12)
const INK := Color(0.07, 0.06, 0.09)
const PARCHMENT := Color(0.96, 0.92, 0.82)

var _prev: Button
var _next: Button
var _name: Label
var _rule: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_prev = _arrow("◀")
	_prev.pressed.connect(shift.bind(-1))
	add_child(_prev)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _box(Color(INK, 0.85), GOLD_DARK))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	panel.add_child(v)
	_name = _label(17, GOLD)
	v.add_child(_name)
	_rule = _label(12, Color(PARCHMENT, 0.8))
	_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rule.custom_minimum_size = Vector2(210, 0)
	v.add_child(_rule)
	_next = _arrow("▶")
	_next.pressed.connect(shift.bind(1))
	add_child(_next)
	refresh()


func shift(delta: int) -> void:
	Difficulty.select(Difficulty.selected() + delta)
	refresh()


func refresh() -> void:
	var tier := Difficulty.selected()
	var open := Difficulty.unlocked()
	_name.text = "Ступень Пепла %d · %s" % [tier, Difficulty.title(tier)]
	if open == 0:
		_rule.text = "Победи босса, чтобы открыть ступень 1"
	elif tier == 0:
		_rule.text = Difficulty.rule(0)
	else:
		_rule.text = "%s%s. Осколки +%d%%, опыт +%d%%" % [Difficulty.rule(tier), " и правила ступеней ниже" if tier > 1 else "",
			roundi((Difficulty.reward(tier, "shards") - 1.0) * 100.0), roundi((Difficulty.reward(tier, "xp") - 1.0) * 100.0)]
	_prev.disabled = tier <= 0
	_next.disabled = tier >= open
	_prev.modulate.a = 0.35 if _prev.disabled else 1.0
	_next.modulate.a = 0.35 if _next.disabled else 1.0


func _arrow(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(52, 56)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_color_override("font_disabled_color", GOLD_DARK)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, _box(Color(INK, 0.85), GOLD_DARK))
	return b


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(6)
	return sb
