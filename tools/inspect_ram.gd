extends SceneTree
func _init():
	var ps = load("res://assets/Lord Ram.glb")
	if ps == null:
		print("LOAD FAILED"); quit(); return
	var inst = ps.instantiate()
	print("=== LORD RAM GLB TREE ===")
	var total := AABB()
	var first := true
	for n in _all(inst):
		var line = n.get_class() + "  '" + String(n.name) + "'"
		if n is MeshInstance3D and n.mesh:
			var ab = n.mesh.get_aabb()
			line += "  size=" + str(ab.size).pad_decimals(2)
			line += "  surfaces=" + str(n.mesh.get_surface_count())
			var gx = n.global_transform
			var world = gx * ab
			if first: total = world; first = false
			else: total = total.merge(world)
		if n is Skeleton3D:
			line += "  bones=" + str(n.get_bone_count())
		if n is AnimationPlayer:
			line += "  anims=" + str(n.get_animation_list())
		print(line)
	print("=== SKELETON BONES ===")
	for n in _all(inst):
		if n is Skeleton3D:
			for b in n.get_bone_count():
				print("  [", b, "] ", n.get_bone_name(b), "  parent=", n.get_bone_parent(b))
	print("=== COMBINED WORLD AABB ===")
	print("pos=", total.position, " size=", total.size)
	quit()
func _all(n):
	var out = [n]
	for c in n.get_children():
		out += _all(c)
	return out
