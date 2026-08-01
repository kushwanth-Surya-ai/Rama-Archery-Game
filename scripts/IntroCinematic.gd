extends Node3D
## Opening drone-cam cinematic. Plays in the existing sunset world but starts
## FAR from the tower/giant ("another space"): a high drone glide over the
## forest where Lord Hanuman flies through the sky.
##
## Beats:
##   1. The camera approaches and PASSES Hanuman in flight.
##   2. Having crossed him, it TURNS BACK to frame his face for a held beat.
##   3. It then sweeps DOWN to the tower's foot and tilts UP the spire,
##      bottom-to-top, settling into the gameplay framing — at which point it
##      hands off to gameplay (emits `finished`).
##
## Hanuman is a static mesh, so "flight" is the whole model swept through the air,
## oriented along its travel with a slight forward lean. Press any key / click to
## skip.

signal finished

const DUR := 26.0
const HANUMAN := "res://assets/lord-hanuman/source/model.glb"
const HANUMAN_SCALE := 7.0
const HANUMAN_LEAN := 18.0      # forward lean (deg) so he reads as flying, not standing

# Camera path: [time, position, look_at].
#   FOREST CLOSE-UP (t0-5.5): a low drone skims OVER the canopy looking across the treetops —
#     this billboard forest only reads as a realistic forest from a low AERIAL angle (above the
#     canopy); going down INTO it shows flat tree-cards, so the camera stays above the treetops
#     (no clipping → no glitches), then rises toward the sky.
#   Then the ORIGINAL pre-transfer cinematic (recovered from the shipped .pck): a high drone
#     closes on Lord Hanuman, PASSES him, frames his FACE for a held beat (the "Hanuman zoom"),
#     then sweeps DOWN to the tower and tilts UP the spire into the gameplay framing.
var _cam_keys := [
	# Continues straight from the forest prelude. A LONG, far back-travel INTRODUCES
	# Hanuman: the drone starts high and far behind him (small in frame), then slowly
	# glides forward along his back across the forest before crossing to his face —
	# mirroring the long dive travel that follows the face beat.
	# (t0 here == the prelude camera's final frame, so the two flow as one shot.)
	[0.0,  Vector3(46, 52, 246), Vector3(30, 34, 188)],  # FAR & high behind Hanuman — the introduction
	[2.0,  Vector3(41, 47, 224), Vector3(28, 33, 176)],  # FAST glide forward along his back
	[4.0,  Vector3(35, 42, 200), Vector3(26, 32, 166)],  # fast, still far behind
	[5.5,  Vector3(28, 37, 178), Vector3(23, 31, 156)],  # fast, rushing up on his back
	[7.0,  Vector3(22, 33, 158), Vector3(20, 30, 148)],  # REACHED — right behind him; now ease off
	[9.5,  Vector3(17, 30, 140), Vector3(18, 30, 140)],  # drawing alongside (slowing)
	[12.0, Vector3(15, 30, 125), Vector3(16, 33, 131)],  # crossing to his front
	[13.5, Vector3(14, 30, 120), Vector3(15, 34, 127)],  # FACE zoom — his face fills frame, FAR from the tower
	[15.0, Vector3(13, 29, 117), Vector3(14, 33, 124)],  # hold on his face
	# DIVE — long sweep down from far Hanuman, across the battlefield, onto the tower.
	[17.5, Vector3(8, 30, 95),   Vector3(2, 16, 55)],    # stay HIGH over the canopy, gaze toward the warzone
	[20.0, Vector3(0, 24, 55),   Vector3(0, 12, 25)],    # cross the forest edge, descending into the clearing
	[22.0, Vector3(-5, 14, 34),  Vector3(0, 6, 8)],      # into the OPEN warzone toward the tower
	[23.5, Vector3(-6, 9, 25),   Vector3(0, 4, 1)],      # at the base
	[24.7, Vector3(-6, 16, 26),  Vector3(0, 15, 0)],     # tilting UP the taller spire
	[26.0, Vector3(-6, 30, 28),  Vector3(0, 27, 0)],     # top/archer framed ~= gameplay cam
]
# Hanuman flight path: [time, position] — he stays FAR from the tower (z~122-160), only edging
# slowly inward; the camera flies OUT to him (far over the forest), frames his face, then dives
# back to the tower. He never gets close to the tower.
var _han_keys := [
	[0.0,  Vector3(28, 33, 178)],   # handed over from the prelude; drifting slowly through the mid-forest
	[4.0,  Vector3(25, 32, 166)],
	[7.0,  Vector3(21, 31, 150)],
	[11.0, Vector3(17, 30, 134)],
	[15.0, Vector3(13, 28, 124)],   # at the face beat; still FAR from the tower
]

var existing_hanuman: Node3D = null   # handed over from the forest prelude (set BEFORE add_child)

var _cam: Camera3D
var _hanuman: Node3D
var _han_meshes: Array = []     # his MeshInstance3Ds, faded in so he "appears"
var _face_light: OmniLight3D    # warm fill that rides in front of Hanuman's face
var _t := 0.0
var _done := false

# dev-only frame grabs (DBG_INTRO=1)
var _shots := [2.0, 9.5, 14.0, 19.0, 23.5]
var _shot_i := 0


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.attributes = CameraAttributesPractical.new()
	_cam.current = true
	add_child(_cam)

	# Reuse the Hanuman the prelude was already flying (no pop), else spawn our own.
	if existing_hanuman != null and is_instance_valid(existing_hanuman):
		_hanuman = existing_hanuman
		add_child(_hanuman)
		_han_meshes = _collect_mesh_instances(_hanuman)
	else:
		var scene := load(HANUMAN) as PackedScene
		if scene:
			_hanuman = scene.instantiate()
			_hanuman.scale = Vector3.ONE * HANUMAN_SCALE
			add_child(_hanuman)
			_han_meshes = _collect_mesh_instances(_hanuman)
			for mi in _han_meshes:
				(mi as GeometryInstance3D).transparency = 0.0    # visible from the start (no fade)

	# The world is backlit by a low sun, so without a dedicated fill Hanuman is a
	# black silhouette and his face never reads. This omni rides just in front of his
	# face for the FACE beat. It starts OFF (energy 0): during the far/back shots it's a
	# very bright source (well above the bloom HDR threshold) and would FLASH white around
	# his silhouette when the camera is behind him — so it only ramps on for the face shot.
	_face_light = OmniLight3D.new()
	_face_light.light_color = Color(1.0, 0.93, 0.78)
	_face_light.light_energy = 0.0
	_face_light.omni_range = 24.0
	_face_light.omni_attenuation = 0.6
	add_child(_face_light)

	_update(0.0)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t >= DUR:
		_finish()
		return
	_update(_t)

	if OS.get_environment("DBG_INTRO") == "1" and _shot_i < _shots.size() and _t >= _shots[_shot_i]:
		_capture(_shot_i)
		_shot_i += 1


func _capture(i: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/intro_%d.png" % i)


func _input(event: InputEvent) -> void:
	# Press any key / click to skip the intro.
	if _done:
		return
	if (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	finished.emit()


func _update(t: float) -> void:
	_cam.global_position = _interp(_cam_keys, t)
	_cam.look_at(_interp_look(t), Vector3.UP)

	if _hanuman:
		var p := _interp(_han_keys, t)
		# FIXED flight heading from the whole path (first → last key), computed once and held
		# constant. A per-frame sampled delta SHRINKS/FLIPS near the path ends (both samples
		# clamp to the same key → dir≈0 → it snaps to a fallback), which made his facing pop —
		# that was the "facing/backshot glitch". A constant horizontal heading + a fixed forward
		# lean keeps his orientation rock-stable from any camera angle.
		var first: Vector3 = _han_keys[0][1]
		var last: Vector3 = _han_keys[-1][1]
		var heading := last - first
		heading.y = 0.0                        # yaw only; the lean below supplies the flight pitch
		if heading.length() < 0.01:
			heading = Vector3(0, 0, -1)        # fallback heading toward the warzone
		# Natural soaring wobble layered on the fixed heading + lean (mirrors
		# ForestPrelude._flight_motion so his flight reads identically across the handoff):
		# wandering vertical bob + a lateral weave he banks into, with pitch/yaw micro-sway.
		var right := heading.cross(Vector3.UP).normalized()
		var sway := sin(t * 0.37)
		var bob := sin(t * 1.1) * 0.42 + sin(t * 0.53 + 1.3) * 0.26
		var pos := p + Vector3(0, bob, 0) + right * (sway * 0.9 + sin(t * 0.8) * 0.3)
		_hanuman.global_position = pos
		# Model faces +Z, so aim -Z at (pos - heading) → +Z points along travel; offset the
		# target by the SAME sway so the lateral drift never bends his heading.
		_hanuman.look_at(pos - heading, Vector3.UP)
		_hanuman.rotate_object_local(Vector3.RIGHT, deg_to_rad(HANUMAN_LEAN))
		_hanuman.rotate_object_local(Vector3.FORWARD, cos(t * 0.37) * 0.13 + sin(t * 0.9 + 0.7) * 0.04)  # bank into the weave
		_hanuman.rotate_object_local(Vector3.RIGHT, cos(t * 1.1) * 0.045)                                # nose dip/rise with the bob
		_hanuman.rotate_object_local(Vector3.UP, cos(t * 0.37) * 0.05)                                   # gentle heading weave

		# Keep the fill just ahead of (and slightly above) his face — +Z is the model's
		# facing axis. It RAMPS ON only for the face shot (off during the far/back beats) and
		# stays modest so it lights his face without blooming white. Off → no backside flash.
		if _face_light:
			var face_dir := _hanuman.global_transform.basis.z.normalized()
			_face_light.global_position = _hanuman.global_position + face_dir * 9.0 + Vector3(0, 7.0, 0)
			_face_light.light_energy = 9.0 * clampf((t - 11.0) / 2.0, 0.0, 1.0)


func _interp_look(t: float) -> Vector3:
	# Look target shares the cam_keys timing (3rd element) and uses the SAME time-aware
	# Hermite as the position, so the gaze and the path move with matched, continuous
	# velocity. The monotone tangents give zero overshoot, so the gaze never whips on a
	# direction change (the old "facing glitch") yet never stops-and-goes at a key either.
	return _smooth_path(_cam_keys, t, 2)


func _interp(keys: Array, t: float) -> Vector3:
	return _smooth_path(keys, t, 1)


## Time-aware Hermite spline with monotone-clamped tangents — one curve for BOTH the
## camera path and the look target. Two properties make it read as VERY smooth:
##   • Continuous velocity across every key. The keys are unevenly spaced in time
##     (gaps run 3.5s → 1.1s); a plain Catmull-Rom basis ignores that and the speed
##     JUMPS at each key (jerk). Here the tangents are scaled by the real time gaps, so
##     the speed flows continuously through every key regardless of spacing.
##   • Zero overshoot. Tangents flatten to 0 at the endpoints (gentle ease in/out from
##     rest) and at any per-axis local extremum, so the curve can never bulge past a
##     keyframe value — no camera whip, and the dive can't dip down into the tree-cards.
func _smooth_path(keys: Array, t: float, idx: int) -> Vector3:
	if t <= keys[0][0]:
		return keys[0][idx]
	if t >= keys[-1][0]:
		return keys[-1][idx]
	for i in range(keys.size() - 1):
		var t1: float = keys[i][0]
		var t2: float = keys[i + 1][0]
		if t >= t1 and t <= t2:
			var dt: float = t2 - t1
			var s: float = (t - t1) / dt
			var p1: Vector3 = keys[i][idx]
			var p2: Vector3 = keys[i + 1][idx]
			var m1: Vector3 = _tangent(keys, i, idx) * dt
			var m2: Vector3 = _tangent(keys, i + 1, idx) * dt
			var s2: float = s * s
			var s3: float = s2 * s
			var h00: float = 2.0 * s3 - 3.0 * s2 + 1.0
			var h10: float = s3 - 2.0 * s2 + s
			var h01: float = -2.0 * s3 + 3.0 * s2
			var h11: float = s3 - s2
			return p1 * h00 + m1 * h10 + p2 * h01 + m2 * h11
	return keys[-1][idx]


## Monotone, time-weighted tangent at key `i` (per component). Endpoints get a zero
## tangent (ease in/out from rest); interior keys average the incoming and outgoing
## slopes but FLATTEN any component at a local extremum (sign change) so the curve
## stays monotonic across that key and can't overshoot.
func _tangent(keys: Array, i: int, idx: int) -> Vector3:
	if i == 0 or i == keys.size() - 1:
		return Vector3.ZERO
	var p: Vector3 = keys[i][idx]
	var pp: Vector3 = keys[i - 1][idx]
	var pn: Vector3 = keys[i + 1][idx]
	var dt_prev: float = float(keys[i][0]) - float(keys[i - 1][0])
	var dt_next: float = float(keys[i + 1][0]) - float(keys[i][0])
	var sp: Vector3 = (p - pp) / dt_prev      # incoming slope
	var sn: Vector3 = (pn - p) / dt_next      # outgoing slope
	var m: Vector3 = (sp + sn) * 0.5
	if sp.x * sn.x <= 0.0:
		m.x = 0.0
	if sp.y * sn.y <= 0.0:
		m.y = 0.0
	if sp.z * sn.z <= 0.0:
		m.z = 0.0
	return m


## Every MeshInstance3D under `n` (used to fade Hanuman in via GeometryInstance.transparency).
func _collect_mesh_instances(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_collect_mesh_instances(c))
	return out
