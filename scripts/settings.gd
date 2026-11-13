## Настройки игрока: стиль графики, громкость, вибрация. Хранятся в user://settings.cfg.
## STYLES — параметры света и цвета для каждого стиля; игра читает их в _apply_style().
extends RefCounted

const PATH := "user://settings.cfg"
const STYLE_ORDER := ["pixel", "toon", "real", "horror"]
## pixel — размер пикселя для шейдера (0 = выключен); realistic — каменные текстуры
## и скелеты с человеческими пропорциями вместо мультяшных.
const STYLES := {
	"pixel": {
		"name": "Пиксельный", "hint": "Крупные пиксели, ретро-палитра",
		"pixel": 4.0, "realistic": false,
		"ambient": Color(0.3, 0.33, 0.45), "ambient_energy": 0.55,
		"fog": Color(0.08, 0.1, 0.18), "fog_density": 0.06,
		"torch": Color(1.0, 0.62, 0.3), "torch_energy": 1.7, "flicker": 1.0,
		"lantern": Color(1.0, 0.82, 0.55), "lantern_energy": 0.8, "moon": 0.4,
		"saturation": 1.1, "contrast": 1.1, "brightness": 1.05,
		"vignette": 0.5, "tint": Color(0, 0, 0, 0),
	},
	"toon": {
		"name": "Мультяшный", "hint": "Ярко и тепло",
		"pixel": 0.0, "realistic": false,
		"ambient": Color(0.25, 0.3, 0.42), "ambient_energy": 0.45,
		"fog": Color(0.08, 0.1, 0.16), "fog_density": 0.075,
		"torch": Color(1.0, 0.62, 0.3), "torch_energy": 1.6, "flicker": 1.0,
		"lantern": Color(1.0, 0.82, 0.55), "lantern_energy": 0.7, "moon": 0.35,
		"saturation": 1.0, "contrast": 1.0, "brightness": 1.0,
		"vignette": 0.62, "tint": Color(0, 0, 0, 0),
	},
	"real": {
		"name": "Реалистичный", "hint": "Камень, кости, глубокие тени",
		"pixel": 0.0, "realistic": true,
		"ambient": Color(0.2, 0.19, 0.26), "ambient_energy": 0.32,
		"fog": Color(0.05, 0.045, 0.07), "fog_density": 0.1,
		"torch": Color(1.0, 0.52, 0.22), "torch_energy": 1.9, "flicker": 1.6,
		"lantern": Color(1.0, 0.78, 0.5), "lantern_energy": 0.75, "moon": 0.22,
		"saturation": 0.62, "contrast": 1.15, "brightness": 0.98,
		"vignette": 0.85, "tint": Color(0.1, 0.03, 0.06, 0.08),
	},
	"horror": {
		"name": "Жуткий", "hint": "Темно, холодный туман",
		"pixel": 0.0, "realistic": true,
		"ambient": Color(0.08, 0.13, 0.14), "ambient_energy": 0.22,
		"fog": Color(0.015, 0.03, 0.035), "fog_density": 0.19,
		"torch": Color(0.75, 0.8, 0.55), "torch_energy": 0.9, "flicker": 3.2,
		"lantern": Color(0.8, 0.9, 0.85), "lantern_energy": 0.55, "moon": 0.08,
		"saturation": 0.35, "contrast": 1.25, "brightness": 0.9,
		"vignette": 1.0, "tint": Color(0.0, 0.08, 0.06, 0.14),
	},
}

static var style := "toon"
static var volume := 1.0
static var music := 0.7
static var vibration := true
## Цветовая обработка картинки и сглаживание. Выключено по умолчанию: на части телефонов
## (GL Compatibility) эти проходы отрисовки приводят к зависанию изображения.
static var effects := false
static var _loaded := false


static func load_once() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	var s := str(cf.get_value("game", "style", style))
	style = s if STYLES.has(s) else "toon"
	volume = clampf(float(cf.get_value("game", "volume", volume)), 0.0, 1.0)
	music = clampf(float(cf.get_value("game", "music", music)), 0.0, 1.0)
	vibration = bool(cf.get_value("game", "vibration", vibration))
	effects = bool(cf.get_value("game", "effects", effects))


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "style", style)
	cf.set_value("game", "volume", volume)
	cf.set_value("game", "music", music)
	cf.set_value("game", "vibration", vibration)
	cf.set_value("game", "effects", effects)
	cf.save(PATH)


static func current() -> Dictionary:
	return STYLES[style]


static func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.0)
	var mi := AudioServer.get_bus_index("Music")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(music * 0.8, 0.0001)))
		AudioServer.set_bus_mute(mi, music <= 0.0)
