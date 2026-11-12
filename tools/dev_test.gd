## Автотест меню разработчика: нажимает настоящие кнопки меню и проверяет результат.
## Запуск: godot --headless --path . -- --devtest [--shots=папка]
## Код выхода 0 — все проверки прошли. Последний шаг — перезапуск забега с сидом,
## поэтому тест продолжается после перезагрузки сцены (этап хранится в Engine).
extends Node

const Enemy := preload("res://scripts/enemy.gd")
const Save := preload("res://scripts/save.gd")
const Items := preload("res://scripts/items.gd")
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
	await _until(func() -> bool: return game.state == "loot")
	_check(int(game.meta_ui.offered.rarity) >= 2, "с босса выпадает эпическое или легендарное оружие")
	game.meta_ui.choose(false)
	_check(game.state == "cutscene", "после добычи с босса начинается кат-сцена")

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

	# Добыча: взять легендарное, разобрать обычное
	dev._set_open(true)
	_press("wipe")
	_press("legend")
	_check(game.meta_ui.is_loot_open() and int(game.meta_ui.offered.rarity) == 3, "карточка легендарного оружия")
	await _wait(0.3)
	await _shot("loot")
	var offered: Dictionary = game.meta_ui.offered
	game.meta_ui.choose(true)
	_check(Save.data.weapon == offered and not game.meta_ui.is_loot_open(), "взять оружие: оно в руке")
	_check(is_equal_approx(float(game.p.attack_damage),
		float(game.cfg.player.attack_damage) * Items.damage_mult(game.items, offered) * (1.2 if str(offered.affix) == "keen" else 1.0)),
		"урон пересчитан под новое оружие")
	dev._set_open(true)
	_press("drop")
	var shards: int = game.shards
	var salvage := Items.salvage(game.items, game.meta_ui.offered)
	game.meta_ui.choose(false)
	_check(game.shards == shards + salvage and Save.data.weapon == offered, "разобрать: осколки начислены, оружие прежнее")

	# Кузница: улучшения и заточка
	dev._set_open(true)
	_press("money")
	_press("forge")
	_check(game.meta_ui.is_forge_open(), "кузница открывается")
	await _wait(0.2)
	await _shot("forge")
	var max_hp: float = game.max_hp
	var before_shards: int = game.shards
	game.meta_ui._forge_buttons["hp"].pressed.emit()
	_check(is_equal_approx(game.max_hp, max_hp + 10.0) and game.shards == before_shards - 8, "улучшение «Закалка»: +10 здоровья за 8 осколков")
	var dmg: float = float(game.p.attack_damage)
	var gold2: int = game.gold
	game.meta_ui._forge_buttons["sharpen"].pressed.emit()
	_check(int(Save.data.weapon.level) == 1 and float(game.p.attack_damage) > dmg and game.gold == gold2 - 40, "заточка: +1 уровень за 40 золота")
	_press("wipe")
	_check(game.shards == 0 and str(Save.data.weapon.id) == "guard_sword" and is_equal_approx(game.max_hp, 100.0), "сброс сохранения")
	game.meta_ui.hide_forge()

	# Дары и лавка
	dev._set_open(true)
	_press("boon")
	_check(game.meta_ui.is_choice_open() and game.meta_ui.choice_kind == "boon" and game.meta_ui.choice_options.size() == 3, "три дара на выбор")
	await _wait(0.3)
	await _shot("boon")
	var boon_id: String = game.meta_ui.choice_options[1].tag
	game.meta_ui.pick(1)
	_check(game.has_boon(boon_id) and not game.meta_ui.is_choice_open(), "дар получен: " + boon_id)
	game.gold = 100
	game.hp = 40.0
	game._open_shop()
	await _wait(0.3)
	await _shot("shop")
	_check(game.meta_ui.choice_kind == "shop", "лавка открывается")
	game.meta_ui.pick(0)
	_check(is_equal_approx(game.hp, 80.0) and game.gold == 75 and game.meta_ui.is_choice_open(), "лавка: лечение +40 за 25 золота, лавка остаётся открытой")
	game.meta_ui.pick(1)
	_check(game.gold == 15 and game.meta_ui.is_loot_open(), "лавка: куплено оружие, показана карточка")
	game.meta_ui.choose(false)
	_check(game.meta_ui.is_choice_open() and game.meta_ui.choice_kind == "shop", "после карточки возврат в лавку")
	_check(not bool(game.meta_ui.choice_options[1].enabled), "без золота покупка недоступна")
	game.meta_ui.cancel_choice()
	game.dev_goto_room(1)
	await _until(func() -> bool: return game.state != "walk")
	game.hp = game.max_hp
	game.gold = 0

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
