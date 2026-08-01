extends Node3D
## Lives on AimYaw (the archer's yaw pivot at the top of the tower).
## Drives yaw on itself and pitch on pitch_node from InputRouter look delta,
## and handles the charged-shot bow: tap = fast flat arrow, hold = stronger arc.

const SENS := 0.0024
const PITCH_MIN := -0.87        # ~ -50 deg
const PITCH_MAX := 1.22         # ~  70 deg
# Real-bow launch speeds (m/s). A traditional longbow looses an arrow around
# 50 m/s (~165 fps); a strong recurve/compound reaches 80-100 m/s (~260-330 fps).
# Tap (min draw) -> a soft 48 m/s lob; full draw -> a fast, flat 90 m/s shot.
const MIN_SPEED := 48.0
const MAX_SPEED := 90.0
const MAX_CHARGE := 1.2
const MIN_DAMAGE := 10.0
const MAX_DAMAGE := 55.0
const DRAW_SCOPE_DELAY := 0.12   # bow must be drawn this long before the scope zooms in

const ArrowScript := preload("res://scripts/Arrow.gd")

var pitch_node: Node3D
var muzzle: Node3D
var bow_tip: Node3D             # exact arrow exit on the bow; falls back to muzzle
var bow_mesh: Node3D
var archer: Node3D              # posed archer body; animates the draw/loose
var view_cam: Camera3D          # third-person cam used for cursor aim raycasts (stable)

var _yaw := 0.0
var _pitch := 0.0
var _charging := false
var _charge_t := 0.0
@onready var _is_touch: bool = DisplayServer.is_touchscreen_available()


func _process(delta: float) -> void:
	# MOUSELOOK mode keeps the classic relative-look aiming. POINTER mode aims at
	# the mouse cursor instead (handled in _physics_process so the raycast is
	# safe), so we skip the relative path here.
	if not InputRouter.touch_mode:
		var look: Vector2 = InputRouter.consume_look()
		# Slow the aim while scoped so the zoomed view is easy to hold steady.
		var sens := SENS * (0.4 if InputRouter.scope else 1.0)
		_yaw -= look.x * sens
		_pitch = clampf(_pitch - look.y * sens, PITCH_MIN, PITCH_MAX)
		rotation.y = _yaw
		if pitch_node:
			pitch_node.rotation.x = _pitch
	elif _is_touch and InputRouter.scope:
		# TOUCH scope: there is no mouse cursor to aim, so a drag PANS the aim
		# (crosshair stays centred). Slowed like the mouselook scope for a steady hold.
		var pan: Vector2 = InputRouter.consume_scope_look()
		var psens := SENS * 0.5
		_yaw -= pan.x * psens
		_pitch = clampf(_pitch - pan.y * psens, PITCH_MIN, PITCH_MAX)
		rotation.y = _yaw
		if pitch_node:
			pitch_node.rotation.x = _pitch

	# Lean the visible archer to match the aim pitch (set in either input mode).
	if archer:
		archer.call("set_pitch", _pitch)

	if InputRouter.shoot_just_pressed:
		_charging = true
		_charge_t = 0.0
		Audio.play_draw()        # bow creak as the string is pulled
	if _charging:
		_charge_t = minf(_charge_t + delta, MAX_CHARGE)
		if bow_mesh:
			bow_mesh.scale = Vector3.ONE * lerpf(1.0, 1.18, _charge_t / MAX_CHARGE)
		if archer:
			archer.call("set_charge", _charge_t / MAX_CHARGE)
	if InputRouter.shoot_just_released and _charging:
		_fire()
		_charging = false
		if bow_mesh:
			bow_mesh.scale = Vector3.ONE
		if archer:
			archer.call("set_charge", 0.0)
			archer.call("release")        # snap the draw hand forward (the loose)
	elif _charging and not InputRouter.shoot_held:
		# the hold turned into a drag-turn -> cancel the shot, don't fire
		_charging = false
		if bow_mesh:
			bow_mesh.scale = Vector3.ONE
		if archer:
			archer.call("set_charge", 0.0)

	# The aim scope is LINKED to the bow: drawing the bow past a brief threshold
	# engages it (InputRouter ORs this with the on-screen scope button).
	InputRouter.bow_drawn = _charging and _charge_t >= DRAW_SCOPE_DELAY


## POINTER mode: rotate the archer (yaw) + bow (pitch) to face the world point
## under the mouse cursor, so the muzzle — and therefore the arrow — points
## exactly where the on-screen reticle is. Camera is decoupled, so no feedback.
func _physics_process(_delta: float) -> void:
	if not InputRouter.touch_mode:
		return
	if _is_touch and InputRouter.scope:
		return   # scoped aim is drag-panned in _process on touch devices (not cursor-aimed)
	# Always raycast through the third-person view cam (not the active scope cam),
	# so aiming the cursor stays stable while scoped instead of running away.
	var cam: Camera3D = view_cam if view_cam else get_viewport().get_camera_3d()
	if cam == null:
		return
	var mp := get_viewport().get_mouse_position()
	var ro := cam.project_ray_origin(mp)
	var rn := cam.project_ray_normal(mp)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ro, ro + rn * 2000.0, 1)
	var hit := space.intersect_ray(query)
	var target: Vector3 = hit.position if hit.has("position") else ro + rn * 400.0

	var d := target - global_position
	var hd := sqrt(d.x * d.x + d.z * d.z)
	_yaw = atan2(-d.x, -d.z)            # face the target horizontally (archer faces -Z)
	rotation.y = _yaw
	if pitch_node:
		_pitch = clampf(atan2(d.y, hd), PITCH_MIN, PITCH_MAX)
		pitch_node.rotation.x = _pitch


func get_charge_ratio() -> float:
	return (_charge_t / MAX_CHARGE) if _charging else 0.0


func _fire() -> void:
	var r := _charge_t / MAX_CHARGE
	var speed := lerpf(MIN_SPEED, MAX_SPEED, r)
	var dmg := lerpf(MIN_DAMAGE, MAX_DAMAGE, r)

	# Arrow leaves from the bow tip (the arrow rest), but flies along the aim
	# direction (muzzle -Z, which carries the pitch) so it goes where you point.
	var origin: Vector3
	if bow_tip:
		origin = bow_tip.global_position
	elif muzzle:
		origin = muzzle.global_position
	else:
		origin = global_position
	var dir: Vector3
	if muzzle:
		dir = -muzzle.global_transform.basis.z
	else:
		dir = -global_transform.basis.z

	# SCOPED precision shot: aim at the exact world point under the scope crosshair
	# (centre of the scope camera) and fire a flat, fast, drop-free arrow so it hits
	# precisely where the scope points — line it up on the head for the bonus.
	var flat := false
	if InputRouter.scope:
		var scam := get_viewport().get_camera_3d()
		if scam:
			var center := get_viewport().get_visible_rect().size * 0.5
			var ro := scam.project_ray_origin(center)
			var rn := scam.project_ray_normal(center)
			var space := get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(ro, ro + rn * 3000.0, 1)
			var hit := space.intersect_ray(q)
			var tgt: Vector3 = hit.position if hit.has("position") else ro + rn * 1200.0
			dir = (tgt - origin).normalized()
			speed = maxf(speed, 150.0)      # fast enough that drop-free flight reads instant
			flat = true

	var arrow := RigidBody3D.new()
	arrow.set_script(ArrowScript)
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = origin
	arrow.call("launch", dir.normalized() * speed, dmg, flat)

	Audio.play_shoot()           # bow twang + arrow whoosh on the loose

	# Haptic kick on release (iPhone/Android/Web; a no-op on desktop). A fuller draw
	# buzzes a touch longer — on iOS the duration is ignored and you get the standard
	# system vibration, on Android it scales 60–160 ms with the charge.
	Input.vibrate_handheld(int(lerpf(60.0, 160.0, r)))
