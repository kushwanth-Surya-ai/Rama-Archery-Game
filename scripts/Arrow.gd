extends RigidBody3D
## Ballistic arrow. Built entirely from primitives in _ready(); launched by
## ArcherAim via launch(). Detection uses a child Area3D (mask = world/targets
## only) so the arrow never sticks to the tower it was fired from.

const ARROW_SCALE := 2.6     # overall size multiplier for a big, dramatic arrow

var damage := 10.0
var _life := 10.0                     # stray-arrow safety: only frees shots that never hit anything
var _stuck := false
var _model: Node3D
var _glow: OmniLight3D                # in-flight glow; switched off once the arrow comes to rest
var _last_dir := Vector3.FORWARD     # cached flight heading, used to set the stuck angle


func _ready() -> void:
	# Real projectile flight: full gravity so the arrow follows a true parabolic
	# arc (rises, slows, drops) like an actual loosed arrow, plus a touch of air
	# drag. Speed is set by the bow's draw at launch (see ArcherAim) — aim a hair
	# high for distance, exactly like real archery.
	gravity_scale = 1.0
	linear_damp = 0.03          # subtle air resistance; bleeds a little speed in flight
	mass = 0.1
	collision_layer = 0          # arrow body collides with nothing in flight
	collision_mask = 0           # (hit detection is done by the Area3D below)
	can_sleep = false

	# Procedural arrow that clearly reads as an arrow (shaft + cone head +
	# fletching), pointing along -Z (our "forward").
	_model = Node3D.new()
	add_child(_model)
	var arrow_vis := _make_arrow()
	arrow_vis.scale = Vector3.ONE * ARROW_SCALE
	_model.add_child(arrow_vis)

	# A warm glow so the arrow reads dramatically in flight (switched off on rest
	# so persisted arrows don't pile up dynamic lights).
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.6, 0.25)
	_glow.light_energy = 2.5
	_glow.omni_range = 5.0
	_model.add_child(_glow)

	var area := Area3D.new()
	area.collision_mask = 1              # ground + targets live on layer 1
	var acol := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	acol.shape = sph
	area.add_child(acol)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func launch(vel: Vector3, dmg: float, flat: bool = false) -> void:
	damage = dmg
	# A scoped precision shot flies DEAD STRAIGHT (no gravity/drag) so it lands exactly
	# on the scope crosshair; normal shots keep their realistic ballistic arc.
	if flat:
		gravity_scale = 0.0
		linear_damp = 0.0
	linear_velocity = vel
	if vel.length() > 0.1:
		_last_dir = vel.normalized()


func _physics_process(delta: float) -> void:
	if _stuck:
		return
	# Safety net only: a shot that sails off and never strikes anything is freed
	# so strays don't pile up. Arrows that land stick and persist (see _embed_into).
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# Orient the visual model along the velocity arc; the nose pitches down for free
	# as velocity.y goes negative on descent. (Body itself stays unrotated.)
	if _model and linear_velocity.length() > 0.1:
		_last_dir = linear_velocity.normalized()
		_model.look_at(_model.global_position + linear_velocity, _safe_up(_last_dir))


## A clear arrow built from primitives, forward = -Z. Shaft + conical steel head
## + three fletching vanes, so it reads as an arrow (not a thin line) at any size.
func _make_arrow() -> Node3D:
	var root := Node3D.new()

	# Emissive materials so the arrow shows its true colours even when strongly
	# backlit by the sun (otherwise it reads as a black silhouette).
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.34, 0.16)
	wood.roughness = 1.0
	wood.emission_enabled = true
	wood.emission = Color(0.55, 0.32, 0.14)
	wood.emission_energy_multiplier = 1.1
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.74, 0.8)
	steel.metallic = 0.5
	steel.roughness = 0.35
	steel.emission_enabled = true
	steel.emission = Color(0.5, 0.52, 0.6)
	steel.emission_energy_multiplier = 0.9
	var feather := StandardMaterial3D.new()
	feather.albedo_color = Color(0.95, 0.45, 0.18)
	feather.roughness = 1.0
	feather.emission_enabled = true
	feather.emission = Color(0.95, 0.42, 0.15)
	feather.emission_energy_multiplier = 1.4

	# shaft (CylinderMesh is along +Y; rotate so its length lies along Z)
	var shaft := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.045
	sc.bottom_radius = 0.045
	sc.height = 1.4
	sc.radial_segments = 8
	shaft.mesh = sc
	shaft.material_override = wood
	shaft.rotation.x = -PI / 2          # length now along Z (top -> -Z)
	root.add_child(shaft)

	# conical head at the front (-Z)
	var head := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = 0.0
	hc.bottom_radius = 0.13
	hc.height = 0.36
	hc.radial_segments = 8
	head.mesh = hc
	head.material_override = steel
	head.rotation.x = -PI / 2           # tip points -Z
	head.position = Vector3(0, 0, -(0.7 + 0.18))
	root.add_child(head)

	# three fletching vanes at the back (+Z)
	for i in range(3):
		var vane := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.015, 0.20, 0.30)
		vane.mesh = bm
		vane.material_override = feather
		vane.rotation.z = deg_to_rad(120.0 * i)
		vane.position = Vector3(0, 0, 0.52)
		vane.translate_object_local(Vector3(0, 0.11, 0))   # push out radially
		root.add_child(vane)

	return root


## Pick an up vector that isn't parallel to dir, so look_at / looking_at never NaN
## on near-vertical lob shots.
func _safe_up(dir: Vector3) -> Vector3:
	return Vector3.FORWARD if absf(dir.dot(Vector3.UP)) > 0.99 else Vector3.UP


func _on_body_entered(body: Node) -> void:
	if _stuck or body == self:
		return
	if body.has_method("take_hit"):
		body.take_hit(damage, global_position)
		Audio.play_arrow_flash()     # bright arrow-flash zip on the monster (no drum thud)
	_stuck = true
	if _glow:
		_glow.visible = false        # stop persisted arrows from accumulating dynamic lights
	# Freeze the body carrying the impact angle, and reparent it so it embeds into
	# the surface and rides the target (e.g. the Giant as it topples).
	var aligned := Basis.looking_at(_last_dir, _safe_up(_last_dir))   # model -Z faces flight dir
	var embed_pos := global_position + _last_dir * 0.35              # sink the tip into the surface
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	_model.transform = Transform3D.IDENTITY                         # body now carries the angle
	call_deferred("_embed_into", body, Transform3D(aligned, embed_pos))


func _embed_into(body: Node, xform: Transform3D) -> void:
	var p := get_parent()
	if p:
		p.remove_child(self)
	body.add_child(self)
	global_transform = xform        # preserve world pose, now relative to the hit body
	# No despawn: the arrow stays embedded for good — sticking in the body or the
	# ground just like a real arrow, instead of fading out after a few seconds.
