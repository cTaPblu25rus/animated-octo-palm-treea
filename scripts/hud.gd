## Сенсорный HUD боя: здоровье и стойкость врага сверху, стрелка стороны удара,
## всплывающие цифры урона, сообщения, полоски игрока и зона жестов снизу.
## Рисуется через _draw() одного Control — без лишних нод.
extends CanvasLayer

const Enemy := preload("res://scripts/enemy.gd")
const ROOM_HINTS := {"chest": "открыть сундук", "altar": "коснуться алтаря", "event": "осмотреть"}
const PIP_COLORS := {"fight": Color(0.85, 0.25, 0.2), "chest": Color(1.0, 0.8, 0.3),
	"altar": Color(0.5, 0.8, 1.0), "event": Color(0.75, 0.6, 0.9)}

var game: Node

var _canvas: Control
var _font: Font
var _msg := ""
var _msg_color := Color.WHITE
var _msg_t := 0.0
var _msg_dur := 1.0
var _hurt := 0.0
var _popups: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)


func say(text: String, color: Color, dur: float) -> void:
	_msg = text
	_msg_color = color
	_msg_t = dur
	_msg_dur = dur


func hurt_flash() -> void:
	_hurt = 1.0


## Всплывающая цифра урона над точкой мира.
func popup(text: String, world_pos: Vector3, color: Color, big: bool) -> void:
	var cam: Camera3D = game.camera
	if cam == null or cam.is_position_behind(world_pos):
		return
	var pos := cam.unproject_position(world_pos) + Vector2(randf_range(-30, 30), 0)
	_popups.append({"text": text, "pos": pos, "t": 0.0, "color": color, "big": big})


func _process(delta: float) -> void:
	_time += delta
	_msg_t = maxf(0.0, _msg_t - delta)
	_hurt = maxf(0.0, _hurt - delta * 2.5)
	for i in range(_popups.size() - 1, -1, -1):
		_popups[i].t += delta
		if _popups[i].t > 0.9:
			_popups.remove_at(i)
	_canvas.queue_redraw()


func _on_draw() -> void:
	var size := _canvas.size
	var w := size.x
	var h := size.y
	var enemy: Enemy = game.enemy

	# Красная вспышка по краям при получении урона
	if _hurt > 0.0:
		var a := _hurt * 0.45
		var edge := w * 0.12
		_canvas.draw_rect(Rect2(0, 0, edge, h), Color(0.8, 0.05, 0.02, a))
		_canvas.draw_rect(Rect2(w - edge, 0, edge, h), Color(0.8, 0.05, 0.02, a))
		_canvas.draw_rect(Rect2(0, 0, w, edge * 0.6), Color(0.8, 0.05, 0.02, a * 0.7))
		_canvas.draw_rect(Rect2(0, h - edge * 0.6, w, edge * 0.6), Color(0.8, 0.05, 0.02, a * 0.7))

	# Путь забега: точки комнат, текущая крупнее
	var n: int = game.rooms.size()
	var step := 22.0
	var px0 := w * 0.5 - step * (n - 1) * 0.5
	for i in n:
		var kind: String = game.rooms[i].kind
		var pc: Color = PIP_COLORS[kind]
		if i > game.room_index:
			pc.a = 0.35
		var r := 6.5 if i == game.room_index else 4.0
		_canvas.draw_circle(Vector2(px0 + i * step, 18), r + 1.5, Color(0, 0, 0, 0.6))
		_canvas.draw_circle(Vector2(px0 + i * step, 18), r, pc)

	# Враг: имя, здоровье, стойкость
	if enemy != null and enemy.state != Enemy.State.DEAD:
		var bw := w * 0.7
		var x0 := (w - bw) * 0.5
		_text("%s   %d/%d" % [enemy.display_name, game.wave_index + 1, game.wave.size()],
			Vector2(w * 0.5, 46), 20, Color(0.92, 0.88, 0.82))
		_bar(Rect2(x0, 58, bw, 14), enemy.hp / enemy.max_hp, Color(0.78, 0.12, 0.1))
		_bar(Rect2(x0, 76, bw, 7), enemy.stagger / enemy.stagger_max, Color(1.0, 0.8, 0.25))
		if enemy.state == Enemy.State.WINDUP:
			_draw_threat(enemy, w, h)

	# Всплывающие цифры
	for pp in _popups:
		var t: float = pp.t
		var c: Color = pp.color
		c.a = 1.0 - t / 0.9
		var big: bool = pp.big
		_text(pp.text, pp.pos + Vector2(0, -70.0 * t), 34 if big else 24, c)

	# Сообщение по центру
	if _msg_t > 0.0:
		var c := _msg_color
		c.a = clampf(_msg_t / minf(0.3, _msg_dur), 0.0, 1.0)
		_text(_msg, Vector2(w * 0.5, h * 0.36), 30, c)

	# Зона жестов: еле заметная граница
	var zone_y := h * 0.55
	_canvas.draw_line(Vector2(w * 0.1, zone_y), Vector2(w * 0.9, zone_y), Color(1, 1, 1, 0.07), 2.0)

	# Подсказка
	_text(_hint(enemy), Vector2(w * 0.5, h - 118), 16, Color(0.8, 0.8, 0.85, 0.75))

	# Игрок: здоровье и стойкость
	var pw := w * 0.8
	var px := (w - pw) * 0.5
	_bar(Rect2(px, h - 92, pw, 16), game.hp / game.max_hp, Color(0.25, 0.75, 0.35))
	_bar(Rect2(px, h - 70, pw, 9), game.stamina / game.max_stamina, Color(0.35, 0.65, 1.0))
	_text("Осколки: %d    Золото: %d" % [game.shards, game.gold], Vector2(w * 0.5, h - 14), 14, Color(0.9, 0.82, 0.6, 0.9))
	if game.block_t > 0.0:
		_text("ЩИТ", Vector2(w * 0.5, h - 38), 18, Color(0.75, 0.85, 1.0))
	elif game.charging:
		var k := clampf(game.charge_t / float(game.p.charge_time), 0.0, 1.0)
		_bar(Rect2(w * 0.3, h - 46, w * 0.4, 8), k, Color(1.0, 0.6, 0.2) if k < 1.0 else Color(1.0, 0.95, 0.5))

	# Затемнение при переходе между комнатами
	if game.fade > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, game.fade))
		if game.state == "walk" and game.room_index < n:
			var fc := Color(0.85, 0.82, 0.75, game.fade)
			_text("Комната %d из %d" % [game.room_index + 1, n], Vector2(w * 0.5, h * 0.45), 26, fc)

	# Итог
	if game.state == "victory" or game.state == "defeat":
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		var ok: bool = game.state == "victory"
		_text("Забег пройден" if ok else "Страж пал", Vector2(w * 0.5, h * 0.4), 36,
			Color(1.0, 0.85, 0.4) if ok else Color(1.0, 0.35, 0.3))
		var s: Dictionary = game.stats
		_text("Точных ударов: %d   Парирований: %d" % [s.weak_hits, s.parries], Vector2(w * 0.5, h * 0.47), 18, Color.WHITE)
		_text("Блоков: %d   Уклонений: %d   Получено урона: %d" % [s.blocks, s.dodges, roundi(s.taken)],
			Vector2(w * 0.5, h * 0.51), 18, Color.WHITE)
		_text("Комнат: %d из %d   Осколки: %d   Золото: %d" % [s.rooms, n, game.shards, game.gold],
			Vector2(w * 0.5, h * 0.55), 18, Color(1.0, 0.88, 0.6))
		_text("Сид забега: %d" % game.run_seed, Vector2(w * 0.5, h * 0.67), 14, Color(0.7, 0.7, 0.75))
		_text("Тап — заново", Vector2(w * 0.5, h * 0.62), 22, Color(0.85, 0.85, 0.9, 0.6 + 0.4 * sin(_time * 4.0)))


## Стрелка у края экрана со стороны удара. В окне парирования — белая и крупнее.
func _draw_threat(enemy: Enemy, w: float, h: float) -> void:
	var in_window: bool = enemy.time_to_impact() <= float(game.p.parry_window)
	var c := Color(1.0, 0.95, 0.85, 0.95) if in_window else Color(1.0, 0.15, 0.08, 0.55 + 0.35 * sin(_time * 18.0))
	var s := 46.0 if in_window else 34.0
	var pts := PackedVector2Array()
	match enemy.attack_side:
		Enemy.Side.LEFT:
			var c0 := Vector2(26, h * 0.4)
			pts = PackedVector2Array([c0 + Vector2(-s * 0.4, 0), c0 + Vector2(s * 0.6, -s), c0 + Vector2(s * 0.6, s)])
		Enemy.Side.RIGHT:
			var c1 := Vector2(w - 26, h * 0.4)
			pts = PackedVector2Array([c1 + Vector2(s * 0.4, 0), c1 + Vector2(-s * 0.6, -s), c1 + Vector2(-s * 0.6, s)])
		_:
			var c2 := Vector2(w * 0.5, 112)
			pts = PackedVector2Array([c2 + Vector2(0, -s * 0.4), c2 + Vector2(-s, s * 0.6), c2 + Vector2(s, s * 0.6)])
	_canvas.draw_colored_polygon(pts, c)


func _hint(enemy: Enemy) -> String:
	if game.state == "room":
		return "Тап — " + str(ROOM_HINTS[game.room.kind])
	if enemy == null or game.state != "fight":
		return ""
	if enemy.state == Enemy.State.WINDUP:
		return "Удар %s! Свайп навстречу при вспышке · вниз — щит · двойной — уклон" % game.SIDE_NAMES[enemy.attack_side]
	if enemy.state == Enemy.State.STUNNED:
		return "Удержи палец и отпусти — заряженный удар"
	return "Свайп к жёлтой метке — точный удар"


func _bar(r: Rect2, k: float, c: Color) -> void:
	_canvas.draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6))
	_canvas.draw_rect(r, Color(0.12, 0.12, 0.14, 0.9))
	var f := r
	f.size.x *= clampf(k, 0.0, 1.0)
	_canvas.draw_rect(f, c)


func _text(t: String, center: Vector2, fsize: int, c: Color) -> void:
	var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var pos := center - Vector2(tw * 0.5, 0)
	_canvas.draw_string_outline(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, c.a * 0.8))
	_canvas.draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, c)
