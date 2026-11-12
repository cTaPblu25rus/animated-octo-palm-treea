## Автотест меню разработчика: нажимает настоящие кнопки меню и проверяет результат.
## Запуск: godot --headless --path . -- --devtest [--shots=папка]
## Код выхода 0 — все проверки прошли. Последний шаг — перезапуск забега с сидом,
## поэтому тест продолжается после перезагрузки сцены (этап хранится в Engine).
extends Node

const Enemy := preload("res://scripts/enemy.gd")
const STAGE := "dev_test_stage"

var game: Node
var shots_dir := ""
var _fails: Array[String] = []
var _passed := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(shots_dir)
	if Engine.has_meta(STAGE):
		_after_reload()
	else:
		_run()


func _run() -> void:
	var dev: Node = game.dev_menu
	_check(dev != null, "меню создано в debug-сборке")
	await _until(func() -> bool: return game.state == "fight" and game.enemy != null)
	await _wait(1.2)

	# Открыть меню: игра на паузе, жесты выключены
	dev._toggle.pressed.emit()
	_check(get_tree().paused and dev._panel.visible and not game.gestures.enabled, "меню открывается, игра на паузе")
	await _shot("menu")

	_press("god")
	var hp: float = game.hp
	game._on_struck(Enemy.Side.LEFT, 50.0)
	_check(is_equal_approx(game.hp, hp), "бессмертие: удар не снял здоровье")
	_press("god")
	game._on_struck(Enemy.Side.LEFT, 10.0)
	_check(game.hp < hp, "бессмертие выключается")

	_press("hurt")
	_check(game.hp <= game.max_hp - 30.0, "−30 здоровья")
	_press("heal")
	_check(is_equal_approx(game.hp, game.max_hp), "полное здоровье")

	_press("stamina")
	var st: float = game.stamina
	game._spend(60.0)
	_check(is_equal_approx(game.stamina, st), "бесконечная стойкость")
	_press("stamina")

	var gold: int = game.gold
	_press("money")
	_check(game.gold == gold + 100, "+100 золота")

	_press("stun")
	_check(game.enemy.state == Enemy.State.STUNNED, "оглушить врага")

	_press("one_hit")
	dev._set_open(false)
	game._attack(game.enemy.weak_side, 1.0)
	_check(not game.enemy.is_alive(), "убийство с одного удара")
	dev._set_open(true)
	_press("one_hit")

	# Переход к комнате и пропуск комнаты
	var before: int = game.room_index
	_press("skip")
	_check(game.room_index == before + 1, "пропустить комнату")
	dev._set_open(false)
	await _until(func() -> bool: return game.state != "walk")

	# Босс и его фазы
	dev._set_open(true)
	_press("boss")
	_check(game.room_index == game.rooms.size() - 1, "перейти к боссу")
	await _until(func() -> bool: return game.enemy != null and game.enemy.is_boss and game.enemy.state != Enemy.State.APPEAR)
	dev._set_open(true)
	_press("phase")
	_check(game.enemy.phase == 1, "следующая фаза босса (1 → 2)")
	_press("phase")
	_check(game.enemy.phase == 2, "следующая фаза босса (2 → 3)")
	_press("kill")
	_check(not game.enemy.is_alive(), "убить босса")
	dev._set_open(false)
	await _until(func() -> bool: return game.state == "cutscene")
	_check(true, "после босса начинается кат-сцена")

	# Кат-сцена с кнопки и экран итога
	dev._set_open(true)
	_press("cutscene")
	_check(game.state == "cutscene", "кат-сцена с кнопки")
	await _until(func() -> bool: return game.state == "victory")
	_check(true, "кат-сцена доходит до экрана итога")
	dev._set_open(true)
	_press("room_pick")
	_press("room_pick")
	_press("goto")
	_check(game.room_index == 2 and game.state == "walk", "перейти в выбранную комнату после победы")
	_check(is_zero_approx(game.white) and is_zero_approx(game.cut_t), "рассвет сброшен при переходе")

	# Отладка
	_press("overlay")
	dev._set_open(false)
	await _wait(0.2)
	_check(dev._overlay.visible and dev._overlay.text.begins_with("FPS"), "оверлей FPS")
	await _shot("overlay")
	dev._set_open(true)
	_press("overlay")
	_press("speed")
	_check(is_equal_approx(Engine.time_scale, 0.25), "скорость ×0.25")
	for i in 4:
		_press("speed")
	_check(is_equal_approx(Engine.time_scale, 1.0), "скорость возвращается к ×1")
	_press("sound")
	_press("buzz")
	_press("bot")
	_check(dev._bot != null, "автоигрок включается из меню")
	_press("bot")
	_check(dev._bot == null, "автоигрок выключается")

	# Новый забег с выбранным сидом: проверка продолжится после перезагрузки
	dev._seed_pick = 12345
	_press("seed_plus")
	Engine.set_meta(STAGE, {"passed": _passed, "fails": _fails})
	_press("seed_new")


func _after_reload() -> void:
	var saved: Dictionary = Engine.get_meta(STAGE)
	Engine.remove_meta(STAGE)
	_passed = int(saved.passed)
	_fails.assign(saved.fails)
	await _wait(0.3)
	_check(game.run_seed == 12346, "новый забег с сидом 12346 (было %d)" % game.run_seed)
	_check(not get_tree().paused, "после перезапуска игра не на паузе")
	game.dev_menu._restart_random_flag_only()
	_finish()


func _press(key: String) -> void:
	var b: Button = game.dev_menu._buttons[key]
	b.pressed.emit()


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("DEVTEST: ok   ", what)
	else:
		_fails.append(what)
		print("DEVTEST: FAIL ", what)


func _until(cond: Callable, timeout: float = 30.0) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	if t >= timeout:
		_check(false, "таймаут ожидания")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout


func _finish() -> void:
	print("DEVTEST: прошло %d, ошибок %d" % [_passed, _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)


func _shot(shot_name: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots_dir, shot_name])
