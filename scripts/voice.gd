## Озвучка с субтитрами. Реплики описаны в data/voice.json, звук — assets/voice/<id>.ogg
## (генерируется скриптом tools/make_voice.py). Пока реплика звучит, HUD показывает её текст.
extends Node

const DATA := "res://data/voice.json"
const DIR := "res://assets/voice/"

var lines: Dictionary = {}
var subtitle := ""
var speaker := ""
var _player: AudioStreamPlayer
var _left := 0.0
var _queue: Array = []      # [задержка до старта, id]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			lines = parsed
	_player = AudioStreamPlayer.new()
	_player.volume_db = 3.0
	add_child(_player)


func length(id: String) -> float:
	var path := DIR + id + ".ogg"
	if not ResourceLoader.exists(path):
		return 2.0
	var stream: AudioStream = load(path)
	return stream.get_length()


## Произнести реплику сейчас. Возвращает её длину в секундах.
func say(id: String) -> float:
	if not lines.has(id):
		return 0.0
	var path := DIR + id + ".ogg"
	var dur := 2.0
	if ResourceLoader.exists(path):
		_player.stream = load(path)
		_player.play()
		dur = _player.stream.get_length()
	subtitle = str(lines[id].text)
	speaker = str(lines[id].who)
	_left = dur + 0.35
	return dur


## Произнести реплики подряд с паузой между ними. Возвращает общую длину.
func say_sequence(ids: Array, gap: float = 0.45, delay: float = 0.0) -> float:
	_queue.clear()
	var t := delay
	for id: String in ids:
		_queue.append([t, id])
		t += length(id) + gap
	return t


func stop() -> void:
	_queue.clear()
	_player.stop()
	subtitle = ""
	_left = 0.0


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	for i in range(_queue.size() - 1, -1, -1):
		_queue[i][0] -= delta
	while not _queue.is_empty() and _queue[0][0] <= 0.0:
		var id: String = _queue.pop_front()[1]
		say(id)
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			subtitle = ""
