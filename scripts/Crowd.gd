extends Node3D
## The villagers Rama defends: thousands of farmers (single MultiMesh, a few instanced
## draw calls). They hold TWO defensive lines facing the incoming monsters (which come
## from -Z): a FRONT line (half the crowd) out in the field, and the other half massed
## in front of the monkey tower. They don't charge — they hold their ground and rain Hanzo arrows on whatever
## monster is in range. A monster stops to maul the villagers blocking it (grabbing and
## hurling them) and only WALKS on once its path is clear. Fallen villagers lie as
## bodies on the field. If every villager dies, Rama has failed.

signal population_changed(alive: int, total: int)
signal depleted

const FarmerMesh := preload("res://assets/farmer/source/extracted/Farmer.obj")
const FarmerAlbedo := preload("res://assets/farmer/textures/Farmer_LowRes_All_BaseColor.png")
const ArrowScene := preload("res://assets/overwatch_-_hanzos_arrow.glb")
const FarmerPoseScript := preload("res://scripts/FarmerPose.gd")

const FARMER_HEIGHT := 2.8        # world height to fit the model to (tall enough to read at range)
const FARMER_FACE := 0.0          # yaw offset (rad) if the model's forward isn't -Z

# Two formations on the -Z side (monsters approach from -Z). The first HALF of the
# crowd forms the front line out in the field; the rest mass in front of the tower.
# Both are wide, deep blocks sized to hold thousands without becoming a solid wall.
const FRONT_Z0 := -80.0
const FRONT_Z1 := -54.0
const FRONT_HALF_X := 52.0
const TOWER_Z0 := -38.0
const TOWER_Z1 := -10.0
const TOWER_HALF_X := 40.0

const FIRE_RANGE := 80.0          # archers open up on a monster within this range
const POOL := 600                 # max arrows in flight at once — a thick, readable volley
const ARROW_LEN := 3.0            # world length to fit the (very long) arrow model — big enough to read in the air
const HELD_LEN := 1.4             # world length of the arrow each villager holds in hand
const ARROW_SPEED := 34.0         # units/sec — slow enough that you can follow each shaft's flight
const ARROW_DMG := 0.012          # tiny per-arrow; the swarm chips in but Rama is the hunter
const SPAWN_PER_FRAME := 9        # new volley arrows started each frame — a steady rain of shafts
# Loft: arrows are LOBBED, not shot flat, so the volley visibly arcs up and rains
# down. Peak height scales with throw distance, clamped to a dramatic range.
const LOFT_FACTOR := 0.32
const LOFT_MIN := 8.0
const LOFT_MAX := 24.0

# Arrows that land on a living monster STICK in its body (a ring buffer, so the
# oldest shafts are recycled once the monster is a pincushion). Each stuck arrow
# rides its monster's transform, so it stays embedded as the monster marches and
# even as it topples over dead.
const STUCK_POOL := 260
const STUCK_Y := Vector2(4.0, 11.0)    # world-height torso band to embed within (matches the +7 aim point)
const STUCK_R := Vector2(1.2, 3.0)     # radial spread around the monster centre

# Monster hand-throw: grabbed villagers are hurled back in an arc and land broken.
const GRAV := 24.0
const THROW_H := 13.0
const THROW_V := 10.5

# Victory cheer: fast desynced hops so the field reads as a roaring crowd.
const CHEER_FREQ := 6.0
const CHEER_JUMP := 0.9            # metres of hop height

var total := 1000
var targets: Array = []           # the monsters (set by Main) the villagers shoot at

var _mm: MultiMesh
var _foot := 0.0                  # y so the model's feet rest on the ground
var _scale := 1.0
var _pos: PackedVector3Array = PackedVector3Array()   # home position per villager (they hold it)
var _phase: PackedFloat32Array = PackedFloat32Array() # idle sway phase
var _alive_idx: Array[int] = []
var _alive := 0
var _fire_cursor := 0
var _rng := RandomNumberGenerator.new()
var _flying: Array = []           # villagers currently airborne (grabbed + thrown)
var _celebrating := false         # victory! everyone drops their bow and cheers

# An arrow held in each villager's hand (one MultiMesh instance per villager, kept at
# the hand and pointed at the monster they face; hidden when they're seized/thrown).
var _held_mm: MultiMesh
var _held_scale := 1.0

# Arrow pool (parallel arrays; inactive slots are scaled to 0 in the MultiMesh).
var _arrow_mm: MultiMesh
var _arrow_scale := 1.0
var _ar_active: Array[bool] = []
var _ar_from: PackedVector3Array = PackedVector3Array()
var _ar_to: PackedVector3Array = PackedVector3Array()
var _ar_t: PackedFloat32Array = PackedFloat32Array()
var _ar_dur: PackedFloat32Array = PackedFloat32Array()
var _ar_peak: PackedFloat32Array = PackedFloat32Array()   # loft (metres) of each arrow's arc
var _ar_target: Array = []
var _ar_free: Array[int] = []

# Stuck-arrow pool (arrows embedded in monster bodies). Ring buffer.
var _stuck_mm: MultiMesh
var _st_mon: Array = []            # the monster each stuck arrow rides (may become invalid)
var _st_local: Array = []         # the arrow's transform in that monster's local space
var _st_used: Array[bool] = []
var _st_cursor := 0


func _ready() -> void:
	_rng.seed = 770214
	_build_farmers()
	_build_arrows()


func _build_farmers() -> void:
	# The raw Farmer.obj is baked arms-spread; fold the arms down into a holding
	# stance once here so all 1000 villagers read as gripping an arrow, not
	# scarecrows. (Static mesh + MultiMesh: no per-instance limb animation.)
	var mesh: Mesh = FarmerPoseScript.repose(FarmerMesh)
	var aabb := mesh.get_aabb()
	_scale = FARMER_HEIGHT / maxf(0.001, aabb.size.y)
	_foot = -aabb.position.y * _scale          # lift so the lowest vertex sits at y=0

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = total

	for i in total:
		var p := _home_pos(i)
		_pos.append(p)
		_phase.append(_rng.randf() * TAU)
		_alive_idx.append(i)
		_mm.set_instance_transform(i, _farmer_xform(p, PI + FARMER_FACE, 0.0))   # face -Z
	_alive = total

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = FarmerAlbedo
	mat.roughness = 0.95
	mmi.material_override = mat
	# 1000 densely-packed villagers casting into the directional shadow map is a
	# heavy per-frame cost for shadows the haze all but hides — drop them from the
	# shadow pass. They still receive light/shadow, just don't cast.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	population_changed.emit(_alive, total)


## Formation home: the first half form the front line out in the field; the rest mass
## in front of the tower. Random scatter within each block so it reads as a crowd.
func _home_pos(i: int) -> Vector3:
	var x: float
	var z: float
	if i < total / 2:
		x = _rng.randf_range(-FRONT_HALF_X, FRONT_HALF_X)
		z = _rng.randf_range(FRONT_Z0, FRONT_Z1)
	else:
		x = _rng.randf_range(-TOWER_HALF_X, TOWER_HALF_X)
		z = _rng.randf_range(TOWER_Z0, TOWER_Z1)
	return Vector3(x, 0.0, z)


func _build_arrows() -> void:
	var inst := ArrowScene.instantiate()
	var amesh: Mesh = _first_mesh(inst)
	inst.free()
	if amesh:
		_arrow_scale = ARROW_LEN / maxf(0.001, amesh.get_aabb().size.z)
		_held_scale = HELD_LEN / maxf(0.001, amesh.get_aabb().size.z)
		_build_held_arrows(amesh)

	_arrow_mm = MultiMesh.new()
	_arrow_mm.transform_format = MultiMesh.TRANSFORM_3D
	_arrow_mm.mesh = amesh
	_arrow_mm.instance_count = POOL
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in POOL:
		_ar_active.append(false)
		_ar_from.append(Vector3.ZERO)
		_ar_to.append(Vector3.ZERO)
		_ar_t.append(0.0)
		_ar_dur.append(1.0)
		_ar_peak.append(LOFT_MIN)
		_ar_target.append(null)
		_ar_free.append(i)
		_arrow_mm.set_instance_transform(i, hidden)

	if amesh:
		var ami := MultiMeshInstance3D.new()
		ami.multimesh = _arrow_mm
		add_child(ami)

	# Pool for arrows embedded in monster bodies.
	_stuck_mm = MultiMesh.new()
	_stuck_mm.transform_format = MultiMesh.TRANSFORM_3D
	_stuck_mm.mesh = amesh
	_stuck_mm.instance_count = STUCK_POOL
	for i in STUCK_POOL:
		_st_mon.append(null)
		_st_local.append(Transform3D.IDENTITY)
		_st_used.append(false)
		_stuck_mm.set_instance_transform(i, hidden)
	if amesh:
		var smi := MultiMeshInstance3D.new()
		smi.multimesh = _stuck_mm
		add_child(smi)


## One arrow nocked in every villager's hand. Updated each frame in `_hold` to ride
## the hand and point at the monster they face; hidden when the villager is seized.
func _build_held_arrows(amesh: Mesh) -> void:
	_held_mm = MultiMesh.new()
	_held_mm.transform_format = MultiMesh.TRANSFORM_3D
	_held_mm.mesh = amesh
	_held_mm.instance_count = total
	for i in total:
		_held_mm.set_instance_transform(i, _held_xform(_pos[i], PI + FARMER_FACE))
	var hmi := MultiMeshInstance3D.new()
	hmi.multimesh = _held_mm
	add_child(hmi)


func alive() -> int:
	return _alive


## Living villagers within `radius` (XZ) of a point — the monster uses this to decide
## whether its path is blocked (stop and maul) or clear (walk on).
func living_near(p: Vector3, radius: float) -> int:
	var r2 := radius * radius
	var c := 0
	for idx in _alive_idx:
		var q := _pos[idx]
		if (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z) <= r2:
			c += 1
	return c


## World position of the living villager nearest `p` (XZ distance). Returns `p` itself
## when nobody is left — callers treat "no move needed" as the all-dead case. The monster
## uses this to HUNT the crowd: steer toward the closest person instead of the tower.
func nearest_living(p: Vector3) -> Vector3:
	var best := p
	var best_d2 := INF
	for idx in _alive_idx:
		var q := _pos[idx]
		var d2 := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
		if d2 < best_d2:
			best_d2 = d2
			best = Vector3(q.x, 0.0, q.z)
	return best


func _process(delta: float) -> void:
	_step_stuck()   # embedded arrows keep riding their monsters (incl. while celebrating)
	if _celebrating:
		_cheer(delta)
		_step_thrown(delta)   # let any villagers still airborne land
		return
	var live_monsters := _live_targets()
	_hold(delta, live_monsters)
	if not live_monsters.is_empty():
		_fire(live_monsters)
	_step_arrows(delta)
	_step_thrown(delta)


## All monsters are dead — switch the line of villagers from "holding" to a
## victory celebration: bows down, turn toward the hero on the tower, and hop.
func celebrate() -> void:
	if _celebrating:
		return
	_celebrating = true
	# Desync each villager's hop so the crowd roars instead of bouncing as one.
	for idx in _alive_idx:
		_phase[idx] = _rng.randf() * TAU


## Per-frame victory cheer: face the hero (tower at origin) with a little excited
## wiggle, hop with abs(sin) so feet plant between jumps, and stow the held arrow.
func _cheer(delta: float) -> void:
	for idx in _alive_idx:
		var p := _pos[idx]
		_phase[idx] += delta * CHEER_FREQ
		var hop: float = absf(sin(_phase[idx])) * CHEER_JUMP
		var wiggle := sin(_phase[idx] * 0.5) * 0.25
		var face := atan2(-p.x, -p.z) + FARMER_FACE + wiggle
		_mm.set_instance_transform(idx, _farmer_xform(p, face, hop))
		if _held_mm:
			# Hide the held arrow (degenerate scale) — they've put the bows down.
			_held_mm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(p.x, _foot, p.z)))


## Monsters that are released AND still standing — only these draw fire.
func _live_targets() -> Array:
	var out: Array = []
	for m in targets:
		if is_instance_valid(m) and m.call("is_engaged"):
			out.append(m)
	return out


## Villagers hold their line: stand their ground, turn to face the nearest monster
## (or forward when none), with a small ready-stance sway so they aren't frozen.
func _hold(delta: float, live_monsters: Array) -> void:
	var has := not live_monsters.is_empty()
	for idx in _alive_idx:
		var p := _pos[idx]
		var face := PI + FARMER_FACE
		if has:
			var m: Node3D = _nearest(p, live_monsters)
			var mp: Vector3 = m.global_position
			face = atan2(mp.x - p.x, mp.z - p.z) + FARMER_FACE
		_phase[idx] += delta * 2.2
		var sway := sin(_phase[idx]) * 0.05
		_mm.set_instance_transform(idx, _farmer_xform(p, face + sway, 0.0))
		if _held_mm:
			_held_mm.set_instance_transform(idx, _held_xform(p, face + sway))


## Stagger arrow volleys: each frame a few villagers within firing range of a monster
## loose an arrow at the nearest one. Round-robins so the fire spreads across the line.
func _fire(live_monsters: Array) -> void:
	if _alive_idx.is_empty():
		return
	var launched := 0
	var tries := 0
	var n := _alive_idx.size()
	# Thin the volley as the crowd falls: fewer archers left → fewer shafts loosed.
	var cap := maxi(1, int(round(SPAWN_PER_FRAME * float(_alive) / float(total))))
	while launched < cap and tries < n:
		tries += 1
		_fire_cursor = (_fire_cursor + 1) % n
		var idx: int = _alive_idx[_fire_cursor]
		var p := _pos[idx]
		var m: Node3D = _nearest(p, live_monsters)
		var mp: Vector3 = m.global_position
		if Vector3(p.x - mp.x, 0.0, p.z - mp.z).length() > FIRE_RANGE:
			continue
		if _launch_arrow(p + Vector3(0, FARMER_HEIGHT * 0.6, 0), mp + Vector3(0, 7.0, 0), m):
			launched += 1


func _launch_arrow(from: Vector3, to: Vector3, m: Node3D) -> bool:
	if _ar_free.is_empty():
		return false
	var s: int = _ar_free.pop_back()
	_ar_active[s] = true
	_ar_from[s] = from
	_ar_to[s] = to
	_ar_t[s] = 0.0
	var dist := from.distance_to(to)
	_ar_dur[s] = maxf(0.25, dist / ARROW_SPEED)
	_ar_peak[s] = clampf(dist * LOFT_FACTOR, LOFT_MIN, LOFT_MAX)
	_ar_target[s] = m
	return true


## Fly active arrows along a shallow arc; on landing deal a tiny hit and recycle.
func _step_arrows(delta: float) -> void:
	for s in POOL:
		if not _ar_active[s]:
			continue
		_ar_t[s] += delta / _ar_dur[s]
		var t: float = _ar_t[s]
		if t >= 1.0:
			_ar_active[s] = false
			_ar_free.append(s)
			_arrow_mm.set_instance_transform(s, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			var m = _ar_target[s]
			if is_instance_valid(m) and m.call("is_alive"):
				m.call("take_hit_silent", ARROW_DMG)
				_stick_arrow(m, _ar_from[s])   # embed the shaft in the body
			continue
		var a: Vector3 = _ar_from[s]
		var b: Vector3 = _ar_to[s]
		var peak: float = _ar_peak[s]
		var pos := a.lerp(b, t)
		pos.y += sin(t * PI) * peak
		var nt: float = minf(1.0, t + 0.04)
		var npos := a.lerp(b, nt)
		npos.y += sin(nt * PI) * peak
		# Orient each shaft along its actual travel (incl. the arc) so it noses up on
		# the way out and pitches down as it falls — the movement reads clearly.
		_arrow_mm.set_instance_transform(s, _arrow_xform(pos, (npos - pos)))


## Embed a landed arrow in monster `m`'s body: pick a torso point (biased to the side
## the shaft came in from), nose it inward, and store it in the monster's LOCAL space
## so it rides along as the monster moves and topples. Ring buffer recycles old shafts.
func _stick_arrow(m: Node3D, from: Vector3) -> void:
	if _stuck_mm == null:
		return
	var mp: Vector3 = m.global_position
	var side := Vector3(from.x - mp.x, 0.0, from.z - mp.z)   # back toward the shooter
	if side.length() < 0.01:
		side = Vector3(0, 0, 1)
	side = side.normalized().rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7))
	var radius := _rng.randf_range(STUCK_R.x, STUCK_R.y)
	var embed := mp + side * radius + Vector3(0, _rng.randf_range(STUCK_Y.x, STUCK_Y.y), 0)
	# Shaft noses INTO the body (tail out toward the shooter), tipped slightly down.
	var shaft := -side + Vector3(0, _rng.randf_range(-0.15, 0.1), 0)
	var world := _arrow_xform(embed, shaft)

	var slot := _st_cursor
	_st_cursor = (_st_cursor + 1) % STUCK_POOL
	_st_mon[slot] = m
	_st_local[slot] = m.global_transform.affine_inverse() * world
	_st_used[slot] = true
	_stuck_mm.set_instance_transform(slot, world)


## Keep embedded arrows glued to their monster (marching, lunging, toppling). Once a
## monster is freed, its arrows hold their last transform (frozen on the fallen body).
func _step_stuck() -> void:
	if _stuck_mm == null:
		return
	for slot in STUCK_POOL:
		if not _st_used[slot]:
			continue
		var m = _st_mon[slot]
		if is_instance_valid(m):
			_stuck_mm.set_instance_transform(slot, m.global_transform * _st_local[slot])


## A monster grabs the `n` villagers nearest its hands (`mpos`) and HURLS them back —
## they tumble through the air and land broken. Counted as casualties when seized.
func throw(n: int, mpos: Vector3) -> void:
	if _alive <= 0:
		return
	var thrown := 0
	for _k in n:
		if _alive_idx.is_empty():
			break
		var bs := -1
		var best := -1
		var bd := INF
		for si in _alive_idx.size():
			var ix: int = _alive_idx[si]
			var pp := _pos[ix]
			var dd := (pp.x - mpos.x) * (pp.x - mpos.x) + (pp.z - mpos.z) * (pp.z - mpos.z)
			if dd < bd:
				bd = dd
				best = ix
				bs = si
		if best < 0:
			break
		_alive_idx.remove_at(bs)
		if _held_mm:
			_held_mm.set_instance_transform(best, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		var p := _pos[best]
		var dir := Vector3(p.x - mpos.x, 0.0, p.z - mpos.z)
		if dir.length() < 0.1:
			dir = Vector3(_rng.randf() - 0.5, 0.0, _rng.randf() - 0.5)
		dir = dir.normalized()
		_flying.append({
			"idx": best,
			"pos": Vector3(p.x, _foot + 1.0, p.z),
			"vel": dir * THROW_H + Vector3.UP * THROW_V,
			"ang": _rng.randf() * TAU,
			"axis": Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5).normalized(),
			"rate": _rng.randf_range(7.0, 13.0),
		})
		thrown += 1
	_alive = maxi(0, _alive - thrown)
	population_changed.emit(_alive, total)
	if _alive <= 0:
		depleted.emit()


## Animate grabbed villagers flying through the air; on landing they lie broken.
func _step_thrown(delta: float) -> void:
	if _flying.is_empty():
		return
	var still: Array = []
	for f in _flying:
		var v: Vector3 = f["vel"]
		v.y -= GRAV * delta
		var p: Vector3 = f["pos"] + v * delta
		f["vel"] = v
		f["pos"] = p
		f["ang"] = f["ang"] + f["rate"] * delta
		if p.y <= _foot + 0.05 and v.y < 0.0:
			_mm.set_instance_transform(f["idx"], _fallen_xform(Vector3(p.x, 0.12, p.z)))
		else:
			var b := Basis(f["axis"], f["ang"]).scaled(Vector3.ONE * _scale)
			_mm.set_instance_transform(f["idx"], Transform3D(b, p))
			still.append(f)
	_flying = still


# --- helpers --------------------------------------------------------------

func _nearest(p: Vector3, live_monsters: Array) -> Node3D:
	var best: Node3D = live_monsters[0]
	var bd := INF
	for m in live_monsters:
		var mp: Vector3 = m.global_position
		var d := (p.x - mp.x) * (p.x - mp.x) + (p.z - mp.z) * (p.z - mp.z)
		if d < bd:
			bd = d
			best = m
	return best


## Upright farmer transform: scaled, yaw-faced, feet on the ground (+ optional bob).
func _farmer_xform(p: Vector3, yaw: float, bob: float) -> Transform3D:
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * _scale)
	return Transform3D(b, Vector3(p.x, _foot + bob, p.z))


## A slain villager lying flat on the ground (a body).
func _fallen_xform(at: Vector3) -> Transform3D:
	var fell := Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _scale)
	return Transform3D(fell, at)


## The arrow a villager holds: nocked at hand height on their bow-hand side, pointed
## at the monster they face (local +Z along the aim, scaled to the held length).
func _held_xform(p: Vector3, yaw: float) -> Transform3D:
	var f := Vector3(sin(yaw), 0.0, cos(yaw))            # forward (toward the monster)
	var r := Vector3(cos(yaw), 0.0, -sin(yaw))           # throwing-hand side
	# Arms now hang down and slightly forward (see FarmerPose): the gripping hand
	# sits near hip height, close to the body's centre, held out toward the monster.
	var hand := Vector3(p.x, _foot + FARMER_HEIGHT * 0.42, p.z) \
		+ r * (0.14 * FARMER_HEIGHT) + f * (0.26 * FARMER_HEIGHT)
	var fz := (f + Vector3(0, 0.12, 0)).normalized()
	var fx := Vector3.UP.cross(fz)
	if fx.length() < 0.0001:
		fx = Vector3.RIGHT
	fx = fx.normalized()
	var fy := fz.cross(fx).normalized()
	var s := _held_scale
	return Transform3D(Basis(fx * s, fy * s, fz * s), hand)


## Arrow transform: local +Z aligned to the flight direction, scaled to length.
func _arrow_xform(pos: Vector3, dir: Vector3) -> Transform3D:
	var fz := dir
	if fz.length() < 0.0001:
		fz = Vector3.FORWARD
	fz = fz.normalized()
	var fx := Vector3.UP.cross(fz)
	if fx.length() < 0.0001:
		fx = Vector3.RIGHT
	fx = fx.normalized()
	var fy := fz.cross(fx).normalized()
	var s := _arrow_scale
	return Transform3D(Basis(fx * s, fy * s, fz * s), pos)


func _first_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D and n.mesh:
		return n.mesh
	for c in n.get_children():
		var m := _first_mesh(c)
		if m:
			return m
	return null
