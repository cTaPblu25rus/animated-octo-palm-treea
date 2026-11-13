## Ступени Пепла: добровольная сложность от 0 до 10. Правила ступеней накапливаются:
## на ступени 3 действуют правила 1, 2 и 3. Победа над боссом на высшей открытой
## ступени открывает следующую. Чем выше ступень, тем больше осколков и опыта.
extends RefCounted

const Save := preload("res://scripts/save.gd")
const PATH := "res://data/difficulty.json"
const KEYS := ["hp", "damage", "windup", "idle", "altar", "regen"]

static var cfg: Dictionary = {}


static func load_once() -> void:
	if not cfg.is_empty():
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("Не найден файл сложности: " + PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		cfg = parsed


static func top() -> int:
	return cfg.tiers.size() - 1


## Высшая открытая ступень.
static func unlocked() -> int:
	return clampi(int(Save.data.get("tier_max", 0)), 0, top())


## Ступень, выбранная игроком для следующего забега.
static func selected() -> int:
	return clampi(int(Save.data.get("tier", 0)), 0, unlocked())


static func select(tier: int) -> void:
	Save.data.tier = clampi(tier, 0, unlocked())
	Save.save()


static func title(tier: int) -> String:
	return str(cfg.tiers[clampi(tier, 0, top())].name)


static func rule(tier: int) -> String:
	return str(cfg.tiers[clampi(tier, 0, top())].rule)


## Множители ступени: произведение правил всех ступеней от первой до выбранной.
static func mods(tier: int) -> Dictionary:
	var m := {}
	for key: String in KEYS:
		m[key] = 1.0
	for i in range(1, clampi(tier, 0, top()) + 1):
		var t: Dictionary = cfg.tiers[i]
		for key: String in KEYS:
			m[key] = float(m[key]) * float(t.get(key, 1.0))
	return m


## Множитель награды: kind — "shards" или "xp".
static func reward(tier: int, kind: String) -> float:
	return 1.0 + float(cfg.reward[kind]) * tier


## Рост силы врагов с глубиной: kind — "hp" или "damage", room_index считается с нуля.
static func depth(room_index: int, kind: String) -> float:
	return 1.0 + float(cfg.depth[kind]) * maxi(0, room_index)


## Победа над боссом на ступени tier. Возвращает номер новой открытой ступени или −1.
static func on_win(tier: int) -> int:
	if tier < unlocked() or tier >= top():
		return -1
	Save.data.tier_max = tier + 1
	Save.save()
	return tier + 1
