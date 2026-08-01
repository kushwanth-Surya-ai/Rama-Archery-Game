extends Node3D
## The "monkey mountain": the tower is built from the REAL spider-monkey model
## (assets/Spider_Monkey_v1_L2…/12958_Spider_Monkey_v1_l2.obj — the only monkey
## asset we have) cloned a few hundred times over a convex cone surface and drawn
## in a single MultiMesh (one draw call). Reads as a teeming vanara pillar at
## golden hour, narrowing to the summit the archer stands on.
##
## It is a CHILD of the tower CharacterBody3D, so it slides rigidly with the
## base. In _process it only leans into motion + breathes — the camera/player
## mount is a separate sibling, so aiming stays stable.
##
## If the model has not been imported yet, it falls back to the old yellow blob
## cone so the game still runs; focus the Godot editor once to import the OBJ.

# Cone geometry — a BIG, fat, bulky monkey-mountain: wide convex base tapering
# to the summit. Keep H in sync with TopMount in Main.gd (apex = cone.y -1 + H).
const R := 10.0                     # base radius (huge + fat)
const H := 32.0                     # cone height (towering)
const K := 0.6                      # profile exponent (<1 = convex "fat mountain")
const N_RINGS := 46
const RING_SPACING := 1.15          # arc length between monkeys (smaller = more monkeys)
const PROTRUDE_MIN := -0.2
const PROTRUDE_MAX := 0.55          # wider spread -> teeming, bulging body pile
const Y_JITTER := 0.30

# Monkey model placement. Low-poly (~5.7k tris, decimated from the 47k OBJ) so
# hundreds of instances stay smooth. Still 3ds-Max Z-up; STAND_UP corrects it.
const MONKEY_OBJ := "res://assets/spider_monkey_low.glb"
const TARGET_H := 1.8               # height of one monkey, metres
const STAND_UP := PI                # ORIGINAL design value (verified against the 03:24
                                    # reference build). The "fan" glitch was never this —
                                    # it was the tower free-falling and dragging the rig.
const FACE_YAW := 0.0               # extra spin so the body faces radially outward
const SCALE_MIN := 0.80
const SCALE_MAX := 1.25
const TILT_JITTER := 0.40           # random lean/roll for an organic clump (rad)
const SEED := 53124

# Living wobble
const MAX_CONE_TILT := 0.08         # rad (~4.6deg) max lean into motion
const TILT_SMOOTH := 4.0
const BREATHE_FREQ := 1.2
const BREATHE_AMP := 0.012

# Always-on idle sway: the whole pile is alive even standing still. Two slow,
# out-of-phase leans (X+Z) read as a slow drunken-tower wobble pivoting at the base.
const IDLE_SWAY_AMP := 0.022        # rad (~1.3deg) gentle always-on lean
const IDLE_SWAY_FREQ := 0.55

# Per-monkey living shimmer: each monkey drifts a little, and the higher it sits
# the more it moves — base monkeys stay planted, the summit whips. This is what
# reads as "hundreds of real monkeys constantly re-gripping each other".
const INST_SWAY_AMP := 0.16         # metres of lateral drift at the summit
const INST_SWAY_FREQ := 1.7
const INST_SWAY_EXP := 1.6          # >1 so base stays planted, top whips

var controller: Node

var _t := 0.0
var _cur := Basis()
var _mesh_material: Material = null   # captured from the GLB so MultiMesh shows its texture

# Per-instance shimmer state (parallel arrays, indexed by MultiMesh instance)
var _mm: MultiMesh = null
var _base_xforms: Array[Transform3D] = []
var _hfrac := PackedFloat32Array()    # height fraction 0..1 of each monkey
var _phase := PackedFloat32Array()    # random phase offset per monkey


func _ready() -> void:
	_build_cone()


func _load_monkey_mesh() -> Mesh:
	if not ResourceLoader.exists(MONKEY_OBJ):
		return null
	var res := load(MONKEY_OBJ)
	# OBJ-as-Mesh: material rides on the mesh surface, used by MultiMesh directly.
	if res is Mesh:
		return res
	# GLB-as-scene: dig out the first MeshInstance3D's mesh AND its material
	# (MultiMesh won't inherit the instance's material, so we capture it here).
	if res is PackedScene:
		var inst: Node = (res as PackedScene).instantiate()
		var found: Mesh = null
		var stack: Array[Node] = [inst]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				found = (n as MeshInstance3D).mesh
				_mesh_material = (n as MeshInstance3D).get_active_material(0)
				break
			for c in n.get_children():
				stack.append(c)
		inst.queue_free()
		return found
	return null


func _build_cone() -> void:
	var mesh := _load_monkey_mesh()
	if mesh == null:
		push_warning("MonkeyCone: spider-monkey model not imported yet — focus the Godot editor to import it. Using blob fallback.")
		_build_blob_fallback()
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	# Per-instance base transform that stands the model up, centres it on its
	# own bounding box and scales it to TARGET_H. (Z is the model's up axis.)
	var aabb := mesh.get_aabb()
	var center := aabb.get_center()
	var stand := Basis(Vector3.RIGHT, STAND_UP)   # stand the model upright
	# measure the model's height AFTER standing it up, so scaling is correct
	# regardless of which model axis ends up vertical.
	var stood_aabb := Transform3D(stand, Vector3.ZERO) * aabb
	var model_up: float = max(stood_aabb.size.y, 0.001)
	var s_base := TARGET_H / model_up

	var xforms: Array[Transform3D] = []
	for j in range(N_RINGS):
		var t := float(j) / float(N_RINGS - 1)
		var y := t * H
		var r := R * pow(1.0 - t, K)
		var count_j: int = max(3, int(round(TAU * r / RING_SPACING)))
		for m in range(count_j):
			var ang := TAU * float(m) / float(count_j) + (j % 2) * (PI / float(count_j)) + rng.randf() * 0.12
			var rr := r + rng.randf_range(PROTRUDE_MIN, PROTRUDE_MAX)
			var px := cos(ang) * rr
			var pz := sin(ang) * rr
			var py := y + rng.randf_range(-Y_JITTER, Y_JITTER)

			# face radially outward, stand upright, add organic lean/roll
			var yaw := atan2(pz, px) + FACE_YAW
			var b := Basis(Vector3.UP, yaw) * stand
			b = b * Basis(Vector3.FORWARD, rng.randf_range(-TILT_JITTER, TILT_JITTER))
			b = b * Basis(Vector3.RIGHT, rng.randf_range(-TILT_JITTER, TILT_JITTER) * 0.5)
			var s := s_base * rng.randf_range(SCALE_MIN, SCALE_MAX)
			b = b.scaled(Vector3(s, s, s))

			var origin := Vector3(px, py, pz) - b * center  # model centre on the cone point
			xforms.append(Transform3D(b, origin))

	# Apex cap so the summit reads solid under the archer.
	for _i in range(5):
		var yaw := rng.randf() * TAU
		var b := Basis(Vector3.UP, yaw) * stand
		var s := s_base * rng.randf_range(0.7, 1.0)
		b = b.scaled(Vector3(s, s, s))
		var off := Vector3(rng.randf_range(-0.4, 0.4), H - rng.randf_range(0.0, 0.6), rng.randf_range(-0.4, 0.4))
		xforms.append(Transform3D(b, off - b * center))

	_add_multimesh(mesh, xforms)


func _add_multimesh(mesh: Mesh, xforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])

	# Cache for the per-monkey shimmer in _process. Height fraction drives how
	# much each monkey moves; a deterministic phase keeps neighbours out of sync
	# so the surface ripples instead of pulsing as one block.
	_mm = mm
	_base_xforms = xforms
	_hfrac = PackedFloat32Array()
	_phase = PackedFloat32Array()
	_hfrac.resize(xforms.size())
	_phase.resize(xforms.size())
	for i in range(xforms.size()):
		_hfrac[i] = clampf(xforms[i].origin.y / H, 0.0, 1.0)
		_phase[i] = float(i) * 0.733

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MonkeyInstances"
	mmi.multimesh = mm
	if _mesh_material != null:
		mmi.material_override = _mesh_material
	# Shadows OFF on the pile: the per-instance shadow pass over hundreds of
	# bodies was the main hitch. At backlit golden hour they read as a silhouette
	# anyway, so nothing is lost visually.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# ---- yellow-blob fallback (only if the model isn't imported) ---------------
func _build_blob_fallback() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var sph := SphereMesh.new()
	sph.radius = 0.62
	sph.height = 1.24
	sph.radial_segments = 12
	sph.rings = 6
	var xforms: Array[Transform3D] = []
	var cols := PackedColorArray()
	for j in range(N_RINGS):
		var t := float(j) / float(N_RINGS - 1)
		var y := t * H
		var r := R * pow(1.0 - t, K)
		var count_j: int = max(3, int(round(TAU * r / 0.72)))
		for m in range(count_j):
			var ang := TAU * float(m) / float(count_j) + rng.randf() * 0.1
			var rr := r + rng.randf_range(-0.1, 0.55)
			xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.85, 1.3)),
				Vector3(cos(ang) * rr, y + rng.randf_range(-0.18, 0.18), sin(ang) * rr)))
			cols.append(Color.from_hsv(lerpf(0.14, 0.045, t), 0.85, 0.97))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sph
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mmi.material_override = mat
	add_child(mmi)


func _process(delta: float) -> void:
	_t += delta

	# Lean into motion (needs the controller); skip cleanly if not wired up yet.
	var tgt := Basis()
	if controller != null:
		var v: Vector3 = controller.velocity
		v.y = 0.0
		var sp := v.length()
		if sp > 0.5:
			var amt := clampf(sp / 9.0, 0.0, 1.0) * MAX_CONE_TILT
			var axis := Vector3.UP.cross(v.normalized())
			if axis.length() > 0.001:
				tgt = Basis(axis.normalized(), amt)

	_cur = _cur.slerp(tgt, clampf(TILT_SMOOTH * delta, 0.0, 1.0))

	# Always-on idle sway, pivoting about the base (the node origin sits at the
	# cone base), so the summit swings most — a slow living lean in two axes.
	var idle := Basis(Vector3.RIGHT, sin(_t * IDLE_SWAY_FREQ) * IDLE_SWAY_AMP) \
		* Basis(Vector3.FORWARD, cos(_t * IDLE_SWAY_FREQ * 0.8) * IDLE_SWAY_AMP)
	var bs := 1.0 + sin(_t * BREATHE_FREQ) * BREATHE_AMP
	transform.basis = (_cur * idle).scaled(Vector3(bs, bs, bs))

	# Per-monkey shimmer: each monkey drifts laterally (and a touch vertically),
	# scaled by its height so the base stays planted and the top whips around.
	if _mm != null:
		for i in range(_base_xforms.size()):
			var bx: Transform3D = _base_xforms[i]
			var w := pow(_hfrac[i], INST_SWAY_EXP) * INST_SWAY_AMP
			var ph := _phase[i]
			var ox := sin(_t * INST_SWAY_FREQ + ph) * w
			var oz := cos(_t * INST_SWAY_FREQ * 0.9 + ph * 1.3) * w
			var oy := sin(_t * INST_SWAY_FREQ * 1.4 + ph) * w * 0.25
			_mm.set_instance_transform(i, Transform3D(bx.basis, bx.origin + Vector3(ox, oy, oz)))
