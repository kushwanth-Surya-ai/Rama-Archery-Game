extends CharacterBody3D
## Locomotion for the monkey tower's physics BASE (an invisible capsule).
## Reads merged intent from InputRouter, moves the base, and records a
## position-history breadcrumb trail that TowerSway samples to place the
## visible stacked monkeys with snake-like lag + whip.

const BASE_SPEED := 9.0
const SPRINT_MULT := 1.8
const ACCEL := 9.0
const GRAVITY := 26.0
const DODGE_SPEED := 24.0
const DODGE_TIME := 0.25
const DODGE_CD := 0.8
const TRAIL_SPACING := 0.15      # record a breadcrumb every this many metres
const MAX_TRAIL := 400
const MAX_LEAN := 0.35

var aim_node: Node3D             # AimYaw — provides camera-relative facing

var trail: Array[Dictionary] = []  # newest first: {pos: Vector3, dir: Vector3}
var total_distance := 0.0          # continuous, drives the sway phase
var forward_dir := Vector3.FORWARD
var lean := 0.0

var _dodge_timer := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector3.ZERO
var _last_record_pos := Vector3.ZERO
var _anchor := Vector3.ZERO       # spawn x/z the tower is pinned to (it never wanders)


func _ready() -> void:
	collision_layer = 2          # tower base on its own layer (arrows ignore it)
	collision_mask = 1           # collide with the world (layer 1)
	_anchor = global_position
	_last_record_pos = global_position
	trail.push_front({"pos": global_position, "dir": forward_dir})


func _physics_process(delta: float) -> void:
	var intent: Vector2 = InputRouter.move_vector
	var speed := BASE_SPEED
	if InputRouter.sprint:
		speed *= SPRINT_MULT

	# Camera-relative movement basis (flattened to the ground plane).
	var fwd := Vector3.FORWARD
	var right := Vector3.RIGHT
	if aim_node:
		var b := aim_node.global_transform.basis
		fwd = Vector3(-b.z.x, 0, -b.z.z)
		right = Vector3(b.x.x, 0, b.x.z)
		if fwd.length() > 0.001: fwd = fwd.normalized()
		if right.length() > 0.001: right = right.normalized()
	var wish := right * intent.x + fwd * intent.y
	if wish.length() > 1.0:
		wish = wish.normalized()

	# Dodge: short timed burst with cooldown.
	_dodge_cd = max(0.0, _dodge_cd - delta)
	if InputRouter.dodge_pressed and _dodge_cd <= 0.0:
		_dodge_timer = DODGE_TIME
		_dodge_cd = DODGE_CD
		_dodge_dir = wish if wish.length() > 0.1 else forward_dir

	var horiz := Vector3(velocity.x, 0, velocity.z)
	if _dodge_timer > 0.0:
		_dodge_timer -= delta
		horiz = _dodge_dir * DODGE_SPEED
	else:
		horiz = horiz.lerp(wish * speed, clampf(ACCEL * delta, 0.0, 1.0))

	# The tower is FIXED in place: ignore any horizontal locomotion. Only gravity
	# acts, so it just rests on the floor and never wanders from its spawn spot.
	velocity.x = 0.0
	velocity.z = 0.0
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# Hard-pin the horizontal position so nothing (dodge, sway, drift) can move it.
	global_position.x = _anchor.x
	global_position.z = _anchor.z

	# Heading + travel distance for the sway system.
	var flat := Vector3(velocity.x, 0, velocity.z)
	var flat_speed := flat.length()
	total_distance += flat_speed * delta
	if flat_speed > 0.3:
		forward_dir = flat.normalized()

	# Bank into lateral motion (and harder during a dodge).
	var side := flat.dot(right)
	var lean_target := clampf(-side / BASE_SPEED * MAX_LEAN, -MAX_LEAN, MAX_LEAN)
	if _dodge_timer > 0.0:
		lean_target = clampf(lean_target * 2.0, -MAX_LEAN * 1.5, MAX_LEAN * 1.5)
	lean = lerpf(lean, lean_target, clampf(6.0 * delta, 0.0, 1.0))

	# Record breadcrumb every fixed travel distance (not every frame).
	var moved := global_position - _last_record_pos
	moved.y = 0
	if moved.length() >= TRAIL_SPACING:
		trail.push_front({"pos": global_position, "dir": forward_dir})
		if trail.size() > MAX_TRAIL:
			trail.resize(MAX_TRAIL)
		_last_record_pos = global_position


## Interpolated breadcrumb at travel-distance `d` back along the trail.
func sample_trail_at_distance(d: float) -> Dictionary:
	if trail.is_empty():
		return {"pos": global_position, "dir": forward_dir}
	if d <= 0.0:
		return {"pos": trail[0].pos, "dir": trail[0].dir}
	var acc := 0.0
	for i in range(trail.size() - 1):
		var a: Dictionary = trail[i]
		var b: Dictionary = trail[i + 1]
		var seg := (a.pos as Vector3).distance_to(b.pos)
		if seg <= 0.00001:
			continue
		if acc + seg >= d:
			var t := (d - acc) / seg
			var dir: Vector3 = (a.dir as Vector3).lerp(b.dir, t)
			if dir.length() < 0.001:
				dir = forward_dir
			return {"pos": (a.pos as Vector3).lerp(b.pos, t), "dir": dir.normalized()}
		acc += seg
	var last: Dictionary = trail[trail.size() - 1]
	return {"pos": last.pos, "dir": last.dir}
