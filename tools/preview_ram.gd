extends SceneTree
## Isolated preview of the rigged RamArcher in its AIM (draw) pose, lit plainly
## and shot from the side, so we can confirm the bow-draw pose without the
## in-game sun washing it out. Saves /tmp/ram_preview.png.
func _init():
	var root := Node3D.new()
	get_root().add_child(root)

	# Plain neutral environment so the model reads in full colour.
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.ambient_light_energy = 1.0
	we.environment = env
	root.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.5
	root.add_child(key)

	# Static Lord Ram.glb — the reference model. Show its baked pose.
	var ps = load("res://assets/Lord Ram.glb")
	var ram = ps.instantiate()
	ram.scale = Vector3.ONE * 1.7
	root.add_child(ram)
	# Find the model's vertical centre to aim the camera.
	var ab := _world_aabb(ram)
	var ctr := ab.position + ab.size * 0.5

	# Camera 3/4 from the front-right so the bow draw is clearly visible.
	var aim_at := ctr + Vector3(0, ab.size.y * 0.42, 0)   # bias up to the torso/head
	var cam := Camera3D.new()
	var dist: float = ab.size.length() * 2.4 + 4.0
	cam.position = aim_at + Vector3(dist * 0.5, ab.size.y * 0.35, dist)
	cam.look_at_from_position(cam.position, aim_at, Vector3.UP)
	root.add_child(cam)
	cam.make_current()

	# Let the AnimationPlayer settle on the aim pose, then capture.
	await process_frame
	for i in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png("/tmp/ram_preview.png")
	print("PREVIEW SAVED")
	quit()

func _world_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in _all(n):
		if c is MeshInstance3D and c.mesh:
			var wa: AABB = c.global_transform * c.mesh.get_aabb()
			if first:
				out = wa; first = false
			else:
				out = out.merge(wa)
	return out

func _all(n: Node) -> Array:
	var o := [n]
	for c in n.get_children():
		o += _all(c)
	return o
