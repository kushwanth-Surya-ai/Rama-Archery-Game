extends Node3D
## Lord Ram (Maryada Purushottam) rendered as a stylised — but human-proportioned
## — archer built from primitives, posed mid-draw, with a LIVE draw/release
## animation. The rear (draw) hand is the only thing that moves:
##  - while charging it pulls back a touch deeper,
##  - on release it snaps forward along the arrow line (the loose), then eases
##    back as the archer re-nocks.
## The bent draw-arm, draw hand, both string halves and the nocked arrow all
## follow the hand, so the whole draw triangle reads as a real shot from any angle.
##
## Human readability comes from filling every joint with a sphere and adding a
## neck, hands, feet and a simple face — but the SKELETON (joint constants) and
## the action maths are unchanged, so motion is identical to before.
##
## Build is self-contained (see _ready); Main just instances this, reads
## bow_tip, and ArcherAim drives it via set_charge()/set_pitch()/release().

# Key joints in the archer's local space (it faces -Z, toward the giant).
const HIP := Vector3(0, 0.85, 0)
const SHOULDER := Vector3(0, 1.32, 0)
const HEAD_P := Vector3(0, 1.58, 0.02)
const BOW_HAND := Vector3(0.10, 1.12, -0.52)    # front hand pushed forward
const DRAW_REST := Vector3(-0.05, 1.40, 0.18)   # rear hand at the cheek (nocked)
const KNEE_F := Vector3(0.16, 0.45, -0.30)
const FOOT_F := Vector3(0.20, 0.0, -0.34)
const KNEE_B := Vector3(-0.14, 0.46, 0.20)
const FOOT_B := Vector3(-0.18, 0.0, 0.42)

# How far past full-draw the hand creeps while charging, and how long the loose
# + re-nock takes. The snap-forward is a small slice of that, the rest is the
# hand drifting back to the rest pose.
const CHARGE_PULL := 0.10        # extra metres drawn back at full charge
const RELEASE_TIME := 0.45       # seconds for the whole loose -> re-nock cycle
const SNAP_FRAC := 0.18          # fraction of RELEASE_TIME spent snapping forward
const LEAN_FACTOR := 0.85        # how much of the aim pitch the torso leans with

var bow_tip: Node3D              # arrow-rest at the bow's centre (arrows spawn here)

# Upper-body pivot at the hip: yawing happens above us, but this node pitches
# the whole torso/arms/bow/head up & down with the aim while the legs stay put.
var _torso: Node3D

# Limbs that depend on the draw hand and get rebuilt every frame it moves.
var _draw_arm: MeshInstance3D
var _draw_hand: MeshInstance3D   # cosmetic hand that rides the draw hand each frame
var _string_up: MeshInstance3D
var _string_lo: MeshInstance3D
var _arrow: MeshInstance3D

# Bow stave tips + key joints, expressed in TORSO-LOCAL space (hip at origin),
# since the dynamic limbs all live under _torso.
var _bow_top: Vector3
var _bow_bot: Vector3
var _sh: Vector3                 # shoulder centre, torso-local
var _r_sh: Vector3               # draw-side shoulder (broad), torso-local
var _bh: Vector3                 # bow hand, torso-local
var _draw_rest: Vector3          # nocked draw hand, torso-local

var _gear: StandardMaterial3D
var _charge := 0.0               # 0..1 current draw charge (from ArcherAim)
var _release_t := -1.0           # >= 0 while the loose animation plays
var _cur_hand := Vector3.ZERO    # last applied draw-hand position (torso-local)


func _ready() -> void:
	position = Vector3(0, 0.4, 0)         # stand on top of the summit blobs
	rotation.y = deg_to_rad(-32.0)        # 3/4 turn so the draw pose reads from behind
	scale = Vector3.ONE * 2.2             # normal human proportions on the summit

	# --- Lord Ram palette (Maryada Purushottam, the divine archer) --------
	var skin := StandardMaterial3D.new()         # traditional shyam (blue) complexion
	skin.albedo_color = Color(0.30, 0.45, 0.72)
	skin.roughness = 0.5
	var gold := StandardMaterial3D.new()         # crown, ornaments, the Kodanda bow
	gold.albedo_color = Color(0.92, 0.72, 0.20)
	gold.metallic = 0.9
	gold.roughness = 0.30
	var cloth := StandardMaterial3D.new()        # saffron dhoti / pitambar
	cloth.albedo_color = Color(0.95, 0.55, 0.12)
	cloth.roughness = 0.85
	var hair := StandardMaterial3D.new()
	hair.albedo_color = Color(0.06, 0.05, 0.06)
	hair.roughness = 1.0
	var string_mat := StandardMaterial3D.new()   # bowstring + sacred thread
	string_mat.albedo_color = Color(0.92, 0.88, 0.72)
	string_mat.roughness = 0.6
	var leather := StandardMaterial3D.new()      # boots, bracers, belt
	leather.albedo_color = Color(0.32, 0.20, 0.10)
	leather.roughness = 0.9
	_gear = gold                                  # bow stave + arrows use gold

	# --- Legs: slim, normal proportions (root space) -----------------------
	_ball(self, skin, HIP, 0.13)                 # pelvis
	_limb(self, skin, HIP, KNEE_F, 0.075)        # front thigh
	_limb(self, skin, HIP, KNEE_B, 0.075)        # back thigh
	_ball(self, skin, KNEE_F, 0.06)              # front knee
	_ball(self, skin, KNEE_B, 0.06)              # back knee
	_limb(self, skin, KNEE_F, FOOT_F, 0.058)     # front shin
	_limb(self, skin, KNEE_B, FOOT_B, 0.058)     # back shin
	# Boots: leather over the lower shin + foot.
	_limb(self, leather, KNEE_F.lerp(FOOT_F, 0.45), FOOT_F, 0.066)
	_limb(self, leather, KNEE_B.lerp(FOOT_B, 0.45), FOOT_B, 0.066)
	_foot(self, leather, FOOT_F)                 # front boot toe
	_foot(self, leather, FOOT_B)                 # back boot toe

	# Dhoti skirt: a flared saffron cloth from the hips down over the thighs.
	# On the root (planted), so it doesn't lean with the upper body.
	var skirt := MeshInstance3D.new()
	var skm := CylinderMesh.new()
	skm.top_radius = 0.17
	skm.bottom_radius = 0.30
	skm.height = 0.42
	skirt.mesh = skm
	skirt.material_override = cloth
	skirt.position = HIP + Vector3(0, -0.16, 0)   # hangs from hip toward the knees
	add_child(skirt)

	# Upper body hangs off a hip pivot so it can pitch up/down with the aim.
	# Everything below is in TORSO-LOCAL space (hip at the origin).
	_torso = Node3D.new()
	_torso.name = "Torso"
	_torso.position = HIP
	add_child(_torso)

	_sh = SHOULDER - HIP
	_bh = BOW_HAND - HIP
	_draw_rest = DRAW_REST - HIP
	_cur_hand = _draw_rest
	var head_l := HEAD_P - HIP
	var l_sh := _sh + Vector3(0.16, 0.02, 0)     # bow-side shoulder
	var r_sh := _sh + Vector3(-0.15, 0.02, 0)    # draw-side shoulder
	_r_sh = r_sh                                  # remembered for the live draw arm

	# --- Torso: a clothed tunic (saffron), normal build, slight taper -------
	var tunic := MeshInstance3D.new()
	var tm2 := CylinderMesh.new()
	tm2.top_radius = 0.135                        # shoulders
	tm2.bottom_radius = 0.16                      # hem at the hip
	tm2.height = 0.50
	tunic.mesh = tm2
	tunic.material_override = cloth
	tunic.position = Vector3(0, 0.22, 0)          # hip(0) up to the shoulders(0.47)
	_torso.add_child(tunic)
	# Bare upper chest / collar above the tunic (skin) so the neck reads.
	_ball(_torso, skin, _sh + Vector3(0, -0.02, 0), 0.13)
	# Leather belt at the waist.
	var belt := MeshInstance3D.new()
	var bem := TorusMesh.new()
	bem.inner_radius = 0.14
	bem.outer_radius = 0.18
	belt.mesh = bem
	belt.material_override = leather
	belt.rotation.x = deg_to_rad(90.0)
	belt.position = Vector3(0, 0.08, 0)
	_torso.add_child(belt)

	# Shoulders (normal deltoids).
	_ball(_torso, skin, l_sh, 0.075)
	_ball(_torso, skin, r_sh, 0.075)

	# --- Bow arm: upper arm + hand, plus a gold armlet (bajuband) -----------
	_limb(_torso, skin, l_sh, _bh, 0.05)
	_ball(_torso, skin, _bh, 0.052)              # bow hand grips the stave
	_ball(_torso, gold, l_sh.lerp(_bh, 0.4), 0.05)
	_ball(_torso, leather, l_sh.lerp(_bh, 0.72), 0.052)   # bracer / forearm guard

	# --- Neck + head -------------------------------------------------------
	var neck_base := _sh + Vector3(0, 0.05, 0)
	var head_base := head_l + Vector3(0, -0.11, 0)
	_ball(_torso, skin, neck_base, 0.058)
	_limb(_torso, skin, neck_base, head_base, 0.05)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.145
	hm.height = 0.31
	head.mesh = hm
	head.material_override = skin
	head.position = head_l
	head.scale = Vector3(0.92, 1.06, 0.96)       # egg-shaped, not a beach ball
	_torso.add_child(head)

	# Hair: dark cap over the back/top of the head.
	var hcap := _ball(_torso, hair, head_l + Vector3(0, 0.04, 0.05), 0.15)
	hcap.scale = Vector3(1.0, 0.82, 1.02)

	# Simple face: a nose ridge and two small dark eyes (archer faces -Z).
	_ball(_torso, skin, head_l + Vector3(0, -0.02, -0.15), 0.028)
	_ball(_torso, hair, head_l + Vector3(0.052, 0.02, -0.135), 0.018)
	_ball(_torso, hair, head_l + Vector3(-0.052, 0.02, -0.135), 0.018)

	# --- Mukut (crown): a gold band + tapered finial, not a party cone ------
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.15
	bm.bottom_radius = 0.16
	bm.height = 0.10
	band.mesh = bm
	band.material_override = gold
	band.position = head_l + Vector3(0, 0.15, 0)
	_torso.add_child(band)

	var finial := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.0
	fm.bottom_radius = 0.085
	fm.height = 0.18
	finial.mesh = fm
	finial.material_override = gold
	finial.position = head_l + Vector3(0, 0.27, 0)
	_torso.add_child(finial)

	# Tilak on the forehead.
	_ball(_torso, _make_color(Color(0.85, 0.10, 0.10)), head_l + Vector3(0, 0.05, -0.145), 0.02)

	# Necklace (haar): a flat gold ring at the collar.
	var neck := MeshInstance3D.new()
	var nm := TorusMesh.new()
	nm.inner_radius = 0.10
	nm.outer_radius = 0.15
	neck.mesh = nm
	neck.material_override = gold
	neck.rotation.x = deg_to_rad(90.0)
	neck.position = _sh + Vector3(0, -0.06, 0)
	_torso.add_child(neck)

	# Sacred thread (janeu) draped from the shoulder across the torso.
	_limb(_torso, string_mat, l_sh, Vector3(-0.10, 0.10, 0), 0.011)

	# Quiver of arrows slung on the back, with shafts poking out.
	var back := Vector3.ZERO.lerp(_sh, 0.7) + Vector3(0, 0, 0.18)
	_limb(_torso, cloth, back + Vector3(0, -0.10, 0), back + Vector3(0.05, 0.42, 0.10), 0.06)
	for i in 3:
		var off := Vector3(-0.035 + i * 0.035, 0.0, 0.0)
		_limb(_torso, _gear, back + Vector3(0, 0.38, 0.08) + off, back + Vector3(0, 0.60, 0.12) + off, 0.01)

	# Cape: a single draped cloth hanging from the shoulders down the back
	# (+Z is behind the archer, who faces -Z). One smooth piece, not planks.
	var cape_mat := StandardMaterial3D.new()
	cape_mat.albedo_color = Color(0.70, 0.16, 0.08)   # deep saffron-red
	cape_mat.roughness = 0.95
	var cape := MeshInstance3D.new()
	var capem := BoxMesh.new()
	capem.size = Vector3(0.34, 0.82, 0.04)
	cape.mesh = capem
	cape.material_override = cape_mat
	cape.position = _sh + Vector3(0, -0.40, 0.17)
	cape.rotation.x = deg_to_rad(7.0)                 # drapes slightly outward at the hem
	_torso.add_child(cape)
	# A small collar clasp where the cape meets the shoulders.
	_ball(_torso, gold, _sh + Vector3(0, 0.0, 0.10), 0.05)

	# Bow stave (the Kodanda): two gold limbs from the grip, drawn into an arc.
	_bow_top = _bh + Vector3(0, 0.62, -0.08)
	_bow_bot = _bh + Vector3(0, -0.62, -0.08)
	_limb(_torso, _gear, _bh, _bow_top, 0.034)
	_limb(_torso, _gear, _bh, _bow_bot, 0.034)
	_ball(_torso, gold, _bow_top, 0.04)          # nock tips
	_ball(_torso, gold, _bow_bot, 0.04)

	# Draw-arm bracer (forearm guard) — static, near the rear elbow/forearm.
	_ball(_torso, leather, _r_sh.lerp(_draw_rest, 0.6), 0.052)

	# Animated limbs: bent draw arm, draw hand, both string halves, nocked arrow.
	# Built once at the rest pose and re-pointed each frame the hand moves.
	_draw_arm = _limb(_torso, skin, _r_sh, _draw_rest, 0.05)
	_draw_hand = _ball(_torso, skin, _draw_rest, 0.052)
	_string_up = _limb(_torso, string_mat, _bow_top, _draw_rest, 0.01)
	_string_lo = _limb(_torso, string_mat, _bow_bot, _draw_rest, 0.01)
	_arrow = _limb(_torso, _gear, _draw_rest, _arrow_tip(_draw_rest), 0.016)

	# Spawn marker at the dead centre of the bow stave (the arrow rest). Parented
	# to the ROOT (yaw only), NOT the leaning torso, so the arrow always releases
	# from the middle of the bow on the aim line — exactly as before the lean.
	bow_tip = Marker3D.new()
	bow_tip.name = "BowTip"
	bow_tip.position = HIP + (_bow_top + _bow_bot) * 0.5
	add_child(bow_tip)


func _process(delta: float) -> void:
	var hand := _draw_rest
	if _release_t >= 0.0:
		_release_t += delta
		var p := _release_t / RELEASE_TIME
		if p >= 1.0:
			_release_t = -1.0          # loose finished; back to charge-driven pose
		else:
			hand = _release_hand(p)
			_apply_hand(hand)
			return

	# Idle / charging: hold full draw, creeping back a touch as charge builds.
	var back := (_draw_rest - _bh).normalized()
	hand = _draw_rest + back * (CHARGE_PULL * _charge)
	_apply_hand(hand)


## Where the draw hand sits at progress p (0..1) through the loose. Snaps forward
## to the bow centre fast, then eases back to the cheek as the archer re-nocks.
func _release_hand(p: float) -> Vector3:
	var loosed := (_bow_top + _bow_bot) * 0.5    # string at rest, hand returns to grip line
	if p < SNAP_FRAC:
		var f := p / SNAP_FRAC                    # 0..1 over the snap
		return _cur_hand.lerp(loosed, f * f)      # ease-in: accelerate into the loose
	var f := (p - SNAP_FRAC) / (1.0 - SNAP_FRAC)  # 0..1 over the re-nock drift
	return loosed.lerp(_draw_rest, f * f * (3.0 - 2.0 * f))   # smoothstep back


## Called by ArcherAim each frame with the current draw charge (0..1).
func set_charge(ratio: float) -> void:
	_charge = clampf(ratio, 0.0, 1.0)


## Called by ArcherAim each frame with the aim pitch (rad, +up). Leans the
## upper body so the archer visibly aims up/down with the shot.
func set_pitch(pitch: float) -> void:
	if _torso:
		_torso.rotation.x = pitch * LEAN_FACTOR


## Called by ArcherAim the instant an arrow is fired. Kicks off the loose.
func release() -> void:
	_release_t = 0.0


# --- internals ------------------------------------------------------------

func _arrow_tip(hand: Vector3) -> Vector3:
	var dir := (_bh - hand).normalized()
	return hand + dir * 1.05


## Re-point the draw-dependent limbs to follow the hand, and hide the nocked
## arrow once it has left (during the forward snap) until it re-nocks.
func _apply_hand(hand: Vector3) -> void:
	_cur_hand = hand
	_point_limb(_draw_arm, _r_sh, hand, 0.05)
	if _draw_hand:
		_draw_hand.position = hand
	_point_limb(_string_up, _bow_top, hand, 0.01)
	_point_limb(_string_lo, _bow_bot, hand, 0.01)

	# The arrow is gone while the string drives forward, back once we re-nock.
	var nocked := _release_t < 0.0 or (_release_t / RELEASE_TIME) > 0.6
	_arrow.visible = nocked
	if nocked:
		_point_limb(_arrow, hand, _arrow_tip(hand), 0.016)


## Build a capsule "bone" between two points (in `parent`'s local space) and
## return it, parented under `parent`.
func _limb(parent: Node3D, mat: Material, a: Vector3, b: Vector3, radius: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	m.mesh = cm
	m.material_override = mat
	parent.add_child(m)
	_point_limb(m, a, b, radius)
	return m


## Build a sphere joint at `pos` (in `parent`'s local space) and return it.
func _ball(parent: Node3D, mat: Material, pos: Vector3, r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	m.mesh = s
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


## Build a flattened box foot at `ankle`, sole on the ground, toes forward (-Z).
func _foot(parent: Node3D, mat: Material, ankle: Vector3) -> void:
	var m := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(0.13, 0.07, 0.28)
	m.mesh = bx
	m.material_override = mat
	m.position = ankle + Vector3(0, 0.035, -0.08)
	parent.add_child(m)


## One-off material for a small accent (tilak, eyes, ...).
func _make_color(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


## Re-orient/resize an existing capsule limb to span a -> b.
func _point_limb(m: MeshInstance3D, a: Vector3, b: Vector3, radius: float) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.001:
		return
	(m.mesh as CapsuleMesh).height = maxf(length, radius * 2.0)
	var yax := dir / length
	var xax := Vector3.RIGHT
	if absf(yax.dot(xax)) > 0.95:
		xax = Vector3.FORWARD
	var zax := xax.cross(yax).normalized()
	xax = yax.cross(zax).normalized()
	m.transform = Transform3D(Basis(xax, yax, zax), (a + b) * 0.5)
