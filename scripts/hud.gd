## Сенсорный HUD: панель врага с рамкой и «следом» урона, путь забега со значками,
## кошель с осколками и золотом, полосы героя, стрелка удара, всплывающие цифры,
## заставка босса, кат-сцена победы и экран итога.
## Всё рисуется кодом через _draw() одного Control: без картинок и лишних нод.
extends CanvasLayer

const Enemy := preload("res://scripts/enemy.gd")
const Save := preload("res://scripts/save.gd")
const Items := preload("res://scripts/items.gd")

const GOLD := Color(0.96, 0.78, 0.36)
const GOLD_DARK := Color(0.45, 0.3, 0.12)
const INK := Color(0.07, 0.06, 0.09)
const PARCHMENT := Color(0.96, 0.92, 0.82)
const HP_RED := Color(0.86, 0.16, 0.14)
const HP_GREEN := Color(0.36, 0.8, 0.32)
const STAMINA := Color(0.3, 0.66, 1.0)
const ROOM_HINTS := {"chest": "открыть сундук", "altar": "коснуться алтаря", "event": "осмотреть"}
const PIP_COLORS := {"fight": Color(0.86, 0.3, 0.24), "chest": Color(1.0, 0.8, 0.3),
	"altar": Color(0.5, 0.82, 1.0), "event": Color(0.78, 0.62, 0.95), "boss": Color(0.75, 0.1, 0.2)}

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
var _vignette: GradientTexture2D
var _shade_bottom: GradientTexture2D
var _shade_top: GradientTexture2D
var _enemy_trail := 1.0       # «след» урона на полосе врага
var _hp_trail := 1.0          # и на полосе героя
var _result_t := 0.0
var _boss_card := 0.0
var _fx: Array[Dictionary] = []   # эффекты ударов: вспышки, следы клинка, кольца, когти
var _flash := 0.0                 # белая вспышка экрана на крит
var combo := 0                    # серия точных ударов подряд
var _combo_t := 0.0
var _combo_pop := 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_vignette = _radial(Color(0, 0, 0, 0), Color(0, 0, 0, 0.62))
	_shade_bottom = _linear(Color(0, 0, 0, 0), Color(0.02, 0.01, 0.04, 0.85))
	_shade_top = _linear(Color(0.02, 0.01, 0.04, 0.75), Color(0, 0, 0, 0))
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
func popup(text: String, world_pos: Vector3, color: Color, big: bool, crit: bool = false) -> void:
	var cam: Camera3D = game.camera
	if cam == null or cam.is_position_behind(world_pos):
		return
	var pos := cam.unproject_position(world_pos) + Vector2(randf_range(-36, 36), randf_range(-10, 10))
	_popups.append({"text": text, "pos": pos, "t": 0.0, "color": color, "big": big, "crit": crit})


# ============================================================ эффекты ударов

func _screen(world_pos: Vector3) -> Vector2:
	var cam: Camera3D = game.camera
	if cam == null or cam.is_position_behind(world_pos):
		return _canvas.size * 0.5
	return cam.unproject_position(world_pos)


## Попадание по врагу: след клинка, вспышка-звезда; на крит — надпись, лучи и вспышка экрана.
func fx_hit(world_pos: Vector3, side: int, weak: bool, crit: bool, charged: bool, color: Color) -> void:
	var pos := _screen(world_pos)
	_fx.append({"type": "slash", "pos": pos, "side": side, "t": 0.0, "dur": 0.26,
		"color": color, "size": 150.0 if charged or crit else 110.0})
	var burst_color := Color(0.9, 0.9, 0.9)
	var size := 34.0
	if weak:
		burst_color = Color(1.0, 0.85, 0.3)
		size = 54.0
	if crit:
		burst_color = Color(1.0, 0.4, 0.15)
		size = 92.0
	if charged:
		size *= 1.3
	_fx.append({"type": "burst", "pos": pos, "t": 0.0, "dur": 0.3, "color": burst_color,
		"size": size, "rot": randf() * TAU})
	if crit:
		_fx.append({"type": "crit", "pos": pos + Vector2(0, -175), "t": 0.0, "dur": 0.8, "rot": randf_range(-0.18, 0.18)})
		_flash = 0.3
	if weak:
		combo += 1
		_combo_t = 3.0
		_combo_pop = 1.0
	else:
		combo = 0


## Парирование: расходящееся кольцо и искры.
func fx_parry(world_pos: Vector3) -> void:
	_fx.append({"type": "ring", "pos": _screen(world_pos), "t": 0.0, "dur": 0.4, "rot": randf() * TAU})
	_flash = 0.15


## Герой получил урон: следы когтей со стороны удара, серия обрывается.
func fx_hurt(side: int) -> void:
	_fx.append({"type": "claw", "side": side, "t": 0.0, "dur": 0.55})
	combo = 0


func _draw_fx(w: float, h: float) -> void:
	for f in _fx:
		var k: float = f.t / f.dur
		match str(f.type):
			"slash":
				_draw_slash(f.pos, int(f.side), k, f.color, float(f.size))
			"burst":
				var c: Color = f.color
				var grow := 0.35 + 0.65 * (1.0 - pow(1.0 - k, 3.0))
				_spikes(f.pos, float(f.size) * grow, float(f.rot), 10, Color(c, (1.0 - k) * 0.9))
				_spikes(f.pos, float(f.size) * grow * 0.55, float(f.rot) + 0.3, 8, Color(1, 1, 1, (1.0 - k)))
			"crit":
				_draw_crit(f.pos, k, float(f.rot), w, h)
			"ring":
				var r := 30.0 + 150.0 * (1.0 - pow(1.0 - k, 2.0))
				_canvas.draw_arc(f.pos, r, 0.0, TAU, 40, Color(1.0, 0.95, 0.7, 1.0 - k), 7.0 * (1.0 - k) + 1.0)
				_canvas.draw_arc(f.pos, r * 0.6, 0.0, TAU, 32, Color(1, 1, 1, (1.0 - k) * 0.6), 3.0)
				for i in 10:
					var ang := float(f.rot) + i * TAU / 10.0
					var dir := Vector2(cos(ang), sin(ang))
					_canvas.draw_line(f.pos + dir * r * 0.7, f.pos + dir * (r * 0.7 + 34.0 * (1.0 - k)),
						Color(1.0, 0.9, 0.5, 1.0 - k), 3.0)
			"claw":
				_draw_claw(int(f.side), k, w, h)
	if _flash > 0.0:
		_canvas.draw_rect(Rect2(0, 0, w, h), Color(1, 1, 1, _flash * 0.5))


## След клинка: серп, который проносится через точку удара в сторону свайпа.
func _draw_slash(pos: Vector2, side: int, k: float, color: Color, size: float) -> void:
	var d := Vector2(0, 1)                     # удар сверху вниз
	var n := Vector2(1, 0)
	if side == Enemy.Side.LEFT:
		d = Vector2(-1, 0)                     # справа налево
		n = Vector2(0, -1)
	elif side == Enemy.Side.RIGHT:
		d = Vector2(1, 0)                      # слева направо
		n = Vector2(0, -1)
	# Голова следа убегает вперёд, хвост догоняет: серп проносится и тает
	var head := -1.0 + 2.0 * minf(1.0, k * 2.2)
	var tail := -1.0 + 2.0 * clampf(k * 2.2 - 0.7, 0.0, 1.0)
	if head - tail < 0.05:
		return
	var steps := 12
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in steps + 1:
		var u := lerpf(tail, head, float(i) / steps)
		var mid := pos + d * u * size + n * (1.0 - u * u) * size * 0.3
		var thick := size * 0.16 * (1.0 - u * u) * sin(float(i) / steps * PI)
		outer.append(mid + n * thick)
		inner.append(mid - n * thick * 0.35)
	inner.reverse()
	outer.append_array(inner)
	var a := 1.0 - smoothstep(0.55, 1.0, k)
	_canvas.draw_colored_polygon(outer, Color(color.lerp(Color.WHITE, 0.65), a * 0.92))


func _draw_crit(pos: Vector2, k: float, rot: float, w: float, h: float) -> void:
	var a := 1.0 - smoothstep(0.6, 1.0, k)
	# Лучи скорости от точки удара к краям экрана
	var rays := 14
	for i in rays:
		var ang := i * TAU / rays + rot * 3.0
		var dir := Vector2(cos(ang), sin(ang))
		var near := 120.0 + 260.0 * k
		var far := maxf(w, h)
		var side := dir.orthogonal() * 9.0
		_canvas.draw_colored_polygon(PackedVector2Array([
			pos + dir * near, pos + dir * far + side, pos + dir * far - side]),
			Color(1.0, 0.8, 0.4, a * 0.22 * (1.0 - k)))
	var pop := 1.0 + 0.9 * (1.0 - smoothstep(0.0, 0.16, k))
	_canvas.draw_set_transform(pos + Vector2(0, -50.0 * k), rot, Vector2.ONE * pop)
	_spikes(Vector2.ZERO, 74.0, 0.2, 12, Color(0.55, 0.05, 0.02, a * 0.9))
	_spikes(Vector2.ZERO, 62.0, 0.2, 12, Color(1.0, 0.35, 0.1, a))
	_text("КРИТ!", Vector2(0, 14), 40, Color(1.0, 0.97, 0.75, a))
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Три рваных следа когтей поперёк экрана со стороны удара.
func _draw_claw(side: int, k: float, w: float, h: float) -> void:
	var a := 1.0 - smoothstep(0.3, 1.0, k)
	var reveal := minf(1.0, k * 5.0)
	var from := Vector2(w * 0.1, h * 0.25)
	var to := Vector2(w * 0.9, h * 0.62)
	if side == Enemy.Side.RIGHT:
		from = Vector2(w * 0.9, h * 0.25)
		to = Vector2(w * 0.1, h * 0.62)
	elif side == Enemy.Side.TOP:
		from = Vector2(w * 0.5, h * 0.12)
		to = Vector2(w * 0.5, h * 0.7)
	var dir := (to - from)
	var n := dir.normalized().orthogonal()
	for i in 3:
		var off := n * (i - 1) * 46.0
		var p0 := from + off
		var p1 := from + off + dir * reveal
		var mid := (p0 + p1) * 0.5
		_canvas.draw_colored_polygon(PackedVector2Array([p0, mid + n * 11.0, p1, mid - n * 11.0]),
			Color(0.75, 0.03, 0.03, a * 0.85))
		_canvas.draw_colored_polygon(PackedVector2Array([p0, mid + n * 4.0, p1, mid - n * 4.0]),
			Color(1.0, 0.45, 0.35, a))


## Звёздочки, кружащие над оглушённым врагом.
func _draw_stun_stars(enemy: Enemy) -> void:
	var pos := _screen(enemy.global_position + Vector3(0, 2.25 * enemy.scale.y * 0.62, 0))
	for i in 3:
		var ang := _time * 4.0 + i * TAU / 3.0
		var sp := pos + Vector2(cos(ang) * 46.0, sin(ang) * 13.0)
		var front := sin(ang) > 0.0
		_star(sp, 13.0 if front else 9.0, Color(1.0, 0.9, 0.35, 1.0 if front else 0.55))


## Счётчик серии точных ударов справа.
func _draw_combo(w: float, h: float) -> void:
	if combo < 2:
		return
	var a := clampf(_combo_t, 0.0, 1.0)
	var pop := 1.0 + 0.6 * _combo_pop
	var pos := Vector2(w - 62, h * 0.3)
	_canvas.draw_set_transform(pos, -0.12, Vector2.ONE * pop)
	_text("×%d" % combo, Vector2(0, 0), 40, Color(GOLD.lerp(Color(1.0, 0.4, 0.2), clampf((combo - 2) / 8.0, 0.0, 1.0)), a))
	_canvas.draw_set_transform(pos, -0.12, Vector2.ONE)
	_text("серия", Vector2(0, 22), 15, Color(PARCHMENT, a * 0.9))
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Звезда-вспышка с острыми лучами (треугольники вокруг центра).
func _spikes(c: Vector2, r: float, rot: float, n: int, col: Color) -> void:
	if col.a <= 0.0:
		return
	var inner := PackedVector2Array()
	for i in n:
		var a0 := rot + i * TAU / n
		var half := PI / n
		var left := c + Vector2(cos(a0 - half), sin(a0 - half)) * r * 0.42
		var right := c + Vector2(cos(a0 + half), sin(a0 + half)) * r * 0.42
		var reach := r * (1.0 if i % 2 == 0 else 0.68)
		inner.append(right)
		_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(cos(a0), sin(a0)) * reach, right, left]), col)
	_canvas.draw_colored_polygon(inner, col)


func _process(delta: float) -> void:
	_time += delta
	for i in range(_fx.size() - 1, -1, -1):
		_fx[i].t += delta
		if _fx[i].t >= _fx[i].dur:
			_fx.remove_at(i)
	_flash = maxf(0.0, _flash - delta * 4.0)
	_combo_pop = maxf(0.0, _combo_pop - delta * 6.0)
	_combo_t = maxf(0.0, _combo_t - delta)
	if _combo_t <= 0.0:
		combo = 0
	_msg_t = maxf(0.0, _msg_t - delta)
	_hurt = maxf(0.0, _hurt - delta * 2.5)
	for i in range(_popups.size() - 1, -1, -1):
		_popups[i].t += delta
		if _popups[i].t > 0.9:
			_popups.remove_at(i)
	# «След» урона догоняет настоящее значение с задержкой
	var enemy: Enemy = game.enemy
	var enemy_k := enemy.hp / enemy.max_hp if enemy != null else 1.0
	_enemy_trail = enemy_k if enemy_k > _enemy_trail else move_toward(_enemy_trail, enemy_k, delta * 0.45)
	var hp_k: float = game.hp / game.max_hp
	_hp_trail = hp_k if hp_k > _hp_trail else move_toward(_hp_trail, hp_k, delta * 0.35)
	var ended: bool = game.state == "victory" or game.state == "defeat"
	_result_t = _result_t + delta if ended else 0.0
	var boss_intro := enemy != null and enemy.is_boss and enemy.state == Enemy.State.APPEAR
	_boss_card = move_toward(_boss_card, 1.0 if boss_intro else 0.0, delta * 2.5)
	_canvas.queue_redraw()


func _on_draw() -> void:
	var size := _canvas.size
	var w := size.x
	var h := size.y
	var enemy: Enemy = game.enemy
	var cinematic: bool = game.state == "cutscene" or _boss_card > 0.01

	# Виньетка и затемнения под интерфейс
	# Тонировка и виньетка зависят от стиля графики; на рассвете кат-сцены сходят на нет
	var st: Dictionary = game.style
	var calm: float = 1.0 - game.dawn
	var tint: Color = st.tint
	if tint.a > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(tint, tint.a * calm))
	var vig := lerpf(0.62, float(st.vignette), calm)
	_canvas.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, minf(1.0, vig / 0.62)))
	if vig > 0.62:
		_canvas.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, (vig - 0.62) / 0.62))
	_canvas.draw_texture_rect(_shade_top, Rect2(0, 0, w, 150), false)
	_canvas.draw_texture_rect(_shade_bottom, Rect2(0, h - 230, w, 230), false)

	# Красная вспышка по краям при получении урона
	if _hurt > 0.0:
		_canvas.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false, Color(1.0, 0.1, 0.05, _hurt))

	if not cinematic and game.state != "victory" and game.state != "loot":
		_draw_path(w)
		_draw_purse(w)
		if enemy != null and enemy.state != Enemy.State.DEAD:
			_draw_enemy_panel(enemy, w)
			if enemy.state == Enemy.State.WINDUP:
				_draw_threat(enemy, w, h)
			if enemy.state == Enemy.State.STUNNED:
				_draw_stun_stars(enemy)
		_draw_fx(w, h)
		_draw_combo(w, h)
		_draw_popups()
		_draw_message(w, h)
		_draw_player(w, h, enemy)

	# Заставка босса: чёрные полосы и имя
	if _boss_card > 0.01 and enemy != null:
		_letterbox(w, h, _boss_card)
		_ornament(Vector2(w * 0.5, h * 0.63), w * 0.6, Color(GOLD, _boss_card))
		_text(enemy.display_name.to_upper(), Vector2(w * 0.5, h * 0.68), 38, Color(1.0, 0.3, 0.25, _boss_card))
		_text("Страж Пепельной Короны", Vector2(w * 0.5, h * 0.72), 18, Color(PARCHMENT, _boss_card * 0.85))

	# Затемнение при переходе между комнатами
	if game.fade > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.01, 0.03, game.fade))
		if game.state == "walk" and game.room_index < game.rooms.size():
			var kind: String = game.room.kind
			_ornament(Vector2(w * 0.5, h * 0.42), w * 0.45, Color(GOLD, game.fade))
			_text(str(game.KIND_NAMES[kind]), Vector2(w * 0.5, h * 0.47), 30, Color(PARCHMENT, game.fade))
			_text("Комната %d из %d" % [game.room_index + 1, game.rooms.size()], Vector2(w * 0.5, h * 0.51), 17,
				Color(GOLD, game.fade * 0.9))

	if game.state == "cutscene" or (game.state == "victory" and game.cut_t > 0.0):
		_draw_cutscene(w, h)
	if game.state == "victory" or game.state == "defeat":
		_draw_result(w, h)


# ============================================================ части интерфейса

## Путь забега: линия и ромбы комнат; пройденные яркие, текущая крупнее и пульсирует.
func _draw_path(w: float) -> void:
	var n: int = game.rooms.size()
	var step := minf(30.0, (w - 180.0) / maxf(1.0, n - 1))
	var x0 := w * 0.5 - step * (n - 1) * 0.5
	var y := 24.0
	_canvas.draw_line(Vector2(x0, y), Vector2(x0 + step * (n - 1), y), Color(GOLD_DARK, 0.9), 2.0)
	if game.room_index > 0:
		_canvas.draw_line(Vector2(x0, y), Vector2(x0 + step * mini(game.room_index, n - 1), y), GOLD, 2.0)
	for i in n:
		var kind: String = game.rooms[i].kind
		var c: Color = PIP_COLORS[kind]
		var r := 6.0
		if kind == "boss":
			r = 8.0
		if i == game.room_index:
			r += 2.5 + sin(_time * 5.0) * 1.0
		elif i > game.room_index:
			c = c.darkened(0.55)
		var p := Vector2(x0 + i * step, y)
		_diamond(p, r + 2.5, GOLD if i <= game.room_index else GOLD_DARK)
		_diamond(p, r + 1.0, INK)
		_diamond(p, r - 0.5, c)


## Кошель: осколки слева, золото справа от пути.
func _draw_purse(w: float) -> void:
	_chip(Rect2(10, 12, 62, 24))
	_diamond(Vector2(24, 24), 6.5, Color(0.55, 0.85, 1.0))
	_diamond(Vector2(24, 24), 3.0, Color(0.9, 0.97, 1.0))
	_text_left(str(game.shards), Vector2(36, 30), 16, PARCHMENT)
	_chip(Rect2(w - 72, 12, 62, 24))
	_canvas.draw_circle(Vector2(w - 58, 24), 6.5, GOLD)
	_canvas.draw_circle(Vector2(w - 58, 24), 4.0, Color(1.0, 0.9, 0.55))
	_text_left(str(game.gold), Vector2(w - 46, 30), 16, PARCHMENT)


func _draw_enemy_panel(enemy: Enemy, w: float) -> void:
	var bw := w * (0.84 if enemy.is_boss else 0.7)
	var x0 := (w - bw) * 0.5
	var y := 72.0
	var bh := 18.0 if enemy.is_boss else 14.0
	_text(enemy.display_name, Vector2(w * 0.5, y - 8), 19, Color(1.0, 0.45, 0.4) if enemy.is_boss else PARCHMENT)
	if game.wave.size() > 1:
		_text_left("%d/%d" % [game.wave_index + 1, game.wave.size()], Vector2(x0 + bw + 8, y + 12), 13, Color(GOLD, 0.9))
	_fancy_bar(Rect2(x0, y, bw, bh), enemy.hp / enemy.max_hp, _enemy_trail, HP_RED)
	# Деления фаз босса
	var phases: Array = enemy.data.get("phases", [])
	for ph: Dictionary in phases:
		var px := x0 + bw * float(ph.hp)
		_canvas.draw_line(Vector2(px, y - 2), Vector2(px, y + bh + 2), GOLD, 2.0)
	# Стойкость: тонкая полоса под здоровьем, при оглушении мигает
	var sy := y + bh + 7.0
	var sc := GOLD
	if enemy.state == Enemy.State.STUNNED:
		sc = Color(1.0, 0.95, 0.6).lerp(GOLD, 0.5 + 0.5 * sin(_time * 14.0))
	_canvas.draw_rect(Rect2(x0 + bw * 0.1 - 1, sy - 1, bw * 0.8 + 2, 7), Color(INK, 0.85))
	_canvas.draw_rect(Rect2(x0 + bw * 0.1, sy, bw * 0.8 * clampf(enemy.stagger / enemy.stagger_max, 0.0, 1.0), 5), sc)


func _draw_popups() -> void:
	for pp in _popups:
		var t: float = pp.t
		var c: Color = pp.color
		c.a = 1.0 - smoothstep(0.5, 0.9, t)
		var big: bool = pp.big
		# Цифра «выстреливает» крупной и оседает
		var pop := 1.0 + 0.7 * (1.0 - smoothstep(0.0, 0.18, t))
		var fsize := int((40 if big else 27) * pop)
		if bool(pp.get("crit", false)):
			fsize = int(54 * pop)
		_text(pp.text, pp.pos + Vector2(0, -80.0 * (1.0 - pow(1.0 - t / 0.9, 2.0))), fsize, c)


func _draw_message(w: float, h: float) -> void:
	if _msg_t <= 0.0:
		return
	var age := _msg_dur - _msg_t
	var c := _msg_color
	c.a = clampf(_msg_t / minf(0.3, _msg_dur), 0.0, 1.0)
	var pop := 1.0 + 0.35 * (1.0 - smoothstep(0.0, 0.15, age))
	var fsize := int(28 * pop)
	var lines := _wrap(_msg, fsize, w * 0.84)
	var y := h * 0.34
	var tw := 0.0
	for line in lines:
		tw = maxf(tw, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x)
	var band := Rect2(w * 0.5 - tw * 0.5 - 22, y - fsize - 4, tw + 44, lines.size() * (fsize + 6) + 14)
	_canvas.draw_style_box(_box_style(Color(INK, 0.55 * c.a), Color(0, 0, 0, 0), 0, 14), band)
	for line in lines:
		_text(line, Vector2(w * 0.5, y), fsize, c)
		y += fsize + 6


## Полосы героя: здоровье со значком сердца и числом, стойкость, заряд, подсказка.
func _draw_player(w: float, h: float, enemy: Enemy) -> void:
	_text(_hint(enemy), Vector2(w * 0.5, h - 112), 15, Color(PARCHMENT, 0.8))

	var px := 62.0
	var pw := w - px - 22.0
	var hy := h - 88.0
	var low: bool = game.hp / game.max_hp <= 0.3
	_fancy_bar(Rect2(px, hy, pw, 20), game.hp / game.max_hp, _hp_trail,
		HP_RED.lerp(Color(1, 0.5, 0.3), 0.5 + 0.5 * sin(_time * 8.0)) if low else HP_GREEN)
	_text("%d / %d" % [roundi(game.hp), roundi(game.max_hp)], Vector2(px + pw * 0.5, hy + 16), 14, Color.WHITE)
	# Медальон-сердце слева
	var hc := Vector2(34, hy + 12)
	_canvas.draw_circle(hc, 22, GOLD_DARK)
	_canvas.draw_circle(hc, 20, GOLD)
	_canvas.draw_circle(hc, 17, INK)
	_heart(hc + Vector2(0, 1), 10.0 + (1.2 * sin(_time * 8.0) if low else 0.0), HP_RED)

	_fancy_bar(Rect2(px, hy + 30.0, pw * 0.5, 10), game.stamina / game.max_stamina, 0.0, STAMINA)
	# Оружие в руке: название цветом редкости
	var wpn: Dictionary = Save.data.weapon
	_text_right(Items.title(game.items, wpn), Vector2(px + pw, hy + 41.0), 14, Items.color(game.items, wpn))

	if game.block_t > 0.0:
		_chip(Rect2(w * 0.5 - 42, h - 40, 84, 26))
		_text("ЩИТ", Vector2(w * 0.5, h - 21), 16, Color(0.8, 0.9, 1.0))
	elif game.charging:
		var k := clampf(game.charge_t / float(game.p.charge_time), 0.0, 1.0)
		_fancy_bar(Rect2(w * 0.25, h - 34, w * 0.5, 10), k, 0.0, Color(1.0, 0.6, 0.2) if k < 1.0 else Color(1.0, 0.95, 0.5))


## Стрелка у края экрана со стороны удара. В окне парирования — белая, крупная, со свечением.
func _draw_threat(enemy: Enemy, w: float, h: float) -> void:
	var in_window: bool = enemy.time_to_impact() <= float(game.p.parry_window)
	var c := Color(1.0, 0.97, 0.88, 0.98) if in_window else Color(1.0, 0.18, 0.1, 0.6 + 0.35 * sin(_time * 18.0))
	var s := 46.0 if in_window else 32.0
	var center := Vector2(w * 0.5, 150)
	var dir := Vector2(0, -1)
	match enemy.attack_side:
		Enemy.Side.LEFT:
			center = Vector2(34, h * 0.4)
			dir = Vector2(-1, 0)
		Enemy.Side.RIGHT:
			center = Vector2(w - 34, h * 0.4)
			dir = Vector2(1, 0)
	var side := Vector2(-dir.y, dir.x)
	# Два шеврона: мягкое свечение и чёткая стрелка
	for pass_i in 2:
		var ss := s + (10.0 if pass_i == 0 else 0.0)
		var col := Color(c, c.a * 0.25) if pass_i == 0 else c
		_canvas.draw_colored_polygon(PackedVector2Array([
			center + dir * ss * 0.5, center - dir * ss * 0.5 + side * ss,
			center - dir * ss * 0.1, center - dir * ss * 0.5 - side * ss]), col)


func _hint(enemy: Enemy) -> String:
	if game.state == "room":
		return "Тап — " + str(ROOM_HINTS[game.room.kind])
	if enemy == null or game.state != "fight" or enemy.state == Enemy.State.APPEAR:
		return ""
	if enemy.state == Enemy.State.WINDUP:
		return "Удар %s! Свайп навстречу при вспышке" % game.SIDE_NAMES[enemy.attack_side]
	if enemy.state == Enemy.State.STUNNED:
		return "Удержи палец и отпусти — заряженный удар"
	return "Свайп к жёлтой метке — точный удар"


## Кат-сцена победы над боссом: чёрные полосы, строки истории по очереди, белая заря.
func _draw_cutscene(w: float, h: float) -> void:
	var t: float = game.cut_t
	if game.state == "cutscene":
		_letterbox(w, h, smoothstep(0.0, 0.8, t))
		var lines: Array = game.run_cfg.get("cutscene", [])
		var slot: float = (game.CUT_TIME - 2.4) / maxf(1.0, lines.size())
		for i in lines.size():
			var lt := t - 0.6 - i * slot
			var a := smoothstep(0.0, 0.6, lt) * (1.0 - smoothstep(slot - 0.5, slot, lt))
			if a <= 0.0:
				continue
			var y := h * 0.925
			for line in _wrap(str(lines[i]), 19, w * 0.9):
				_text(line, Vector2(w * 0.5, y), 19, Color(PARCHMENT, a))
				y += 28
	if game.white > 0.0:
		var a: float = game.white if game.state == "cutscene" else maxf(0.0, 1.0 - _result_t * 1.2)
		_canvas.draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.95, 0.82, a))


## Экран итога: тёмная панель с золотой рамкой, звёзды, строки статистики.
func _draw_result(w: float, h: float) -> void:
	var a := smoothstep(0.0, 0.5, _result_t)
	var ok: bool = game.state == "victory"
	_canvas.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.01, 0.04, 0.6 * a))
	var slide := (1.0 - smoothstep(0.0, 0.45, _result_t)) * 60.0
	var panel := Rect2(w * 0.07, h * 0.22 + slide, w * 0.86, 430)
	_canvas.draw_style_box(_box_style(Color(0.12, 0.09, 0.13, 0.96 * a), Color(GOLD, a), 3, 18), panel)
	_canvas.draw_style_box(_box_style(Color(0, 0, 0, 0), Color(GOLD_DARK, a), 1, 13), panel.grow(-8))
	var cx := w * 0.5
	var y := panel.position.y + 62
	_text("ПОБЕДА" if ok else "СТРАЖ ПАЛ", Vector2(cx, y), 40, Color(GOLD if ok else HP_RED, a))
	_ornament(Vector2(cx, y + 20), panel.size.x * 0.6, Color(GOLD, a))
	var s: Dictionary = game.stats

	# Звёзды: за победу, за мало полученного урона, за парирования
	var stars := 0
	if ok:
		stars = 1 + int(float(s.taken) < 40.0) + int(int(s.parries) >= 5)
	y += 70
	for i in 3:
		var appear := smoothstep(0.5 + i * 0.25, 0.75 + i * 0.25, _result_t)
		var lit := i < stars
		var r := 20.0 * (1.0 + 0.5 * (1.0 - appear)) if lit else 18.0
		var sp := Vector2(cx + (i - 1) * 62.0, y)
		_star(sp, r + 3.0, Color(GOLD_DARK, a))
		_star(sp, r, Color(GOLD, a * appear) if lit else Color(0.2, 0.17, 0.2, a))

	y += 62
	var rows := [
		["Комнат пройдено", "%d из %d" % [s.rooms, game.rooms.size()]],
		["Точных ударов", str(s.weak_hits)],
		["Парирований", str(s.parries)],
		["Блоков и уклонений", str(int(s.blocks) + int(s.dodges))],
		["Получено урона", str(roundi(s.taken))],
		["Осколки / золото", "%d / %d" % [game.shards, game.gold]],
	]
	for i in rows.size():
		var ra := a * smoothstep(0.6 + i * 0.1, 0.9 + i * 0.1, _result_t)
		_text_left(str(rows[i][0]), Vector2(panel.position.x + 34, y), 17, Color(PARCHMENT, ra * 0.85))
		_text_right(str(rows[i][1]), Vector2(panel.end.x - 34, y), 17, Color(GOLD, ra))
		y += 30
	_text("Сид забега: %d" % game.run_seed, Vector2(cx, panel.end.y - 18), 12, Color(PARCHMENT, 0.45 * a))
	if _result_t > 1.6:
		_text("II — кузница и настройки", Vector2(cx, panel.end.y + 76), 15, Color(GOLD, 0.8))
		_text("Тап — новый забег", Vector2(cx, panel.end.y + 44), 21, Color(PARCHMENT, 0.6 + 0.4 * sin(_time * 4.0)))


# ============================================================ примитивы

func _letterbox(w: float, h: float, k: float) -> void:
	var bar := h * 0.12 * k
	_canvas.draw_rect(Rect2(0, 0, w, bar), Color.BLACK)
	_canvas.draw_rect(Rect2(0, h - bar, w, bar), Color.BLACK)


## Полоса с тёмной рамкой, золотым кантом, «следом» урона и бликом сверху.
func _fancy_bar(r: Rect2, k: float, trail: float, c: Color) -> void:
	var radius := int(r.size.y * 0.5)
	_canvas.draw_style_box(_box_style(INK, GOLD_DARK, 2, radius + 3), r.grow(3.0))
	_canvas.draw_style_box(_box_style(Color(0.16, 0.13, 0.17), Color(0, 0, 0, 0), 0, radius), r)
	k = clampf(k, 0.0, 1.0)
	if trail > k:
		var tr := r
		tr.size.x = maxf(r.size.y, r.size.x * clampf(trail, 0.0, 1.0))
		_canvas.draw_style_box(_box_style(Color(1.0, 0.95, 0.85, 0.85), Color(0, 0, 0, 0), 0, radius), tr)
	if k > 0.0:
		var f := r
		f.size.x = maxf(r.size.y, r.size.x * k)
		_canvas.draw_style_box(_box_style(c, Color(0, 0, 0, 0), 0, radius), f)
		var hl := Rect2(f.position + Vector2(5, 2), Vector2(maxf(0.0, f.size.x - 10), f.size.y * 0.3))
		_canvas.draw_style_box(_box_style(Color(1, 1, 1, 0.28), Color(0, 0, 0, 0), 0, 4), hl)


func _chip(r: Rect2) -> void:
	_canvas.draw_style_box(_box_style(Color(INK, 0.8), GOLD_DARK, 1, 12), r)


func _box_style(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb


func _diamond(c: Vector2, r: float, col: Color) -> void:
	_canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


## Орнамент-разделитель: линия с ромбами.
func _ornament(c: Vector2, width: float, col: Color) -> void:
	_canvas.draw_line(c - Vector2(width * 0.5, 0), c - Vector2(12, 0), col, 1.5)
	_canvas.draw_line(c + Vector2(12, 0), c + Vector2(width * 0.5, 0), col, 1.5)
	_diamond(c, 6.0, col)
	_diamond(c - Vector2(width * 0.5, 0), 3.0, col)
	_diamond(c + Vector2(width * 0.5, 0), 3.0, col)


func _heart(c: Vector2, r: float, col: Color) -> void:
	_canvas.draw_circle(c + Vector2(-r * 0.45, -r * 0.25), r * 0.52, col)
	_canvas.draw_circle(c + Vector2(r * 0.45, -r * 0.25), r * 0.52, col)
	_canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-r * 0.93, 0), c + Vector2(r * 0.93, 0), c + Vector2(0, r * 0.95)]), col)


func _star(c: Vector2, r: float, col: Color) -> void:
	if col.a <= 0.0:
		return
	# Пять треугольников-лучей и пятиугольник в центре: невыпуклую звезду рисуем по частям
	var inner := PackedVector2Array()
	for i in 5:
		var a0 := -PI / 2.0 + i * TAU / 5.0
		var left := c + Vector2(cos(a0 - PI / 5.0), sin(a0 - PI / 5.0)) * r * 0.45
		var right := c + Vector2(cos(a0 + PI / 5.0), sin(a0 + PI / 5.0)) * r * 0.45
		inner.append(right)
		_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(cos(a0), sin(a0)) * r, right, left]), col)
	_canvas.draw_colored_polygon(inner, col)


func _text(t: String, center: Vector2, fsize: int, c: Color) -> void:
	var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	_text_left(t, center - Vector2(tw * 0.5, 0), fsize, c)


func _text_right(t: String, right: Vector2, fsize: int, c: Color) -> void:
	var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	_text_left(t, right - Vector2(tw, 0), fsize, c)


## Текст с мягкой тенью и тонкой обводкой: читается на любом фоне.
func _text_left(t: String, pos: Vector2, fsize: int, c: Color) -> void:
	if c.a <= 0.0 or t == "":
		return
	_canvas.draw_string(_font, pos + Vector2(0, 2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, c.a * 0.5))
	_canvas.draw_string_outline(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, maxi(2, fsize / 8), Color(INK, c.a * 0.9))
	_canvas.draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, c)


## Перенос длинной строки по словам под ширину экрана.
func _wrap(t: String, fsize: int, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in t.split(" "):
		var probe := word if line == "" else line + " " + word
		if line != "" and _font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > max_w:
			out.append(line)
			line = word
		else:
			line = probe
	if line != "":
		out.append(line)
	return out


func _radial(inner: Color, outer: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	g.set_offset(0, 0.45)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 1.0)
	t.width = 128
	t.height = 128
	return t


func _linear(from: Color, to: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 8
	t.height = 64
	return t
