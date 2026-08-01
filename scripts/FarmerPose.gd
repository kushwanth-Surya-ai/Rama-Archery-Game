class_name FarmerPose
extends RefCounted
## The Farmer.obj is a single STATIC mesh baked in a wide arms-spread (scarecrow)
## stance, and every villager shares it through a MultiMesh — there's no skeleton
## to animate. So we re-pose the geometry ONCE at load: fold the outstretched arms
## down and forward about each shoulder so the crowd reads as villagers holding an
## arrow ready to throw, not spreading their hands.
##
## Geometry (model-local, pre-scale, Y up, feet at the bottom, faces -Z):
##   head ~y[-2..4], shoulders ~y-5, arms splay out to hands at x≈±16 / y≈-14,
##   legs/torso below y-16 stay narrow (|x|<~4). Arm vertices are therefore just
##   "the wide ones": |x| > SHOULDER_HALF. We rotate those about the shoulder pivot
##   on their side — down (about Z) and forward toward -Z (about X).

const SHOULDER_Y := -5.0        # height the arms attach at
const SHOULDER_HALF := 5.5      # |x| beyond this is an arm, not the torso
const FOLD := 55.0              # degrees to swing the arm DOWN about the shoulder
const SWING := 45.0             # degrees to swing the hand FORWARD (toward -Z) into a throwing hold


## Return a new ArrayMesh that is `src` with the arms folded into a holding stance.
## Falls back to `src` unchanged if it exposes no vertex array.
static func repose(src: Mesh) -> Mesh:
	if src == null or src.get_surface_count() == 0:
		return src
	var out := ArrayMesh.new()
	for surf in src.get_surface_count():
		var arrays := src.surface_get_arrays(surf)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			continue
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var fold := deg_to_rad(FOLD)
		var swing := deg_to_rad(SWING)
		for i in verts.size():
			var v := verts[i]
			if absf(v.x) <= SHOULDER_HALF:
				continue
			var side := signf(v.x)
			# Fold DOWN about Z: right arm (+x) turns clockwise (-angle), left mirrors.
			# Then swing FORWARD about X so the hands come to the front of the body.
			var rot := Basis(Vector3(1, 0, 0), -swing) * Basis(Vector3(0, 0, 1), -side * fold)
			var pivot := Vector3(side * SHOULDER_HALF, SHOULDER_Y, 0.0)
			verts[i] = pivot + rot * (v - pivot)
			if i < norms.size():
				norms[i] = (rot * norms[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = verts
		if not norms.is_empty():
			arrays[Mesh.ARRAY_NORMAL] = norms
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out
