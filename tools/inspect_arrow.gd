extends SceneTree
func _init():
	var ps = load("res://assets/weapons/arrow.glb")
	if ps == null:
		print("LOAD FAILED")
		quit(); return
	var inst = ps.instantiate()
	print("=== ARROW MODEL TREE ===")
	_walk(inst, 0)
	quit()
func _walk(n, d):
	var pad = ""
	for i in range(d): pad += "  "
	var extra = ""
	if n is MeshInstance3D and n.mesh:
		extra = " AABB pos=" + str(n.mesh.get_aabb().position) + " size=" + str(n.mesh.get_aabb().size)
	print(pad, n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_walk(c, d + 1)
