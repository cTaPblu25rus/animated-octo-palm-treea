## Снимки заставки для документации: godot --path . -- --title --titleshots=папка
extends Node

var dir := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for moment: float in [2.4, 4.6, 8.0]:
		get_tree().create_timer(moment).timeout.connect(_shot.bind("title_%d" % roundi(moment * 10.0)))
	# Затем «В бой»: в первый раз показывается вступление рассказчика
	get_tree().create_timer(8.3).timeout.connect(func() -> void: get_parent().title.start())
	get_tree().create_timer(10.6).timeout.connect(_shot.bind("intro"))
	get_tree().create_timer(11.2).timeout.connect(func() -> void: get_tree().quit(0))


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, shot_name])
