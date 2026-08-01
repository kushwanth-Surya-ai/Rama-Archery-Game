extends Node3D
## Third-person establishing hero camera. Pulled well back and elevated at golden
## hour so the WHOLE monkey spire reads centre-frame with the giant looming on the
## ground beyond — matching the reference (yesterday's) design. Adds subtle FOV +
## counter-roll sway from tower motion. The rig is parented under the summit mount
## but the camera is re-placed at an explicit WORLD transform EVERY frame, so the
## framing is rock-stable no matter how the mount moves.

const BASE_FOV := 58.0
const SPRINT_FOV_KICK := 8.0

# Establishing framing in WORLD space. The cone rises from y~1 (base) to y~33
# (summit, where the archer stands). We sit close-ish and at the archer's height,
# aimed at the upper cone/archer so Rama reads as a clear hero figure atop the
# spire with the giant looming behind — matching the reference (yesterday's) shot.
const CAM_POS_W := Vector3(-4.0, 32.0, 30.0)   # world: archer-height, pulled in
const LOOK_AT_W := Vector3(0.0, 27.0, 0.0)     # world: upper cone / archer

const MAX_SHAKE := 0.5         # cap so the tremor never gets nauseating
const SHAKE_DECAY := 1.6       # how fast a footfall tremor fades

var controller: Node          # TowerController (for speed/lean)
var _cam: Camera3D
var _sway_t := 0.0
var _shake := 0.0             # current ground-tremor amplitude (footfalls add to it)


## A monster footfall nudges this; the camera trembles smoothly until it decays.
func add_shake(a: float) -> void:
	_shake = minf(_shake + a, MAX_SHAKE)


## Creates the camera on demand and returns it. Called by Main right after the rig
## is built (BEFORE the rig enters the tree, so _ready hasn't run yet) so the
## gameplay camera reference is wired immediately — otherwise grabbing it from the
## rig's children comes back empty and the scope cam never hands control back.
func ensure_camera() -> Camera3D:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = BASE_FOV
		_cam.current = true
		_cam.attributes = CameraAttributesPractical.new()
		add_child(_cam)
	return _cam


func _ready() -> void:
	ensure_camera()


func _process(delta: float) -> void:
	# Drag-to-turn orbit is DISABLED: swinging the rig around the summit could fly
	# the camera straight into the monkey cone. The view stays locked to the stable
	# hero framing — aim with the cursor and the scope.
	InputRouter.consume_orbit()   # drain the accumulator so it never piles up
	rotation = Vector3.ZERO
	_sway_t += delta

	# Re-assert the hero framing in WORLD space EVERY frame. The rig is parented
	# under the summit mount, which is still settling during the intro->gameplay
	# handoff (and sways with the tower in play). Caching a one-shot LOCAL pose let
	# the camera drift down into the giant once the mount settled — recomputing from
	# world each frame eliminates that drift entirely.
	var breathe := sin(_sway_t * 0.6) * 0.03
	var lean: float = controller.lean if controller else 0.0
	var pos := CAM_POS_W + Vector3(0.0, sin(_sway_t * 0.8) * 0.05, 0.0)
	# Ground tremor from monster footfalls: smooth multi-frequency sway (not raw
	# noise) so the land "vibrates" without a harsh, jittery feel. Decays each frame.
	if _shake > 0.0001:
		_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
		var tr := _sway_t * 38.0
		pos += Vector3(sin(tr * 1.0), sin(tr * 1.37 + 1.1), sin(tr * 0.91 + 2.3)) * _shake
	_cam.look_at_from_position(pos, LOOK_AT_W, Vector3.UP)
	# Gentle cinematic breathing + counter-roll opposite the tower's lean.
	_cam.rotation.z += breathe - lean * 0.5

	# Speed-reactive FOV kick (sprint).
	if controller:
		var vel: Vector3 = controller.velocity
		var spd := Vector3(vel.x, 0, vel.z).length()
		var target_fov := BASE_FOV + clampf(spd * 0.7, 0.0, SPRINT_FOV_KICK)
		_cam.fov = lerpf(_cam.fov, target_fov, clampf(4.0 * delta, 0.0, 1.0))
