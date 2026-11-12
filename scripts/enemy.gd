## Враг ближнего боя из примитивов: туловище, голова, светящиеся глаза, клинок.
## Цикл: появление → стойка (открыт, видна жёлтая метка слабого места) →
## замах (клинок наливается красным, сторона удара известна) → удар → восстановление.
## Парирование отменяет удар; полная шкала стойкости — оглушение.
extends Node3D

signal windup_started(side: int)
signal struck(side: int, damage: float)
signal stunned
signal died
signal phase_changed(index: int, title: String)

enum Side { LEFT, RIGHT, TOP }
enum State { APPEAR, IDLE, WINDUP, RECOVER, STUNNED, DYING, DEAD }

const SIDE_BY_NAME := {"left": Side.LEFT, "right": Side.RIGHT, "top": Side.TOP}
const APPEAR_TIME := 0.9
const DYING_TIME := 1.4
const STAGGER_DECAY := 6.0

const MODELS := {
	"minion": preload("res://assets/kaykit/skeletons/Skeleton_Minion.glb"),
	"rogue": preload("res://assets/kaykit/skeletons/Skeleton_Rogue.glb"),
	"warrior": preload("res://assets/kaykit/skeletons/Skeleton_Warrior.glb"),
}
const WEAPONS := {
	"blade": preload("res://assets/kaykit/skeletons/Skeleton_Blade.gltf"),
	"axe": preload("res://assets/kaykit/skeletons/Skeleton_Axe.gltf"),
}
## Модель KayKit высотой ~2.17; приводим к росту человека.
const MODEL_SCALE := 1.0
const ANIM_IDLE := "Idle_Combat"
const ANIM_APPEAR := "Skeletons_Awaken_Standing"
const ANIM_HIT := "Hit_A"
const ANIM_PARRIED := "Hit_B"
const ANIM_STUN := "Sit_Floor_Down"
const ANIM_DEATH := "Death_C_Skeletons"
const ANIM_ATTACK := {
	Side.LEFT: "1H_Melee_Attack_Slice_Horizontal",
	Side.RIGHT: "1H_Melee_Attack_Slice_Horizontal",
	Side.TOP: "1H_Melee_Attack_Chop",
}
## Доля длины анимации атаки до момента удара: замах растягивается под windup из JSON.
const HIT_FRACTION := 0.42
const ORB_POS := {
	Side.LEFT: Vector3(-0.5, 1.15, 0.45),
	Side.RIGHT: Vector3(0.5, 1.15, 0.45),
	Side.TOP: Vector3(0.0, 2.2, 0.25),
}

var id := ""
var display_name := ""
var data: Dictionary = {}
var max_hp := 1.0
var hp := 1.0
var stagger := 0.0
var stagger_max := 100.0
var state: int = State.APPEAR
var state_t := 0.0
var state_dur := APPEAR_TIME
var attack_side: int = Side.LEFT
var weak_side: int = Side.RIGHT
## Окно парирования (задаёт игра) — в нём клинок вспыхивает ярче.
var parry_window := 0.25
## Сколько ударов враг терпит в стойке, прежде чем ответить контратакой.
var guard_hits := 2
var _hits_in_idle := 0
## Босс: фазы по порогам здоровья меняют длину замаха и число ударов подряд.
var is_boss := false
var phase := 0
var windup_time := 1.0
var combo := 1
var _combo_left := 0
## Счётчик замахов — по нему автоигрок отличает новый удар внутри серии.
var windup_count := 0

var _rng := RandomNumberGenerator.new()
var _sides: Array[int] = []
var _time := 0.0
var _hit_flash := 0.0
var _shake := 0.0
var _body_root: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _orb: MeshInstance3D
var _flash_mat: StandardMaterial3D     # вспышка тела при попадании (оверлей)
var _blade_mat: StandardMaterial3D     # свечение оружия при замахе (оверлей)
var _eye_mat: StandardMaterial3D
var _orb_mat: StandardMaterial3D
var _eye_color := Color.ORANGE


func setup(enemy_id: String, d: Dictionary, seed_value: int) -> void:
	id = enemy_id
	data = d
	display_name = str(d.get("name", "Враг"))
	max_hp = float(d.get("hp", 50))
	hp = max_hp
	stagger_max = float(d.get("stagger_max", 100))
	guard_hits = int(d.get("guard_hits", 2))
	is_boss = bool(d.get("boss", false))
	windup_time = float(d.get("windup", 1.0))
	_rng.seed = seed_value
	for s in d.get("sides", ["left", "right"]):
		_sides.append(int(SIDE_BY_NAME[s]))
	_eye_color = Color.html(str(d.get("eyes", "#ff7a1a")))
	_build(str(d.get("model", "minion")), str(d.get("weapon", "blade")), float(d.get("scale", 1.0)))
	_enter(State.APPEAR, float(d.get("appear_time", APPEAR_TIME)))


func is_alive() -> bool:
	return state != State.DYING and state != State.DEAD


## Открыт для точного удара: метка слабого места видна.
func is_open() -> bool:
	return state == State.IDLE or state == State.RECOVER or state == State.STUNNED


func time_to_impact() -> float:
	return state_dur - state_t if state == State.WINDUP else INF


func take_hit(damage: float, stagger_add: float) -> void:
	if not is_alive():
		return
	hp = maxf(0.0, hp - damage)
	_hit_flash = 1.0
	_shake = 1.0
	if hp <= 0.0:
		_enter(State.DYING, DYING_TIME)
		return
	if _check_phase():
		return
	if state == State.IDLE or state == State.RECOVER:
		_play(ANIM_HIT, 1.3, 0.05)
		_anim.queue(ANIM_IDLE)
	if state != State.STUNNED:
		stagger += stagger_add
		if stagger >= stagger_max:
			_stun()
			return
	# В стойке метка перескакивает, а после нескольких ударов враг контратакует
	if state == State.IDLE:
		_hits_in_idle += 1
		weak_side = (weak_side + _rng.randi_range(1, 2)) % 3
		if _hits_in_idle >= guard_hits:
			_start_attack()


## Удачное парирование: удар отменён, враг отброшен в восстановление.
func parried(stagger_add: float) -> void:
	if state != State.WINDUP:
		return
	_shake = 0.6
	_combo_left = 0
	stagger += stagger_add
	if stagger >= stagger_max:
		_stun()
	else:
		_enter(State.RECOVER, float(data.get("recover", 0.7)) * 1.5)
		_play(ANIM_PARRIED, 1.0, 0.05)
		_anim.queue(ANIM_IDLE)


func _start_attack() -> void:
	_combo_left = combo - 1
	_enter(State.WINDUP, windup_time)


## Переход в следующую фазу, когда здоровье упало ниже порога. Возвращает true, если фаза сменилась.
func _check_phase() -> bool:
	var phases: Array = data.get("phases", [])
	if phase >= phases.size():
		return false
	var ph: Dictionary = phases[phase]
	if hp / max_hp > float(ph.hp):
		return false
	phase += 1
	windup_time = float(ph.get("windup", windup_time))
	combo = int(ph.get("combo", combo))
	stagger = 0.0
	_combo_left = 0
	_model.scale.x = 1.0
	_enter(State.RECOVER, 1.6)
	_play("Taunt", 1.2, 0.1)
	_anim.queue(ANIM_IDLE)
	phase_changed.emit(phase, str(ph.get("title", "")))
	return true


func _stun() -> void:
	_combo_left = 0
	stagger = stagger_max
	_enter(State.STUNNED, float(data.get("stun_time", 2.0)))
	stunned.emit()


func _enter(s: int, dur: float) -> void:
	state = s
	state_t = 0.0
	state_dur = dur
	match s:
		State.APPEAR:
			var appear := str(data.get("appear_anim", ANIM_APPEAR))
			_play(appear, _len(appear) / dur, 0.0)
		State.IDLE:
			weak_side = _rng.randi_range(0, 2)
			_hits_in_idle = 0
			_model.scale.x = 1.0
			_play(ANIM_IDLE, 1.0, 0.25)
		State.WINDUP:
			windup_count += 1
			attack_side = _sides[_rng.randi_range(0, _sides.size() - 1)]
			# Удар слева — та же анимация, отражённая зеркально
			_model.scale.x = -1.0 if attack_side == Side.LEFT else 1.0
			var attack: String = ANIM_ATTACK[attack_side]
			_play(attack, _len(attack) * HIT_FRACTION / dur, 0.1)
			windup_started.emit(attack_side)
		State.STUNNED:
			_model.scale.x = 1.0
			_play(ANIM_STUN, 1.6, 0.15)
		State.DYING:
			_play(ANIM_DEATH, _len(ANIM_DEATH) / dur, 0.1)


func _process(delta: float) -> void:
	_time += delta
	state_t += delta
	match state:
		State.APPEAR:
			if state_t >= state_dur:
				_enter(State.IDLE, _idle_time())
		State.IDLE:
			if state_t >= state_dur:
				_start_attack()
		State.WINDUP:
			if state_t >= state_dur:
				var side := attack_side
				if _combo_left > 0:
					# Серия: следующий удар без передышки, замах короче
					_combo_left -= 1
					_enter(State.WINDUP, windup_time * 0.8)
					struck.emit(side, float(data.get("damage", 10)))
					return
				_enter(State.RECOVER, float(data.get("recover", 0.7)))
				# Довести удар в обычном темпе (та же анимация продолжается без рестарта)
				_anim.play(ANIM_ATTACK[side], -1, 1.3)
				_anim.queue(ANIM_IDLE)
				struck.emit(side, float(data.get("damage", 10)))
		State.RECOVER:
			if state_t >= state_dur:
				_enter(State.IDLE, _idle_time())
		State.STUNNED:
			stagger = stagger_max * (1.0 - clampf(state_t / state_dur, 0.0, 1.0))
			if state_t >= state_dur:
				stagger = 0.0
				_enter(State.IDLE, _idle_time())
		State.DYING:
			if state_t >= state_dur:
				state = State.DEAD
				visible = false
				died.emit()
	if state != State.STUNNED:
		stagger = maxf(0.0, stagger - STAGGER_DECAY * delta)
	_animate(delta)


func _idle_time() -> float:
	return _rng.randf_range(float(data.get("idle_min", 1.2)), float(data.get("idle_max", 2.0)))


# ============================================================ анимация

func _play(anim: String, speed: float, blend: float) -> void:
	_anim.speed_scale = 1.0
	_anim.play(anim, blend, speed)


func _len(anim: String) -> float:
	return _anim.get_animation(anim).length


func _animate(delta: float) -> void:
	var p := clampf(state_t / maxf(state_dur, 0.001), 0.0, 1.0)

	# Дрожь от попадания; в окне парирования враг мелко вибрирует
	_shake = maxf(0.0, _shake - delta * 4.0)
	var jitter := 0.0
	if state == State.WINDUP and time_to_impact() < parry_window:
		jitter = 0.012
	_body_root.position = Vector3(sin(_time * 90.0) * (0.05 * _shake + jitter), 0.0, 0.0)

	# Вспышка тела при попадании
	_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
	_flash_mat.albedo_color = Color(1.0, 0.92, 0.75, _hit_flash * 0.55)

	# Оружие наливается красным во время замаха, в окне парирования — почти белое
	var glow := 0.0
	var glow_color := Color(1.0, 0.12, 0.04)
	if state == State.WINDUP:
		glow = 0.25 + 0.6 * p
		if time_to_impact() < parry_window:
			glow_color = Color(1.0, 0.9, 0.8)
			glow = 0.95
	glow_color.a = glow
	_blade_mat.albedo_color = glow_color

	# Глаза тускнеют при оглушении
	_eye_mat.albedo_color = _eye_color * (0.3 if state == State.STUNNED else 1.0)

	# Метка слабого места
	_orb.visible = is_open() and state != State.APPEAR
	if _orb.visible:
		var target: Vector3 = ORB_POS[weak_side]
		if state == State.STUNNED:
			target = Vector3(target.x * 0.8, minf(target.y, 1.3) * 0.75, target.z)
		_orb.position = _orb.position.lerp(target, 1.0 - exp(-18.0 * delta))
		_orb.scale = Vector3.ONE * (1.0 + 0.18 * sin(_time * 8.0))


# ============================================================ модель

func _build(model_id: String, weapon_id: String, sc: float) -> void:
	_body_root = Node3D.new()
	add_child(_body_root)
	scale = Vector3.ONE * sc

	var scene: PackedScene = MODELS[model_id]
	_model = scene.instantiate()
	_model.scale = Vector3.ONE * MODEL_SCALE
	_body_root.add_child(_model)
	_anim = _find(_model, "AnimationPlayer")
	_anim.get_animation(ANIM_IDLE).loop_mode = Animation.LOOP_LINEAR

	_flash_mat = _overlay()
	_blade_mat = _overlay()
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = _eye_color
	for mi: MeshInstance3D in _meshes(_model):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if String(mi.name).ends_with("_Eyes"):
			mi.material_override = _eye_mat
		else:
			mi.material_overlay = _flash_mat

	# Оружие в правой руке: слот кости handslot.r
	var skeleton: Skeleton3D = _find(_model, "Skeleton3D")
	var slot := BoneAttachment3D.new()
	slot.bone_name = "handslot.r"
	skeleton.add_child(slot)
	var weapon_scene: PackedScene = WEAPONS[weapon_id]
	var weapon: Node3D = weapon_scene.instantiate()
	slot.add_child(weapon)
	for mi: MeshInstance3D in _meshes(weapon):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_overlay = _blade_mat

	# Метка слабого места
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_orb_mat.albedo_color = Color(1.0, 0.85, 0.2)
	_orb_mat.no_depth_test = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	sphere.radial_segments = 16
	sphere.rings = 8
	_orb = MeshInstance3D.new()
	_orb.mesh = sphere
	_orb.material_override = _orb_mat
	_orb.position = ORB_POS[Side.RIGHT]
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body_root.add_child(_orb)


## Полупрозрачный несветящийся слой поверх материала модели: цвет и сила задаются альфой.
func _overlay() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0)
	return m


func _find(root: Node, type_name: String) -> Node:
	if root.is_class(type_name):
		return root
	for c in root.get_children():
		var found := _find(c, type_name)
		if found != null:
			return found
	return null


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_meshes(c))
	return out
