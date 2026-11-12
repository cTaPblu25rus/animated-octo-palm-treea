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
signal choice_made(kind: String, tag: String)

var game: Node
var offered: Dictionary = {}

var _dim: ColorRect
var _loot: PanelContainer
var _loot_box: VBoxContainer
var _forge: PanelContainer
var _forge_box: VBoxContainer
var _forge_buttons := {}
var _choice: PanelContainer
var _choice_box: VBoxContainer
var choice_kind := ""
var choice_options: Array = []     # [{title, text, color, tag, enabled, icon}]
var _cards: Array[Button] = []
var _picking := false
var _stage: Control
var _preview: Node3D
var _loot_color := Color.WHITE
var _loot_rarity := 0
var _loot_t := 0.0
var _flash := 0.0


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
	_choice = _panel()
	_choice_box = _choice.get_child(0)


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
	var rarity := int(weapon.rarity)
	_loot_color = col
	_loot_rarity = rarity
	_loot_t = 0.0
	var seq: Array = []      # [узел, задержка появления]

	_loot_box.add_child(_label("ДОБЫЧА", 30, GOLD, true))
	# Сцена: лучи цвета редкости и вращающаяся модель оружия
	_stage = Control.new()
	_stage.custom_minimum_size = Vector2(412, 230)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.draw.connect(_draw_stage)
	_loot_box.add_child(_stage)
	_build_preview(cfg.weapons[weapon.id])

	var name_l := _label(Items.title(cfg, weapon), 27, col, true)
	_loot_box.add_child(name_l)
	seq.append([name_l, 0.55])
	var pill := _label(str(cfg.rarities[rarity].name).to_upper(), 15, INK, true)
	pill.custom_minimum_size = Vector2(170, 0)
	var pill_box := PanelContainer.new()
	pill_box.add_theme_stylebox_override("panel", _box(col, Color(1, 1, 1, 0.5), 1, 12))
	pill_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pill_box.add_child(pill)
	_loot_box.add_child(pill_box)
	seq.append([pill_box, 0.7])
	var note := _label(str(cfg.weapons[weapon.id].note), 15, Color(PARCHMENT, 0.75), true)
	_loot_box.add_child(note)
	seq.append([note, 0.8])
	var delay := 0.95
	for row: Array in Items.compare(cfg, weapon, cur):
		var d: int = row[2]
		var arrow := "" if d == 0 else ("  ▲" if d > 0 else "  ▼")
		var r := _row(str(row[0]), str(row[1]) + arrow, PARCHMENT if d == 0 else (GOOD if d > 0 else BAD))
		_loot_box.add_child(r)
		seq.append([r, delay])
		delay += 0.1
	if str(weapon.affix) != "":
		var af: Dictionary = cfg.affixes[weapon.affix]
		var af_l := _label("✦ %s: %s" % [af.name, af.text], 16, GOLD, true)
		_loot_box.add_child(af_l)
		seq.append([af_l, delay])
		delay += 0.12
	var cur_l := _label("Сейчас: %s (сила %d)" % [Items.title(cfg, cur), Items.power(cfg, cur)], 14, Color(PARCHMENT, 0.6), true)
	_loot_box.add_child(cur_l)
	seq.append([cur_l, delay])
	var take := _button("Взять", 64)
	take.add_theme_font_size_override("font_size", 22)
	take.add_theme_color_override("font_color", col)
	for st in ["normal", "hover", "pressed", "focus"]:
		take.add_theme_stylebox_override(st, _box(Color(INK, 0.9), col, 2, 12))
	take.pressed.connect(choose.bind(true))
	_loot_box.add_child(take)
	seq.append([take, delay + 0.15])
	var scrap := _button("Разобрать: +%d осколков" % Items.salvage(cfg, weapon), 54)
	scrap.pressed.connect(choose.bind(false))
	_loot_box.add_child(scrap)
	seq.append([scrap, delay + 0.25])

	# Строки появляются по очереди, пока оружие «выпрыгивает» из света
	for item: Array in seq:
		var node: Control = item[0]
		node.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(node, "modulate:a", 1.0, 0.22).set_delay(float(item[1]))
	_loot.visible = true
	_dim.visible = true
	_flash = 0.5 + 0.15 * rarity
	game.gestures.enabled = false
	_fit(_loot)
	if rarity >= 1:
		game.sfx.play("parry", -8.0 + 2.0 * rarity, 1.4 - 0.12 * rarity)


## Сцена предпросмотра: отдельный 3D-мир с моделью оружия, камерой и светом.
func _build_preview(base: Dictionary) -> void:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(holder)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.75
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 3.4)
	cam.fov = 34.0
	vp.add_child(cam)
	_preview = Node3D.new()
	_preview.rotation.z = -0.45
	_preview.scale = Vector3.ZERO
	vp.add_child(_preview)
	var scene: PackedScene = load("res://assets/kaykit/hero/%s.gltf" % str(base.model))
	var model: Node3D = scene.instantiate()
	var k := float(base.scale) * 3.3
	model.scale = Vector3.ONE * k
	model.position = Vector3(0, -0.58 * k, 0)
	_preview.add_child(model)


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 2.2)
	if _dim.visible:
		_dim.color = Color(0.02, 0.01, 0.04, 0.6).lerp(Color(_loot_color, 0.75), _flash if _loot.visible else 0.0)
	if not _loot.visible or _stage == null:
		return
	_loot_t += delta
	if _preview != null:
		# Оружие «выпрыгивает» с перелётом и раскручивается, потом вращается спокойно
		var k := clampf((_loot_t - 0.25) / 0.45, 0.0, 1.0)
		var back := 1.0 + 2.70158 * pow(k - 1.0, 3.0) + 1.70158 * pow(k - 1.0, 2.0)
		_preview.scale = Vector3.ONE * maxf(0.001, back)
		_preview.rotation.y += delta * (1.3 + 14.0 * exp(-_loot_t * 2.6))
		_preview.position.y = sin(_loot_t * 2.0) * 0.05
	_stage.queue_redraw()


## Лучи, свечение и искры за оружием: цвет и число лучей зависят от редкости.
func _draw_stage() -> void:
	var c := _stage.size * 0.5
	var t := _loot_t
	var grow := 1.0 - pow(1.0 - clampf(t / 0.5, 0.0, 1.0), 3.0)
	if grow <= 0.01:
		return
	var rays := 10 + _loot_rarity * 4
	for set_i in (2 if _loot_rarity >= 2 else 1):
		var spin := t * (0.35 if set_i == 0 else -0.22)
		var reach := (210.0 if set_i == 0 else 150.0) * grow
		for i in rays:
			var ang := spin + i * TAU / rays
			var dir := Vector2(cos(ang), sin(ang))
			var side := dir.orthogonal() * (13.0 if i % 2 == 0 else 7.0)
			_stage.draw_colored_polygon(PackedVector2Array([c, c + dir * reach + side, c + dir * reach - side]),
				Color(_loot_color, (0.2 if set_i == 0 else 0.12) * grow))
	for i in 5:
		_stage.draw_circle(c, (95.0 - i * 16.0) * grow, Color(_loot_color, 0.07))
	# Вспышка в момент появления
	var burst := maxf(0.0, 1.0 - absf(t - 0.3) * 5.0)
	if burst > 0.0:
		_stage.draw_circle(c, 120.0 * burst, Color(1, 1, 1, 0.55 * burst))
	# Искры кружат вокруг
	for i in 8 + _loot_rarity * 3:
		var ang := t * (0.6 + 0.07 * i) + i * 2.4
		var rad := 70.0 + 22.0 * sin(t * 1.3 + i) + (i % 3) * 22.0
		var sp := c + Vector2(cos(ang) * rad, sin(ang) * rad * 0.75)
		var tw := 0.5 + 0.5 * sin(t * 6.0 + i * 1.7)
		var r := (2.0 + 3.0 * tw) * grow
		_stage.draw_colored_polygon(PackedVector2Array([
			sp + Vector2(0, -r * 2.0), sp + Vector2(r, 0), sp + Vector2(0, r * 2.0), sp + Vector2(-r, 0)]),
			Color(_loot_color.lerp(Color.WHITE, 0.6), 0.9 * tw * grow))


func _close_stage() -> void:
	_clear(_loot_box)
	_stage = null
	_preview = null


## Закрыть карточку без выбора (переход из меню разработчика).
func cancel_loot() -> void:
	if _loot.visible:
		_close_stage()
		_loot.visible = false
		_dim.visible = _forge.visible
		game.gestures.enabled = true


func choose(take: bool) -> void:
	if not _loot.visible:
		return
	_close_stage()
	_loot.visible = false
	_dim.visible = false
	game.gestures.enabled = true
	loot_chosen.emit(take)


# ============================================================ выбор: дары, развилки, лавка

func is_choice_open() -> bool:
	return _choice.visible


## Показать карточки на выбор. Каждая опция: {title, text, color, tag, enabled}.
func show_choice(kind: String, title: String, subtitle: String, options: Array) -> void:
	choice_kind = kind
	choice_options = options
	_picking = false
	_cards.clear()
	_clear(_choice_box)
	_choice_box.add_child(_label(title, 28, GOLD, true))
	if subtitle != "":
		_choice_box.add_child(_label(subtitle, 15, Color(PARCHMENT, 0.75), true))
	for i in options.size():
		var card := _card(options[i], i)
		_choice_box.add_child(card)
		_cards.append(card)
		# Карточки «выезжают» по очереди
		card.modulate.a = 0.0
		card.scale = Vector2(0.86, 0.86)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(card, "modulate:a", 1.0, 0.2).set_delay(0.08 + i * 0.09)
		tw.tween_property(card, "scale", Vector2.ONE, 0.28).set_delay(0.08 + i * 0.09) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_choice.visible = true
	_dim.visible = true
	game.gestures.enabled = false
	_fit(_choice)


## Карточка: значок в цветном круге, название и описание.
func _card(o: Dictionary, index: int) -> Button:
	var col: Color = o.get("color", PARCHMENT)
	var enabled := bool(o.get("enabled", true))
	var has_text := str(o.get("text", "")) != ""
	var b := Button.new()
	b.custom_minimum_size = Vector2(412, 92 if has_text else 70)
	b.pivot_offset = b.custom_minimum_size * 0.5
	b.disabled = not enabled
	for st in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(st, _box(Color(INK, 0.92), Color(col, 0.8), 2, 14))
	b.add_theme_stylebox_override("pressed", _box(Color(col.darkened(0.7), 0.95), col, 3, 14))
	b.add_theme_stylebox_override("disabled", _box(Color(INK, 0.5), Color(col, 0.25), 1, 14))
	b.pressed.connect(_press_card.bind(index))

	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.modulate.a = 1.0 if enabled else 0.4
	b.add_child(h)

	var tex := _icon(str(o.get("icon", "")))
	if tex != null:
		var badge := PanelContainer.new()
		badge.custom_minimum_size = Vector2(60, 60)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bs := _box(Color(col.darkened(0.72), 1.0), col, 2, 30)
		bs.set_content_margin_all(9)
		badge.add_theme_stylebox_override("panel", bs)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.modulate = col.lerp(Color.WHITE, 0.25)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(tr)
		h.add_child(badge)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := _label(str(o.title), 19, col, tex == null)
	t.custom_minimum_size = Vector2(0, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	if has_text:
		var d := _label(str(o.text), 14, Color(PARCHMENT, 0.85), tex == null)
		d.custom_minimum_size = Vector2(0, 0)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(d)
	return b


## Нажатие пальцем: выбранная карточка вспыхивает, остальные гаснут, затем выбор применяется.
func _press_card(index: int) -> void:
	if _picking:
		return
	_picking = true
	game.sfx.play("parry", -8.0, 1.3)
	for i in _cards.size():
		var card: Button = _cards[i]
		var tw := create_tween().set_parallel(true)
		if i == index:
			tw.tween_property(card, "scale", Vector2(1.06, 1.06), 0.12)
			tw.tween_property(card, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.12)
		else:
			tw.tween_property(card, "modulate:a", 0.25, 0.15)
	await get_tree().create_timer(0.24, true, false, true).timeout
	pick(index)


func _icon(icon_name: String) -> Texture2D:
	var path := "res://assets/icons/%s.png" % icon_name
	if icon_name == "" or not ResourceLoader.exists(path):
		return null
	return load(path)


func pick(index: int) -> void:
	_picking = false
	if not _choice.visible or index < 0 or index >= choice_options.size():
		return
	var o: Dictionary = choice_options[index]
	if not bool(o.get("enabled", true)):
		return
	_choice.visible = false
	_dim.visible = false
	game.gestures.enabled = true
	choice_made.emit(choice_kind, str(o.tag))


func cancel_choice() -> void:
	if _choice.visible:
		_choice.visible = false
		_dim.visible = _forge.visible
		game.gestures.enabled = true


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
