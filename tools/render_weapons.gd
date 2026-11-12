## Рендер картинок оружия для окна добычи: каждая модель из data/items.json
## снимается под углом на прозрачном фоне в assets/weapons/<id>.png.
## Запускать на ПК с видеокартой (или под Xvfb):
##   godot --path . -s tools/render_weapons.gd
## В самой игре отдельные 3D-окна не используются: на части телефонов они ломают картинку.
extends SceneTree


func _init() -> void:
	_render()


func _render() -> void:
	var f := FileAccess.open("res://data/items.json", FileAccess.READ)
	var items: Dictionary = JSON.parse_string(f.get_as_text())
	DirAccess.make_dir_recursive_absolute("res://assets/weapons")
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.8
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.4
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.3
	cam.position = Vector3(0, 0, 4)
	vp.add_child(cam)
	for id: String in items.weapons:
		var base: Dictionary = items.weapons[id]
		var holder := Node3D.new()
		holder.rotation = Vector3(0.0, 0.55, -0.6)
		vp.add_child(holder)
		var scene: PackedScene = load("res://assets/kaykit/hero/%s.gltf" % str(base.model))
		var model: Node3D = scene.instantiate()
		holder.add_child(model)
		# Вписать модель в кадр по её габаритам
		var box := _bounds(model)
		var k := 2.0 / maxf(box.size.y, box.size.x * 1.6)
		model.scale = Vector3.ONE * k
		model.position = -box.get_center() * k
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		img.save_png("res://assets/weapons/%s.png" % id)
		print("ok ", id)
		holder.queue_free()
		await process_frame
	quit()


func _bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.transform * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	if node is MeshInstance3D:
		var m2 := node as MeshInstance3D
		out = m2.get_aabb() if first else out.merge(m2.get_aabb())
	return out
