## Журнал запуска для поиска сбоев на телефоне. Пишет в user://log_current.txt строку
## на каждое событие (смена состояния, комната, враг, добыча, пауза приложения, смена
## размера окна, нехватка памяти) и «пульс» раз в секунду. При следующем запуске прошлый
## журнал переносится в user://log_prev.txt и открывается из меню разработчика.
## Файл сбрасывается на диск после каждой строки: при зависании последние строки не теряются.
extends RefCounted

const CUR := "user://log_current.txt"
const PREV := "user://log_prev.txt"

static var _file: FileAccess
static var _started := false
static var _t0 := 0


static func start() -> void:
	if _started:
		return
	_started = true
	_t0 = Time.get_ticks_msec()
	if FileAccess.file_exists(CUR):
		DirAccess.rename_absolute(CUR, PREV)
	_file = FileAccess.open(CUR, FileAccess.WRITE)
	note("старт %s · %s · %s · экран %s · GPU %s" % [
		Time.get_datetime_string_from_system(), OS.get_model_name(), OS.get_name() + " " + OS.get_version(),
		str(DisplayServer.screen_get_size()), RenderingServer.get_video_adapter_name()])


static func note(text: String) -> void:
	if _file == null:
		return
	_file.store_line("%7.1f  %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, text])
	_file.flush()


## Последние строки журнала прошлого запуска.
static func previous(lines: int = 60) -> String:
	if not FileAccess.file_exists(PREV):
		return "Журнала прошлого запуска нет."
	var all := FileAccess.get_file_as_string(PREV).split("\n", false)
	var from := maxi(0, all.size() - lines)
	return "\n".join(all.slice(from))
