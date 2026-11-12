## ПОСЛЕДНИЙ СТРАЖ — прототип «Одна комната».
## Строит комнату из примитивов, камеру от первого лица, меч и щит в руках,
## по очереди выводит врагов из data/combat.json и ведёт бой на свайпах.
## Все действия игрока идут через on_gesture() — и от пальца, и от автоигрока.
extends Node3D

const Gestures := preload("res://scripts/gestures.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Hud := preload("res://scripts/hud.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Run := preload("res://scripts/run.gd")
const DevMenu := preload("res://scripts/dev_menu.gd")
const Settings := preload("res://scripts/settings.gd")
const SettingsMenu := preload("res://scripts/settings_menu.gd")
const Save := preload("res://scripts/save.gd")
const Items := preload("res://scripts/items.gd")
const MetaUi := preload("res://scripts/meta_ui.gd")
const PixelShader := preload("res://shaders/pixel.gdshader")
const Voice := preload("res://scripts/voice.gd")
const Title := preload("res://scripts/title.gd")
const ITEMS_PATH := "res://data/items.json"
const HERO_MODELS := "res://assets/kaykit/hero/"

const DUNGEON := "res://assets/kaykit/dungeon/"
const HERO_SWORD := preload("res://assets/kaykit/hero/sword_1handed.gltf")
const HERO_SHIELD := preload("res://assets/kaykit/hero/shield_round.gltf")
const WALLS := ["wall", "wall_cracked", "wall", "wall_arched", "wall_broken", "wall_shelves"]

const DATA_PATH := "res://data/combat.json"
const RUN_PATH := "res://data/run.json"
const WALK_TIME := 1.5
const WALK_DISTANCE := 3.2
const CLEARED_DELAY := 1.5
const CUT_TIME := 9.0
const KIND_NAMES := {"boss": "Логово босса", "fight": "Бой", "chest": "Сундук", "altar": "Алтарь Зари", "event": "Находка"}
const ENEMY_POS := Vector3(0.0, 0.0, -2.3)
const CAMERA_POS := Vector3(0.0, 1.62, 0.0)
const NEXT_ENEMY_DELAY := 1.3

const SIDE_NAMES := ["слева", "справа", "сверху"]

var cfg: Dictionary = {}
var p: Dictionary = {}          # параметры игрока из JSON
## fight — бой; between — пауза между врагами; room — мирная комната ждёт тапа;
## cleared — комната пройдена, пауза; walk — переход; victory | defeat — итог.
var state := "walk"
var autoplay := false

# Игрок
var hp := 100.0
var max_hp := 100.0
var stamina := 100.0
var max_stamina := 100.0
var attack_cd := 0.0
var block_t := 0.0
var dodge_t := 0.0
var dodge_dir := 0              # -1 влево, 1 вправо
var charging := false
var charge_t := 0.0
var _since_spend := 0.0

# Враги
var enemy: Enemy
var wave: Array = []
var wave_index := -1
var _between_t := 0.0

# Забег
var run_cfg: Dictionary = {}
var run_seed := 0
var rooms: Array = []
var room_index := -1
var room: Dictionary = {}
var shards := 0
var gold := 0
var damage_mult := 1.0
var visited := {}
var cut_t := 0.0                # время кат-сцены после босса, читает HUD
var dawn := 0.0                 # сила рассвета 0..1
var white := 0.0                # белая вспышка рассвета в кат-сцене
var _env: Environment
var _moon: DirectionalLight3D
var _dawn: OmniLight3D
var _dawn_glow: StandardMaterial3D
var fade := 1.0                 # затемнение экрана при переходе, читает HUD
var _walk_t := 0.0
var _prop: Node3D
var _prop_lid: Node3D
var _prop_glow: MeshInstance3D
var _prop_used := false
var _run_rng := RandomNumberGenerator.new()

## Счётчики для автоигрока и итогового экрана.
var stats := {"hits": 0, "weak_hits": 0, "parries": 0, "blocks": 0, "dodges": 0,
	"charged": 0, "stuns": 0, "rooms": 0, "boss": 0, "drops": 0, "taken_loot": 0, "crits": 0, "taken": 0.0, "hurt": 0, "kills": 0}

var gestures: Node
var dev_menu: CanvasLayer
var settings_menu: CanvasLayer
var meta_ui: CanvasLayer
var voice: Node
var title: CanvasLayer
var cut_total := CUT_TIME        # длина кат-сцены: подстраивается под озвучку
var _title_boss: Enemy
var items: Dictionary = {}      # data/items.json
var weapon: Dictionary = {}     # вид текущего оружия из items.weapons
var _sword_model: Node3D
var _last_struck_side := 0
var _chip_pool: Array[CPUParticles3D] = []
var _chip_next := 0
var _hitstop_until := 0          # момент (мс), до которого враг «заморожен»
var _loot_then := ""            # что делать после выбора добычи: cleared | cutscene
var style: Dictionary = {}      # параметры текущего стиля графики, читает HUD
var _lantern: OmniLight3D
var _wall_nodes: Array[Node3D] = []
var _floor_nodes: Array[Node3D] = []
var _stone_wall: StandardMaterial3D
var _stone_floor: StandardMaterial3D
var _pixel_rect: ColorRect
var hud: CanvasLayer
var sfx: Node
var camera: Camera3D
var _shake := 0.0
var _dodge_offset := 0.0
var _sword: Node3D
var _shield: Node3D
var _sword_from := Vector3.ZERO
var _sword_to := Vector3.ZERO
var _sword_t := 1.0
var _sword_dur := 0.2
var _torches: Array[OmniLight3D] = []
var _time := 0.0
var _rng := RandomNumberGenerator.new()

const SWORD_REST := Vector3(-0.25, 0.0, -0.35)
const SWORD_POS := Vector3(0.3, -0.38, -0.62)
const SHIELD_REST := Vector3(-0.42, -0.6, -0.72)
const SHIELD_UP := Vector3(-0.06, -0.2, -0.45)


func _ready() -> void:
	autoplay = OS.get_cmdline_user_args().has("--autoplay")
	_rng.randomize()
	cfg = _load_json(DATA_PATH)
	items = _load_json(ITEMS_PATH)
	var testing := autoplay or OS.get_cmdline_user_args().has("--devtest")
	Save.load_once(testing)
	shards = int(Save.data.shards)
	gold = int(Save.data.gold)
	Save.data.runs = int(Save.data.runs) + 1
	run_cfg = _load_json(RUN_PATH)
	run_seed = 1 if autoplay else int(_rng.randi() % 1000000)
	if int(DevMenu.flags().seed) >= 0 and not autoplay:
		run_seed = int(DevMenu.flags().seed)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			run_seed = int(a.trim_prefix("--seed="))
	rooms = Run.generate(run_cfg, run_seed)
	_run_rng.seed = run_seed

	if not autoplay:
		Engine.time_scale = 1.0     # страховка: скорость не должна «застрять» между сценами
	Settings.load_once()
	Settings.apply_volume()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--style=") and Settings.STYLES.has(a.trim_prefix("--style=")):
			Settings.style = a.trim_prefix("--style=")
	style = Settings.current()
	sfx = Sfx.new()
	voice = Voice.new()
	add_child(voice)
	add_child(sfx)
	_build_room()
	_build_camera()
	gestures = Gestures.new()
	add_child(gestures)
	gestures.gesture.connect(on_gesture)
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	meta_ui = MetaUi.new()
	meta_ui.game = self
	add_child(meta_ui)
	meta_ui.loot_chosen.connect(_on_loot_chosen)
	recalc()
	hp = max_hp
	stamina = max_stamina
	var pixel_layer := CanvasLayer.new()
	pixel_layer.layer = 0
	add_child(pixel_layer)
	_pixel_rect = ColorRect.new()
	_pixel_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pixel_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pixel_mat := ShaderMaterial.new()
	pixel_mat.shader = PixelShader
	_pixel_rect.material = pixel_mat
	_pixel_rect.visible = false
	pixel_layer.add_child(_pixel_rect)
	settings_menu = SettingsMenu.new()
	settings_menu.game = self
	add_child(settings_menu)
	apply_style()
	# Меню разработчика — только в debug-сборке
	if OS.is_debug_build():
		dev_menu = DevMenu.new()
		dev_menu.game = self
		add_child(dev_menu)
	_spawn_embers()
	var skip_title := testing or Engine.has_meta("title_seen") or OS.get_cmdline_user_args().has("--no-title")
	if OS.get_cmdline_user_args().has("--title"):
		skip_title = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--titleshots="):
			var shooter: Node = load("res://tools/title_shot.gd").new()
			shooter.dir = a.trim_prefix("--titleshots=")
			add_child(shooter)
	if skip_title:
		start_run()
	else:
		_show_title()

	if OS.get_cmdline_user_args().has("--devtest"):
		var test: Node = load("res://tools/dev_test.gd").new()
		test.game = self
		add_child(test)
	if autoplay:
		var bot: Node = load("res://tools/autoplay.gd").new()
		bot.game = self
		add_child(bot)


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Нет файла данных: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


# ============================================================ ход боя

func _process(delta: float) -> void:
	_time += delta
	_update_hitstop()
	attack_cd = maxf(0.0, attack_cd - delta)
	block_t = maxf(0.0, block_t - delta)
	dodge_t = maxf(0.0, dodge_t - delta)
	_since_spend += delta
	if _since_spend > float(p.stamina_delay) and not charging:
		stamina = minf(max_stamina, stamina + float(p.stamina_regen) * delta)
	if charging:
		charge_t += delta

	match state:
		"between":
			_between_t -= delta
			if _between_t <= 0.0:
				_spawn_next()
		"cleared":
			_between_t -= delta
			if _between_t <= 0.0:
				_next_room()
		"cutscene":
			_run_cutscene(delta)
		"walk":
			_walk_t -= delta
			fade = clampf(_walk_t / WALK_TIME * 1.6 - 0.3, 0.0, 1.0)
			if _walk_t <= 0.0:
				_arrive()
	_animate_prop(delta)

	_animate_view(delta)


func _spawn_next() -> void:
	wave_index += 1
	if wave_index >= wave.size():
		var reward := int(run_cfg.fight_shards)
		shards += reward
		if str(room.kind) != "boss":
			hud.say("Комната очищена  +%d оск." % reward, Color(1.0, 0.85, 0.4), 1.3)
		_room_cleared()
		return
	var id: String = wave[wave_index]
	enemy = Enemy.new()
	enemy.position = Vector3(0.0, 0.0, -float(cfg.enemies[id].get("distance", -ENEMY_POS.z)))
	add_child(enemy)
	enemy.setup(id, cfg.enemies[id], _run_rng.randi())
	enemy.parry_window = float(p.parry_window)
	enemy.set_realistic(bool(style.realistic))
	enemy.windup_started.connect(_on_windup)
	enemy.struck.connect(_on_struck)
	enemy.stunned.connect(_on_stunned)
	enemy.died.connect(_on_died)
	enemy.phase_changed.connect(_on_phase)
	state = "fight"
	if enemy.is_boss:
		voice.say_sequence(["boss_intro"], 0.0, 0.6)
	else:
		hud.say(enemy.display_name, Color(0.9, 0.85, 0.8), 1.4)


func _on_windup(_side: int) -> void:
	sfx.play("windup", -6.0, 1.0 / maxf(0.5, float(enemy.data.get("windup", 1.0))))


func _on_stunned() -> void:
	stats.stuns += 1
	sfx.play("stun", -3.0)
	hud.say("Оглушён! Бей!", Color(1.0, 0.9, 0.3), 1.2)


func _on_phase(index: int, phase_title: String) -> void:
	sfx.play("death", -3.0, 1.4)
	hud.say(phase_title, Color(1.0, 0.35, 0.25), 1.8)
	voice.say("boss_phase%d" % (index + 1))
	_shake = maxf(_shake, 0.9)
	_buzz(150)


func _on_died() -> void:
	stats.kills += 1
	if str(Save.data.weapon.affix) == "vampire":
		hp = minf(max_hp, hp + 6.0)
	sfx.play("death", -2.0)
	enemy.queue_free()
	enemy = null
	state = "between"
	_between_t = NEXT_ENEMY_DELAY


## Враг ударил. Исход решают уклонение, блок и стойкость игрока.
func _on_struck(side: int, damage: float) -> void:
	_last_struck_side = side
	if state != "fight":
		return
	var side_dir := -1 if side == Enemy.Side.LEFT else (1 if side == Enemy.Side.RIGHT else 0)
	if dodge_t > 0.0 and dodge_dir != side_dir:
		stats.dodges += 1
		hud.say("Уклонение", Color(0.6, 0.85, 1.0), 0.7)
		return
	var dmg := damage
	if block_t > 0.0:
		var cost := float(p.block_cost)
		if stamina >= cost:
			_spend(cost)
			dmg *= 1.0 - float(p.block_reduction)
			stats.blocks += 1
			sfx.play("block")
			hud.say("Блок", Color(0.75, 0.8, 0.9), 0.6)
			_shake = maxf(_shake, 0.35)
			_buzz(25)
		else:
			_spend(stamina)
			hud.say("Щит пробит!", Color(1.0, 0.4, 0.3), 0.9)
	_take_damage(dmg)


func _take_damage(dmg: float) -> void:
	if dmg <= 0.0:
		return
	if DevMenu.flag("god"):
		hud.say("Бессмертие: −%d" % roundi(dmg), Color(0.6, 1.0, 0.6), 0.5)
		return
	hp = maxf(0.0, hp - dmg)
	stats.taken += dmg
	stats.hurt += 1
	sfx.play("hurt")
	hud.hurt_flash()
	hud.fx_hurt(_last_struck_side)
	_shake = maxf(_shake, 0.8)
	_buzz(80)
	if hp <= 0.0:
		state = "defeat"
		charging = false
		voice.say("defeat")


func _spend(amount: float) -> void:
	if DevMenu.flag("stamina"):
		return
	stamina = maxf(0.0, stamina - amount)
	_since_spend = 0.0


# ============================================================ забег

## Заставка: босс встаёт из земли в глубине коридора, поверх — логотип и меню.
func _show_title() -> void:
	state = "title"
	fade = 0.0
	gestures.enabled = false
	_title_boss = Enemy.new()
	_title_boss.passive = true
	_title_boss.position = Vector3(0.0, 0.0, -5.2)
	add_child(_title_boss)
	var boss_data: Dictionary = cfg.enemies[run_cfg.boss].duplicate()
	boss_data.appear_time = 4.0
	_title_boss.setup(str(run_cfg.boss), boss_data, 1)
	_title_boss.set_realistic(bool(style.realistic))
	title = Title.new()
	title.game = self
	add_child(title)


## Начать забег (с заставки или сразу).
func start_run() -> void:
	Engine.set_meta("title_seen", true)
	if _title_boss != null:
		_title_boss.queue_free()
		_title_boss = null
	title = null
	gestures.enabled = true
	_next_room()


## Тлеющие искры в воздухе коридора: дешёвая атмосфера для всех стилей.
func _spawn_embers() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.6, 0.2)
	mesh.material = mat
	var em := CPUParticles3D.new()
	em.amount = 36
	em.lifetime = 5.0
	em.preprocess = 5.0
	em.mesh = mesh
	em.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	em.emission_box_extents = Vector3(1.8, 0.2, 4.5)
	em.position = Vector3(0, 0.3, -4.0)
	em.direction = Vector3(0, 1, 0)
	em.spread = 25.0
	em.gravity = Vector3(0, 0.15, 0)
	em.initial_velocity_min = 0.2
	em.initial_velocity_max = 0.6
	em.scale_amount_min = 0.5
	em.scale_amount_max = 1.6
	add_child(em)


func _next_room() -> void:
	room_index += 1
	if _prop != null:
		_prop.queue_free()
		_prop = null
	if room_index >= rooms.size():
		state = "victory"
		sfx.play("victory", -2.0)
		_buzz(120)
		return
	room = rooms[room_index]
	visited[room.kind] = true
	_prop_used = false
	_prop_lid = null
	_prop_glow = null
	match str(room.kind):
		"chest":
			_make_chest()
		"altar":
			_make_altar()
		"event":
			_make_wisp()
	state = "walk"
	_walk_t = WALK_TIME
	fade = 1.0


## Дошли до комнаты: начинаем бой или ждём тапа по находке.
func _arrive() -> void:
	fade = 0.0
	stats.rooms += 1
	if str(room.kind) == "fight" or str(room.kind) == "boss":
		wave = room.wave
		wave_index = -1
		_spawn_next()
		return
	state = "room"
	var title: String = KIND_NAMES[room.kind]
	if str(room.kind) == "event":
		title = str(room.event.text)
	hud.say(title, Color(0.9, 0.88, 0.8), 2.5)


func _room_cleared() -> void:
	charging = false
	var kind := str(room.kind)
	if kind == "boss":
		stats.boss = 1
		Save.data.wins = int(Save.data.wins) + 1
	persist()
	var then := "cutscene" if kind == "boss" else "cleared"
	if _roll_drop(kind):
		_loot_then = then
		state = "loot"
		return
	_finish_room(then)


func _begin_cutscene() -> void:
	state = "cutscene"
	cut_t = 0.0
	_shake = 0.0
	cut_total = maxf(CUT_TIME, voice.say_sequence(["cut_1", "cut_2", "cut_3"], 0.5, 0.8) + 2.6)


func _finish_room(then: String) -> void:
	if then == "cutscene":
		_begin_cutscene()
		return
	state = "cleared"
	_between_t = CLEARED_DELAY


# ============================================================ добыча и улучшения

## Выпало ли оружие за комнату. Если да — показывает карточку добычи.
func _roll_drop(kind: String) -> bool:
	var chances: Dictionary = items.drop_chance
	var key := kind
	if kind == "fight" and room_index == rooms.size() - 2:
		key = "final"
	if not chances.has(key) or _run_rng.randf() >= float(chances[key]):
		return false
	var depth := float(room_index) / maxf(1.0, rooms.size() - 1)
	offer_loot(Items.roll(items, _run_rng, depth, 2 if kind == "boss" else 0))
	return true


func offer_loot(w: Dictionary) -> void:
	stats.drops += 1
	sfx.play("victory", -8.0, 1.5)
	meta_ui.show_loot(w)


func _on_loot_chosen(take: bool) -> void:
	var w: Dictionary = meta_ui.offered
	if take:
		Save.data.weapon = w
		recalc()
		hud.say("В руке: " + Items.title(items, w), Items.color(items, w), 1.6)
		stats.taken_loot += 1
	else:
		var n := Items.salvage(items, w)
		shards += n
		hud.say("Разобрано: +%d оск." % n, Color(0.6, 0.85, 1.0), 1.4)
	persist()
	if state == "loot":
		_finish_room(_loot_then)


## Пересчитать параметры героя из базовых (combat.json), улучшений и оружия.
func recalc() -> void:
	var up: Dictionary = Save.data.upgrades
	var w: Dictionary = Save.data.weapon
	if not items.weapons.has(w.id):
		w = Save.defaults().weapon
		Save.data.weapon = w
	weapon = items.weapons[w.id]
	p = cfg.player.duplicate()
	var dmg := Items.damage_mult(items, w) * (1.0 + 0.05 * int(up.damage))
	p.attack_damage = float(p.attack_damage) * dmg * (1.2 if str(w.affix) == "keen" else 1.0)
	p.attack_off_damage = float(p.attack_off_damage) * dmg
	p.attack_recovery = float(p.attack_recovery) * float(weapon.speed)
	p.attack_cost = float(p.attack_cost) * float(weapon.cost) * (0.75 if str(w.affix) == "light" else 1.0)
	p.weak_stagger = float(p.weak_stagger) * float(weapon.stagger)
	p.off_stagger = float(p.off_stagger) * float(weapon.stagger)
	p.parry_stagger = float(p.parry_stagger) * (1.4 if str(w.affix) == "breaker" else 1.0)
	p.charge_mult = float(p.charge_mult) * float(weapon.charge)
	p.parry_window = float(p.parry_window) + 0.01 * int(up.parry)
	var old_max := max_hp
	max_hp = float(p.hp) + 10.0 * int(up.hp)
	hp = minf(max_hp, hp + maxf(0.0, max_hp - old_max))
	max_stamina = float(p.stamina) + 10.0 * int(up.stamina)
	stamina = minf(stamina, max_stamina)
	if enemy != null:
		enemy.parry_window = float(p.parry_window)
	# Модель оружия в руке
	if _sword_model != null:
		_sword_model.queue_free()
	var scene: PackedScene = load(HERO_MODELS + str(weapon.model) + ".gltf")
	_sword_model = scene.instantiate()
	_sword_model.scale = Vector3.ONE * float(weapon.scale)
	_sword.add_child(_sword_model)


## Записать осколки и золото в сохранение.
func persist() -> void:
	Save.data.shards = shards
	Save.data.gold = gold
	Save.save()


## Тап в мирной комнате: открыть сундук, коснуться алтаря, разобрать находку.
func _use_room() -> void:
	_prop_used = true
	match str(room.kind):
		"chest":
			shards += int(room.shards)
			gold += int(room.gold)
			sfx.play("block", -4.0, 0.7)
			hud.say("Осколки +%d   Золото +%d" % [int(room.shards), int(room.gold)], Color(1.0, 0.85, 0.4), 1.5)
		"altar":
			var heal := max_hp * float(room.heal)
			hp = minf(max_hp, hp + heal)
			sfx.play("stun", -4.0, 0.6)
			hud.say("Свет Зари исцеляет: +%d" % roundi(heal), Color(0.6, 0.85, 1.0), 1.5)
		"event":
			_apply_event(room.event)
	_buzz(30)
	_room_cleared()


func _apply_event(ev: Dictionary) -> void:
	var value := float(ev.value)
	match str(ev.effect):
		"damage":
			damage_mult += value
		"heal":
			hp = minf(max_hp, hp + value)
		"gold":
			gold += int(value)
		"ash":
			hp = maxf(1.0, hp - value)
			shards += 5
			hud.hurt_flash()
	sfx.play("parry", -8.0, 0.8)
	hud.say(str(ev.result), Color(0.95, 0.9, 0.7), 1.5)


## Кат-сцена победы: за решёткой разгорается заря, туман теплеет, герой идёт к свету.
func _run_cutscene(delta: float) -> void:
	cut_t += delta
	_set_dawn(smoothstep(0.8, 6.5, cut_t))
	white = smoothstep(cut_total - 2.2, cut_total - 0.6, cut_t)
	if cut_t >= cut_total:
		state = "victory"
		sfx.play("victory", -2.0)
		_buzz(120)


## Сила рассвета 0..1: свет за решёткой, тёплый туман, яркость окружения.
func _set_dawn(k: float) -> void:
	dawn = k
	_dawn.light_energy = 6.0 * k
	_dawn_glow.albedo_color = Color(0.02, 0.02, 0.03).lerp(Color(1.0, 0.86, 0.55), k)
	var fog: Color = style.fog
	var ambient: Color = style.ambient
	_env.fog_light_color = fog.lerp(Color(0.95, 0.7, 0.4), k)
	_env.fog_density = lerpf(float(style.fog_density), 0.035, k)
	_env.ambient_light_color = ambient.lerp(Color(1.0, 0.85, 0.65), k)
	_env.ambient_light_energy = lerpf(float(style.ambient_energy), 1.0, k)
	_moon.light_energy = lerpf(float(style.moon), 0.0, k)
	# Заря возвращает миру цвет в любом стиле
	_env.adjustment_saturation = lerpf(float(style.saturation), 1.0, k)
	_env.adjustment_contrast = lerpf(float(style.contrast), 1.0, k)
	_env.adjustment_brightness = lerpf(float(style.brightness), 1.0, k)


## Применить стиль графики из настроек: свет, туман, цветокоррекция. Можно звать на лету.
func apply_style() -> void:
	style = Settings.current()
	_env.adjustment_enabled = true
	_lantern.light_color = style.lantern
	_lantern.light_energy = float(style.lantern_energy)
	for t in _torches:
		t.light_color = style.torch
	_set_dawn(dawn)

	# Пиксельный стиль: шейдер поверх 3D-сцены, под интерфейсом
	var px := float(style.pixel)
	_pixel_rect.visible = px > 0.0
	if px > 0.0:
		(_pixel_rect.material as ShaderMaterial).set_shader_parameter("pixel_size", px)

	# Реалистичный стиль: каменная кладка вместо мультяшных текстур, скелеты с человеческими пропорциями
	var realistic := bool(style.realistic)
	if realistic and _stone_wall == null:
		_stone_wall = _stone("castle_brick_07", 0.42)
		_stone_floor = _stone("cobblestone_floor_08", 0.5)
	for n in _wall_nodes:
		_override(n, _stone_wall if realistic else null)
	for n in _floor_nodes:
		_override(n, _stone_floor if realistic else null)
	if enemy != null:
		enemy.set_realistic(realistic)


## Камень Poly Haven с трипланарной развёрткой: ложится на любые модули без своих UV.
func _stone(tex_name: String, uv_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/polyhaven/%s_diff.jpg" % tex_name)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/polyhaven/%s_nor_gl.jpg" % tex_name)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * uv_scale
	m.roughness = 0.95
	return m


func _override(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for c in node.get_children():
		_override(c, mat)


# ============================================================ для меню разработчика

func _dev_clear() -> void:
	meta_ui.cancel_loot()
	if enemy != null:
		enemy.queue_free()
		enemy = null
	charging = false
	block_t = 0.0
	dodge_t = 0.0
	cut_t = 0.0
	white = 0.0
	_set_dawn(0.0)


## Перейти в комнату i (номер с нуля). За последней комнатой — экран итога.
func dev_goto_room(i: int) -> void:
	_dev_clear()
	room_index = clampi(i, 0, rooms.size()) - 1
	_next_room()


func dev_cutscene() -> void:
	_dev_clear()
	if _prop != null:
		_prop.queue_free()
		_prop = null
	fade = 0.0
	stats.boss = 1
	_begin_cutscene()


func dev_victory() -> void:
	_dev_clear()
	fade = 0.0
	state = "victory"


func _walk_offset() -> float:
	if state == "title":
		return 0.6 + sin(_time * 0.25) * 0.35
	if state == "cutscene" or (state == "victory" and cut_t > 0.0):
		return -6.5 * smoothstep(1.2, cut_total, cut_t)
	if state != "walk":
		return 0.0
	var k := clampf(_walk_t / WALK_TIME, 0.0, 1.0)
	return WALK_DISTANCE * k * k


func _walk_bob() -> float:
	if state != "walk":
		return 0.0
	return sin(_time * 11.0) * 0.035 * clampf(_walk_t / WALK_TIME * 2.0, 0.0, 1.0)


func _make_chest() -> void:
	_prop = Node3D.new()
	_prop.position = ENEMY_POS + Vector3(0, 0, 0.2)
	add_child(_prop)
	var chest := _model("chest_gold", Vector3.ZERO, 0.0, 0.62, _prop)
	_prop_lid = chest.find_child("chest*lid*", true, false)
	_prop_glow = _part(_prop, _box(Vector3(0.8, 0.04, 0.5)), Vector3(0, 0.36, 0), _glow_mat(Color(1.0, 0.8, 0.3)))
	_prop_glow.visible = false
	_model("coin_stack_large", Vector3(0.75, 0, 0.25), 0.5, 0.6, _prop)


func _make_altar() -> void:
	_prop = Node3D.new()
	_prop.position = ENEMY_POS
	add_child(_prop)
	_model("column", Vector3.ZERO, 0.0, 0.85, _prop)
	var orb := SphereMesh.new()
	orb.radius = 0.16
	orb.height = 0.32
	_prop_glow = _part(_prop, orb, Vector3(0, 1.5, 0), _glow_mat(Color(0.6, 0.85, 1.0)))
	_prop_light(Color(0.55, 0.8, 1.0), Vector3(0, 1.6, 0.4))


func _make_wisp() -> void:
	_prop = Node3D.new()
	_prop.position = ENEMY_POS
	add_child(_prop)
	# Сломанные меч и щит павшего стража и огонёк над ними
	var relic := _model("sword_shield_broken", Vector3(0, 0.5, 0), 0.0, 0.6, _prop)
	relic.rotation.x = -0.5
	var orb := SphereMesh.new()
	orb.radius = 0.09
	orb.height = 0.18
	_prop_glow = _part(_prop, orb, Vector3(0, 1.1, 0), _glow_mat(Color(1.0, 0.75, 0.4)))
	_prop_light(Color(1.0, 0.7, 0.4), Vector3(0, 1.1, 0.3))


func _prop_light(color: Color, pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = 1.4
	light.omni_range = 3.5
	light.shadow_enabled = false
	_prop.add_child(light)


func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _animate_prop(delta: float) -> void:
	if _prop == null:
		return
	match str(room.kind):
		"chest":
			if _prop_used:
				_prop_lid.rotation.x = lerpf(_prop_lid.rotation.x, -1.5, 1.0 - exp(-9.0 * delta))
				_prop_glow.visible = true
		"altar", "event":
			var base_y := 1.5 if str(room.kind) == "altar" else 1.1
			_prop_glow.position.y = base_y + sin(_time * 2.2) * 0.06
			var target := 0.3 if _prop_used else 1.0 + 0.12 * sin(_time * 5.0)
			_prop_glow.scale = _prop_glow.scale.lerp(Vector3.ONE * target, 1.0 - exp(-6.0 * delta))


# ============================================================ жесты

func on_gesture(kind: String) -> void:
	if state == "victory" or state == "defeat":
		if kind == "tap" and hud.result_ready():
			get_tree().reload_current_scene()
		return
	if state == "room":
		if kind == "tap":
			_use_room()
		return
	if state == "cutscene":
		if kind == "tap" and cut_t > 1.0:
			cut_t = maxf(cut_t, cut_total - 1.2)     # тап пропускает сцену
			voice.stop()
		return
	if state != "fight":
		charging = false
		return
	if enemy == null or not enemy.is_alive() or enemy.state == Enemy.State.APPEAR:
		charging = false
		return
	match kind:
		"swipe_left":
			_swipe(Enemy.Side.LEFT)
		"swipe_right":
			_swipe(Enemy.Side.RIGHT)
		"swipe_up":
			_swipe(Enemy.Side.TOP)
		"swipe_down":
			_block()
		"dodge_left":
			_dodge(-1)
		"dodge_right":
			_dodge(1)
		"charge_start":
			if attack_cd <= 0.0 and stamina >= float(p.charge_cost):
				charging = true
				charge_t = 0.0
		"charge_release":
			_release_charge()


## Свайп к стороне удара врага во время замаха — парирование, иначе — атака.
func _swipe(side: int) -> void:
	charging = false
	if enemy.state == Enemy.State.WINDUP and side == enemy.attack_side:
		if enemy.time_to_impact() <= float(p.parry_window):
			enemy.parried(float(p.parry_stagger))
			stats.parries += 1
			sfx.play("parry")
			hud.say("Парирование!", Color(1.0, 0.95, 0.7), 0.9)
			_sword_move(_parry_pose(side), 0.12)
			var clash := enemy.global_position + Vector3(0, 1.3 * enemy.scale.y, 0.9)
			hud.fx_parry(clash)
			_chips(clash, 10, Color(1.0, 0.85, 0.4))
			_hitstop(0.07)
			_shake = maxf(_shake, 0.3)
			_buzz(15)
			_buzz_later(15, 0.08)
		else:
			_spend(float(p.early_parry_cost))
			_sword_move(_parry_pose(side), 0.15)
			hud.say("Рано!", Color(1.0, 0.6, 0.4), 0.6)
		return
	_attack(side, 1.0)


func _attack(side: int, mult: float) -> void:
	if attack_cd > 0.0:
		return
	var cost := float(p.attack_cost)
	if stamina < cost:
		hud.say("Нет сил", Color(0.7, 0.7, 0.8), 0.5)
		return
	_spend(cost)
	attack_cd = float(p.attack_recovery)
	_sword_slash(side)
	var weak := enemy.is_open() and side == enemy.weak_side
	var dmg := float(p.attack_damage) if weak else float(p.attack_off_damage)
	var stg := float(p.weak_stagger) if weak else float(p.off_stagger)
	if enemy.state == Enemy.State.STUNNED:
		dmg *= float(p.stun_mult)
	var crit := weak and _rng.randf() < float(p.crit_chance)
	if crit:
		dmg *= float(p.crit_mult)
		stats.crits += 1
	dmg *= mult * damage_mult
	if DevMenu.flag("one_hit"):
		dmg = enemy.hp + 1.0
	stg *= mult
	enemy.take_hit(dmg, stg)
	stats.hits += 1
	if weak:
		stats.weak_hits += 1
	sfx.play("crit" if weak else "hit", 2.0 if crit else 0.0, (1.0 if mult <= 1.0 else 0.8) * (0.85 if crit else 1.0))
	sfx.play("swing", -8.0)
	if crit:
		sfx.play("parry", -5.0, 1.5)
	var hit_pos := enemy.global_position + Vector3(0, 1.25 * enemy.scale.y, 0.3)
	var num_color := Color(0.85, 0.85, 0.85)
	if weak:
		num_color = Color(1.0, 0.85, 0.3)
	if crit:
		num_color = Color(1.0, 0.45, 0.2)
	hud.popup("%d" % roundi(dmg), hit_pos + Vector3(0, 0.25, 0), num_color, mult > 1.0 or weak, crit)
	hud.fx_hit(hit_pos, side, weak, crit, mult > 1.0, Items.color(items, Save.data.weapon))
	_chips(hit_pos, 14 if crit or mult > 1.0 else (8 if weak else 4))
	_shake = maxf(_shake, 0.25 if mult <= 1.0 else 0.55)
	if crit:
		_shake = maxf(_shake, 0.7)
	_hitstop(0.11 if crit else (0.08 if mult > 1.0 else (0.045 if weak else 0.0)))
	_buzz(12 if mult <= 1.0 and not crit else 40)


func _release_charge() -> void:
	if not charging:
		return
	charging = false
	if charge_t < float(p.charge_time) or stamina < float(p.charge_cost):
		return
	_spend(float(p.charge_cost) - float(p.attack_cost))
	stats.charged += 1
	var side: int = enemy.weak_side if enemy.is_open() else Enemy.Side.TOP
	_attack(side, float(p.charge_mult))
	hud.say("Заряженный удар!", Color(1.0, 0.7, 0.3), 0.8)


func _block() -> void:
	charging = false
	block_t = float(p.block_time)


func _dodge(dir: int) -> void:
	charging = false
	var cost := float(p.dodge_cost)
	if stamina < cost:
		hud.say("Нет сил", Color(0.7, 0.7, 0.8), 0.5)
		return
	_spend(cost)
	dodge_t = float(p.dodge_time)
	dodge_dir = dir
	block_t = 0.0
	sfx.play("dodge", -4.0)


## Осколки костей и искры из точки удара: пул из четырёх излучателей, без создания нод в бою.
func _chips(pos: Vector3, amount: int, color: Color = Color(0.93, 0.9, 0.8)) -> void:
	if _chip_pool.is_empty():
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.03, 0.03, 0.03)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mesh.material = mat
		for i in 4:
			var cp := CPUParticles3D.new()
			cp.emitting = false
			cp.one_shot = true
			cp.explosiveness = 1.0
			cp.lifetime = 0.55
			cp.mesh = mesh
			cp.direction = Vector3(0, 1.0, 0.35)
			cp.spread = 60.0
			cp.initial_velocity_min = 1.5
			cp.initial_velocity_max = 4.5
			cp.gravity = Vector3(0, -9.0, 0)
			cp.angular_velocity_min = -400.0
			cp.angular_velocity_max = 400.0
			cp.scale_amount_min = 0.5
			cp.scale_amount_max = 1.5
			add_child(cp)
			_chip_pool.append(cp)
	var e := _chip_pool[_chip_next]
	_chip_next = (_chip_next + 1) % _chip_pool.size()
	e.position = pos
	e.amount = amount
	e.color = color
	e.restart()


## Короткая «заморозка» врага на сильном ударе: придаёт удару вес.
## Замирает только враг (его логика и анимация), по настоящим часам. Общую скорость
## игры не трогаем: застрявший Engine.time_scale замедлил бы всё, включая экран итога.
func _hitstop(sec: float) -> void:
	if sec <= 0.0 or autoplay or OS.get_cmdline_user_args().has("--devtest"):
		return
	if enemy == null or not enemy.is_alive():
		return
	_hitstop_until = maxi(_hitstop_until, Time.get_ticks_msec() + int(sec * 1000.0))
	enemy.process_mode = Node.PROCESS_MODE_DISABLED


func _update_hitstop() -> void:
	if _hitstop_until > 0 and Time.get_ticks_msec() >= _hitstop_until:
		_hitstop_until = 0
		if enemy != null:
			enemy.process_mode = Node.PROCESS_MODE_INHERIT


func _buzz(ms: int) -> void:
	if OS.has_feature("mobile") and Settings.vibration:
		Input.vibrate_handheld(ms)


func _buzz_later(ms: int, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	_buzz(ms)


# ============================================================ камера и руки

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.position = CAMERA_POS
	camera.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 68.0
	camera.near = 0.05
	camera.far = 40.0
	add_child(camera)

	# Фонарь-реликвия Стража: тёплый свет от героя, подсвечивает врага спереди
	var lantern := OmniLight3D.new()
	lantern.position = Vector3(-0.35, -0.3, -0.2)
	lantern.light_color = Color(1.0, 0.82, 0.55)
	lantern.light_energy = 0.7
	lantern.omni_range = 6.0
	lantern.omni_attenuation = 1.2
	lantern.shadow_enabled = false
	camera.add_child(lantern)
	_lantern = lantern

	_sword = Node3D.new()
	_sword.position = SWORD_POS
	_sword.rotation = SWORD_REST
	camera.add_child(_sword)

	_shield = Node3D.new()
	_shield.position = SHIELD_REST
	_shield.rotation = Vector3(0.0, 0.35, 0.1)
	camera.add_child(_shield)
	var shield_model: Node3D = HERO_SHIELD.instantiate()
	shield_model.scale = Vector3.ONE * 0.42
	shield_model.rotation = Vector3(0.0, PI, 0.0)    # лицевой стороной от игрока
	_shield.add_child(shield_model)


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func _sword_move(to: Vector3, dur: float) -> void:
	_sword_from = _sword.rotation
	_sword_to = to
	_sword_t = 0.0
	_sword_dur = dur


## Удар мечом в сторону цели: из противоположной стороны через центр.
func _sword_slash(side: int) -> void:
	match side:
		Enemy.Side.LEFT:
			_sword.rotation = Vector3(-0.2, 0.0, -1.0)
			_sword_move(Vector3(-0.9, 0.0, 1.3), 0.14)
		Enemy.Side.RIGHT:
			_sword.rotation = Vector3(-0.2, 0.0, 0.9)
			_sword_move(Vector3(-0.9, 0.0, -1.3), 0.14)
		_:
			_sword.rotation = Vector3(0.6, 0.0, 0.0)
			_sword_move(Vector3(-1.5, 0.0, 0.0), 0.14)


func _parry_pose(side: int) -> Vector3:
	match side:
		Enemy.Side.LEFT:
			return Vector3(0.1, 0.0, 1.2)
		Enemy.Side.RIGHT:
			return Vector3(0.1, 0.0, -1.2)
	return Vector3(0.2, 0.0, 1.57)


func _animate_view(delta: float) -> void:
	# Меч: быстрое движение к позе, затем плавный возврат в покой
	if _sword_t < 1.0:
		_sword_t = minf(1.0, _sword_t + delta / _sword_dur)
		_sword.rotation = _sword_from.lerp(_sword_to, 1.0 - pow(1.0 - _sword_t, 3.0))
	else:
		var rest := SWORD_REST
		if charging:
			rest = Vector3(0.5, 0.0, -0.6) + Vector3(sin(_time * 50.0), 0, 0) * 0.015 * minf(charge_t * 3.0, 1.0)
		_sword.rotation = _sword.rotation.lerp(rest, 1.0 - exp(-8.0 * delta))

	# Щит поднимается при блоке; в кат-сцене руки опускаются
	var shield_target := SHIELD_UP if block_t > 0.0 else SHIELD_REST
	var hands_down := cut_t > 0.0 or state == "title"
	if hands_down:
		shield_target = SHIELD_REST + Vector3(0, -0.6, 0)
	_sword.position = _sword.position.lerp(SWORD_POS + Vector3(0, -0.8 if hands_down else 0.0, 0),
		1.0 if state == "title" else 1.0 - exp(-2.5 * delta))
	_shield.position = _shield.position.lerp(shield_target, 1.0 - exp(-22.0 * delta))

	# Уклонение: камера уходит в сторону и возвращается
	var dodge_target := float(dodge_dir) * 0.55 if dodge_t > 0.0 else 0.0
	_dodge_offset = lerpf(_dodge_offset, dodge_target, 1.0 - exp(-18.0 * delta))

	# Тряска и лёгкое покачивание дыхания
	_shake = maxf(0.0, _shake - delta * 3.0)
	var s := _shake * _shake * 0.06
	camera.position = CAMERA_POS + Vector3(
		_dodge_offset + _rng.randf_range(-s, s),
		sin(_time * 1.6) * 0.008 + _rng.randf_range(-s, s) + _walk_bob(), _walk_offset())

	# Мерцание факелов
	for i in _torches.size():
		var fl := float(style.flicker)
		_torches[i].light_energy = float(style.torch_energy) * maxf(0.15,
			1.0 + fl * (0.15 * sin(_time * 9.0 + i * 2.1) + 0.1 * sin(_time * 23.0 + i)))


# ============================================================ комната

func _build_room() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.025, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.3, 0.42)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.08, 0.1, 0.16)
	e.fog_density = 0.075
	env.environment = e
	_env = e

	# Заря за решёткой: до кат-сцены погашена
	_dawn_glow = _glow_mat(Color(0.02, 0.02, 0.03))
	var dawn_plane := BoxMesh.new()
	dawn_plane.size = Vector3(5.0, 4.2, 0.1)
	_static(dawn_plane, Vector3(0, 2.0, -11.4), _dawn_glow)
	_dawn = OmniLight3D.new()
	_dawn.position = Vector3(0, 2.2, -9.2)
	_dawn.light_color = Color(1.0, 0.8, 0.5)
	_dawn.light_energy = 0.0
	_dawn.omni_range = 16.0
	_dawn.omni_attenuation = 0.8
	_dawn.shadow_enabled = false
	add_child(_dawn)
	add_child(env)

	var stone_dark := _mat(Color(0.1, 0.095, 0.11), 0.95)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5

	# Коридор из модулей 4×4: пол и стены по обе стороны, потолок — тёмная плита
	for i in 4:
		var z := 2.0 - i * 4.0
		_floor_nodes.append(_model("floor_tile_large_rocks" if i == 2 else "floor_tile_large", Vector3(0, 0, z), 0.0))
		for side: float in [-1.0, 1.0]:
			var wall: String = WALLS[rng.randi_range(0, WALLS.size() - 1)]
			_wall_nodes.append(_model(wall, Vector3(side * 2.5, 0, z), -side * PI / 2.0))
	_wall_nodes.append(_model("wall_gated", Vector3(0, 0, -10.5), 0.0))
	_static(_box(Vector3(6.0, 0.2, 18.0)), Vector3(0, 4.1, -4.0), stone_dark)

	# Убранство: знамёна, бочки, ящики
	_model("banner_patternA_red", Vector3(-2.5, 0, -4.2), PI / 2.0)
	_model("banner_shield_red", Vector3(2.5, 0, -4.2), -PI / 2.0)
	_model("barrel_large", Vector3(-1.5, 0, -5.6), 0.4, 0.5)
	_model("barrel_small_stack", Vector3(1.45, 0, -6.4), -0.6, 0.6)
	_model("box_stacked", Vector3(1.5, 0, -8.2), 0.3, 0.45)
	_model("rubble_half", Vector3(-1.4, 0, -8.6), 0.9, 0.5)

	# Факелы на стенах: модель + тёплый свет без теней
	for t in [Vector3(-2.0, 2.0, -2.6), Vector3(2.0, 2.0, -2.6), Vector3(-2.0, 2.0, -6.6), Vector3(2.0, 2.0, -6.6)]:
		var pos: Vector3 = t
		_model("torch_mounted", pos, PI / 2.0 if pos.x < 0.0 else -PI / 2.0, 0.8)
		var flame_mat := StandardMaterial3D.new()
		flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_mat.albedo_color = Color(1.0, 0.65, 0.25)
		var flame := SphereMesh.new()
		flame.radius = 0.08
		flame.height = 0.22
		_static(flame, pos + Vector3(-signf(pos.x) * 0.36, 0.62, 0), flame_mat)
		var light := OmniLight3D.new()
		light.position = pos + Vector3(-signf(pos.x) * 0.5, 0.6, 0)
		light.light_color = Color(1.0, 0.62, 0.3)
		light.omni_range = 5.5
		light.omni_attenuation = 1.3
		light.shadow_enabled = false
		add_child(light)
		_torches.append(light)

	# Холодный «лунный» свет сверху — читаемость силуэта врага
	var moon := DirectionalLight3D.new()
	_moon = moon
	moon.rotation_degrees = Vector3(-55.0, 20.0, 0.0)
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.light_energy = 0.35
	moon.shadow_enabled = false
	add_child(moon)


## Поставить модель из набора подземелья. Возвращает узел, чтобы его можно было анимировать.
func _model(model_name: String, pos: Vector3, rot_y: float, sc: float = 1.0, parent: Node3D = null) -> Node3D:
	var scene: PackedScene = load(DUNGEON + model_name + ".glb")
	var node: Node3D = scene.instantiate()
	node.position = pos
	node.rotation.y = rot_y
	node.scale = Vector3.ONE * sc
	(parent if parent != null else self).add_child(node)
	return node


func _static(mesh: Mesh, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
