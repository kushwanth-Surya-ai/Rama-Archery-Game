extends SceneTree
func _init():
	var ps = load("res://assets/forest/source/Forest.glb")
	if ps == null:
		print("LOAD FAILED"); quit(); return
	var inst = ps.instantiate()
	get_root().add_child(inst)
	var total := AABB()
	var first := true
	var meshes := 0
	for n in _all(inst):
		if n is MeshInstance3D and n.mesh:
			meshes += 1
			var wa: AABB = n.global_transform * n.mesh.get_aabb()
			if first: total = wa; first = false
			else: total = total.merge(wa)
	print("MESH NODES=", meshes)
	print("AABB pos=", total.position, " size=", total.size)
	quit()
func _all(n):
	var o = [n]
	for c in n.get_children():
		o += _all(c)
	return o
