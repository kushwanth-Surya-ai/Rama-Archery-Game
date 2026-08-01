extends SceneTree
## Isolated preview of the new bhagwan_shri_ram.glb player model, lit plainly and
## shot 3/4 from the front-right, so we can confirm it loads, faces the right way,
## and stands on its feet without the in-game sun washing it out.
## Saves /tmp/bhagwan_preview.png.
func _init():
	var root := Node3D.new()
	get_root().add_child(root)

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

	# Same scale + facing the game uses (ARCHER_SCALE / ARCHER_ROT).
	var ps = load("res://assets/bhagwan_shri_ram.glb")
	var ram = ps.instantiate()
	ram.rotation_degrees = Vector3(0, 180, 0)
	root.add_child(ram)
	await process_frame
	await process_frame
	# auto-fit to ~3 units tall, the same normalisation the game now uses
	var pre := _world_aabb(ram)
	if pre.size.y > 0.0001:
		ram.scale *= 3.0 / pre.size.y
	await process_frame
	var ab := _world_aabb(ram)
	print("AABB pos=", ab.position, " size=", ab.size)
	var ctr := ab.position + ab.size * 0.5

	var aim_at := ctr
	var cam := Camera3D.new()
	var dist: float = ab.size.length() * 2.2 + 3.0
	cam.position = aim_at + Vector3(dist * 0.5, ab.size.y * 0.2, dist)
	cam.look_at_from_position(cam.position, aim_at, Vector3.UP)
	root.add_child(cam)
	cam.make_current()

	await process_frame
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png("/tmp/bhagwan_preview.png")
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
