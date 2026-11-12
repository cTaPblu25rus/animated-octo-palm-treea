## Автоигрок прототипа: проходит бой с тремя врагами через тот же распознаватель
## жестов, что и палец (press/release в gestures.gd), и проверяет, что сработал
## каждый приём: точный удар, парирование, блок, уклонение, заряженный удар.
## Запуск: godot --headless --path . -- --autoplay [--shots=папка]
## Код выхода 0 — комната очищена и все приёмы сработали.
##
## План реакции на замах врага (по кругу): парирование, блок, парирование, уклонение.
## Оглушённого врага добивает заряженным ударом, в остальное время бьёт в метку.
extends Node

const Enemy := preload("res://scripts/enemy.gd")
const Save := preload("res://scripts/save.gd")
const Items := preload("res://scripts/items.gd")
const TIMEOUT := 420.0
const REACTIONS := ["parry", "block", "parry", "dodge"]

var game: Node
## false — запущен из меню разработчика: в конце не выходить из игры, только сообщить.
var quit_on_end := true
## --alt: на развилках бот сворачивает на вторую дорогу (элитные бои и лавки).
var alt_path := false
var shots_dir := ""
var t := 0.0
var done := false
var _reaction := 0
var _reacted_windup := false
var _hold_t := -1.0          # >0: палец удержан, отпустить по истечении
var _queue: Array = []       # отложенные свайпы: [задержка, направление]
var _shot_t := 0.0
var _shot_n := 0
var _last_windup := -1
var _room_t := 0.0
var _fx_seen := {}
var _shop_buys := 0
var _fx_shots: Array = []


func _ready() -> void:
	alt_path = OS.get_cmdline_user_args().has("--alt")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(shots_dir)
	if quit_on_end:
		Engine.time_scale = 3.0 if shots_dir == "" else 1.0
	var kinds: Array = []
	for r: Dictionary in game.rooms:
		kinds.append(r.kind)
	print("BOT: старт, сид %d, комнаты: %s" % [game.run_seed, ", ".join(kinds)])


func _process(delta: float) -> void:
	if done:
		return
	t += delta
	if shots_dir != "":
		# Кадры эффектов: через мгновение после крита, парирования и полученного удара
		for key: String in ["crits", "parries", "hurt"]:
			var n := int(game.stats[key])
			if n != int(_fx_seen.get(key, 0)):
				_fx_seen[key] = n
				_fx_shots.append([0.09, "%s_%d" % [key, n]])
		for i in range(_fx_shots.size() - 1, -1, -1):
			_fx_shots[i][0] -= delta
			if _fx_shots[i][0] <= 0.0:
				_shot(_fx_shots[i][1])
				_fx_shots.remove_at(i)
		_shot_t += delta
		if _shot_t > 0.7:
			_shot_t = 0.0
			_shot("s%03d" % _shot_n)
			_shot_n += 1
	if game.state == "victory":
		_finish()
		return
	if game.state == "defeat" or t > TIMEOUT:
		_fail("страж пал" if game.state == "defeat" else "таймаут")
		return
	_run_queue(delta)
	if game.state == "loot":
		# Берём оружие, если оно сильнее текущего, иначе разбираем
		_room_t += delta
		if _room_t > 0.8:
			_room_t = 0.0
			var cur: Dictionary = Save.data.weapon
			game.meta_ui.choose(Items.power(game.items, game.meta_ui.offered) > Items.power(game.items, cur))
		return
	if game.state == "choice":
		# Развилка — основная дорога; дар — первый; лавка — купить доступное, иначе уйти
		_room_t += delta
		if _room_t > 0.8 and game.meta_ui.is_choice_open():
			_room_t = 0.0
			var opts: Array = game.meta_ui.choice_options
			var pick := 0
			if game.meta_ui.choice_kind == "fork" and alt_path:
				pick = 1
			if game.meta_ui.choice_kind == "shop":
				pick = opts.size() - 1
				for i in opts.size() - 1:
					if bool(opts[i].get("enabled", true)) and _shop_buys < 2:
						pick = i
						_shop_buys += 1
						break
			game.meta_ui.pick(pick)
		return
	if game.state == "room":
		_room_t += delta
		if _room_t > 0.8:
			_room_t = 0.0
			var c := _center()
			game.gestures.press(c)
			game.gestures.release(c)
		return
	_room_t = 0.0
	if game.state != "fight":
		return
	if _hold_t > 0.0:
		_hold_t -= delta
		if _hold_t <= 0.0:
			game.gestures.release(_center())
		return
	var e: Enemy = game.enemy
	if e == null or not e.is_alive() or e.state == Enemy.State.APPEAR:
		return
	if e.windup_count != _last_windup:
		_last_windup = e.windup_count
		_reacted_windup = false
	if e.state == Enemy.State.WINDUP:
		_react(e)
		return
	# Умения, если открыты: лечение при низком здоровье, вихрь по открытому врагу
	if game.skill_ready(2) and game.hp < game.max_hp * 0.6:
		game.use_skill(2)
	if game.skill_ready(1) and e.is_open():
		game.use_skill(1)
		return
	if game.attack_cd > 0.0 or game.stamina < 30.0:
		return
	var break_guard: bool = e.guarded() and e.state_t < e.state_dur - 1.0
	if ((e.state == Enemy.State.STUNNED and game.stats.charged < 3) or break_guard) and game.stamina >= 40.0:
		game.gestures.press(_center())
		_hold_t = 0.75
		return
	_swipe(_dir(e.weak_side))


## Реакция на замах: ждём окна парирования и делаем очередной приём из плана.
func _react(e: Enemy) -> void:
	if _reacted_windup:
		return
	var window: float = float(game.p.parry_window)
	var kind: String = REACTIONS[_reaction % REACTIONS.size()]
	if kind == "block" and game.skill_ready(0):
		# Удар щитом прерывает замах
		_reacted_windup = true
		_reaction += 1
		game.use_skill(0)
		return
	if e.combo > 1 or game.stamina < 40.0:
		kind = "parry"      # в серии босса и без сил надёжно только парирование
	var lead := window * 0.5 if kind == "parry" else 0.35
	if e.time_to_impact() > lead:
		return
	_reacted_windup = true
	_reaction += 1
	match kind:
		"parry":
			_swipe(_dir(e.attack_side))
		"block":
			_swipe("down")
		"dodge":
			# Уходим в сторону, противоположную удару; от удара сверху — влево
			var d := "left" if e.attack_side != Enemy.Side.LEFT else "right"
			_swipe(d)
			_queue.append([0.05, d])
	print("BOT: t=%.1f %s против удара %s (здоровье %d, стойкость %d)" % [
		t, kind, game.SIDE_NAMES[e.attack_side], game.hp, game.stamina])


func _run_queue(delta: float) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		_queue[i][0] -= delta
		if _queue[i][0] <= 0.0:
			var d: String = _queue[i][1]
			_queue.remove_at(i)
			_swipe(d)


func _swipe(dir: String) -> void:
	var c := _center()
	var off := {"left": Vector2(-160, 0), "right": Vector2(160, 0),
		"up": Vector2(0, -160), "down": Vector2(0, 160)}
	game.gestures.press(c)
	game.gestures.release(c + off[dir])


func _dir(side: int) -> String:
	match side:
		Enemy.Side.LEFT:
			return "left"
		Enemy.Side.RIGHT:
			return "right"
	return "up"


func _center() -> Vector2:
	var s: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(s.x * 0.5, s.y * 0.75)


func _finish() -> void:
	var s: Dictionary = game.stats
	print("BOT: итог за %.0f с: %s, здоровье %d" % [t, str(s), game.hp])
	var missing: Array[String] = []
	for key in ["weak_hits", "parries", "blocks", "dodges", "charged"]:
		if int(s[key]) == 0:
			missing.append(key)
	# На основной дороге обязаны встретиться все мирные комнаты, на второй — элита или лавка
	var must: Array = ["fight", "chest", "altar", "event"]
	if alt_path:
		must = ["fight"]
		if not (game.visited.has("elite") or game.visited.has("shop")):
			missing.append("на второй дороге нет ни элиты, ни лавки")
	for kind: String in must:
		if not game.visited.has(kind):
			missing.append("комната " + kind)
	if int(Save.data.level) >= 6 and int(s.skills) == 0:
		missing.append("умения открыты, но не применялись")
	if int(s.boons) == 0:
		missing.append("не выбран ни один дар")
	if int(s.forks) == 0:
		missing.append("не было развилок")
	if int(s.drops) == 0:
		missing.append("не выпало оружие")
	if int(s.boss) == 0:
		missing.append("босс не побеждён")
	if int(s.rooms) != game.rooms.size():
		missing.append("пройдено комнат %d из %d" % [s.rooms, game.rooms.size()])
	var path: Array = []
	for r: Dictionary in game.rooms:
		path.append(str(r.kind) + ("(" + ",".join(r.wave) + ")" if r.has("wave") else ""))
	print("BOT: путь: ", " → ".join(path))
	print("BOT: уровень %d, опыт за забег %d, умений применено %d" % [int(Save.data.level), game.run_xp, int(s.skills)])
	if missing.is_empty():
		print("BOT: ЗАБЕГ ПРОЙДЕН (сид %d, осколки %d, золото %d), все приёмы и типы комнат сработали" % [
			game.run_seed, game.shards, game.gold])
		await _end(0)
	else:
		_fail("не сработали приёмы: " + ", ".join(missing))


func _fail(reason: String) -> void:
	print("BOT: НЕ ПРОЙДЕНО — %s. Статистика: %s" % [reason, str(game.stats)])
	await _end(1)


func _exit_tree() -> void:
	# Не оставлять палец «прижатым», если бота выключили посреди удержания
	if _hold_t > 0.0:
		game.gestures.release(_center())


func _end(code: int) -> void:
	done = true
	if not quit_on_end:
		game.hud.say("Автоигрок: %s" % ("всё прошло" if code == 0 else "не прошёл, см. лог"), Color(0.6, 1.0, 0.6), 2.5)
		return
	Engine.time_scale = 1.0
	if shots_dir != "":
		await get_tree().create_timer(3.0).timeout
		_shot("final")
	get_tree().quit(code)


func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [shots_dir, shot_name])
