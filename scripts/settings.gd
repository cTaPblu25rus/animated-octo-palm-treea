## Настройки игрока: стиль графики, громкость, вибрация. Хранятся в user://settings.cfg.
## STYLES — параметры света и цвета для каждого стиля; игра читает их в _apply_style().
extends RefCounted

const PATH := "user://settings.cfg"
const STYLE_ORDER := ["toon", "dark", "horror"]
const STYLES := {
	"toon": {
		"name": "Мультяшный", "hint": "Ярко и тепло",
		"ambient": Color(0.25, 0.3, 0.42), "ambient_energy": 0.45,
		"fog": Color(0.08, 0.1, 0.16), "fog_density": 0.075,
		"torch": Color(1.0, 0.62, 0.3), "torch_energy": 1.6, "flicker": 1.0,
		"lantern": Color(1.0, 0.82, 0.55), "lantern_energy": 0.7, "moon": 0.35,
		"saturation": 1.0, "contrast": 1.0, "brightness": 1.0,
		"vignette": 0.62, "tint": Color(0, 0, 0, 0),
	},
	"dark": {
		"name": "Тёмное фэнтези", "hint": "Контраст, глубокие тени",
		"ambient": Color(0.17, 0.16, 0.27), "ambient_energy": 0.3,
		"fog": Color(0.05, 0.04, 0.08), "fog_density": 0.11,
		"torch": Color(1.0, 0.5, 0.2), "torch_energy": 1.5, "flicker": 1.6,
		"lantern": Color(1.0, 0.75, 0.45), "lantern_energy": 0.55, "moon": 0.22,
		"saturation": 0.8, "contrast": 1.15, "brightness": 0.95,
		"vignette": 0.85, "tint": Color(0.12, 0.02, 0.1, 0.1),
	},
	"horror": {
		"name": "Жуткий", "hint": "Темно, холодный туман",
		"ambient": Color(0.08, 0.13, 0.14), "ambient_energy": 0.2,
		"fog": Color(0.015, 0.03, 0.035), "fog_density": 0.19,
		"torch": Color(0.75, 0.8, 0.55), "torch_energy": 0.75, "flicker": 3.2,
		"lantern": Color(0.8, 0.9, 0.85), "lantern_energy": 0.5, "moon": 0.08,
		"saturation": 0.4, "contrast": 1.25, "brightness": 0.9,
		"vignette": 1.0, "tint": Color(0.0, 0.08, 0.06, 0.14),
	},
}

static var style := "toon"
static var volume := 1.0
static var vibration := true
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
	vibration = bool(cf.get_value("game", "vibration", vibration))


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "style", style)
	cf.set_value("game", "volume", volume)
	cf.set_value("game", "vibration", vibration)
	cf.save(PATH)


static func current() -> Dictionary:
	return STYLES[style]


static func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.0)
