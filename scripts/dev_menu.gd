## Меню разработчика для тестов на телефоне. Есть только в debug-сборке
## (OS.is_debug_build()), в релизе не создаётся.
##
## Открывается кнопкой «DEV» под кошельком слева. Пока меню открыто, игра на паузе.
## Читы: бессмертие, бесконечная стойкость, убийство с одного удара.
## Переходы: убить или оглушить врага, пропустить комнату, перейти к любой комнате,
## к боссу, к следующей фазе босса, к кат-сцене; новый забег со своим сидом.
## Отладка: скорость игры, FPS и счётчики рендера, лог жестов, состояние врага,
## автоигрок прямо в игре, проверка звуков и вибрации.
## Флаги переживают перезапуск сцены: хранятся в метаданных Engine.
extends CanvasLayer

const Enemy := preload("res://scripts/enemy.gd")
const Settings := preload("res://scripts/settings.gd")
const Save := preload("res://scripts/save.gd")
const Items := preload("res://scripts/items.gd")
const Hero := preload("res://scripts/hero.gd")
const Diag := preload("res://scripts/diag.gd")
const SPEEDS := [1.0, 0.25, 0.5, 2.0, 4.0]
const SOUNDS := ["swing", "hit", "crit", "parry", "block", "hurt", "windup", "stun", "dodge", "death", "victory"]
const META := "dev_menu"

var game: Node

var _toggle: Button
var _panel: PanelContainer
var _grid: GridContainer
var _title: Label
var _overlay: Label
var _buttons := {}
var _gesture_log: Array[String] = []
var _speed_i := 0
var _sound_i := 0
var _room_pick := 0
var _seed_pick := 0
var _bot: Node


## Флаги, которые читает игра. Живут в метаданных Engine, чтобы пережить перезапуск.
static func flags() -> Dictionary:
	if not Engine.has_meta(META):
		Engine.set_meta(META, {"god": false, "stamina": false, "one_hit": false,
			"overlay": false, "speed": 1.0, "seed": -1})
	return Engine.get_meta(META)


static func flag(key: String) -> bool:
	return bool(flags().get(key, false))


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_speed_i = maxi(0, SPEEDS.find(float(flags().speed)))
	if not game.autoplay:
		Engine.time_scale = SPEEDS[_speed_i]
	_seed_pick = game.run_seed
	game.gestures.gesture.connect(_on_gesture)
	_build()
	_refresh()


func _process(_delta: float) -> void:
	_overlay.visible = flag("overlay") and not _panel.visible
	if _overlay.visible:
		_overlay.text = _overlay_text()
	if _panel.visible:
		_title.text = "Меню разработчика · комната %d/%d · %s" % [
			game.room_index + 1, game.rooms.size(), game.state]


# ============================================================ интерфейс

func _build() -> void:
	_toggle = Button.new()
	_toggle.text = "DEV"
	_toggle.position = Vector2(10, 44)
	_toggle.custom_minimum_size = Vector2(62, 34)
	_toggle.add_theme_font_size_override("font_size", 15)
	_toggle.modulate = Color(1, 1, 1, 0.75)
	_toggle.pressed.connect(_set_open.bind(true))
	add_child(_toggle)

	_overlay = Label.new()
	_overlay.position = Vector2(10, 84)
	_overlay.add_theme_font_size_override("font_size", 13)
	_overlay.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	_overlay.add_theme_constant_override("outline_size", 4)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.08, 0.94)
	bg.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", bg)
	_panel.visible = false
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", Color(0.96, 0.78, 0.36))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)

	_section("Читы")
	_add("god", _toggle_flag.bind("god"))
	_add("stamina", _toggle_flag.bind("stamina"))
	_add("one_hit", _toggle_flag.bind("one_hit"))
	_add("heal", _heal, "Полное здоровье")
	_add("hurt", _hurt, "−30 здоровья")
	_add("money", _money, "+100 золота и осколков")

	_add("drop", _drop, "Выпадение оружия")
	_add("legend", _drop_legend, "Легендарное оружие")
	_add("boon", _boon, "Дар на выбор")
	_add("forge", _forge, "Открыть кузницу")
	_add("levelup", _levelup, "+1 уровень героя")
	_add("talents", _talents, "Открыть таланты")
	_add("cooldowns", _cooldowns, "Сбросить перезарядку умений")
	_add("wipe", _wipe, "Сбросить сохранение")

	_section("Бой")
	_add("kill", _kill, "Убить врага")
	_add("stun", _stun, "Оглушить врага")
	_add("phase", _boss_phase, "Босс: следующая фаза")
	_add("bot", _toggle_bot)

	_section("Забег")
	_add("skip", _skip_room, "Пропустить комнату")
	_add("room_pick", _cycle_room)
	_add("goto", _goto_picked)
	_add("boss", _goto_boss, "К боссу")
	_add("cutscene", _cutscene, "Кат-сцена победы")
	_add("victory", _victory, "Экран итога")
	_add("seed_minus", _seed_step.bind(-1), "Сид −1")
	_add("seed_plus", _seed_step.bind(1), "Сид +1")
	_add("seed_new", _restart_with_seed, "Новый забег с сидом")
	_add("restart", _restart_random, "Новый случайный забег")

	_section("Отладка")
	_add("speed", _cycle_speed)
	_add("overlay", _toggle_flag.bind("overlay"))
	_add("style", _cycle_style)
	_add("sound", _test_sound)
	_add("buzz", _test_buzz, "Тест вибрации")
	_add("log", _show_log, "Журнал прошлого запуска")
	_add("log_now", _show_log_now, "Журнал этого запуска")

	var close := Button.new()
	close.text = "Закрыть"
	close.custom_minimum_size = Vector2(0, 64)
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(_set_open.bind(false))
	vbox.add_child(close)


func _section(text: String) -> void:
	for i in 2:
		var l := Label.new()
		l.text = text if i == 0 else ""
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(0.6, 0.55, 0.7))
		_grid.add_child(l)


func _add(key: String, action: Callable, text: String = "") -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 58)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 16)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(func() -> void:
		action.call()
		_refresh())
	_grid.add_child(b)
	_buttons[key] = b


func _set_open(open: bool) -> void:
	if not open:
		game.meta_ui.hide_forge()
		game.meta_ui.hide_talents()
	_panel.visible = open
	_toggle.visible = not open
	game.gestures.enabled = not open
	get_tree().paused = open
	_refresh()


## Подписи переключателей отражают текущее состояние.
func _refresh() -> void:
	_label("god", "Бессмертие", flag("god"))
	_label("stamina", "Бесконечная стойкость", flag("stamina"))
	_label("one_hit", "Убийство с удара", flag("one_hit"))
	_label("overlay", "FPS и отладка", flag("overlay"))
	_label("bot", "Автоигрок", _bot != null)
	_buttons.speed.text = "Скорость игры: ×%s" % str(SPEEDS[_speed_i])
	_buttons.style.text = "Графика: %s" % Settings.current().name
	_buttons.sound.text = "Звук: %s" % SOUNDS[_sound_i]
	_room_pick = clampi(_room_pick, 0, game.rooms.size() - 1)
	var kind: String = game.rooms[_room_pick].kind
	_buttons.room_pick.text = "Выбрать комнату: %d (%s)" % [_room_pick + 1, game.KIND_NAMES[kind]]
	_buttons.goto.text = "Перейти в комнату %d" % (_room_pick + 1)
	_buttons.seed_new.text = "Новый забег, сид %d" % _seed_pick


func _label(key: String, text: String, on: bool) -> void:
	var b: Button = _buttons[key]
	b.text = "%s: %s" % [text, "ВКЛ" if on else "выкл"]
	b.modulate = Color(0.6, 1.0, 0.6) if on else Color.WHITE


func _overlay_text() -> String:
	var lines := PackedStringArray()
	lines.append("FPS %d  draw %d  obj %d  %.0f МБ" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	lines.append("сид %d  комната %d/%d  %s  ×%s" % [game.run_seed, game.room_index + 1,
		game.rooms.size(), game.state, str(Engine.time_scale)])
	lines.append("герой %d/%d  стойкость %d  урон ×%.2f" % [game.hp, game.max_hp, game.stamina, game.damage_mult])
	var e: Enemy = game.enemy
	if e != null:
		var st: String = Enemy.State.keys()[e.state]
		var line := "враг %s  %s  hp %d/%d  стойк. %d/%d" % [e.id, st, e.hp, e.max_hp, e.stagger, e.stagger_max]
		if e.state == Enemy.State.WINDUP:
			line += "\nудар %s через %.2f с%s" % [game.SIDE_NAMES[e.attack_side], e.time_to_impact(),
				"  ← ПАРИРУЙ" if e.time_to_impact() <= float(game.p.parry_window) else ""]
		if e.is_boss:
			line += "\nфаза %d  серия %d  замах %.2f с" % [e.phase + 1, e.combo, e.windup_time]
		lines.append(line)
	if not _gesture_log.is_empty():
		lines.append("жесты: " + ", ".join(_gesture_log))
	return "\n".join(lines)


func _on_gesture(kind: String) -> void:
	_gesture_log.push_front(kind)
	if _gesture_log.size() > 4:
		_gesture_log.pop_back()


# ============================================================ действия

func _toggle_flag(key: String) -> void:
	flags()[key] = not flag(key)


func _heal() -> void:
	game.hp = game.max_hp
	game.stamina = game.max_stamina


func _hurt() -> void:
	game.hp = maxf(1.0, game.hp - 30.0)
	game.hud.hurt_flash()


func _money() -> void:
	game.gold += 100
	game.shards += 100


func _drop() -> void:
	_set_open(false)
	game.offer_loot(Items.roll(game.items, RandomNumberGenerator.new(), 0.5))


func _drop_legend() -> void:
	_set_open(false)
	game.offer_loot(Items.roll(game.items, RandomNumberGenerator.new(), 1.0, 3))


func _boon() -> void:
	_set_open(false)
	game.offer_boons()


func _levelup() -> void:
	game.gain_xp(Hero.need(game.hero_cfg, int(Save.data.level)) - int(Save.data.xp))


func _talents() -> void:
	_set_open(false)
	game.meta_ui.show_talents()


func _cooldowns() -> void:
	for i in game.skill_cd.size():
		game.skill_cd[i] = 0.0


func _forge() -> void:
	_set_open(false)
	game.meta_ui.show_forge()


func _wipe() -> void:
	Save.reset()
	game.shards = 0
	game.gold = 0
	game.recalc()


func _kill() -> void:
	var e: Enemy = game.enemy
	if e != null and e.is_alive():
		e.take_hit(e.hp + 1.0, 0.0)


func _stun() -> void:
	var e: Enemy = game.enemy
	if e != null and e.is_alive():
		e.take_hit(0.0, e.stagger_max * 2.0)


## Снять с босса здоровье до порога следующей фазы.
func _boss_phase() -> void:
	var e: Enemy = game.enemy
	if e == null or not e.is_boss or not e.is_alive():
		game.hud.say("Босса нет в комнате", Color(1, 0.6, 0.4), 1.0)
		return
	var phases: Array = e.data.get("phases", [])
	if e.phase >= phases.size():
		e.take_hit(e.hp + 1.0, 0.0)
		return
	var target := float(phases[e.phase].hp) * e.max_hp
	e.take_hit(maxf(1.0, e.hp - target + 1.0), 0.0)


func _toggle_bot() -> void:
	if _bot != null:
		_bot.queue_free()
		_bot = null
		return
	_bot = load("res://tools/autoplay.gd").new()
	_bot.game = game
	_bot.quit_on_end = false
	game.add_child(_bot)


func _skip_room() -> void:
	game.dev_goto_room(game.room_index + 1)


func _cycle_room() -> void:
	_room_pick = (_room_pick + 1) % game.rooms.size()


func _goto_picked() -> void:
	game.dev_goto_room(_room_pick)
	_set_open(false)


func _goto_boss() -> void:
	game.dev_goto_room(game.rooms.size() - 1)
	_set_open(false)


func _cutscene() -> void:
	game.dev_cutscene()
	_set_open(false)


func _victory() -> void:
	game.dev_victory()
	_set_open(false)


func _seed_step(d: int) -> void:
	_seed_pick = maxi(0, _seed_pick + d)


func _restart_with_seed() -> void:
	flags().seed = _seed_pick
	get_tree().paused = false
	get_tree().reload_current_scene()


func _restart_random() -> void:
	flags().seed = -1
	get_tree().paused = false
	get_tree().reload_current_scene()


## Для автотеста: сбросить сохранённый сид, не перезапуская сцену.
func _restart_random_flag_only() -> void:
	flags().seed = -1


func _cycle_speed() -> void:
	_speed_i = (_speed_i + 1) % SPEEDS.size()
	flags().speed = SPEEDS[_speed_i]
	Engine.time_scale = SPEEDS[_speed_i]


func _cycle_style() -> void:
	var i := Settings.STYLE_ORDER.find(Settings.style)
	Settings.style = Settings.STYLE_ORDER[(i + 1) % Settings.STYLE_ORDER.size()]
	Settings.save()
	game.apply_style()


func _test_sound() -> void:
	game.sfx.play(SOUNDS[_sound_i])
	_sound_i = (_sound_i + 1) % SOUNDS.size()


func _show_log() -> void:
	_log_view(Diag.previous(70))


func _show_log_now() -> void:
	var path := "user://log_current.txt"
	var lines := FileAccess.get_file_as_string(path).split("\n", false) if FileAccess.file_exists(path) else PackedStringArray()
	_log_view("\n".join(lines.slice(maxi(0, lines.size() - 70))))


## Окно с текстом журнала поверх меню: его удобно сфотографировать и прислать.
func _log_view(text: String) -> void:
	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.03, 0.05, 0.98)
	bg.set_content_margin_all(10)
	box.add_theme_stylebox_override("panel", bg)
	var v := VBoxContainer.new()
	box.add_child(v)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(label)
	var close := Button.new()
	close.text = "Закрыть журнал"
	close.custom_minimum_size = Vector2(0, 60)
	close.pressed.connect(box.queue_free)
	v.add_child(close)
	add_child(box)
	# Прокрутить к последним строкам
	await get_tree().process_frame
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _test_buzz() -> void:
	Input.vibrate_handheld(150)
