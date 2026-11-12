## Распознавание жестов для боя одной рукой.
## Ловит касания только в нижней части экрана (ниже ZONE_TOP): верх остаётся для обзора.
##
## Сигнал gesture(kind) выдаёт:
##   swipe_left, swipe_right, swipe_up, swipe_down — обычный свайп;
##   dodge_left, dodge_right — второй свайп в ту же сторону за DOUBLE_TIME;
##   charge_start, charge_release — палец удержан на месте и отпущен;
##   tap — короткое касание без сдвига.
## Автоигрок вызывает press()/move()/release() напрямую — тот же код, что и для пальца.
extends Node

signal gesture(kind: String)
## Палец нажал на зону-кнопку (умение): жестом это касание не считается.
signal zone_pressed(index: int)

const ZONE_TOP := 0.55          # доля высоты экрана: жесты принимаются ниже этой линии
const SWIPE_MIN := 0.07         # минимальная длина свайпа в долях ширины экрана
const SWIPE_MAX_TIME := 0.45    # дольше — уже не свайп
const HOLD_TIME := 0.35         # удержание для заряда
const HOLD_SLOP := 0.035        # допустимый сдвиг пальца при удержании
const DOUBLE_TIME := 0.3        # окно для двойного свайпа

var enabled := true
var tap_zones: Array[Rect2] = []
var _active := false
var _index := -1
var _start := Vector2.ZERO
var _cur := Vector2.ZERO
var _start_t := 0.0
var _charging := false
var _last_swipe := ""
var _last_swipe_t := -10.0
var _now := 0.0


func _process(delta: float) -> void:
	_now += delta
	if _active and not _charging and _now - _start_t >= HOLD_TIME:
		if (_cur - _start).length() / _width() < HOLD_SLOP:
			_charging = true
			gesture.emit("charge_start")


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not _active:
			for i in tap_zones.size():
				if tap_zones[i].has_point(t.position):
					zone_pressed.emit(i)
					return
			if t.position.y >= _height() * ZONE_TOP:
				_index = t.index
				press(t.position)
		elif not t.pressed and _active and t.index == _index:
			release(t.position)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _active and d.index == _index:
			move(d.position)


func press(pos: Vector2) -> void:
	_active = true
	_charging = false
	_start = pos
	_cur = pos
	_start_t = _now


func move(pos: Vector2) -> void:
	_cur = pos


func release(pos: Vector2) -> void:
	if not _active:
		return
	_active = false
	_cur = pos
	if _charging:
		_charging = false
		gesture.emit("charge_release")
		return
	var d := pos - _start
	var dist := d.length() / _width()
	var dt := _now - _start_t
	if dist < SWIPE_MIN:
		gesture.emit("tap")
		return
	if dt > SWIPE_MAX_TIME:
		return
	var dir := ""
	if absf(d.x) >= absf(d.y):
		dir = "right" if d.x > 0.0 else "left"
	else:
		dir = "down" if d.y > 0.0 else "up"
	if (dir == "left" or dir == "right") and dir == _last_swipe and _now - _last_swipe_t <= DOUBLE_TIME:
		_last_swipe = ""
		gesture.emit("dodge_" + dir)
		return
	_last_swipe = dir
	_last_swipe_t = _now
	gesture.emit("swipe_" + dir)


## Палец сейчас на экране и копит заряд.
func is_charging() -> bool:
	return _charging


func _width() -> float:
	return maxf(1.0, get_viewport().get_visible_rect().size.x)


func _height() -> float:
	return maxf(1.0, get_viewport().get_visible_rect().size.y)
