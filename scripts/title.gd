## Заставка при запуске: логотип появляется по буквам над коридором, где из земли
## встаёт босс; рассказчик произносит вступление с субтитрами; полоса загрузки
## с советами сменяется главным меню — «В бой», «Кузница», «Настройки».
extends CanvasLayer

const Save := preload("res://scripts/save.gd")
const GOLD := Color(0.96, 0.78, 0.36)
const GOLD_DARK := Color(0.45, 0.3, 0.12)
const INK := Color(0.07, 0.06, 0.09)
const PARCHMENT := Color(0.96, 0.92, 0.82)
const LOAD_TIME := 6.5
const TIPS := [
	"Свайп навстречу удару в момент вспышки — парирование",
	"Жёлтая метка на враге — слабое место",
	"Удержи палец и отпусти — заряженный удар",
	"Двойной свайп в сторону — уклонение",
	"Оглушённый враг получает двойной урон",
	"Редкое оружие чаще выпадает в глубине забега",
]

var game: Node
var t := 0.0
var _canvas: Control
var _font: Font
var _menu: VBoxContainer
var _leaving := -1.0
var _shade: GradientTexture2D
var _art_corridor: Texture2D = preload("res://assets/art/title.jpg")
var _art_outpost: Texture2D = preload("res://assets/art/outpost.jpg")


func _ready() -> void:
	layer = 5
	_font = ThemeDB.fallback_font
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.01, 0.04, 0.9))
	g.set_color(1, Color(0, 0, 0, 0))
	_shade = GradientTexture2D.new()
	_shade.gradient = g
	_shade.fill_to = Vector2(0, 1)
	_shade.width = 8
	_shade.height = 64
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)

	_menu = VBoxContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_menu.custom_minimum_size = Vector2(340, 0)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_menu.position.y = -150
	_menu.add_theme_constant_override("separation", 12)
	_menu.modulate.a = 0.0
	_menu.visible = false
	add_child(_menu)
	var play := _button("В БОЙ", 84, 30, true)
	play.pressed.connect(start)
	_menu.add_child(play)
	var talents := _button("Таланты", 58, 20, false)
	talents.pressed.connect(func() -> void: game.meta_ui.show_talents())
	_menu.add_child(talents)
	var forge := _button("Кузница", 58, 20, false)
	forge.pressed.connect(func() -> void: game.meta_ui.show_forge())
	_menu.add_child(forge)
	var settings := _button("Настройки", 58, 20, false)
	settings.pressed.connect(func() -> void: game.settings_menu.set_open(true))
	_menu.add_child(settings)
	game.voice.say_sequence(["title_1", "title_2", "title_3"], 0.5, 1.4)


func is_ready() -> bool:
	return t >= LOAD_TIME


func start() -> void:
	if _leaving >= 0.0:
		return
	_leaving = 0.0
	_menu.visible = false
	game.voice.stop()
	game.sfx.play("parry", -4.0, 0.7)


func _process(delta: float) -> void:
	t += delta
	if is_ready() and _leaving < 0.0:
		_menu.visible = true
		_menu.modulate.a = minf(1.0, _menu.modulate.a + delta * 2.5)
	if _leaving >= 0.0:
		_leaving += delta
		if _leaving >= 0.7:
			game.start_run()
			queue_free()
			return
	_canvas.queue_redraw()


func _on_draw() -> void:
	var size := _canvas.size
	var w := size.x
	var h := size.y
	# Иллюстрации: коридор с рыцарем во время загрузки, затем Застава Зари под меню.
	# Медленный наезд камеры и плавная смена.
	var menu_k := smoothstep(LOAD_TIME - 0.4, LOAD_TIME + 1.0, t)
	_cover(_art_corridor, w, h, 1.0 + 0.06 * minf(1.0, t / 12.0), 1.0)
	if menu_k > 0.0:
		_cover(_art_outpost, w, h, 1.0 + 0.04 * minf(1.0, maxf(0.0, t - LOAD_TIME) / 14.0), menu_k)
	_canvas.draw_texture_rect(_shade, Rect2(0, 0, w, h * 0.5), false)
	_canvas.draw_texture_rect(_shade, Rect2(0, h, w, -h * 0.55), false)

	# Эмблема: вращающиеся лучи и меч за логотипом
	var c := Vector2(w * 0.5, h * 0.2)
	var glow := smoothstep(0.3, 2.0, t)
	for i in 16:
		var ang := i * TAU / 16.0 + t * 0.12
		var dir := Vector2(cos(ang), sin(ang))
		var side := dir.orthogonal() * (10.0 if i % 2 == 0 else 5.0)
		var reach := (230.0 if i % 2 == 0 else 150.0) * glow
		_canvas.draw_colored_polygon(PackedVector2Array([c, c + dir * reach + side, c + dir * reach - side]),
			Color(1.0, 0.75, 0.35, 0.07 * glow))
	_sword(c + Vector2(0, 10), 150.0 * glow, Color(GOLD, 0.35 * glow))

	# Логотип по буквам: каждая падает на место с задержкой
	_letters("ПОСЛЕДНИЙ", Vector2(w * 0.5, h * 0.17), 44, PARCHMENT, 0.5)
	_letters("СТРАЖ", Vector2(w * 0.5, h * 0.17 + 78), 92, GOLD, 1.1)
	var line_a := smoothstep(1.9, 2.5, t)
	var lw := w * 0.6 * line_a
	var ly := h * 0.17 + 104
	_canvas.draw_line(Vector2(w * 0.5 - lw * 0.5, ly), Vector2(w * 0.5 + lw * 0.5, ly), Color(GOLD, line_a), 2.0)
	_diamond(Vector2(w * 0.5, ly), 7.0 * line_a, Color(GOLD, line_a))
	_text("Заря ещё вернётся", Vector2(w * 0.5, ly + 34), 19, Color(PARCHMENT, smoothstep(2.3, 3.0, t) * 0.85))

	# Субтитры рассказчика
	var sub: String = game.voice.subtitle
	if sub != "" and _leaving < 0.0:
		_text(sub, Vector2(w * 0.5, h * 0.56), 21, Color(PARCHMENT, 0.95))

	# Загрузка с советами → меню
	if not is_ready():
		var k := clampf(t / LOAD_TIME, 0.0, 1.0)
		var bw := w * 0.7
		var bx := (w - bw) * 0.5
		var by := h - 150.0
		_canvas.draw_style_box(_box(INK, GOLD_DARK, 2, 9), Rect2(bx - 3, by - 3, bw + 6, 18))
		_canvas.draw_style_box(_box(GOLD, Color(0, 0, 0, 0), 0, 6), Rect2(bx, by, maxf(12.0, bw * k), 12))
		_text("Загрузка… %d%%" % roundi(k * 100.0), Vector2(w * 0.5, by - 14), 15, Color(PARCHMENT, 0.8))
		var tip: String = TIPS[int(t / 2.2) % TIPS.size()]
		var ta := smoothstep(0.0, 0.3, fmod(t, 2.2)) * (1.0 - smoothstep(1.9, 2.2, fmod(t, 2.2)))
		_text(tip, Vector2(w * 0.5, by + 48), 15, Color(GOLD, ta * 0.9))
	var d: Dictionary = Save.data
	_text("Забегов: %d  ·  Побед: %d" % [int(d.runs) - 1, int(d.wins)], Vector2(w * 0.5, h - 44), 14, Color(PARCHMENT, 0.55))
	_text("версия 0.4 · ранний доступ", Vector2(w * 0.5, h - 22), 12, Color(PARCHMENT, 0.35))

	if _leaving >= 0.0:
		_canvas.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.01, 0.03, clampf(_leaving / 0.6, 0.0, 1.0)))


## Нарисовать картинку так, чтобы она закрыла весь экран (обрезка по краям), с масштабом и прозрачностью.
func _cover(tex: Texture2D, w: float, h: float, zoom: float, alpha: float) -> void:
	if tex == null:
		return
	var ts := tex.get_size()
	var k := maxf(w / ts.x, h / ts.y) * zoom
	var size := ts * k
	_canvas.draw_texture_rect(tex, Rect2((Vector2(w, h) - size) * 0.5, size), false, Color(1, 1, 1, alpha))


func _letters(word: String, center: Vector2, fsize: int, color: Color, start: float) -> void:
	var total := _font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var x := center.x - total * 0.5
	for i in word.length():
		var ch := word[i]
		var cw := _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var k := smoothstep(0.0, 0.35, t - start - i * 0.07)
		if k > 0.0:
			var drop := (1.0 - k) * -46.0
			var pos := Vector2(x, center.y + drop)
			_canvas.draw_string(_font, pos + Vector2(0, 4), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, 0.55 * k))
			_canvas.draw_string_outline(_font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, maxi(3, fsize / 9), Color(0.2, 0.1, 0.03, k))
			_canvas.draw_string(_font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(color, k))
			# Блик пробегает по буквам раз в несколько секунд
			var shine := maxf(0.0, 1.0 - absf(fmod(t * 0.9, 4.0) - 1.0 - float(i) / word.length()) * 6.0)
			if shine > 0.0:
				_canvas.draw_string(_font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1, 1, 1, shine * 0.7 * k))
		x += cw


func _sword(c: Vector2, size: float, col: Color) -> void:
	if size <= 1.0:
		return
	var s := size
	_canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -s), c + Vector2(s * 0.09, -s * 0.8), c + Vector2(s * 0.09, s * 0.45),
		c + Vector2(-s * 0.09, s * 0.45), c + Vector2(-s * 0.09, -s * 0.8)]), col)
	_canvas.draw_rect(Rect2(c.x - s * 0.32, c.y + s * 0.45, s * 0.64, s * 0.07), col)
	_canvas.draw_rect(Rect2(c.x - s * 0.045, c.y + s * 0.52, s * 0.09, s * 0.3), col)
	_canvas.draw_circle(c + Vector2(0, s * 0.87), s * 0.07, col)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	_canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


func _text(s: String, center: Vector2, fsize: int, c: Color) -> void:
	if c.a <= 0.0:
		return
	var tw := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var pos := center - Vector2(tw * 0.5, 0)
	_canvas.draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, maxi(2, fsize / 6), Color(INK, c.a * 0.9))
	_canvas.draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, c)


func _button(text: String, height: float, fsize: int, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_color", INK if primary else PARCHMENT)
	b.add_theme_color_override("font_hover_color", INK if primary else PARCHMENT)
	b.add_theme_color_override("font_pressed_color", INK if primary else PARCHMENT)
	for st in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(st, _box(GOLD if primary else Color(INK, 0.85), Color(1.0, 0.93, 0.7) if primary else GOLD_DARK, 2, 14))
	b.add_theme_stylebox_override("pressed", _box(GOLD.darkened(0.2) if primary else Color(0.2, 0.16, 0.2), GOLD, 2, 14))
	return b


func _box(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb
