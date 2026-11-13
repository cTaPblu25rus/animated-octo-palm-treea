## Снимки паузы и экрана итога: godot --path . -- --no-title --tier=3 --uishots=папка
extends Node

var dir := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var game: Node = get_parent()
	await get_tree().create_timer(3.0).timeout
	game.settings_menu.set_open(true)
	await _shot("pause")
	game.settings_menu.set_open(false)
	game.tier_unlocked = mini(game.tier + 1, 10)
	game.dev_victory()
	await get_tree().create_timer(3.0).timeout
	await _shot("result")
	get_tree().quit(0)


func _shot(shot_name: String) -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, shot_name])
