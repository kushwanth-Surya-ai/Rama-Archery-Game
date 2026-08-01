extends Node3D
## Dev-only: loads a model on a neutral backdrop and renders front + 3/4 + side
## views to /tmp, then quits. Used to eyeball poses without the game camera.

const MODEL := "res://assets/lord-hanuman/source/model.glb"

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.22, 0.28)
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 35, 0)
	sun.light_energy = 1.5
	add_child(sun)

	var scene := load(MODEL) as PackedScene
	var m := scene.instantiate() as Node3D
	add_child(m)

	await get_tree().process_frame
	var aabb := _aabb(m)
	var center := aabb.position + aabb.size * 0.5
	var h: float = maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z))

	var cam := Camera3D.new()
	add_child(cam)
	await _shot(cam, center, h, Vector3(0, 0, 1), "/tmp/ram_render.png")    # front
	await _shot(cam, center, h, Vector3(1, 0, 1), "/tmp/ram_34.png")        # 3/4
	await _shot(cam, center, h, Vector3(1, 0, 0), "/tmp/ram_side.png")      # side
	get_tree().quit()


func _shot(cam: Camera3D, center: Vector3, h: float, dir: Vector3, path: String) -> void:
	cam.position = center + dir.normalized() * (h * 1.7)
	cam.look_at(center, Vector3.UP)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for c in _meshes(n):
		var b: AABB = c.global_transform * c.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
