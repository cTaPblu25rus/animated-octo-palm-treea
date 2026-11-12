## Карточка добычи (взять оружие или разобрать на осколки) и кузница
## (постоянные улучшения за осколки, заточка оружия за золото).
## Кузница открывается из паузы; карточка появляется сама, когда выпало оружие.
extends CanvasLayer

const Items := preload("res://scripts/items.gd")
const Save := preload("res://scripts/save.gd")
const GOLD := Color(0.96, 0.78, 0.36)
const GOLD_DARK := Color(0.45, 0.3, 0.12)
const INK := Color(0.07, 0.06, 0.09)
const PARCHMENT := Color(0.96, 0.92, 0.82)
const GOOD := Color(0.45, 0.9, 0.4)
const BAD := Color(1.0, 0.45, 0.4)

signal loot_chosen(take: bool)

var game: Node
var offered: Dictionary = {}

var _dim: ColorRect
var _loot: PanelContainer
var _loot_box: VBoxContainer
var _forge: PanelContainer
var _forge_box: VBoxContainer
var _forge_buttons := {}


func _ready() -> void:
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.01, 0.04, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)
	_loot = _panel()
	_loot_box = _loot.get_child(0)
	_forge = _panel()
	_forge_box = _forge.get_child(0)


func is_loot_open() -> bool:
	return _loot.visible


func is_forge_open() -> bool:
	return _forge.visible


# ============================================================ добыча

func show_loot(weapon: Dictionary) -> void:
	offered = weapon
	var cfg: Dictionary = game.items
	var cur: Dictionary = Save.data.weapon
	_clear(_loot_box)
	var col := Items.color(cfg, weapon)
	_loot_box.add_child(_label("ДОБЫЧА", 30, GOLD, true))
	_loot_box.add_child(_label(Items.title(cfg, weapon), 26, col, true))
	_loot_box.add_child(_label(str(cfg.rarities[int(weapon.rarity)].name), 16, Color(col, 0.85), true))
	_loot_box.add_child(_label(str(cfg.weapons[weapon.id].note), 15, Color(PARCHMENT, 0.75), true))
	for row: Array in Items.compare(cfg, weapon, cur):
		var d: int = row[2]
		var arrow := "" if d == 0 else ("  ▲" if d > 0 else "  ▼")
		_loot_box.add_child(_row(str(row[0]), str(row[1]) + arrow, PARCHMENT if d == 0 else (GOOD if d > 0 else BAD)))
	if str(weapon.affix) != "":
		var af: Dictionary = cfg.affixes[weapon.affix]
		_loot_box.add_child(_label("%s: %s" % [af.name, af.text], 16, GOLD, true))
	_loot_box.add_child(_label("Сейчас: %s (сила %d)" % [Items.title(cfg, cur), Items.power(cfg, cur)], 14,
		Color(PARCHMENT, 0.6), true))
	var take := _button("Взять", 64)
	take.add_theme_font_size_override("font_size", 22)
	take.pressed.connect(choose.bind(true))
	_loot_box.add_child(take)
	var scrap := _button("Разобрать: +%d осколков" % Items.salvage(cfg, weapon), 54)
	scrap.pressed.connect(choose.bind(false))
	_loot_box.add_child(scrap)
	_loot.visible = true
	_dim.visible = true
	game.gestures.enabled = false
	_fit(_loot)


## Закрыть карточку без выбора (переход из меню разработчика).
func cancel_loot() -> void:
	if _loot.visible:
		_loot.visible = false
		_dim.visible = _forge.visible
		game.gestures.enabled = true


func choose(take: bool) -> void:
	if not _loot.visible:
		return
	_loot.visible = false
	_dim.visible = false
	game.gestures.enabled = true
	loot_chosen.emit(take)


# ============================================================ кузница

func show_forge() -> void:
	_forge.visible = true
	_dim.visible = true
	_rebuild_forge()


func hide_forge() -> void:
	_forge.visible = false
	_dim.visible = false


func _rebuild_forge() -> void:
	var cfg: Dictionary = game.items
	var w: Dictionary = Save.data.weapon
	_clear(_forge_box)
	_forge_buttons.clear()
	_forge_box.add_child(_label("КУЗНИЦА", 30, GOLD, true))
	_forge_box.add_child(_label("Осколки: %d     Золото: %d" % [game.shards, game.gold], 17, PARCHMENT, true))

	_forge_box.add_child(_label("Оружие", 15, Color(PARCHMENT, 0.6), false))
	_forge_box.add_child(_label("%s · сила %d" % [Items.title(cfg, w), Items.power(cfg, w)], 19, Items.color(cfg, w), false))
	var max_lvl := int(cfg.sharpen.max)
	var lvl := int(w.level)
	var price := int(cfg.sharpen.gold) * (lvl + 1)
	var sharpen := _button("", 58)
	if lvl >= max_lvl:
		sharpen.text = "Заточка: предел"
		sharpen.disabled = true
	else:
		sharpen.text = "Заточить +%d%% урона — %d золота" % [roundi(float(cfg.sharpen.bonus) * 100.0), price]
		sharpen.disabled = game.gold < price
	sharpen.pressed.connect(buy_sharpen)
	_forge_box.add_child(sharpen)
	_forge_buttons["sharpen"] = sharpen

	_forge_box.add_child(_label("Улучшения героя", 15, Color(PARCHMENT, 0.6), false))
	for id: String in cfg.upgrades:
		var up: Dictionary = cfg.upgrades[id]
		var have := int(Save.data.upgrades.get(id, 0))
		var cost := int(up.shards) * (have + 1)
		var b := _button("", 58)
		if have >= int(up.max):
			b.text = "%s %d/%d — предел" % [up.name, have, int(up.max)]
			b.disabled = true
		else:
			b.text = "%s %d/%d · %s — %d оск." % [up.name, have, int(up.max), up.text, cost]
			b.disabled = game.shards < cost
		b.pressed.connect(buy_upgrade.bind(id))
		_forge_box.add_child(b)
		_forge_buttons[id] = b

	var back := _button("Назад", 60)
	back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(hide_forge)
	_forge_box.add_child(back)
	_fit(_forge)


func buy_upgrade(id: String) -> bool:
	var up: Dictionary = game.items.upgrades[id]
	var have := int(Save.data.upgrades.get(id, 0))
	var cost := int(up.shards) * (have + 1)
	if have >= int(up.max) or game.shards < cost:
		return false
	game.shards -= cost
	Save.data.upgrades[id] = have + 1
	game.recalc()
	game.persist()
	game.sfx.play("parry", -6.0, 1.2)
	if _forge.visible:
		_rebuild_forge()
	return true


func buy_sharpen() -> bool:
	var cfg: Dictionary = game.items
	var w: Dictionary = Save.data.weapon
	var price := int(cfg.sharpen.gold) * (int(w.level) + 1)
	if int(w.level) >= int(cfg.sharpen.max) or game.gold < price:
		return false
	game.gold -= price
	w.level = int(w.level) + 1
	game.recalc()
	game.persist()
	game.sfx.play("block", -4.0, 1.3)
	if _forge.visible:
		_rebuild_forge()
	return true


# ============================================================ примитивы

func _panel() -> PanelContainer:
	var pnl := PanelContainer.new()
	pnl.set_anchors_preset(Control.PRESET_CENTER)
	pnl.custom_minimum_size = Vector2(460, 0)
	pnl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pnl.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bg := _box(Color(0.12, 0.09, 0.13, 0.97), GOLD, 3, 18)
	bg.set_content_margin_all(22)
	pnl.add_theme_stylebox_override("panel", bg)
	pnl.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pnl.add_child(v)
	add_child(pnl)
	return pnl


## Сжать панель под новое содержимое и вернуть в центр экрана.
func _fit(pnl: PanelContainer) -> void:
	await get_tree().process_frame
	pnl.size = Vector2.ZERO
	pnl.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _label(text: String, size: int, color: Color, center: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# Ширина задана явно: иначе перенос строк при нулевой ширине раздувает панель по высоте
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(412, 0)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _row(left: String, right: String, right_color: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	var a := _label(left, 17, Color(PARCHMENT, 0.85), false)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.autowrap_mode = TextServer.AUTOWRAP_OFF
	a.custom_minimum_size = Vector2.ZERO
	var b := _label(right, 17, right_color, false)
	b.autowrap_mode = TextServer.AUTOWRAP_OFF
	b.custom_minimum_size = Vector2.ZERO
	h.add_child(a)
	h.add_child(b)
	return h


func _button(text: String, height: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", PARCHMENT)
	b.add_theme_color_override("font_disabled_color", Color(PARCHMENT, 0.35))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, _box(Color(INK, 0.9), GOLD_DARK, 1, 12))
	b.add_theme_stylebox_override("disabled", _box(Color(INK, 0.5), Color(GOLD_DARK, 0.4), 1, 12))
	return b


func _box(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	return sb
