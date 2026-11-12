## Сохранение между забегами: осколки, золото, улучшения и оружие героя (user://save.json).
## В автотестах ephemeral = true: ничего не читается и не пишется на диск.
extends RefCounted

const PATH := "user://save.json"

static var data: Dictionary = {}
static var ephemeral := false
static var _loaded := false


static func defaults() -> Dictionary:
	return {
		"shards": 0, "gold": 0, "runs": 0, "wins": 0,
		"upgrades": {"hp": 0, "damage": 0, "stamina": 0, "parry": 0},
		"weapon": {"id": "guard_sword", "rarity": 0, "level": 0, "affix": ""},
	}


static func load_once(is_ephemeral: bool) -> void:
	if _loaded:
		return
	_loaded = true
	ephemeral = is_ephemeral
	data = defaults()
	if ephemeral or not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		# Сливаем с умолчаниями: старое сохранение не ломается, когда появляются новые поля
		for key: String in parsed:
			if data.has(key) and typeof(data[key]) == TYPE_DICTIONARY and parsed[key] is Dictionary:
				for k2: String in parsed[key]:
					data[key][k2] = parsed[key][k2]
			else:
				data[key] = parsed[key]


static func save() -> void:
	if ephemeral:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))


static func reset() -> void:
	data = defaults()
	save()
