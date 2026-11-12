## Генератор забега: по сиду собирает список комнат из data/run.json.
## Правила: первая и последняя комнаты — бой (последняя — усиленный),
## в середине обязательно встречаются сундук, алтарь и событие, остальное — бои.
## Если в данных задан босс, он всегда идёт последней комнатой.
## Один и тот же сид всегда даёт один и тот же забег.
extends RefCounted


static func generate(cfg: Dictionary, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var length := int(cfg.length)

	var middle: Array = []
	for kind: String in cfg.required:
		middle.append(kind)
	while middle.size() < length - 2:
		middle.append("fight")
	# Перемешивание Фишера — Йетса своим генератором, чтобы результат зависел только от сида
	for i in range(middle.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = middle[i]
		middle[i] = middle[j]
		middle[j] = tmp

	var rooms: Array = []
	for i in length:
		var kind := "fight"
		if i > 0 and i < length - 1:
			kind = middle[i - 1]
		var tier := "first" if i == 0 else ("final" if i == length - 1 else "middle")
		var room := make_room(cfg, rng, kind, i, tier)
		rooms.append(room)
	if cfg.has("boss"):
		rooms.append({"kind": "boss", "index": length, "wave": [cfg.boss]})
	return rooms


## Собрать комнату нужного вида. tier выбирает набор врагов для боя.
static func make_room(cfg: Dictionary, rng: RandomNumberGenerator, kind: String, index: int, tier: String = "middle") -> Dictionary:
	var room := {"kind": kind, "index": index}
	match kind:
		"fight", "elite":
			var pool: Array = cfg.fights["elite" if kind == "elite" else tier]
			room.wave = pool[rng.randi_range(0, pool.size() - 1)]
		"chest":
			room.shards = rng.randi_range(int(cfg.chest.shards_min), int(cfg.chest.shards_max))
			room.gold = rng.randi_range(int(cfg.chest.gold_min), int(cfg.chest.gold_max))
		"altar":
			room.heal = float(cfg.altar.heal)
		"event":
			var events: Array = cfg.events
			room.event = events[rng.randi_range(0, events.size() - 1)]
	return room


## Развилки: для каждой комнаты середины забега — вторая дорога другого вида (или null).
## Основной путь (rooms) не меняется, поэтому в нём по-прежнему есть сундук, алтарь и событие.
static func alternatives(cfg: Dictionary, rooms: Array, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	var table: Dictionary = cfg.get("alternatives", {})
	var out: Array = []
	var length := int(cfg.length)
	var last := ""
	var shop_used := false
	for i in rooms.size():
		var kind := str(rooms[i].kind)
		if i == 0 or i >= length - 1 or not table.has(kind):
			out.append(null)
			continue
		# Не ставим одинаковые вторые дороги подряд и не больше одной лавки на забег
		var options: Array = []
		for o: String in table[kind]:
			if o != last and not (o == "shop" and shop_used):
				options.append(o)
		if options.is_empty():
			out.append(null)
			continue
		last = str(options[rng.randi_range(0, options.size() - 1)])
		shop_used = shop_used or last == "shop"
		out.append(make_room(cfg, rng, last, i))
	return out
