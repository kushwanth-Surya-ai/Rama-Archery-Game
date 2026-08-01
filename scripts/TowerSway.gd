extends Node3D
## Visual driver for the stacked monkeys. Runs in _process (after physics).
## Each segment follows the controller's breadcrumb trail at an increasing
## distance (higher = more lag), plus a height-amplified perpendicular sine
## "whip" and a banking lean. Also publishes the top transform to TopMount.

const SEGMENT_HEIGHT := 0.5
const SEG_BASE_Y := 0.5
const SEGMENT_SPACING_ALONG_TRAIL := 0.45   # trail distance added per segment
const SWAY_BASE_AMP := 0.45
const SWAY_FREQ := 1.6
const SWAY_WAVELENGTH := 0.5
const SWAY_EXPONENT := 2.1                   # >1 so the top whips, base stays planted
const LEAN_REACH := 1.2
const FOLLOW_SMOOTH := 16.0
const IDLE_SWAY_AMP := 0.12
const IDLE_SWAY_FREQ := 1.4
const BASE_SCALE := 1.2                      # gently wider at the base
const TOP_SCALE := 0.55                      # smaller toward the top -> long tapered spire
const TAPER_CURVE := 0.9                     # <1 stays wide longer, then narrows to a point

var controller: Node                          # TowerController
var segment_count := 14
var top_mount: Node3D

var segments: Array[Node3D] = []
var _scales: Array[float] = []                # per-segment taper scale (base -> top)
var _heights: Array[float] = []               # per-segment stacked y (spacing follows scale)
var _idle_time := 0.0
var _travel := 0.0


func _ready() -> void:
	_precompute_cone()
	for i in range(segment_count):
		var seg := _make_monkey(i)
		add_child(seg)
		segments.append(seg)


## Precompute the cone: scale shrinks toward the top, and vertical spacing
## shrinks with it so smaller monkeys nest closer and the spire stays solid.
func _precompute_cone() -> void:
	var y := SEG_BASE_Y
	for i in range(segment_count):
		var hf := 0.0
		if segment_count > 1:
			hf = float(i) / float(segment_count - 1)
		var f := lerpf(BASE_SCALE, TOP_SCALE, pow(hf, TAPER_CURVE))
		_scales.append(f)
		if i == 0:
			y = SEG_BASE_Y + SEGMENT_HEIGHT * f * 0.5
		else:
			y += SEGMENT_HEIGHT * (_scales[i - 1] + f) * 0.5
		_heights.append(y)


func _process(delta: float) -> void:
	if controller == null:
		return
	_idle_time += delta

	var vel: Vector3 = controller.velocity
	var speed := Vector3(vel.x, 0, vel.z).length()
	# Advance a CONTINUOUS travel value here (render-rate) so the sway sine is
	# smooth instead of stepping at the 60 Hz physics tick.
	_travel += speed * delta
	var moving: bool = speed > 0.3 and controller.trail.size() > 1
	var lean: float = controller.lean

	# Stable head position (path only, no whip) for the camera/aim mount.
	var stable_top := global_position

	for i in range(segments.size()):
		var seg := segments[i]
		var hf := 0.0
		if segment_count > 1:
			hf = float(i) / float(segment_count - 1)

		var sample: Dictionary = controller.sample_trail_at_distance(i * SEGMENT_SPACING_ALONG_TRAIL)
		var base_pos: Vector3 = sample.pos
		base_pos.y = _heights[i]
		var dir: Vector3 = sample.dir
		if dir.length() < 0.001:
			dir = Vector3.FORWARD

		if i == segments.size() - 1:
			stable_top = base_pos    # path position of the head, BEFORE sway

		# Perpendicular (horizontal) to the travel direction.
		var perp := Vector3(dir.z, 0, -dir.x).normalized()

		var amp: float
		var phase: float
		if moving:
			amp = SWAY_BASE_AMP * pow(hf, SWAY_EXPONENT)
			phase = _travel * SWAY_FREQ - i * SWAY_WAVELENGTH
		else:
			amp = IDLE_SWAY_AMP * hf
			phase = _idle_time * IDLE_SWAY_FREQ - i * SWAY_WAVELENGTH

		var sway := perp * sin(phase) * amp
		var lean_off := perp * lean * hf * LEAN_REACH
		var target := base_pos + sway + lean_off

		seg.global_position = seg.global_position.lerp(target, clampf(FOLLOW_SMOOTH * delta, 0.0, 1.0))

		# Face along motion, then roll for the lean.
		var look_target := seg.global_position + dir
		if seg.global_position.distance_to(look_target) > 0.001:
			seg.look_at(look_target, Vector3.UP)
		seg.rotate_object_local(Vector3.FORWARD, lean * hf * 1.5)

	# Camera/aim ride a heavily-smoothed path point, NOT the whipping top monkey,
	# so aiming stays stable while the visible tower still slithers beneath.
	if top_mount:
		var target_top := stable_top + Vector3(0, 0.55, 0)
		top_mount.global_position = top_mount.global_position.lerp(
			target_top, clampf(7.0 * delta, 0.0, 1.0))


## Build one placeholder monkey from primitives, hue-tinted by stack index.
## Visuals live under an inner node scaled by the cone taper, because look_at()
## on the segment root each frame would otherwise wipe a scale set on the root.
func _make_monkey(i: int) -> Node3D:
	var root := Node3D.new()
	var vis := Node3D.new()
	vis.scale = Vector3.ONE * _scales[i]
	root.add_child(vis)

	# Rainbow gradient down the body: orange near the archer (top) -> green at base.
	var hf := 0.0
	if segment_count > 1:
		hf = float(i) / float(segment_count - 1)
	var hue := lerpf(0.33, 0.03, hf)         # 0.33 green (base) -> 0.03 orange (top)
	var col := Color.from_hsv(hue, 0.62, 0.8)
	if i == segment_count - 1:
		col = Color(0.95, 0.82, 0.28)        # distinct top monkey (archer's perch)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.9

	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.45
	bm.height = 1.05
	body.mesh = bm
	body.material_override = mat
	vis.add_child(body)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.3
	hm.height = 0.6
	head.mesh = hm
	head.material_override = mat
	head.position = Vector3(0, 0.55, -0.05)
	vis.add_child(head)

	for sx in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.12
		em.height = 0.24
		ear.mesh = em
		ear.material_override = mat
		ear.position = Vector3(0.28 * sx, 0.72, -0.05)
		vis.add_child(ear)

	# Extra fur lumps so each monkey reads as a furry cluster (the bumpy rope look).
	for off in [Vector3(0.34, 0.12, 0.22), Vector3(-0.32, -0.12, 0.18), Vector3(0.05, -0.05, -0.36)]:
		var lump := MeshInstance3D.new()
		var lmesh := SphereMesh.new()
		lmesh.radius = 0.27
		lmesh.height = 0.54
		lump.mesh = lmesh
		lump.material_override = mat
		lump.position = off
		vis.add_child(lump)

	return root
