## Прогресс героя между забегами: опыт, уровень, очки и ранги талантов.
## Данные — data/hero.json, состояние — в сохранении (Save.data.xp/level/talents).
extends RefCounted

const Save := preload("res://scripts/save.gd")


## Сколько опыта нужно, чтобы перейти с уровня level на следующий.
static func need(cfg: Dictionary, level: int) -> int:
	return int(cfg.xp_base) + int(cfg.xp_step) * (level - 1)


## Начислить опыт. Возвращает, сколько уровней получено.
static func add_xp(cfg: Dictionary, amount: int) -> int:
	var gained := 0
	var level := int(Save.data.level)
	var xp := int(Save.data.xp) + amount
	while level < int(cfg.max_level) and xp >= need(cfg, level):
		xp -= need(cfg, level)
		level += 1
		gained += 1
	if level >= int(cfg.max_level):
		xp = 0
	Save.data.level = level
	Save.data.xp = xp
	return gained


static func rank(id: String) -> int:
	return int(Save.data.talents.get(id, 0))


static func spent() -> int:
	var n := 0
	for id: String in Save.data.talents:
		n += int(Save.data.talents[id])
	return n


## Свободные очки талантов: по одному за каждый уровень после первого.
static func points() -> int:
	return int(Save.data.level) - 1 - spent()


## Можно ли изучить ранг: есть очко, не предел, и изучен предыдущий талант ветки.
static func can_learn(cfg: Dictionary, id: String) -> bool:
	if points() <= 0:
		return false
	for br: Dictionary in cfg.branches:
		var nodes: Array = br.nodes
		for i in nodes.size():
			if str(nodes[i].id) == id:
				if rank(id) >= int(nodes[i].max):
					return false
				return i == 0 or rank(str(nodes[i - 1].id)) > 0
	return false


static func learn(cfg: Dictionary, id: String) -> bool:
	if not can_learn(cfg, id):
		return false
	Save.data.talents[id] = rank(id) + 1
	return true


static func reset() -> void:
	Save.data.talents = {}


static func skill_unlocked(skill: Dictionary) -> bool:
	return int(Save.data.level) >= int(skill.level)
