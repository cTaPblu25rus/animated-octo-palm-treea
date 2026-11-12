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

const DUNGEON := "res://assets/kaykit/dungeon/"
const HERO_SWORD := preload("res://assets/kaykit/hero/sword_1handed.gltf")
const HERO_SHIELD := preload("res://assets/kaykit/hero/shield_round.gltf")
const WALLS := ["wall", "wall_cracked", "wall", "wall_arched", "wall_broken", "wall_shelves"]

const DATA_PATH := "res://data/combat.json"
const RUN_PATH := "res://data/run.json"
const WALK_TIME := 1.5
const WALK_DISTANCE := 3.2
const CLEARED_DELAY := 1.5
const KIND_NAMES := {"fight": "Бой", "chest": "Сундук", "altar": "Алтарь Зари", "event": "Находка"}
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
var fade := 1.0                 # затемнение экрана при переходе, читает HUD
var _walk_t := 0.0
var _prop: Node3D
var _prop_lid: Node3D
var _prop_glow: MeshInstance3D
var _prop_used := false
var _run_rng := RandomNumberGenerator.new()

## Счётчики для автоигрока и итогового экрана.
var stats := {"hits": 0, "weak_hits": 0, "parries": 0, "blocks": 0, "dodges": 0,
	"charged": 0, "stuns": 0, "rooms": 0, "taken": 0.0, "hurt": 0, "kills": 0}

var gestures: Node
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
	p = cfg.player
	max_hp = float(p.hp)
	hp = max_hp
	max_stamina = float(p.stamina)
	stamina = max_stamina
	run_cfg = _load_json(RUN_PATH)
	run_seed = 1 if autoplay else int(_rng.randi() % 1000000)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			run_seed = int(a.trim_prefix("--seed="))
	rooms = Run.generate(run_cfg, run_seed)
	_run_rng.seed = run_seed

	sfx = Sfx.new()
	add_child(sfx)
	_build_room()
	_build_camera()
	gestures = Gestures.new()
	add_child(gestures)
	gestures.gesture.connect(on_gesture)
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	_next_room()

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
		hud.say("Комната очищена  +%d оск." % reward, Color(1.0, 0.85, 0.4), 1.3)
		_room_cleared()
		return
	var id: String = wave[wave_index]
	enemy = Enemy.new()
	enemy.position = ENEMY_POS
	add_child(enemy)
	enemy.setup(id, cfg.enemies[id], _run_rng.randi())
	enemy.parry_window = float(p.parry_window)
	enemy.windup_started.connect(_on_windup)
	enemy.struck.connect(_on_struck)
	enemy.stunned.connect(_on_stunned)
	enemy.died.connect(_on_died)
	state = "fight"
	hud.say(enemy.display_name, Color(0.9, 0.85, 0.8), 1.4)


func _on_windup(_side: int) -> void:
	sfx.play("windup", -6.0, 1.0 / maxf(0.5, float(enemy.data.get("windup", 1.0))))


func _on_stunned() -> void:
	stats.stuns += 1
	sfx.play("stun", -3.0)
	hud.say("Оглушён! Бей!", Color(1.0, 0.9, 0.3), 1.2)


func _on_died() -> void:
	stats.kills += 1
	sfx.play("death", -2.0)
	enemy.queue_free()
	enemy = null
	state = "between"
	_between_t = NEXT_ENEMY_DELAY


## Враг ударил. Исход решают уклонение, блок и стойкость игрока.
func _on_struck(side: int, damage: float) -> void:
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
	hp = maxf(0.0, hp - dmg)
	stats.taken += dmg
	stats.hurt += 1
	sfx.play("hurt")
	hud.hurt_flash()
	_shake = maxf(_shake, 0.8)
	_buzz(80)
	if hp <= 0.0:
		state = "defeat"
		charging = false


func _spend(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_since_spend = 0.0


# ============================================================ забег

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
	if str(room.kind) == "fight":
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
	state = "cleared"
	_between_t = CLEARED_DELAY
	charging = false


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


func _walk_offset() -> float:
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
		if kind == "tap":
			get_tree().reload_current_scene()
		return
	if state == "room":
		if kind == "tap":
			_use_room()
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
	dmg *= mult * damage_mult
	stg *= mult
	enemy.take_hit(dmg, stg)
	stats.hits += 1
	if weak:
		stats.weak_hits += 1
	sfx.play("crit" if weak else "hit", 0.0, 1.0 if mult <= 1.0 else 0.8)
	sfx.play("swing", -8.0)
	hud.popup("%d" % roundi(dmg), enemy.global_position + Vector3(0, 1.4, 0),
		Color(1.0, 0.85, 0.3) if weak else Color(0.85, 0.85, 0.85), mult > 1.0 or weak)
	_shake = maxf(_shake, 0.25 if mult <= 1.0 else 0.55)
	_buzz(12 if mult <= 1.0 else 35)


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


func _buzz(ms: int) -> void:
	if OS.has_feature("mobile"):
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

	_sword = Node3D.new()
	_sword.position = SWORD_POS
	_sword.rotation = SWORD_REST
	camera.add_child(_sword)
	var sword_model: Node3D = HERO_SWORD.instantiate()
	sword_model.scale = Vector3.ONE * 0.36
	_sword.add_child(sword_model)

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

	# Щит поднимается при блоке
	var shield_target := SHIELD_UP if block_t > 0.0 else SHIELD_REST
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
		_torches[i].light_energy = 1.6 + 0.25 * sin(_time * 9.0 + i * 2.1) + 0.15 * sin(_time * 23.0 + i)


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
	add_child(env)

	var stone_dark := _mat(Color(0.1, 0.095, 0.11), 0.95)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5

	# Коридор из модулей 4×4: пол и стены по обе стороны, потолок — тёмная плита
	for i in 4:
		var z := 2.0 - i * 4.0
		_model("floor_tile_large_rocks" if i == 2 else "floor_tile_large", Vector3(0, 0, z), 0.0)
		for side: float in [-1.0, 1.0]:
			var wall: String = WALLS[rng.randi_range(0, WALLS.size() - 1)]
			_model(wall, Vector3(side * 2.5, 0, z), -side * PI / 2.0)
	_model("wall_gated", Vector3(0, 0, -10.5), 0.0)
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
