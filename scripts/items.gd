## Оружие: выпадение, сила, описание. Данные — в data/items.json.
## Экземпляр оружия — словарь {"id", "rarity", "level", "affix"}.
extends RefCounted


## Случайное оружие. depth 0..1 — глубина забега: чем дальше, тем выше шанс редкости.
static func roll(cfg: Dictionary, rng: RandomNumberGenerator, depth: float, min_rarity: int = 0) -> Dictionary:
	var ids: Array = cfg.weapons.keys()
	var weights: Array = cfg.rarity_weights
	var total := 0.0
	var w: Array[float] = []
	for i in weights.size():
		# Глубина перекладывает вес с обычных на редкие
		var k := float(weights[i]) * (1.0 + depth * 1.5 * i) if i > 0 else float(weights[i]) * (1.0 - depth * 0.5)
		if i < min_rarity:
			k = 0.0
		w.append(k)
		total += k
	var r := rng.randf() * total
	var rarity := weights.size() - 1
	for i in w.size():
		r -= w[i]
		if r <= 0.0:
			rarity = i
			break
	var affix := ""
	if rng.randf() < float(cfg.rarities[rarity].affix_chance):
		var affixes: Array = cfg.affixes.keys()
		affix = affixes[rng.randi_range(0, affixes.size() - 1)]
	return {"id": ids[rng.randi_range(0, ids.size() - 1)], "rarity": rarity, "level": 0, "affix": affix}


## Множитель урона экземпляра: вид оружия × редкость × заточка.
static func damage_mult(cfg: Dictionary, w: Dictionary) -> float:
	var base: Dictionary = cfg.weapons[w.id]
	return float(base.damage) * float(cfg.rarities[int(w.rarity)].mult) * (1.0 + float(cfg.sharpen.bonus) * int(w.level))


## Одна цифра для сравнения: урон в секунду с поправкой на стойкость и свойство.
static func power(cfg: Dictionary, w: Dictionary) -> int:
	var base: Dictionary = cfg.weapons[w.id]
	var dps := damage_mult(cfg, w) / float(base.speed)
	var bonus := 1.0 + (float(base.stagger) - 1.0) * 0.25 + (0.12 if str(w.affix) != "" else 0.0)
	return roundi(100.0 * dps * bonus)


static func title(cfg: Dictionary, w: Dictionary) -> String:
	var t := str(cfg.weapons[w.id].name)
	if int(w.level) > 0:
		t += " +%d" % int(w.level)
	return t


static func color(cfg: Dictionary, w: Dictionary) -> Color:
	return Color.html(str(cfg.rarities[int(w.rarity)].color))


static func salvage(cfg: Dictionary, w: Dictionary) -> int:
	return int(cfg.rarities[int(w.rarity)].salvage) + 2 * int(w.level)


## Строки сравнения для карточки: [название, значение, разница со старым (−1, 0, 1)].
static func compare(cfg: Dictionary, w: Dictionary, old: Dictionary) -> Array:
	var a: Dictionary = cfg.weapons[w.id]
	var b: Dictionary = cfg.weapons[old.id]
	var da := damage_mult(cfg, w)
	var db := damage_mult(cfg, old)
	return [
		["Сила", str(power(cfg, w)), signi(power(cfg, w) - power(cfg, old))],
		["Урон", "×%.2f" % da, _cmp(da, db)],
		["Скорость удара", "×%.2f" % (1.0 / float(a.speed)), _cmp(1.0 / float(a.speed), 1.0 / float(b.speed))],
		["Пробитие стойкости", "×%.2f" % float(a.stagger), _cmp(float(a.stagger), float(b.stagger))],
	]


static func _cmp(a: float, b: float) -> int:
	return 0 if absf(a - b) < 0.005 else (1 if a > b else -1)
