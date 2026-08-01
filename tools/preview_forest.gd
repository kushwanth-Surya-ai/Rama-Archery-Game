extends SceneTree
func _init():
	var root := Node3D.new()
	get_root().add_child(root)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.7, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.ambient_light_energy = 1.0
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 40, 0)
	root.add_child(key)

	var f = load("res://assets/forest/source/Forest.glb").instantiate()
	root.add_child(f)
	var ab := AABB()
	var first := true
	for n in _all(f):
		if n is MeshInstance3D and n.mesh:
			var wa: AABB = n.global_transform * n.mesh.get_aabb()
			if first: ab = wa; first = false
			else: ab = ab.merge(wa)
	var ctr := ab.position + ab.size * 0.5
	var cam := Camera3D.new()
	var dist: float = ab.size.length() * 1.1 + 5.0
	cam.position = ctr + Vector3(dist * 0.4, ab.size.y * 0.2, dist)
	cam.look_at_from_position(cam.position, ctr, Vector3.UP)
	root.add_child(cam); cam.make_current()
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("/tmp/forest_preview.png")
	print("FOREST PREVIEW SAVED")
	quit()
func _all(n):
	var o = [n]
	for c in n.get_children():
		o += _all(c)
	return o
