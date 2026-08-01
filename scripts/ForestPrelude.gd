extends Node3D
## OPENING BEAT — before the drone intro. The vanara army pours through the forest:
## separate troops RUN across the ground in loose groups while others CLIMB the
## trees, and the camera cranes UP from down among them to a high drone view that
## lands exactly on the intro cinematic's first frame, so the two flow as one shot.
##
## Reuses the real spider-monkey model (res://assets/spider_monkey_low.glb), drawn
## as two MultiMeshes (runners + climbers) so hundreds of monkeys stay one-draw-call
## cheap. Emits `finished` when the crane-up completes; Main then starts the intro.

signal finished

const MONKEY_GLB := "res://assets/spider_monkey_low.glb"
const TARGET_H := 1.8                # height of one standing monkey, metres
const STAND_UP := PI                 # flip the Z-up model upright (same as MonkeyCone)
const GROUND_HALF := TARGET_H * 0.5  # centre->feet, so feet rest on y=0

const DUR := 8.0                     # long fly-in from far back before we hand to the intro

# Camera travel: OPENS very far back and high (~hundreds of units behind, a long
# fly-in over the forest from the low aerial angle the billboard trees read best at),
# flying forward toward Hanuman and descending onto his back. It stays BEHIND Hanuman
# the whole time (he faces -X/-Z, so his back is on the +X/+Z side — the camera lives
# there). The end frame == the intro's first keyframe, so the two flow as one shot.
const CAM_START_POS := Vector3(28.0, 60.0, 520.0)   # FAR back & high — the long forest fly-in begins
const CAM_START_LOOK := Vector3(28.0, 38.0, 360.0)
const CAM_END_POS := Vector3(46.0, 52.0, 246.0)    # descending onto Hanuman's back
const CAM_END_LOOK := Vector3(30.0, 34.0, 188.0)

# Lord Hanuman flies through the MIDDLE of the far forest from the very start,
# drifting slowly; the crane settles on his back. He is then HANDED to the intro
# (reparented, see Main) so there is no pop when the cinematic takes over.
const HANUMAN_GLB := "res://assets/lord-hanuman/source/model.glb"
const HANUMAN_SCALE := 7.0
const HANUMAN_LEAN := 18.0                  # forward flight lean (deg), matches the intro
const HAN_HEADING := Vector3(-15.0, 0.0, -54.0)   # same yaw heading the intro flies him along
const HAN_START := Vector3(38.0, 36.0, 240.0)     # further back so he visibly flies forward during the fly-in
const HAN_END := Vector3(28.0, 33.0, 178.0)       # == IntroCinematic _han_keys[0]

# Run / climb motion
const RUN_BOB_FREQ := 9.0
const RUN_BOB_AMP := 0.28
const RUN_LEAN := 0.35               # forward lean while sprinting (rad)
const CLIMB_BOB_FREQ := 6.0
const CLIMB_BOB_AMP := 0.12

# Troop definitions: [centre_x, centre_z, heading(rad), count, speed]. Heading ~PI
# means running toward -Z (out of the forest, toward the distant warfront/clearing).
const TROOPS := [
	[10.0, 150.0, PI - 0.25, 14, 6.5],
	[48.0, 168.0, PI + 0.10, 12, 7.2],
	[82.0, 182.0, PI + 0.30, 13, 6.0],
	[-22.0, 192.0, PI - 0.15, 11, 6.8],
	[60.0, 205.0, PI + 0.05, 12, 7.6],
	[24.0, 128.0, PI - 0.05, 10, 8.2],
]
const CLIMBERS := 20                 # monkeys scaling tree trunks

var _cam: Camera3D
var hanuman: Node3D = null            # exposed so Main can hand him to the intro
var _t := 0.0
var _done := false
var _rng := RandomNumberGenerator.new()
var _mesh_material: Material = null

# Shared model maths
var _s_base := 1.0
var _stand := Basis()
var _center := Vector3.ZERO

# Runners (parallel arrays per instance)
var _run_mm: MultiMesh = null
var _run_home := PackedVector3Array()
var _run_vel := PackedVector3Array()
var _run_yaw := PackedFloat32Array()
var _run_phase := PackedFloat32Array()
var _run_scale := PackedFloat32Array()

# Climbers
var _climb_mm: MultiMesh = null
var _climb_base := PackedVector3Array()   # trunk foot (x, startY, z)
var _climb_yaw := PackedFloat32Array()
var _climb_speed := PackedFloat32Array()
var _climb_top := PackedFloat32Array()     # how high up the trunk they go
var _climb_phase := PackedFloat32Array()
var _climb_scale := PackedFloat32Array()


func _ready() -> void:
	_rng.seed = 90217
	var mesh := _load_monkey_mesh()

	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.attributes = CameraAttributesPractical.new()
	add_child(_cam)
	_cam.global_position = CAM_START_POS
	_cam.look_at(CAM_START_LOOK, Vector3.UP)
	_cam.current = true

	# Hanuman is present and already drifting from frame one (no late spawn/pop).
	_spawn_hanuman()

	if mesh != null:
		# Stand-up + uniform scale, matching MonkeyCone so the troops read identically.
		var aabb := mesh.get_aabb()
		_center = aabb.get_center()
		_stand = Basis(Vector3.RIGHT, STAND_UP)
		var stood := Transform3D(_stand, Vector3.ZERO) * aabb
		_s_base = TARGET_H / max(stood.size.y, 0.001)
		_build_runners(mesh)
		_build_climbers(mesh)
	else:
		push_warning("ForestPrelude: monkey model not imported; running camera/Hanuman beat only.")

	set_process(true)


func _spawn_hanuman() -> void:
	var scene := load(HANUMAN_GLB) as PackedScene
	if scene == null:
		return
	hanuman = scene.instantiate()
	hanuman.scale = Vector3.ONE * HANUMAN_SCALE
	add_child(hanuman)
	# Visible from the start (no fade), same as the intro expects.
	for mi in _all_mesh_instances(hanuman):
		(mi as GeometryInstance3D).transparency = 0.0
	_place_hanuman(HAN_START)


## Position + orient Hanuman exactly the way the intro does (fixed heading + lean),
## so his pose is continuous when the cinematic takes him over. `t` drives a natural
## soaring wobble layered on top (see _flight_motion); t=0 gives the clean rest pose.
func _place_hanuman(p: Vector3, t: float = 0.0) -> void:
	if hanuman == null:
		return
	_flight_motion(hanuman, p, HAN_HEADING, deg_to_rad(HANUMAN_LEAN), t)


## Shared natural-flight motion for Hanuman (used identically by the prelude and the intro
## cinematic so his soaring reads the same across the handoff). On top of the fixed heading
## and forward lean — which keep his facing rock-stable and glitch-free — it layers:
##   • a wandering vertical bob (two out-of-phase sines) so he rides air currents, not a rail;
##   • a slow lateral weave perpendicular to travel;
##   • a bank (roll) INTO that weave, a pitch that dips/rises with the climb, and a gentle
##     yaw sway — all small, layered, and out of phase so he reads alive, never mechanical.
func _flight_motion(node: Node3D, p: Vector3, heading: Vector3, lean: float, t: float) -> void:
	var h := heading
	h.y = 0.0
	if h.length() < 0.01:
		h = Vector3(0, 0, -1)
	var right := h.cross(Vector3.UP).normalized()          # sideways axis for the weave
	var sway := sin(t * 0.37)                               # slow side-to-side drift
	var bob := sin(t * 1.1) * 0.42 + sin(t * 0.53 + 1.3) * 0.26   # wandering vertical bob
	var pos := p + Vector3(0, bob, 0) + right * (sway * 0.9 + sin(t * 0.8) * 0.3)
	node.global_position = pos
	# Offset the look target by the SAME sway so lateral drift never bends his heading.
	node.look_at(pos - heading, Vector3.UP)
	node.rotate_object_local(Vector3.RIGHT, lean)
	node.rotate_object_local(Vector3.FORWARD, cos(t * 0.37) * 0.13 + sin(t * 0.9 + 0.7) * 0.04)  # bank into the weave
	node.rotate_object_local(Vector3.RIGHT, cos(t * 1.1) * 0.045)                                # nose dip/rise with the bob
	node.rotate_object_local(Vector3.UP, cos(t * 0.37) * 0.05)                                   # gentle heading weave


func _all_mesh_instances(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_mesh_instances(c))
	return out


func _load_monkey_mesh() -> Mesh:
	if not ResourceLoader.exists(MONKEY_GLB):
		return null
	var res := load(MONKEY_GLB)
	if res is Mesh:
		return res
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


func _build_runners(mesh: Mesh) -> void:
	for troop in TROOPS:
		var cx: float = troop[0]
		var cz: float = troop[1]
		var heading: float = troop[2]
		var count: int = troop[3]
		var speed: float = troop[4]
		var dir := Vector3(sin(heading), 0.0, cos(heading))
		for _i in range(count):
			# Scatter the troop in a loose clump, offset along/across the run line.
			var along := _rng.randf_range(-5.0, 5.0)
			var across := _rng.randf_range(-4.0, 4.0)
			var side := Vector3(dir.z, 0.0, -dir.x)
			var p := Vector3(cx, 0.0, cz) + dir * along + side * across
			var sp := speed * _rng.randf_range(0.85, 1.15)
			var hd := heading + _rng.randf_range(-0.12, 0.12)
			var d := Vector3(sin(hd), 0.0, cos(hd))
			_run_home.append(p)
			_run_vel.append(d * sp)
			_run_yaw.append(atan2(d.x, d.z))
			_run_phase.append(_rng.randf() * TAU)
			_run_scale.append(_rng.randf_range(0.85, 1.2))

	_run_mm = _new_multimesh(mesh, _run_home.size())
	var node := MultiMeshInstance3D.new()
	node.name = "Runners"
	node.multimesh = _run_mm
	if _mesh_material != null:
		node.material_override = _mesh_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _build_climbers(mesh: Mesh) -> void:
	for _i in range(CLIMBERS):
		# Place on a "trunk" within the camera's forest view; vary how far up.
		var x := _rng.randf_range(-45.0, 110.0)
		var z := _rng.randf_range(126.0, 202.0)   # all ahead of the drone's start (z208)
		var start_y := _rng.randf_range(0.0, 4.0)
		_climb_base.append(Vector3(x, start_y, z))
		_climb_yaw.append(_rng.randf() * TAU)
		_climb_speed.append(_rng.randf_range(1.6, 3.2))
		_climb_top.append(_rng.randf_range(6.0, 13.0))
		_climb_phase.append(_rng.randf() * TAU)
		_climb_scale.append(_rng.randf_range(0.85, 1.15))

	_climb_mm = _new_multimesh(mesh, _climb_base.size())
	var node := MultiMeshInstance3D.new()
	node.name = "Climbers"
	node.multimesh = _climb_mm
	if _mesh_material != null:
		node.material_override = _mesh_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _new_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	return mm


## Upright monkey, centred on (x,z), feet near y=ground+bob, with optional lean.
func _xform(x: float, z: float, ground: float, yaw: float, scale_mul: float, lean: float) -> Transform3D:
	var b := Basis(Vector3.UP, yaw) * _stand
	if lean != 0.0:
		b = b * Basis(Vector3.RIGHT, lean)
	var s := _s_base * scale_mul
	b = b.scaled(Vector3(s, s, s))
	var pt := Vector3(x, ground + GROUND_HALF * scale_mul, z)
	return Transform3D(b, pt - b * _center)


func _process(delta: float) -> void:
	_t += delta
	var f: float = clampf(_t / DUR, 0.0, 1.0)
	# Smooth crane-up: ease the whole move, accelerating off the floor then settling.
	var e := f * f * (3.0 - 2.0 * f)
	_cam.global_position = CAM_START_POS.lerp(CAM_END_POS, e)
	_cam.look_at(CAM_START_LOOK.lerp(CAM_END_LOOK, e), Vector3.UP)

	# Hanuman flies slowly + steadily forward through the mid-forest (LINEAR, not eased,
	# so he's visibly moving the whole time, never frozen), ending exactly where the
	# intro picks him up. _place_hanuman layers the natural soaring wobble on top.
	if hanuman != null:
		var hp := HAN_START.lerp(HAN_END, f)
		_place_hanuman(hp, _t)

	# Runners sprint along their heading with a galloping bob + forward lean.
	if _run_mm != null:
		for i in range(_run_home.size()):
			var home := _run_home[i]
			var vel := _run_vel[i]
			var pos := home + vel * _t
			var bob: float = absf(sin(_run_phase[i] + _t * RUN_BOB_FREQ)) * RUN_BOB_AMP
			_run_mm.set_instance_transform(i, _xform(pos.x, pos.z, bob, _run_yaw[i], _run_scale[i], RUN_LEAN))

	# Climbers haul themselves up the trunks, easing to a stop at the canopy.
	if _climb_mm != null:
		for i in range(_climb_base.size()):
			var base := _climb_base[i]
			var up: float = minf(_climb_top[i], _climb_speed[i] * _t)
			var bob: float = sin(_climb_phase[i] + _t * CLIMB_BOB_FREQ) * CLIMB_BOB_AMP
			# Slight inward hug + clamber sway; body stays vertical against the trunk.
			_climb_mm.set_instance_transform(i, _xform(base.x, base.z, base.y + up + bob, _climb_yaw[i], _climb_scale[i], 0.18))

	if _t >= DUR and not _done:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	finished.emit()
