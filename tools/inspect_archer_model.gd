extends SceneTree
func _init():
	var ps = load("res://assets/Archer_model_max2015_and_textures/Archer.FBX")
	if ps == null:
		print("LOAD FAILED"); quit(); return
	var inst = ps.instantiate()
	print("=== ARCHER FBX TREE ===")
	var total := AABB()
	var first := true
	for n in _all(inst):
		var line = n.get_class() + "  '" + String(n.name) + "'"
		if n is MeshInstance3D and n.mesh:
			var ab = n.mesh.get_aabb()
			line += "  AABB pos=" + str(ab.position).pad_decimals(2) + " size=" + str(ab.size).pad_decimals(2)
			line += "  surfaces=" + str(n.mesh.get_surface_count())
			var gx = n.global_transform
			var world = gx * ab
			if first: total = world; first = false
			else: total = total.merge(world)
		print(line)
	print("=== COMBINED WORLD AABB ===")
	print("pos=", total.position, " size=", total.size)
	quit()
func _all(n):
	var out = [n]
	for c in n.get_children():
		out += _all(c)
	return out
