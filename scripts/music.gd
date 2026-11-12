## Фоновая музыка с плавным переходом между треками. Два проигрывателя на шине «Music»:
## один затихает, другой нарастает. Треки — assets/music/<имя>.ogg, зациклены.
extends Node

const DIR := "res://assets/music/"
const FADE := 1.6
const BUS := "Music"

var current := ""
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _duck := 1.0            # приглушение под озвучку
var _duck_target := 1.0


static func ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, BUS)
	AudioServer.set_bus_send(i, "Master")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_bus()
	_a = _make()
	_b = _make()
	_active = _a


func _make() -> AudioStreamPlayer:
	var pl := AudioStreamPlayer.new()
	pl.bus = BUS
	pl.volume_db = -60.0
	add_child(pl)
	return pl


## Включить трек (пустая строка — тишина). Повторный вызов с тем же треком ничего не делает.
func play(track: String) -> void:
	if track == current:
		return
	current = track
	_active = _b if _active == _a else _a
	if track == "":
		return
	var path := DIR + track + ".ogg"
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStreamOggVorbis = load(path)
	stream.loop = true
	_active.stream = stream
	_active.volume_db = -60.0
	_active.play()


## Приглушить музыку, пока звучит реплика.
func duck(on: bool) -> void:
	_duck_target = 0.35 if on else 1.0


func _process(delta: float) -> void:
	_duck = move_toward(_duck, _duck_target, delta * 2.0)
	var step := delta / FADE
	for pl: AudioStreamPlayer in [_a, _b]:
		var lin := db_to_linear(pl.volume_db)
		var target := _duck if (pl == _active and current != "") else 0.0
		lin = move_toward(lin, target, step)
		pl.volume_db = linear_to_db(maxf(lin, 0.001))
		if pl != _active and lin <= 0.002 and pl.playing:
			pl.stop()
