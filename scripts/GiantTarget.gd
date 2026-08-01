extends StaticBody3D
## The Giant target dummy. Built from primitives. Reacts to arrow hits with an
## emission flash + recoil wobble, tracks health on a floating label, and
## topples over when killed.

signal died
signal attacked_tower(dmg: float)   # legacy (unused): kept so old debug paths don't break

const MAX_HEALTH := 800.0

# Approach-to-attack: the monster marches in from far away, stops short of the
# crowd (clustered around origin), then mauls the villagers on a timer until it
# dies. It targets the PEOPLE, not the tower — Rama must hunt it to save them.
const WALK_SPEED := 7.0            # world units/sec — a deliberate, menacing march in
const STOP_DISTANCE := 28.0        # how close (XZ to origin) it gets before attacking
const ATTACK_INTERVAL := 2.2       # seconds between grabs (villagers die slowly, not instantly)
const ATTACK_DMG := 25.0           # (legacy) tower damage per strike
const KILL_PER_HIT := 7            # (legacy) villagers per boulder strike
const ENGAGE_R := 16.0             # villagers within this block its path → stop + maul (walks deeper in first)
const GRAB_COUNT := 5              # villagers seized per attack
const TOWER_DMG := 15.0           # tower health drained per smash (only once all villagers are dead)

# Headshot: arrow hits above this body-LOCAL height (the collision capsule spans
# ~0.5..11.5) count as headshots — much more damage and a bigger blood gush.
const HEAD_LOCAL_Y := 8.5
const HEADSHOT_MULT := 2.6

const TRACK_W := 9.0             # blood-bar width in the giant's local units (×3.6 in world)
const BAR_H := 0.9

# Monster roar: shouts only occasionally — once per N of Rama's arrows, and never
# more often than the cooldown (so rapid fire can't spam it). Death roars bypass it.
const ROAR_EVERY_N_HITS := 4
const ROAR_COOLDOWN_MS := 1800

# The downloaded monster concept model (rigged ogre w/ an "Idle" anim). It replaces
# the old primitive-sculpted body; all behaviour (health bar, boulder, approach,
# flash, recoil, topple) is unchanged — only the visible body mesh swaps in.
const MonsterScene := preload("res://assets/monster_concept.glb")
const MONSTER_SCALE := 84.0      # GLB imports tiny; scale so the head sits ~y10, leaving the boulder (y13) hoisted clearly overhead
const MONSTER_FACE_Y := 0.0      # model already faces +Z (toward the tower) — no yaw fix needed

var max_health := MAX_HEALTH      # set per-monster by Main (200 / 400 / 800)
var health := MAX_HEALTH
# Small monster: hit-COUNT design (independent of arrow draw strength) — a HEAD shot
# is an instant kill, a BODY shot needs two. Set by Main for the small skirmishers.
var small := false
var _body_hits := 0
var crowd: Node                   # the villagers this monster mauls (set by Main)
var _dead := false
var _mat: StandardMaterial3D
var _label: Label3D
var _health_bar: Node3D          # billboarded pivot holding the blood bar
var _fill_mi: MeshInstance3D     # the red fill quad (left-anchored, drains with health)
var _fill_quad: QuadMesh
var _fill_mat: StandardMaterial3D
var _flash_tween: Tween
var _recoil_tween: Tween
var _body: Node3D                 # the imported monster model
var _flash_overlay: StandardMaterial3D   # additive glow laid over the body for hit flashes
var _arrived := false             # reached attack range?
var _active := false              # only march/attack once gameplay actually starts
var _attack_timer := ATTACK_INTERVAL
var _walk_phase := 0.0
var _base_y := 0.0
var _lunge_tween: Tween
var _boulder: Node3D              # the hoisted stone — slammed at the tower to attack
var _boulder_home: Vector3       # its rest position (overhead)
var _smash_tween: Tween
var _grab_tween: Tween
var _blood: GPUParticles3D        # blood spray, restarted at each arrow's impact point
var _blood_timer := 0.0           # keeps the spray alive briefly after the last hit
var _ram_hits := 0                # count of Rama's arrows landed (drives the occasional roar)
var _last_roar_ms := -100000      # cooldown clock for pain roars


func _ready() -> void:
	collision_layer = 1          # arrows (Area mask 1) detect this
	collision_mask = 0
	_base_y = position.y
	_build()
	_update_health_ui()


func _process(delta: float) -> void:
	_billboard_bar()
	# Let the blood spray die out shortly after the last hit lands.
	if _blood and _blood.emitting:
		_blood_timer -= delta
		if _blood_timer <= 0.0:
			_blood.emitting = false
	if _dead:
		return
	# Stay far away (a distant silhouette) until gameplay begins; only then march
	# in toward the tower. Without this gate the giant walks in during the welcome
	# card + intro cinematic and is already on top of the tower at first play.
	if not _active:
		return
	_approach_and_attack(delta)


## Called by Main when gameplay actually starts (after the welcome card + intro).
## Releases the giant to begin its long march in from the horizon.
func begin() -> void:
	_active = true


## Billboard the blood bar to the active camera. We copy the camera's orientation
## (so track + fill share one camera-facing frame and never drift apart) and
## re-apply the giant's world scale so the bar keeps its size.
func _billboard_bar() -> void:
	if _health_bar == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var s := global_transform.basis.get_scale()
	var b := cam.global_transform.basis.orthonormalized().scaled(s)
	_health_bar.global_transform = Transform3D(b, _health_bar.global_position)


## March toward the tower (origin). The TOWER IS UNTOUCHABLE while any villager lives:
## the monster grinds through the people first (mauling whoever blocks it, then picking
## off stragglers). ONLY once every villager is dead does it close on the tower and
## tear it down.
func _approach_and_attack(delta: float) -> void:
	var to_tower := Vector3(-global_position.x, 0.0, -global_position.z)
	var dist := to_tower.length()
	var people_left := 0
	if crowd and is_instance_valid(crowd):
		people_left = crowd.call("alive")

	if people_left <= 0:
		# Every villager is dead — now come close and destroy the tower.
		if dist > STOP_DISTANCE:
			_march(to_tower, delta)
		else:
			position.y = _base_y
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				_attack_timer = ATTACK_INTERVAL
				_smash_tower()
		return

	# Villagers still alive — the tower is safe. HUNT the crowd: stalk toward the nearest
	# person (wherever they are — not a blind beeline at the tower) and maul any within reach.
	var blocked: int = crowd.call("living_near", global_position, ENGAGE_R)
	if blocked > 0:
		# Villagers within reach — hold ground and grab them by the fistful.
		position.y = _base_y
		_face_toward(crowd.call("nearest_living", global_position), delta)
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = ATTACK_INTERVAL
			_grab_and_throw()
	else:
		# Nobody in reach — walk toward the nearest villager, not the tower.
		var target: Vector3 = crowd.call("nearest_living", global_position)
		var to_prey := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
		if to_prey.length() > ENGAGE_R * 0.6:
			_march(to_prey, delta)
		else:
			# Standing among them — plant and start swinging.
			position.y = _base_y
			_face_toward(target, delta)
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				_attack_timer = ATTACK_INTERVAL
				_grab_and_throw()


## Walk one step in `dir` (toward the tower, or toward the villagers it's hunting) with a
## heavy march bob + ground-shaking footfalls, turning to face where it's walking.
func _march(dir: Vector3, delta: float) -> void:
	_face_toward(global_position + dir, delta)
	global_position += dir.normalized() * WALK_SPEED * delta
	var prev := _walk_phase
	_walk_phase += delta * 4.2          # a heavier, smoother gait
	position.y = _base_y + absf(sin(_walk_phase)) * 0.7
	if floori(prev / PI) != floori(_walk_phase / PI):
		_footfall()


## Smoothly yaw the whole monster so its forward (+Z) turns to face `target` (XZ only).
## Used both while stalking and while planted mauling, so it always faces its prey.
func _face_toward(target: Vector3, delta: float) -> void:
	var dx := target.x - global_position.x
	var dz := target.z - global_position.z
	if absf(dx) < 0.001 and absf(dz) < 0.001:
		return
	var want := atan2(dx, dz) + deg_to_rad(MONSTER_FACE_Y)
	rotation.y = lerp_angle(rotation.y, want, clampf(delta * 4.0, 0.0, 1.0))


## A footstep lands: shake the camera proportional to how close this monster is (the
## ground trembles harder as it looms in). The rig smooths it into a soft vibration.
func _footfall() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rig := cam.get_parent()
	if rig and rig.has_method("add_shake"):
		var d := global_position.distance_to(cam.global_position)
		var amt := clampf(remap(d, 130.0, 18.0, 0.0, 0.16), 0.0, 0.16)
		if amt > 0.0:
			rig.call("add_shake", amt)


## A full attacking move: the monster rears back, then LUNGES and SLAMS down to maul
## the villagers (reaching to the ground), gives a swipe twist, and recovers. The grab
## (and casualty count) lands exactly on the slam so the strike reads as the kill. The
## motion drives `_body` — `self`'s Y is reset every frame by the walk logic, so tweening
## the model node instead keeps the animation from being stomped.
func _grab_and_throw() -> void:
	_attack_lunge(_do_grab)


## The same attacking move used to smash the tower once the villagers are all gone.
func _smash_tower() -> void:
	_attack_lunge(_do_tower)


## The shared attack animation: rear back → lunge + SLAM down → swipe → recover, with
## the impact callback (maul villagers / smash tower) firing exactly on the slam.
func _attack_lunge(impact: Callable) -> void:
	if _dead or _body == null:
		return
	if _grab_tween and _grab_tween.is_running():
		_grab_tween.kill()
	_grab_tween = create_tween()
	# 1) Wind up — rear back and rise.
	_grab_tween.tween_property(_body, "rotation:x", -0.32, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_grab_tween.parallel().tween_property(_body, "position:y", 0.9, 0.24).set_trans(Tween.TRANS_SINE)
	# 2) SLAM — lunge forward and bend down hard.
	_grab_tween.tween_property(_body, "rotation:x", 0.72, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_grab_tween.parallel().tween_property(_body, "position:z", 1.3, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_grab_tween.parallel().tween_property(_body, "position:y", 0.0, 0.14)
	# Impact: hurl villagers / strike the tower + thump the ground exactly on the slam.
	_grab_tween.tween_callback(impact)
	# 3) Swipe twist to sell the blow.
	_grab_tween.tween_property(_body, "rotation:y", 0.38, 0.12).set_trans(Tween.TRANS_SINE)
	_grab_tween.tween_property(_body, "rotation:y", 0.0, 0.18).set_trans(Tween.TRANS_SINE)
	# 4) Recover to a neutral stance.
	_grab_tween.tween_property(_body, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_grab_tween.parallel().tween_property(_body, "position:z", 0.0, 0.3).set_trans(Tween.TRANS_SINE)


## The slam connects on the people: seize + hurl a fistful of villagers, shake the ground.
func _do_grab() -> void:
	if _dead:
		return
	if crowd and is_instance_valid(crowd):
		crowd.call("throw", GRAB_COUNT, global_position)
	_footfall()


## The slam connects on the TOWER (only reached after all villagers are dead): deal
## tower damage (Main drains the tower's health → collapse) and shake the ground hard.
func _do_tower() -> void:
	if _dead:
		return
	attacked_tower.emit(TOWER_DMG)
	_footfall()


## The giant heaves the boulder up, then SLAMS it down toward the tower. The
## damage lands at the moment of impact (he never touches Rama — only the stone
## reaches the tower). Tower collapse is triggered by these strikes.
func _boulder_smash() -> void:
	if _boulder == null:
		_strike_crowd()
		return
	if _smash_tween and _smash_tween.is_running():
		_smash_tween.kill()
	var home := _boulder_home
	var raised := home + Vector3(0.0, 2.0, -1.5)      # heave up & back (anticipation)
	# Forward ~8 and down ~6.5 (local; ×3.6 world) lands the stone at the tower top.
	var impact := home + Vector3(0.0, -10.0, 8.0)     # drive forward + down into the people
	_smash_tween = create_tween()
	_smash_tween.tween_property(_boulder, "position", raised, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_smash_tween.tween_property(_boulder, "position", impact, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	# Impact: deal the damage to the tower exactly when the stone lands.
	_smash_tween.tween_callback(_strike_crowd)
	# A short body heave forward synced with the slam.
	var z0 := position.z
	if _lunge_tween and _lunge_tween.is_running():
		_lunge_tween.kill()
	_lunge_tween = create_tween()
	_lunge_tween.tween_property(self, "position:z", z0 + 2.0, 0.34)
	_lunge_tween.tween_property(self, "position:z", z0, 0.3)
	# Recover: haul the stone back overhead for the next blow.
	_smash_tween.tween_property(_boulder, "position", home, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Maul the villagers at the moment the boulder lands.
func _strike_crowd() -> void:
	if _dead:
		return
	if crowd and is_instance_valid(crowd):
		crowd.call("attack", KILL_PER_HIT)


func take_hit(dmg: float, _point: Vector3) -> void:
	if _dead:
		return
	# Headshot: hits high on the body deal far more damage and gush far more blood.
	var lp := to_local(_point)
	var headshot := lp.y >= HEAD_LOCAL_Y

	# Small skirmishers: deterministic hit-count kill — head = one shot, body = two,
	# regardless of how hard the bow was drawn.
	if small:
		if headshot:
			health = 0.0
		else:
			_body_hits += 1
			health = maxf(0.0, max_health * (1.0 - float(_body_hits) / 2.0))
		_flash()
		_recoil()
		_spurt(lp, 0.5 if headshot else 0.18)
		_update_health_ui()
		_try_roar(false)
		if health <= 0.0:
			_die()
		return

	var final_dmg := dmg * (HEADSHOT_MULT if headshot else 1.0)
	health = maxf(0.0, health - final_dmg)
	_flash()
	_recoil()
	_spurt(lp, 0.4 if headshot else 0.12)
	_update_health_ui()
	# Occasional pain roar as Rama's arrows pile up (villager volleys don't count —
	# they go through take_hit_silent). Gated by count AND a cooldown.
	_ram_hits += 1
	if _ram_hits % ROAR_EVERY_N_HITS == 0:
		_try_roar(false)
	if health <= 0.0:
		_die()


## Roar, respecting the cooldown for pain roars. Death roars (deep) always play.
func _try_roar(deep: bool) -> void:
	if not deep:
		var now := Time.get_ticks_msec()
		if now - _last_roar_ms < ROAR_COOLDOWN_MS:
			return
		_last_roar_ms = now
	Audio.play_monster_roar(deep)


## Lightweight damage from the villagers' arrow volleys. Hundreds of these land per
## second, so it skips the per-hit flash/recoil tweens — just drains health + UI.
func take_hit_silent(dmg: float) -> void:
	if _dead:
		return
	# Nimble small monsters shrug off the villagers' volleys — only Rama's aimed
	# arrows fell them, so the head/body shot design stays intact.
	if small:
		return
	health = maxf(0.0, health - dmg)
	# Blood at a random spot on the body mass (these arrows carry no impact point).
	_spurt(Vector3(randf_range(-2.0, 2.0), randf_range(4.0, 9.0), randf_range(-2.5, -0.5)))
	_update_health_ui()
	if health <= 0.0:
		_die()


## Alive iff still has health and hasn't toppled (read by the crowd for targeting).
func is_alive() -> bool:
	return not _dead and health > 0.0


## Engaged = released for gameplay AND still alive. The crowd only charges/shoots
## once the monster is on the move (so villagers don't sprint off during the intro).
func is_engaged() -> bool:
	return _active and not _dead and health > 0.0


func _flash() -> void:
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()
	_mat.emission_energy_multiplier = 4.0          # flashes the boulder
	if _flash_overlay:
		_flash_overlay.albedo_color.a = 0.7        # flashes the body
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	_flash_tween.tween_property(_mat, "emission_energy_multiplier", 0.0, 0.35)
	if _flash_overlay:
		_flash_tween.tween_property(_flash_overlay, "albedo_color:a", 0.0, 0.35)


func _recoil() -> void:
	if _recoil_tween and _recoil_tween.is_running():
		_recoil_tween.kill()
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(self, "rotation:x", -0.12, 0.06)
	_recoil_tween.tween_property(self, "rotation:x", 0.0, 0.25)


func _die() -> void:
	_dead = true
	Audio.play_monster_death()       # sewer-beast death cry (first 3s) on every fall
	if _health_bar:
		_health_bar.visible = false
	if _label:
		_label.visible = false
	_mat.albedo_color = Color(0.35, 0.35, 0.38)
	var t := create_tween()
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(self, "rotation:z", PI / 2.0, 1.1)
	# Emit `died` only AFTER the topple finishes, so the monster is fully fallen (flat on
	# the ground) by the time Main reacts. For the LAST monster this guarantees the Rama
	# victory close-up only starts once it has completely fallen, not mid-topple.
	t.tween_callback(died.emit)


func _update_health_ui() -> void:
	var frac := clampf(health / max_health, 0.0, 1.0)
	if _label:
		_label.text = "MONSTER  %d / %d" % [int(health), int(max_health)]
		_label.modulate = Color(1.0, 0.3 + 0.6 * frac, 0.3 + 0.5 * frac)
	# Drain the blood fill from the left edge; darken it as it empties.
	if _fill_quad and _fill_mi:
		_fill_quad.size = Vector2(maxf(0.0001, TRACK_W * frac), BAR_H)
		_fill_mi.position = Vector3(-TRACK_W * 0.5 + TRACK_W * frac * 0.5, 0.0, 0.02)
		_fill_mi.visible = frac > 0.0
	if _fill_mat:
		_fill_mat.albedo_color = Color(0.85, 0.06 + 0.10 * frac, 0.05 + 0.06 * frac)


func _build() -> void:
	# Dark, near-black so it reads as a backlit SILHOUETTE against the sunset.
	# Emission stays (energy 0 at rest) so hits still flash bright.
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.07, 0.06, 0.05)
	_mat.roughness = 1.0
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.3, 0.12)
	_mat.emission_energy_multiplier = 0.0

	# --- The monster body: the downloaded concept model (rigged ogre). It replaces
	# the old primitive sculpture but keeps the same footprint so the boulder,
	# collision, and health bar below still line up. The model already faces +Z
	# (toward the tower), so it needs no yaw fix.
	_body = MonsterScene.instantiate()
	_body.scale = Vector3.ONE * MONSTER_SCALE
	_body.rotation_degrees = Vector3(0, MONSTER_FACE_Y, 0)
	_body.position = Vector3(0, 0, 0)          # feet on the ground (model origin is at the feet)
	add_child(_body)

	# Show the monster in its ORIGINAL model colours regardless of the backlit sun
	# (no more dark silhouette) — force every body surface unshaded so it looks the
	# same in the normal view and through the scope.
	_force_unshaded(_body)

	# Lay an additive warm overlay over every body surface so arrow hits still flash
	# the monster bright (the old flash drove _mat's emission; the GLB has its own
	# textures, so we glow it from on top without touching its materials).
	_flash_overlay = StandardMaterial3D.new()
	_flash_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_overlay.albedo_color = Color(1.0, 0.35, 0.12, 0.0)   # alpha 0 = invisible at rest
	for mi in _collect_meshes(_body):
		mi.material_overlay = _flash_overlay

	# Bring him to life: loop the bundled idle so he breathes while marching.
	var ap := _find_anim_player(_body)
	if ap and ap.has_animation("Idle"):
		ap.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
		ap.play("Idle")

	# Rough boulder hoisted overhead (several jagged boxes), grouped under a pivot
	# so it can be SLAMMED down toward the tower on each attack.
	var rock_centre := Vector3(0, 13.0, 0.4)
	_boulder = Node3D.new()
	_boulder.position = rock_centre
	_boulder.visible = false          # monster now attacks with its hands, not the rock
	add_child(_boulder)
	_boulder_home = rock_centre
	var chunks := [
		[Vector3(4.6, 2.0, 3.0), Vector3(0.1, 0.2, 0.06)],
		[Vector3(3.6, 2.6, 3.6), Vector3(0.3, 0.7, 0.2)],
		[Vector3(4.2, 1.8, 2.6), Vector3(-0.15, 1.2, -0.1)],
	]
	for c in chunks:
		var rk := MeshInstance3D.new()
		var rkm := BoxMesh.new()
		rkm.size = c[0]
		rk.mesh = rkm
		rk.material_override = _mat
		rk.rotation = c[1]
		rk.position = Vector3.ZERO
		_boulder.add_child(rk)

	# Collision (covers the body mass for arrow hits)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 2.4
	cap.height = 11.0
	col.shape = cap
	col.position = Vector3(0, 6.0, 0.2)
	add_child(col)

	# Floating health numbers (just above the blood bar)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = false
	_label.pixel_size = 0.018
	_label.font_size = 56
	_label.outline_size = 12
	# Kept LOW (near the head, not floating high overhead) so it stays inside the
	# zoomed scope view when you sight the monster. no_depth_test keeps it on top.
	_label.position = Vector3(0, 11.6, 0)
	add_child(_label)

	# Floating blood bar (billboarded each frame in _process). A dark track with
	# a bright-red fill that drains from the left as the giant loses health. Kept low
	# (just over the head) so it's visible through the scope, not way above the frame.
	_health_bar = Node3D.new()
	_health_bar.position = Vector3(0, 10.5, 0)
	add_child(_health_bar)

	var track_mat := StandardMaterial3D.new()
	track_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	track_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	track_mat.no_depth_test = true
	track_mat.albedo_color = Color(0.05, 0.02, 0.02, 0.75)
	var track_mi := MeshInstance3D.new()
	var track_quad := QuadMesh.new()
	track_quad.size = Vector2(TRACK_W, BAR_H)
	track_mi.mesh = track_quad
	track_mi.material_override = track_mat
	_health_bar.add_child(track_mi)

	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.no_depth_test = true
	_fill_mat.albedo_color = Color(0.85, 0.16, 0.11)
	_fill_mi = MeshInstance3D.new()
	_fill_quad = QuadMesh.new()
	_fill_quad.size = Vector2(TRACK_W, BAR_H)
	_fill_mi.mesh = _fill_quad
	_fill_mi.material_override = _fill_mat
	_fill_mi.position = Vector3(0, 0, 0.02)
	_health_bar.add_child(_fill_mi)

	_build_blood()


## A reusable blood spray. One emitter per monster (cheap): each arrow hit moves it to
## the impact point and (re)starts it, so under the villagers' volley it sprays steadily.
func _build_blood() -> void:
	_blood = GPUParticles3D.new()
	_blood.amount = 48
	_blood.lifetime = 0.7
	_blood.one_shot = false
	_blood.local_coords = false
	_blood.emitting = false
	# Cancel the monster's world scale so the droplet sizes/speeds stay in world units.
	_blood.scale = Vector3.ONE / maxf(0.001, scale.x)

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.35, 1)           # spray outward/up from the wound
	pm.spread = 55.0
	pm.flatness = 0.0
	pm.gravity = Vector3(0, -19.0, 0)
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 8.5
	# Air drag so fast droplets decelerate — the spray fans out then hangs, like a real splash.
	pm.damping_min = 2.0
	pm.damping_max = 5.0
	# Break the cone into scattered droplets instead of a uniform fan.
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 3.0
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.4
	# Wide size range: a few fat gouts among many fine droplets reads as a natural burst.
	pm.scale_min = 0.05
	pm.scale_max = 0.28
	# Droplets swell an instant then shrink as they thin out in flight.
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.65))
	sc.add_point(Vector2(0.15, 1.0))
	sc.add_point(Vector2(1.0, 0.35))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	# Bright arterial core -> darkening maroon -> fade out.
	var grad := Gradient.new()
	grad.add_point(0.0, Color(0.85, 0.06, 0.03, 1.0))
	grad.add_point(0.35, Color(0.55, 0.02, 0.01, 1.0))
	grad.add_point(1.0, Color(0.22, 0.0, 0.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	# Hold opacity through flight, then fade late so droplets don't vanish mid-air.
	var ac := Curve.new()
	ac.add_point(Vector2(0.0, 1.0))
	ac.add_point(Vector2(0.7, 1.0))
	ac.add_point(Vector2(1.0, 0.0))
	var act := CurveTexture.new()
	act.curve = ac
	pm.alpha_curve = act
	_blood.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	bmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	bmat.vertex_color_use_as_albedo = true
	bmat.albedo_color = Color(0.7, 0.0, 0.0)
	# Round, soft-edged droplet instead of a hard square quad.
	bmat.albedo_texture = _make_droplet_texture()
	quad.material = bmat
	_blood.draw_pass_1 = quad
	add_child(_blood)


## A radial droplet: opaque red core fading to a soft transparent rim, so each billboard
## reads as a rounded blob of blood rather than a flat square.
func _make_droplet_texture() -> ImageTexture:
	var size := 48
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c   # 0 at centre, 1 at edge
			# Soft falloff, held solid through the core then feathered to the rim.
			var a := clampf(1.0 - smoothstep(0.55, 1.0, d), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Spray blood at a body-local point (restart the shared emitter there). A longer
## `dur` keeps it spraying — used to gush more blood on a headshot.
func _spurt(local_point: Vector3, dur: float = 0.12) -> void:
	if _blood == null or _dead:
		return
	_blood.position = local_point
	_blood.emitting = true
	_blood_timer = maxf(_blood_timer, dur)


## Force every body surface to render unshaded (true texture colour, no lighting), so
## the monster never darkens into a silhouette under the sun or in the scope view.
func _force_unshaded(n: Node) -> void:
	for mi in _collect_meshes(n):
		var inst := mi as MeshInstance3D
		if inst == null or inst.mesh == null:
			continue
		for s in inst.mesh.get_surface_count():
			var mat: Material = inst.get_active_material(s)
			if mat is BaseMaterial3D:
				var d: BaseMaterial3D = (mat as BaseMaterial3D).duplicate()
				d.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				inst.set_surface_override_material(s, d)


## Every MeshInstance3D under a node (so the flash overlay covers the whole body).
func _collect_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_collect_meshes(c))
	return out


## The first AnimationPlayer under a node (the GLB's idle clip lives on one).
func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_anim_player(c)
		if found:
			return found
	return null
