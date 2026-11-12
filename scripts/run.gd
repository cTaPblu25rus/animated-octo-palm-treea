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
		var room := {"kind": kind, "index": i}
		match kind:
			"fight":
				var tier := "first" if i == 0 else ("final" if i == length - 1 else "middle")
				var pool: Array = cfg.fights[tier]
				room.wave = pool[rng.randi_range(0, pool.size() - 1)]
			"chest":
				room.shards = rng.randi_range(int(cfg.chest.shards_min), int(cfg.chest.shards_max))
				room.gold = rng.randi_range(int(cfg.chest.gold_min), int(cfg.chest.gold_max))
			"altar":
				room.heal = float(cfg.altar.heal)
			"event":
				var events: Array = cfg.events
				room.event = events[rng.randi_range(0, events.size() - 1)]
		rooms.append(room)
	if cfg.has("boss"):
		rooms.append({"kind": "boss", "index": length, "wave": [cfg.boss]})
	return rooms
