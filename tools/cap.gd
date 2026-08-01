extends Node3D
## TEMP profile framing of the whole archer (head->legs) with fill light, markers
## RED=spawn(bow_tip) BLUE=muzzle, firing real slow-mo arrows. Shows exactly which
## body part arrows leave from.

func _rt(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func _mark(where: Vector3, col: Color, r: float) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2.0
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col; mat.emission_enabled = true; mat.emission = col
	mat.emission_energy_multiplier = 5.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	add_child(m); m.global_position = where

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = scene.instantiate()
	add_child(main)
	await _rt(1.4)

	var aim: Node3D = main.find_child("AimYaw", true, false)
	var bt: Node3D = aim.get("bow_tip")
	var mz: Node3D = aim.get("muzzle")
	var body: Node3D = main.find_child("BowTip", true, false)
	# archer torso centre to look at (so head+legs are in frame, no centring bias)
	var look: Vector3 = aim.global_position + Vector3(0, 2.6, 0)
	if bt: _mark(bt.global_position, Color(1, 0.05, 0.05), 0.22)
	if mz: _mark(mz.global_position, Color(0.1, 0.4, 1.0), 0.2)

	var fill := DirectionalLight3D.new(); fill.light_energy = 1.5
	add_child(fill); fill.global_position = look + Vector3(4, 5, 6); fill.look_at(look, Vector3.UP)

	# BEHIND-and-above the archer, looking toward the giant (-Z) — the player's view
	var cam := Camera3D.new(); add_child(cam)
	cam.global_position = look + Vector3(1.5, 2.2, 8.0)
	cam.look_at(look + Vector3(0, -0.4, -6.0), Vector3.UP); cam.fov = 50.0; cam.make_current()

	Engine.time_scale = 0.04
	if aim:
		aim.set("_charge_t", 1.2); aim.call("_fire")
		await _rt(0.18)
		aim.set("_charge_t", 1.2); aim.call("_fire")
		await _rt(0.10)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_cap.png")
	await _rt(0.1)
	get_tree().quit()
