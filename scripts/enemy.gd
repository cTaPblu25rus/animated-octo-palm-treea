## Враг ближнего боя из примитивов: туловище, голова, светящиеся глаза, клинок.
## Цикл: появление → стойка (открыт, видна жёлтая метка слабого места) →
## замах (клинок наливается красным, сторона удара известна) → удар → восстановление.
## Парирование отменяет удар; полная шкала стойкости — оглушение.
extends Node3D

signal windup_started(side: int)
signal struck(side: int, damage: float)
signal stunned
signal died

enum Side { LEFT, RIGHT, TOP }
enum State { APPEAR, IDLE, WINDUP, RECOVER, STUNNED, DYING, DEAD }

const SIDE_BY_NAME := {"left": Side.LEFT, "right": Side.RIGHT, "top": Side.TOP}
const APPEAR_TIME := 0.9
const DYING_TIME := 1.1
const STAGGER_DECAY := 6.0

# Позы клинка (поворот руки в радианах): покой, замах и конец удара по сторонам.
const POSE_REST := Vector3(0.35, 0.0, -0.55)
const POSE_RAISE := {
	Side.LEFT: Vector3(-0.35, 0.0, 1.35),
	Side.RIGHT: Vector3(-0.35, 0.0, -1.35),
	Side.TOP: Vector3(-1.15, 0.0, 0.0),
}
const POSE_FOLLOW := {
	Side.LEFT: Vector3(0.9, 0.0, -1.25),
	Side.RIGHT: Vector3(0.9, 0.0, 1.25),
	Side.TOP: Vector3(1.55, 0.0, 0.0),
}
const ORB_POS := {
	Side.LEFT: Vector3(-0.42, 1.25, 0.36),
	Side.RIGHT: Vector3(0.42, 1.25, 0.36),
	Side.TOP: Vector3(0.0, 2.15, 0.18),
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

var _rng := RandomNumberGenerator.new()
var _sides: Array[int] = []
var _time := 0.0
var _hit_flash := 0.0
var _shake := 0.0
var _body_root: Node3D
var _arm: Node3D
var _orb: MeshInstance3D
var _body_mat: StandardMaterial3D
var _blade_mat: StandardMaterial3D
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
	_rng.seed = seed_value
	for s in d.get("sides", ["left", "right"]):
		_sides.append(int(SIDE_BY_NAME[s]))
	_eye_color = Color.html(str(d.get("eyes", "#ff7a1a")))
	_build(Color.html(str(d.get("color", "#555555"))), float(d.get("scale", 1.0)))
	_enter(State.APPEAR, APPEAR_TIME)


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
			_enter(State.WINDUP, float(data.get("windup", 1.0)))


## Удачное парирование: удар отменён, враг отброшен в восстановление.
func parried(stagger_add: float) -> void:
	if state != State.WINDUP:
		return
	_shake = 0.6
	stagger += stagger_add
	if stagger >= stagger_max:
		_stun()
	else:
		_enter(State.RECOVER, float(data.get("recover", 0.7)) * 1.5)


func _stun() -> void:
	stagger = stagger_max
	_enter(State.STUNNED, float(data.get("stun_time", 2.0)))
	stunned.emit()


func _enter(s: int, dur: float) -> void:
	state = s
	state_t = 0.0
	state_dur = dur
	match s:
		State.IDLE:
			weak_side = _rng.randi_range(0, 2)
			_hits_in_idle = 0
		State.WINDUP:
			attack_side = _sides[_rng.randi_range(0, _sides.size() - 1)]
			windup_started.emit(attack_side)


func _process(delta: float) -> void:
	_time += delta
	state_t += delta
	match state:
		State.APPEAR:
			if state_t >= state_dur:
				_enter(State.IDLE, _idle_time())
		State.IDLE:
			if state_t >= state_dur:
				_enter(State.WINDUP, float(data.get("windup", 1.0)))
		State.WINDUP:
			if state_t >= state_dur:
				var side := attack_side
				_enter(State.RECOVER, float(data.get("recover", 0.7)))
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

func _animate(delta: float) -> void:
	var p := clampf(state_t / maxf(state_dur, 0.001), 0.0, 1.0)
	var target := POSE_REST
	var speed := 10.0
	_body_root.position = Vector3.ZERO
	_body_root.rotation = Vector3(0.0, 0.0, sin(_time * 1.7) * 0.04)
	match state:
		State.APPEAR:
			_body_root.position.y = lerpf(-2.2, 0.0, 1.0 - pow(1.0 - p, 3.0))
		State.WINDUP:
			target = POSE_REST.lerp(POSE_RAISE[attack_side], sqrt(p))
			if time_to_impact() < parry_window:
				target += Vector3(sin(_time * 70.0), 0.0, cos(_time * 63.0)) * 0.03
			_body_root.rotation.x = -0.12 * p
		State.RECOVER:
			if state_t < 0.16:
				target = POSE_FOLLOW[attack_side]
				speed = 32.0
				_body_root.rotation.x = 0.18
		State.STUNNED:
			target = Vector3(0.9, 0.0, -0.2)
			_body_root.rotation.z = sin(_time * 4.0) * 0.12
			_body_root.rotation.x = 0.1
		State.DYING:
			_body_root.rotation.x = -p * 1.35
			_body_root.position.y = -p * 0.7
	_arm.rotation = _arm.rotation.lerp(target, 1.0 - exp(-speed * delta))

	# Дрожь от попадания
	_shake = maxf(0.0, _shake - delta * 4.0)
	_body_root.position.x += sin(_time * 90.0) * 0.05 * _shake

	# Вспышка тела при попадании
	_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
	_body_mat.emission = Color(1.0, 0.9, 0.7) * _hit_flash * 0.8

	# Клинок наливается красным во время замаха, в окне парирования — почти белый
	var glow := 0.0
	var glow_color := Color(1.0, 0.15, 0.05)
	if state == State.WINDUP:
		glow = 0.4 + 1.6 * p
		if time_to_impact() < parry_window:
			glow_color = Color(1.0, 0.75, 0.6)
			glow = 3.0
	_blade_mat.emission = glow_color * glow

	# Глаза тускнеют при оглушении
	var eye_k := 0.35 if state == State.STUNNED else 2.2
	_eye_mat.emission = _eye_color * eye_k

	# Метка слабого места
	_orb.visible = is_open() and state != State.APPEAR
	if _orb.visible:
		var stun_k := 1.3 if state == State.STUNNED else 1.0
		_orb.position = _orb.position.lerp(ORB_POS[weak_side], 1.0 - exp(-18.0 * delta))
		_orb.scale = Vector3.ONE * (1.0 + 0.18 * sin(_time * 8.0)) * stun_k


# ============================================================ модель

func _build(color: Color, sc: float) -> void:
	_body_root = Node3D.new()
	add_child(_body_root)
	scale = Vector3.ONE * sc

	_body_mat = _mat(color, 0.9)
	_body_mat.emission_enabled = true
	var dark := _mat(color.darkened(0.45), 0.8)
	_eye_mat = _mat(Color.BLACK, 1.0)
	_eye_mat.emission_enabled = true
	_blade_mat = _mat(Color(0.55, 0.52, 0.5), 0.4)
	_blade_mat.metallic = 0.2
	_blade_mat.emission_enabled = true
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_orb_mat.albedo_color = Color(1.0, 0.85, 0.2)

	# Туловище, плащ, наплечники, голова
	_add_mesh(_capsule(0.34, 1.4), Vector3(0, 0.95, 0), _body_mat)
	_add_mesh(_box(Vector3(0.95, 0.18, 0.4)), Vector3(0, 1.58, 0), dark)
	_add_mesh(_box(Vector3(0.6, 1.0, 0.08)), Vector3(0, 0.95, -0.28), dark)
	var head := _add_mesh(_sphere(0.21), Vector3(0, 1.88, 0.02), _body_mat)
	head.scale = Vector3(1.0, 1.15, 1.0)
	_add_mesh(_box(Vector3(0.5, 0.08, 0.5)), Vector3(0, 2.02, 0), dark)
	for x in [-0.08, 0.08]:
		_add_mesh(_sphere(0.035), Vector3(x, 1.9, 0.19), _eye_mat)

	# Рука с клинком: точка поворота на груди
	_arm = Node3D.new()
	_arm.position = Vector3(0.0, 1.42, 0.22)
	_arm.rotation = POSE_REST
	_body_root.add_child(_arm)
	var blade := MeshInstance3D.new()
	blade.mesh = _box(Vector3(0.09, 1.05, 0.03))
	blade.position = Vector3(0, 0.62, 0)
	blade.material_override = _blade_mat
	_arm.add_child(blade)
	var guard := MeshInstance3D.new()
	guard.mesh = _box(Vector3(0.3, 0.05, 0.06))
	guard.position = Vector3(0, 0.08, 0)
	guard.material_override = dark
	_arm.add_child(guard)

	# Метка слабого места
	_orb = MeshInstance3D.new()
	_orb.mesh = _sphere(0.07)
	_orb.material_override = _orb_mat
	_orb.position = ORB_POS[Side.RIGHT]
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body_root.add_child(_orb)


func _add_mesh(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body_root.add_child(m)
	return m


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 4
	return c
