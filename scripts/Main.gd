extends Node3D
## Builds the entire prototype world in code and wires the component scripts
## together. Cross-references are set BEFORE nodes enter the tree so each
## script's _ready() sees its dependencies.

const SEGMENT_COUNT := 26

const TowerControllerScript := preload("res://scripts/TowerController.gd")
const MonkeyConeScript := preload("res://scripts/MonkeyCone.gd")
const ArcherAimScript := preload("res://scripts/ArcherAim.gd")
const PosedArcherScript := preload("res://scripts/PosedArcher.gd")
const RamArcherScript := preload("res://scripts/RamArcher.gd")
const ArcherFxScript := preload("res://scripts/ArcherFx.gd")
const CameraRigScript := preload("res://scripts/CameraRig.gd")
const ScopeCameraScript := preload("res://scripts/ScopeCamera.gd")
const IntroCinematicScript := preload("res://scripts/IntroCinematic.gd")
const ForestPreludeScript := preload("res://scripts/ForestPrelude.gd")
const GiantTargetScript := preload("res://scripts/GiantTarget.gd")
const CrowdScript := preload("res://scripts/Crowd.gd")
const HudScript := preload("res://scripts/ui/Hud.gd")
const ReticleScript := preload("res://scripts/ui/Reticle.gd")
const ScopeOverlayScript := preload("res://scripts/ui/ScopeOverlay.gd")
const WinScreenScript := preload("res://scripts/ui/WinScreen.gd")
const GameOverScreenScript := preload("res://scripts/ui/GameOverScreen.gd")
const StatBarScript := preload("res://scripts/ui/StatBar.gd")
const WelcomeCardScript := preload("res://scripts/ui/WelcomeCard.gd")
const ArrowModelScene := preload("res://assets/weapons/arrow.glb")
const ArcherModelScene := preload("res://assets/bhagwan_shri_ram.glb")
const HanumanScene := preload("res://assets/lord-hanuman/source/model.glb")
const ForestScene := preload("res://assets/forest/source/Forest.glb")
const HANUMAN_SCALE := 6.0
const HANUMAN_LEAN := 18.0      # forward lean (deg) so he reads as flying

# Rama's tower has its own health: the giant marches in and pounds it; if it
# empties before the giant dies, the tower collapses and Hanuman rescues Rama.
const TOWER_MAX_HEALTH := 100.0
const GIANT_START := Vector3(2, 0, -165)   # giant spawns on the far horizon and marches in after play starts

# Three monsters hunt the villagers. Each entry: [max HP, world scale, spawn pos on
# the horizon]. The weakest is smallest, the boss (800) is the towering silhouette.
const MONSTERS := [
	[200.0, 2.6, Vector3(-46, 0, -150)],
	[400.0, 3.1, Vector3(48, 0, -150)],
	[800.0, 3.6, Vector3(2, 0, -168)],
	# Two SMALL skirmishers. [health, scale, pos, small=true]: health 2 = two body
	# hits; a head shot one-shots them (see GiantTarget.small). Villager volleys don't
	# touch them — only Rama's aimed arrows. Scale 1.6 = visibly smaller + faster reads.
	[2.0, 1.6, Vector3(-22, 0, -134), true],
	[2.0, 1.6, Vector3(26, 0, -136), true],
]
const CROWD_SIZE := 1000

# Player model placement (tunable). The Lord Ram GLB is a static (non-rigged)
# mesh ~1.74 units tall; scale it up onto the cone summit and lift the feet to 0.
# RIGGED route (takes precedence): a real skinned+animated archer (KayKit
# Barbarian) tinted toward Ram — keeps the bow draw/aim/loose ACTIONS alive.
const USE_RIGGED_ARCHER := false  # rigged Barbarian is a cartoon mismatch; the static Lord Ram.glb is the reference look
const USE_FBX_ARCHER := true    # false = posed primitive draw-pose; true = imported Lord Ram GLB
const ARCHER_SCALE := 1.7                          # (legacy) fixed scale — unused now we auto-fit by height
const ARCHER_TARGET_HEIGHT := 6.0                  # world-units tall on the summit; model is rescaled to this
const ARCHER_ROT := Vector3(0.0, 180.0, 0.0)      # face -Z (toward the giant)
const ARCHER_POS := Vector3(0.0, 0.4, 0.0)        # feet on the summit (origin is at the feet)
# Where Ram's arrow leaves the bow, as a FRACTION of ARCHER_TARGET_HEIGHT so it
# tracks the grip no matter how tall he is scaled. Holder space: feet at origin,
# -Z forward (toward the giant), +X is his bow-hand side. Multiplied by height
# below. It hangs off the unscaled holder so it's immune to the auto-fit scale.
const ARCHER_BOW_TIP := Vector3(-0.10, 0.68, -0.18)

var _aim: Node3D
var _muzzle: Node3D
var _bow_tip: Node3D            # exact arrow-exit point on the bow (arrows spawn here)
var _archer: Node3D            # posed archer body, animated on each release
var _win_screen: Control
var _game_over: Control         # defeat overlay (tower collapses)
var _game_cam: Camera3D         # gameplay camera (re-activated after the intro)
var _scope_cam: Camera3D        # first-person scope camera (active while scoping)
var _hud_layer: CanvasLayer     # whole HUD overlay (hidden during the intro)
var _tower: Node3D              # the monkey tower (collapses on defeat)
var _archer_body: Node3D        # Rama's visible body (reparented to Hanuman on defeat)
var _tower_health := TOWER_MAX_HEALTH
var _tower_bar: Control         # top-of-screen bar: villager count, then tower health
var _tower_label: Label         # the bar's caption (VILLAGERS → RAMA'S TOWER)
var _giant: Node3D              # first monster (kept for legacy debug paths)
var _monsters: Array = []       # the 3 monsters (200 / 400 / 800 HP) hunting the people
var _monsters_alive := 0        # decremented as Rama kills them; victory at 0
var _crowd: Node3D              # the 1000 villagers being attacked
var _people_total := 0          # crowd size, for the on-screen villager count
var _lost := false
var _env: Environment           # animated from full-sun (entry) to calm
var _sky_mat: ShaderMaterial    # sky sun glow/core, animated for the entry flare
var _sun: DirectionalLight3D    # key sun, dimmed after the entry


func _ready() -> void:
	_apply_performance_settings()
	_build_environment()
	_build_ground()
	_build_canopy()
	_build_forest()
	_build_tower()
	_build_crowd()
	_build_monsters()
	_build_hud()
	# The title card gates the game: gameplay/HUD/input stay suppressed until the
	# player presses "Play Now". Debug/automation paths bypass it.
	var skip_welcome := OS.get_environment("SKIP_WELCOME") == "1" \
		or OS.get_environment("DBG_SHOT") == "1" \
		or OS.get_environment("DBG_AUTOSHOOT") == "1"
	if skip_welcome:
		_begin_game()
	else:
		_show_welcome()
	if OS.get_environment("DBG_SHOT") == "1":
		_grab_shot()
	if OS.get_environment("DBG_AUTOSHOOT") == "1":
		_auto_shoot_test()
	if OS.get_environment("DBG_LOSE") == "1":
		_dbg_lose_test()
	if OS.get_environment("DBG_SMASH") == "1":
		_dbg_smash_test()
	if OS.get_environment("DBG_FOREST") == "1":
		_dbg_forest_test()
	if OS.get_environment("DBG_RAMCAM") == "1":
		_dbg_ramcam()
	if OS.get_environment("DBG_ATMOS") == "1":
		_dbg_atmos()
	if OS.get_environment("DBG_WIN") == "1":
		_dbg_win_test()
	if OS.get_environment("DBG_BATTLE") == "1":
		_dbg_battle()
	if OS.get_environment("DBG_SCOPESHOT") == "1":
		_dbg_scopeshot()


## Fullscreen on a Retina panel renders several times the pixels of the 1280x720
## window, while the scene is fill-rate heavy (dense ~1000-strong crowd + volumetric
## fog + glow), so fullscreen stutters. Render the 3D viewport below native and
## upscale it; the UI (canvas_items) keeps drawing at full resolution and stays crisp.
## Scaling only kicks in once the framebuffer is well above the windowed size, so
## windowed play is untouched. Re-evaluated whenever the window resizes/toggles.
func _apply_performance_settings() -> void:
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_update_render_scale()
	var win := get_window()
	if win and not win.size_changed.is_connected(_update_render_scale):
		win.size_changed.connect(_update_render_scale)


## Pick a 3D render scale from the current framebuffer size. ~0.92M px = 1280x720.
func _update_render_scale() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var px := float(vp.size.x) * float(vp.size.y)
	if px > 2_500_000.0:
		vp.scaling_3d_scale = 0.66      # big fullscreen panels: render ~44% of the pixels
	elif px > 1_500_000.0:
		vp.scaling_3d_scale = 0.78      # mid fullscreen / large windows
	else:
		vp.scaling_3d_scale = 1.0       # windowed: native, already smooth


## Temporary: aim at a monster, scope in, and capture so we can confirm the health
## bar sits inside the scope view.
func _dbg_scopeshot() -> void:
	await get_tree().create_timer(13.0).timeout
	var m: Node3D = _monsters[2] if _monsters.size() > 2 else (_monsters[0] if not _monsters.is_empty() else null)
	if m and is_instance_valid(m) and _aim:
		_aim.set_physics_process(false)
		_aim.set_process(false)
		var top: Vector3 = _aim.global_position
		var tgt: Vector3 = m.to_global(Vector3(0, 9.0, 0))   # sight the head/chest; bar sits just above
		var d := tgt - top
		var hd := sqrt(d.x * d.x + d.z * d.z)
		_aim.rotation.y = atan2(-d.x, -d.z)
		var pn: Node = _aim.get("pitch_node")
		if pn:
			(pn as Node3D).rotation.x = clampf(atan2(d.y, hd), -0.87, 1.22)
	InputRouter.set("touch_scope", true)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/Users/kushwanth/.claude/jobs/bf8c55d1/tmp/scopeshot.png")
	print("DBG_SCOPESHOT: saved scopeshot.png")


## Temporary: wait for the monsters to reach the line, force the third-person view
## (scope off), and save the actual game framebuffer to inspect the battlefield.
func _dbg_battle() -> void:
	await get_tree().create_timer(12.0).timeout
	InputRouter.set("touch_scope", false)
	if _scope_cam:
		_scope_cam.current = false
	if _game_cam:
		_game_cam.current = true
	await get_tree().create_timer(0.2).timeout   # let the scope overlay clear
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/Users/kushwanth/.claude/jobs/bf8c55d1/tmp/battle_clean.png")
	print("DBG_BATTLE: saved battle_clean.png")


## Temporary: run the victory cinematic straight away and capture the close-up of
## Rama's flaming bow + ascension before the win card lands.
func _dbg_win_test() -> void:
	await get_tree().create_timer(1.0).timeout
	_victory_sequence()
	# The win card appears ~2.8s into the sequence and fades over 0.6s — capture after.
	await get_tree().create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/Users/kushwanth/.claude/jobs/bf8c55d1/tmp/wincard_clean.png")
	print("DBG_WIN: saved wincard_clean.png")


## Temporary: capture the entry flare (1s in) vs. the settled calm look (6s in).
func _dbg_atmos() -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/atmos_entry.png")
	await get_tree().create_timer(5.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/atmos_calm.png")
	print("DBG_ATMOS: saved /tmp/atmos_entry.png + /tmp/atmos_calm.png")
	get_tree().quit()


## Temporary: frame the archer on the summit from the side (sun off-axis) so we
## can actually SEE Rama, away from the in-game sun bloom. Saves /tmp/ramcam.png.
func _dbg_ramcam() -> void:
	await get_tree().create_timer(1.0).timeout
	var base: Vector3 = _archer_body.global_position if (_archer_body and is_instance_valid(_archer_body)) else Vector3(0, 26, 0)
	var tgt := base + Vector3(0, 3.0, 0)
	# Freeze the aim facing -Z so the bow-tip marker sits at its design position
	# (it normally yaws with the aim, landing unpredictably for a still capture).
	if _aim and is_instance_valid(_aim):
		_aim.rotation = Vector3.ZERO
		_aim.set_process(false)
		_aim.set_physics_process(false)
		var pn: Node = _aim.get("pitch_node")
		if pn:
			(pn as Node3D).rotation = Vector3.ZERO
	# Drop a bright marker at the arrow spawn point so we can see it vs. the bow.
	if _bow_tip and is_instance_valid(_bow_tip):
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 0.22; sm.height = 0.44
		dot.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0, 0); mat.emission_enabled = true; mat.emission = Color(1, 0.1, 0.1)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dot.material_override = mat
		_bow_tip.add_child(dot)
	# Strong front light so we see the bow, not a backlit silhouette.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-10, 180, 0)
	key.light_energy = 3.0
	add_child(key)
	var cam := Camera3D.new()
	add_child(cam)
	# 3/4 front view (Rama faces -Z, so look from the -Z/+X side back toward +Z).
	cam.position = tgt + Vector3(5, 0.5, -7)
	cam.look_at(tgt, Vector3.UP)
	cam.current = true
	# Optionally drive the draw/loose so we can SEE the body motion in a still:
	#   DBG_DRAW=1  -> hold a full draw   DBG_DRAW=2 -> capture mid-loose
	var draw_mode := OS.get_environment("DBG_DRAW")
	if draw_mode != "" and _archer and is_instance_valid(_archer):
		_archer.call("set_charge", 1.0)
		await get_tree().create_timer(0.5).timeout
		if draw_mode == "2":
			_archer.call("set_charge", 0.0)
			_archer.call("release")
			await get_tree().create_timer(0.06).timeout
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/ramcam.png")
	print("DBG_RAMCAM: saved /tmp/ramcam.png target=", tgt, " bow_tip=", _bow_tip.global_position if _bow_tip else Vector3.ZERO)


## Temporary: aim a camera at the +Z treeline (sun behind us) and screenshot to
## judge the real forest model up close, away from the sun glare.
func _dbg_forest_test() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 14, 40)
	cam.look_at(Vector3(0, 22, 130), Vector3.UP)
	cam.current = true
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/forest_ingame.png")
	print("DBG_FOREST: saved /tmp/forest_ingame.png")


## Temporary: drop the giant in range and activate it so we can watch the boulder
## smash the tower; screenshot mid-slam.
func _dbg_smash_test() -> void:
	await get_tree().create_timer(0.5).timeout
	if _giant and is_instance_valid(_giant):
		_giant.global_position = Vector3(2, 0, -30)
		_giant.call("begin")
	await get_tree().create_timer(8.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/smash_test.png")
	print("DBG_SMASH: saved /tmp/smash_test.png")


## Temporary: drain the tower to trigger the collapse + Hanuman rescue + game over,
## and screenshot mid-flight to verify the sequence in the full project.
func _dbg_lose_test() -> void:
	await get_tree().create_timer(1.0).timeout
	for i in 5:
		_on_tower_attacked(30.0)
		await get_tree().create_timer(0.25).timeout
	# Capture the whole rescue as a sequence so any camera facing glitch is caught.
	for i in 14:
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/Users/kushwanth/.claude/jobs/bf8c55d1/tmp/lose_%02d.png" % i)
	print("DBG_LOSE: saved lose_00..13")


## Show the "RAMAYANA WAR ZONE" welcome card on top of everything, with gameplay
## input + HUD suppressed until the player commits.
func _show_welcome() -> void:
	if _hud_layer:
		_hud_layer.visible = false
	InputRouter.set("enabled", false)
	var layer := CanvasLayer.new()
	layer.layer = 100
	var card := WelcomeCardScript.new()
	card.connect("play_pressed", _on_welcome_done.bind(layer))
	layer.add_child(card)
	add_child(layer)


func _on_welcome_done(layer: Node) -> void:
	if is_instance_valid(layer):
		layer.queue_free()
	# Music begins only after the player clicks "Play Now". The war-horn intro cue
	# plays over the cinematic; the looping BGM takes over at the handoff (see
	# _start_intro / _on_intro_done). BGM is started directly when the intro is skipped.
	_begin_game()


## Start the actual game: the opening cinematic (unless skipped), which then
## hands control to gameplay.
func _begin_game() -> void:
	if OS.get_environment("SKIP_INTRO") != "1":
		_start_intro()
	else:
		Audio.start_bgm()   # no cinematic → straight to looping BGM
		_on_intro_done(null)


## Temporary: fire arrows from Ram's bow at the giant and verify HP drops.
func _auto_shoot_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var giant := get_node_or_null("GiantTarget")
	if giant == null:
		print("AUTOSHOOT: no giant found"); get_tree().quit(); return
	var ArrowScript := load("res://scripts/Arrow.gd")
	var before: float = giant.get("health")
	print("AUTOSHOOT: bow_tip=", _bow_tip, " muzzle=", _muzzle)
	print("AUTOSHOOT: giant HP before = ", before)
	var gcenter: Vector3 = giant.global_position + Vector3(0, 18, 0)
	for i in 6:
		var origin: Vector3 = _bow_tip.global_position if _bow_tip else _muzzle.global_position
		var dir := (gcenter - origin).normalized()
		var arrow := RigidBody3D.new()
		arrow.set_script(ArrowScript)
		get_tree().current_scene.add_child(arrow)
		arrow.global_position = origin
		arrow.call("launch", dir * 90.0, 25.0)
		print("AUTOSHOOT: fired #%d from %v toward %v" % [i, origin, gcenter])
		await get_tree().create_timer(0.18).timeout
		if i == 2:
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("/tmp/shoot_proof.png")
			print("AUTOSHOOT: saved /tmp/shoot_proof.png mid-volley")
	await get_tree().create_timer(1.5).timeout
	print("AUTOSHOOT: giant HP after  = ", giant.get("health"), " (was ", before, ")")
	get_tree().quit()


## Opening cinematic: drone over the forest + Hanuman flying, then reveal the
## tower and hand off to gameplay. Gameplay input + HUD are suppressed until done.
func _start_intro() -> void:
	if _hud_layer:
		_hud_layer.visible = false
	InputRouter.set("enabled", false)
	# Start the war-horn cue from the top the instant the cinematic camera begins,
	# so the music opens WITH the shot (not partway in). It loops until the handoff,
	# where _on_intro_done() calls stop_intro() and brings up the gameplay BGM.
	Audio.play_intro()
	# OPENING BEAT: the vanara troops pour through the forest (some running, some
	# climbing) while the camera cranes up; it lands on the drone intro's first
	# frame, so the prelude flows straight into the existing cinematic.
	var prelude := Node3D.new()
	prelude.set_script(ForestPreludeScript)
	add_child(prelude)
	prelude.connect("finished", _on_prelude_done.bind(prelude))


func _on_prelude_done(prelude: Node) -> void:
	# Hand off from the forest run-in to the drone cinematic. The intro's own
	# camera goes current synchronously in its _ready (during add_child) before
	# the prelude camera is actually freed, so there's no black frame.
	var intro := Node3D.new()
	intro.set_script(IntroCinematicScript)
	# Reparent the SAME Hanuman the prelude was flying so he doesn't pop/respawn —
	# the cinematic continues drifting him from exactly where the crane left him.
	var han: Variant = prelude.get("hanuman") if is_instance_valid(prelude) else null
	if han != null and is_instance_valid(han):
		(han as Node).get_parent().remove_child(han)
		intro.set("existing_hanuman", han)
	add_child(intro)
	intro.connect("finished", _on_intro_done.bind(intro))
	if is_instance_valid(prelude):
		prelude.queue_free()


func _on_intro_done(intro: Node) -> void:
	# Hand the view to the third-person gameplay camera. Force the scope cam off
	# first so it can't linger as the active camera (it only returns on scope).
	if _scope_cam:
		_scope_cam.current = false
	if _game_cam:
		_game_cam.current = true
	if _hud_layer:
		_hud_layer.visible = true
	InputRouter.set("enabled", true)
	# Cinematic over: silence the war-horn cue and bring up the looping gameplay BGM.
	Audio.stop_intro()
	Audio.start_bgm()
	# Rama's entry: full sun blaze, then it eases down to the calm look after 3s.
	_play_entry_atmos()
	# Release the monsters now — they begin their long march in from the horizon
	# only once the player is actually in control (Rama's top cam view), not before.
	for m in _monsters:
		if is_instance_valid(m):
			m.call("begin")
	# Start in the normal third-person view (never auto-scoped).
	InputRouter.set("touch_scope", false)
	if is_instance_valid(intro):
		intro.queue_free()
	if OS.get_environment("DBG_HANDOFF") == "1":
		_dbg_handoff_caps()
	if OS.get_environment("DBG_TOWERPHASE") == "1":
		_dbg_towerphase()


## Temporary: jump straight to the tower-destruction phase — bring the monsters in
## close, wipe the crowd, and capture the monsters smashing the tower down.
func _dbg_towerphase() -> void:
	await get_tree().create_timer(1.0).timeout
	for i in _monsters.size():
		var m: Node3D = _monsters[i]
		if is_instance_valid(m):
			m.global_position = Vector3(-20.0 + i * 20.0, 0.0, -30.0)
	if _crowd:
		var guard := 0
		while int(_crowd.call("alive")) > 0 and guard < 60:
			_crowd.call("throw", 200, Vector3(0, 0, -40))
			guard += 1
	for i in 16:
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/Users/kushwanth/.claude/jobs/bf8c55d1/tmp/tower_%02d.png" % i)
	print("DBG_TOWERPHASE: saved tower_00..15")


## Temporary: capture frames right after the intro hands off to the tower cam, to
## catch any facing glitch in the transition.
func _dbg_handoff_caps() -> void:
	# Capture the FIRST consecutive frames right after handoff to catch a transient snap.
	for i in 12:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/Users/kushwanth/.claude/jobs/bf8c55d1/tmp/handoff_%02d.png" % i)
	print("DBG_HANDOFF: saved handoff_00..11 (consecutive frames)")


func _grab_shot() -> void:
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/mta_shot.png")
	get_tree().quit()


# --- world dressing -------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()

	# Dramatic clouded sunset sky (custom shader: gradient + scrolling clouds + sun glow).
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://assets/shaders/sunset_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	_sky_mat = sky_mat

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(1.0, 0.72, 0.48)
	env.ambient_light_energy = 0.95   # strong warm fill so the WHOLE scene is lit like the player

	# Light distance haze with a GENTLE sun glow (toned down so it reads as soft
	# atmosphere, not a flare wrapping around Rama).
	env.fog_enabled = true
	env.fog_light_color = Color(1.0, 0.62, 0.34)
	env.fog_light_energy = 0.85
	env.fog_sun_scatter = 0.22
	env.fog_density = 0.007
	env.fog_aerial_perspective = 0.38   # lighter so the monsters keep their real colour, not pure silhouettes

	# Subtle volumetric god-rays: low density + softer scatter for a hint of sun
	# shafts in the distance. gi_inject = 0 keeps the bright summit lights OUT of
	# the fog, so the glow no longer blooms around Rama from every angle.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0022
	env.volumetric_fog_albedo = Color(1.0, 0.72, 0.45)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_sky_affect = 0.5

	# Filmic tonemap + bloom glow for the golden look.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.06
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 2.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.08

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env

	# Low warm sun sitting BEHIND the Giant (which is to the north at -Z), so the
	# Giant reads as a backlit silhouette and a big sun disk hangs near the horizon.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-6, 158, 0)   # azimuth tuned so the sun sits behind the giant
	sun.light_color = Color(1.0, 0.6, 0.32)
	sun.light_energy = 1.0                 # warm key light across the whole scene
	sun.shadow_enabled = true
	sun.light_angular_distance = 4.0      # bigger, softer sun disk
	sun.light_volumetric_fog_energy = 1.0
	add_child(sun)
	_sun = sun

	# Start in the CALM (reduced-sun) state; the entry flare overrides this and
	# eases back to it 3s after Rama appears.
	_apply_atmos(1.0)

	# Faint cool fill so silhouettes aren't pure black (kept low for the backlit look).
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, -20, 0)
	fill.light_color = Color(0.45, 0.55, 0.8)
	fill.light_energy = 0.12
	add_child(fill)


## Blend the whole sky/sun atmosphere between the dramatic "full sun" look (t=0,
## used for Rama's entry) and the calm reduced-sun look (t=1, normal gameplay).
## Every animated lever lives here so the entry flare is a single tweened value.
func _apply_atmos(t: float) -> void:
	if _env:
		_env.tonemap_exposure = lerpf(0.85, 0.6, t)
		_env.glow_intensity = lerpf(0.11, 0.06, t)
		_env.glow_bloom = lerpf(0.18, 0.02, t)
		_env.glow_hdr_threshold = lerpf(1.05, 2.1, t)
		_env.fog_sun_scatter = lerpf(0.75, 0.22, t)
		_env.fog_light_energy = lerpf(1.25, 0.85, t)
		_env.volumetric_fog_density = lerpf(0.0085, 0.0022, t)
		_env.volumetric_fog_anisotropy = lerpf(0.88, 0.6, t)
		_env.volumetric_fog_gi_inject = lerpf(0.9, 0.0, t)
		_env.volumetric_fog_sky_affect = lerpf(1.0, 0.5, t)
	if _sun:
		_sun.light_energy = lerpf(1.35, 1.0, t)
	if _sky_mat:
		_sky_mat.set_shader_parameter("sun_glow", lerpf(0.085, 0.018, t))
		_sky_mat.set_shader_parameter("sun_core", lerpf(0.6, 0.07, t))


## Rama's entry: blaze the full sun for 3s, then ease back to the calm look.
func _play_entry_atmos() -> void:
	_apply_atmos(0.0)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_method(_apply_atmos, 0.0, 1.0, 1.6).set_trans(Tween.TRANS_SINE)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0

	var mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	mesh.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.15, 0.1)
	mat.roughness = 0.85
	mesh.material_override = mat
	ground.add_child(mesh)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)   # top surface at y = 0
	ground.add_child(col)

	add_child(ground)


## A carpet of rounded treetop blobs around the play area to evoke the misty
## forest canopy from the reference; far ones fade into the warm fog.
func _build_canopy() -> void:
	var blob := SphereMesh.new()
	blob.radius = 1.7
	blob.height = 2.4

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blob
	var count := 900
	mm.instance_count = count

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260626
	for i in range(count):
		var ang := rng.randf() * TAU
		var rad := 62.0 + rng.randf() * 110.0   # far ring only — keep the arena clear
		var x := cos(ang) * rad
		var z := sin(ang) * rad
		var s := rng.randf_range(0.7, 2.0)
		var b := Basis().scaled(Vector3(s, s * 0.65, s))
		mm.set_instance_transform(i, Transform3D(b, Vector3(x, -0.4, z)))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.13, 0.16, 0.08)
	cmat.roughness = 1.0
	mmi.material_override = cmat
	add_child(mmi)


## A real forest around the tower: trunked trees, dense undergrowth + grass,
## a few tall gnarled hero trees near camera, and distant hills — all dark and
## warm so they read as backlit silhouettes against the sunset (the reference).
func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1357924

	# --- Real forest model (assets/forest). The world is laid out as a JOURNEY: FOREST
	# FIRST, then the WAR LAND. The drone/Hanuman fly in from +Z over a dense, continuous
	# forest expanse; that forest ENDS at the arena edge and opens into the war land — the
	# tower at centre and the battlefield on the -Z side where the monsters march in. So we
	# fill the +Z approach densely and keep the centre/-Z open, with only a thin distant
	# treeline framing the far perimeter so the battlefield isn't an empty void.
	var FOREST_S := 4.5
	# We DON'T instantiate the Forest.glb scene per patch any more. One Forest.glb is 562
	# separate transparent MeshInstance3Ds; ~96 patches meant ~54,000 transparent draw calls
	# every frame (all in ALPHA_DEPTH_PRE_PASS, double-sided) — that was what made the drone
	# fly-over lag and stutter. Instead we gather every patch's PLACEMENT here, then bake the
	# whole forest into a handful of MultiMeshes (one per material) so the GPU instances it in
	# ~7 draw calls. Same trees, same layout — just drawn cheaply. See _bake_forest().
	var patches: Array[Transform3D] = []
	# (1) The FOREST: a dense grid expanse covering the +Z approach (z 60..235, x ±150).
	# It starts at z~60 so no tree pokes into the gameplay/settle camera's foreground —
	# the war land (tower + battlefield) reads as a clearing in front of the forest.
	var z := 60.0
	while z < 235.0:
		var x := -150.0
		while x < 150.0:
			var fx := x + rng.randf_range(-12.0, 12.0)
			var fz := z + rng.randf_range(-12.0, 12.0)
			var s := FOREST_S * rng.randf_range(0.8, 1.3)
			var rot := rng.randf() * TAU                     # varied facings → no tiling pattern
			# The model's base sits at y≈0 (AABB min y ≈ 0), so it rests flat on the land.
			patches.append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * s), Vector3(fx, 0.0, fz)))
			x += 34.0
		z += 34.0
	# (2) Thin DISTANT treeline framing the war land's far sides and back (-Z, behind the
	# monsters, and the left/right horizons) so the open battlefield reads as a clearing
	# carved out of the forest rather than a void. Kept sparse + far so it never crowds play.
	var border: Array = []
	for bz: float in [-235.0, -200.0]:                       # behind the monster horizon
		for bx in range(-150, 180, 40):
			border.append(Vector3(float(bx), 0.0, bz))
	for bx2: float in [-185.0, -150.0, 150.0, 185.0]:        # left / right horizons
		for bz2 in range(-180, 60, 40):
			border.append(Vector3(bx2, 0.0, float(bz2)))
	for bpos: Vector3 in border:
		var bs := FOREST_S * rng.randf_range(0.8, 1.2)
		var boff := bpos + Vector3(rng.randf_range(-12.0, 12.0), 0.0, rng.randf_range(-12.0, 12.0))
		var brot := rng.randf() * TAU
		patches.append(Transform3D(Basis(Vector3.UP, brot).scaled(Vector3.ONE * bs), boff))

	_bake_forest(patches)

	var hill_mat := StandardMaterial3D.new()
	hill_mat.albedo_color = Color(0.20, 0.14, 0.10)      # hazy far hills (fog fades them)
	hill_mat.roughness = 1.0

	# --- Distant hills ringing the horizon, fading into the warm haze.
	for i in 9:
		var ang := rng.randf() * TAU
		var rad := 170.0 + rng.randf() * 60.0
		var hill := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		hill.mesh = sm
		hill.material_override = hill_mat
		var hs := rng.randf_range(30.0, 70.0)
		hill.scale = Vector3(hs, hs * rng.randf_range(0.35, 0.6), hs)
		hill.position = Vector3(cos(ang) * rad, -hs * 0.15, sin(ang) * rad)
		add_child(hill)


## Bake the Forest.glb into a few GPU-instanced MultiMeshes — the single biggest reason the
## drone fly-over is now smooth. The source scene is 562 tiny transparent MeshInstance3Ds; we
## (a) merge them into ONE mesh per material (so the whole forest is ~7 surfaces, not 562), and
## (b) draw all `patches` copies of that via MultiMesh, so the GPU stamps them in ~7 instanced
## draw calls instead of 562 × ~96 ≈ 54,000 individual ones. We also switch the foliage to
## single-pass alpha-scissor: the GLB ships ALPHA_DEPTH_PRE_PASS (two passes + back-to-front
## sorting every frame), which is both the heaviest transparency mode AND a source of sort
## flicker; scissor writes depth in one pass, so no overdraw blow-up and no popping.
func _bake_forest(patches: Array[Transform3D]) -> void:
	if patches.is_empty():
		return
	# One template, parented temporarily so global_transform (mesh placement within the scene)
	# resolves; we read its geometry, bake it, then free it.
	var template: Node3D = ForestScene.instantiate()
	add_child(template)
	var root_inv: Transform3D = template.global_transform.affine_inverse()

	# Group every surface by its material so we get one merged mesh per material.
	var tools: Dictionary = {}          # material RID -> SurfaceTool (accumulating geometry)
	var mats: Dictionary = {}           # material RID -> tuned Material for that group
	var order: Array = []               # stable material order for deterministic build
	var stack: Array[Node] = [template]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var local: Transform3D = root_inv * mi.global_transform
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(si)
			if mat == null:
				mat = mi.get_active_material(si)
			var key := mat.get_rid() if mat else RID()
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = st
				mats[key] = _foliage_material(mat)
				order.append(key)
			(tools[key] as SurfaceTool).append_from(mi.mesh, si, local)
	template.free()

	# Emit one MultiMeshInstance3D per material group.
	for key in order:
		var merged: ArrayMesh = (tools[key] as SurfaceTool).commit()
		if merged.get_surface_count() == 0:
			continue
		merged.surface_set_material(0, mats[key])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = merged
		mm.instance_count = patches.size()
		for i in patches.size():
			mm.set_instance_transform(i, patches[i])
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		# Distant, dense foliage doesn't need to cast shadows — skipping it is a further win
		# and avoids shadow-acne shimmer on the swaying-looking cards during the fly-over.
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inst)


## A cheap, glitch-free copy of a foliage material: single-pass alpha-scissor instead of the
## GLB's two-pass depth-prepass transparency. Duplicated so we never mutate the shared import.
func _foliage_material(src: Material) -> Material:
	if src is BaseMaterial3D:
		var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		return m
	return src


## Helper: parent a MultiMesh under a new instance with a flat material.
func _add_mm(mm: MultiMesh, mat: Material) -> void:
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	add_child(inst)


## A tall twisting tree built from tapering segments with a few branch stubs and
## a clump of canopy blobs on top — the gnarled foreground silhouette.
func _gnarled_tree(base: Vector3, h: float, trunk_mat: Material, foliage_mat: Material, rng: RandomNumberGenerator) -> void:
	var segs := 7
	var seg_h := h / segs
	var cur := base
	var r := rng.randf_range(0.5, 0.8)
	for s in segs:
		var nxt := cur + Vector3(rng.randf_range(-0.35, 0.35), seg_h, rng.randf_range(-0.35, 0.35))
		_forest_limb(trunk_mat, cur, nxt, r)
		if s >= 2 and rng.randf() < 0.6:
			var bdir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.3, 0.9), rng.randf_range(-1, 1)).normalized()
			_forest_limb(trunk_mat, cur, cur + bdir * rng.randf_range(1.2, 2.6), r * 0.5)
		cur = nxt
		r = maxf(0.14, r * 0.82)
	for _k in 5:
		var off := Vector3(rng.randf_range(-1.8, 1.8), rng.randf_range(-0.6, 1.6), rng.randf_range(-1.8, 1.8))
		_forest_blob(foliage_mat, cur + off, rng.randf_range(1.8, 3.2))


## A capsule-less cylinder "branch" between two world points (under root).
func _forest_limb(mat: Material, a: Vector3, b: Vector3, radius: float) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.001:
		return
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.7
	cm.bottom_radius = radius
	cm.height = length
	m.mesh = cm
	m.material_override = mat
	var yax := dir / length
	var xax := Vector3.RIGHT
	if absf(yax.dot(xax)) > 0.95:
		xax = Vector3.FORWARD
	var zax := xax.cross(yax).normalized()
	xax = yax.cross(zax).normalized()
	m.transform = Transform3D(Basis(xax, yax, zax), (a + b) * 0.5)
	add_child(m)


## A foliage sphere blob at a world point (under root).
func _forest_blob(mat: Material, pos: Vector3, r: float) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 1.7
	m.mesh = s
	m.material_override = mat
	m.position = pos
	add_child(m)


# --- the monkey tower + archer + camera -----------------------------------

func _build_tower() -> void:
	# Base (physics)
	var tower := CharacterBody3D.new()
	tower.name = "MonkeyTower"
	tower.set_script(TowerControllerScript)
	tower.position = Vector3(0, 2, 0)

	var base_col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.8
	cap.height = 2.0
	base_col.shape = cap
	tower.add_child(base_col)

	# TopMount sits at the cone's apex (cone.y -1 + H 32 = 31). AimYaw/AimPitch
	# hang off it. It is a SEPARATE child from the cone, so the cone's lean never
	# rotates the camera.
	var top_mount := Node3D.new()
	top_mount.name = "TopMount"
	top_mount.position = Vector3(0, 31.0, 0)
	tower.add_child(top_mount)

	# Local light on the summit so the archer's body is lit (not a dark
	# backlit silhouette) while the distant giant stays a silhouette.
	var summit_light := OmniLight3D.new()
	summit_light.position = Vector3(0, 3.0, 3.5)
	summit_light.light_color = Color(1.0, 0.94, 0.82)
	summit_light.light_energy = 12.0
	summit_light.omni_range = 16.0
	top_mount.add_child(summit_light)

	# A second fill from the camera side so Ram's textured front reads in colour
	# (the sun is behind him, so without this he stays a silhouette).
	var face_light := OmniLight3D.new()
	face_light.position = Vector3(0, 3.0, 5.0)
	face_light.light_color = Color(1.0, 0.96, 0.9)
	face_light.light_energy = 24.0
	face_light.omni_range = 22.0
	top_mount.add_child(face_light)

	var aim := Node3D.new()
	aim.name = "AimYaw"
	aim.set_script(ArcherAimScript)
	top_mount.add_child(aim)
	_aim = aim

	# Archer body (yaws but does not pitch).
	_add_archer_body(aim)

	var pitch := Node3D.new()
	pitch.name = "AimPitch"
	aim.add_child(pitch)

	var bow := _make_bow()
	bow.visible = false          # the character model carries its own bow
	pitch.add_child(bow)

	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.25, -0.9)
	pitch.add_child(muzzle)
	_muzzle = muzzle

	# First-person SCOPE camera, mounted on the aim pitch so it looks straight
	# down the shot. Active only while scoping (see ScopeCamera.gd); shows the
	# target in front of Rama, not Rama himself.
	var scope_cam := Camera3D.new()
	scope_cam.name = "ScopeCam"
	scope_cam.fov = 28.0
	# Sit clearly ABOVE and FORWARD of the summit so the scope looks out over the
	# cone at the giant down-range, instead of point-blank into the apex-cap monkeys
	# that surround the archer's eye (the old (0,0.55,-0.6) was buried in them).
	scope_cam.position = Vector3(0, 1.4, -2.6)
	scope_cam.near = 0.8                           # clip any monkey that creeps in close
	scope_cam.set_script(ScopeCameraScript)
	scope_cam.attributes = CameraAttributesPractical.new()
	pitch.add_child(scope_cam)
	_scope_cam = scope_cam

	# A real arrow nocked on the bow, hidden (the character holds its own bow).
	var nock := ArrowModelScene.instantiate()
	nock.scale = Vector3.ONE * 1.1
	nock.position = Vector3(0.0, 0.2, -0.55)
	nock.visible = false
	pitch.add_child(nock)

	# Camera hangs off TopMount (NOT the aim pitch) so cursor-aiming can rotate
	# the archer to face the pointer without the camera spinning with it.
	var cam_rig := Node3D.new()
	cam_rig.name = "CameraRig"
	cam_rig.set_script(CameraRigScript)
	cam_rig.set("controller", tower)
	top_mount.add_child(cam_rig)
	# Grab the gameplay camera so the intro/scope can hand control back to it. The
	# rig builds its camera in _ready, which hasn't run yet (the tree isn't entered
	# at build time), so ask the rig to create it now instead of reading its (still
	# empty) child list.
	_game_cam = cam_rig.call("ensure_camera")
	# The scope cam restores this gameplay cam when scoping ends. Keep the scope cam
	# inactive until the player actually engages it (it must not auto-grab the view).
	_scope_cam.current = false
	_scope_cam.set("game_cam", _game_cam)

	# Wire aim references before the tree triggers _ready.
	aim.set("pitch_node", pitch)
	aim.set("muzzle", muzzle)
	aim.set("bow_tip", _bow_tip if _bow_tip else muzzle)   # arrows originate at the bow tip
	aim.set("bow_mesh", bow)
	aim.set("archer", _archer)         # so the loose animates on every shot
	# Cursor aiming always raycasts through the third-person gameplay cam, even
	# while the scope (first-person) cam is showing — otherwise aim would run away.
	aim.set("view_cam", _game_cam)
	tower.set("aim_node", aim)

	# The fat "monkey mountain" cone is a CHILD of the tower so it slides rigidly
	# with the base. Offset -1 so its base sits on the ground (tower origin ~+1).
	var cone := Node3D.new()
	cone.name = "MonkeyCone"
	cone.set_script(MonkeyConeScript)
	cone.set("controller", tower)
	cone.position = Vector3(0, -1.0, 0)
	tower.add_child(cone)

	add_child(tower)
	_tower = tower


func _add_archer_body(parent: Node3D) -> void:
	if USE_RIGGED_ARCHER:
		# Real rigged + animated archer (Ram-tinted). Builds itself in _ready
		# synchronously on add_child, so bow_tip is ready immediately after.
		var ram := Node3D.new()
		ram.set_script(RamArcherScript)
		parent.add_child(ram)
		_archer = ram
		_archer_body = ram
		_bow_tip = ram.get("bow_tip")
		return
	if USE_FBX_ARCHER:
		# A holder sits on the summit; the model is lifted inside it so the
		# figure's FEET rest on the holder origin no matter where the GLB's own
		# origin sits. (Lord Ram.glb was origin-at-feet; bhagwan_shri_ram.glb is
		# origin-at-centre — feet ~0.9 below it — so a raw instance would sink
		# halfway into the tower.) We measure the model's AABB at runtime and drop
		# its feet to y=0 while centring it over x/z.
		# NOTE: this whole tower subtree is built BEFORE add_child(tower), so the
		# nodes are NOT in the SceneTree yet — global_transform is unusable here.
		# All sizing/placement below therefore uses LOCAL-transform math only.
		# The holder carries the draw/loose FX (the static mesh can't rig a hand, so
		# ArcherFx winds the whole body back on draw and snaps it forward on release).
		var holder := Node3D.new()
		holder.set_script(ArcherFxScript)
		holder.position = ARCHER_POS
		parent.add_child(holder)
		var archer := ArcherModelScene.instantiate()
		archer.rotation_degrees = ARCHER_ROT
		holder.add_child(archer)
		# GLBs arrive at wildly different intrinsic scales (the Sketchfab bhagwan
		# model imports only ~2cm tall), so a fixed scale can't be trusted: measure
		# and rescale to ARCHER_TARGET_HEIGHT, then drop the feet to the summit.
		_normalize_height(archer, ARCHER_TARGET_HEIGHT)
		_seat_on_feet(archer)
		holder.call("bind", archer)        # ArcherFx leans this model on each shot
		_archer = holder                   # so ArcherAim drives set_charge/release
		_archer_body = holder
		# Arrows spawn from the MIDDLE of the bow. It hangs off the UNSCALED holder
		# (not the model) so it tracks aim-yaw and is immune to the auto-fit scale;
		# the fraction-of-height keeps it on the grip as ARCHER_TARGET_HEIGHT changes.
		var tip := Marker3D.new()
		tip.name = "BowTip"
		tip.position = ARCHER_BOW_TIP * ARCHER_TARGET_HEIGHT
		holder.add_child(tip)
		_bow_tip = tip
		return
	# Posed primitive archer with a live draw/release animation. It builds itself
	# in _ready (fired synchronously by add_child), so bow_tip is ready below.
	var posed := Node3D.new()
	posed.set_script(PosedArcherScript)
	parent.add_child(posed)
	_archer = posed
	_archer_body = posed
	_bow_tip = posed.get("bow_tip")


## Uniformly rescale `model` so its measured height becomes `target_h` units.
## Robust to whatever intrinsic scale the GLB imported at. Uses LOCAL-transform
## math only, so it is valid before the node is in the SceneTree.
func _normalize_height(model: Node3D, target_h: float) -> void:
	var box := _model_local_aabb(model)
	if box.size.y <= 0.0001:
		return
	model.scale = Vector3.ONE * (target_h / box.size.y)


## Shift `model` so its lowest point sits on its parent's origin and it is centred
## over x/z. Works for any GLB regardless of where the artist put the origin
## (feet vs. centre vs. hips). Call AFTER _normalize_height (reads model.scale).
func _seat_on_feet(model: Node3D) -> void:
	var box: AABB = model.transform * _model_local_aabb(model)   # in parent space
	if box.size == Vector3.ZERO:
		return
	model.position.x -= box.position.x + box.size.x * 0.5   # centre x
	model.position.y -= box.position.y                       # feet to y = 0
	model.position.z -= box.position.z + box.size.z * 0.5   # centre z


## Combined AABB of every MeshInstance3D under `model`, expressed in `model`'s own
## LOCAL space (i.e. excluding model.transform), composed purely from local node
## transforms — so it needs no SceneTree membership / global_transform.
func _model_local_aabb(model: Node3D) -> AABB:
	var boxes: Array = []
	_gather_aabb(model, Transform3D.IDENTITY, boxes)
	var result := AABB()
	var have := false
	for b in boxes:
		if have:
			result = result.merge(b)
		else:
			result = b
			have = true
	return result


## Recurse `node`, accumulating each mesh's AABB mapped into the start frame.
## `to_frame` maps this node's local space into that frame.
func _gather_aabb(node: Node, to_frame: Transform3D, acc: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		acc.append(to_frame * (node as MeshInstance3D).mesh.get_aabb())
	for c in node.get_children():
		if c is Node3D:
			_gather_aabb(c, to_frame * (c as Node3D).transform, acc)


func _make_bow() -> Node3D:
	var bow := Node3D.new()
	var torus := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.34
	tm.outer_radius = 0.4
	torus.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.26, 0.12)
	torus.material_override = mat
	torus.rotation.y = PI / 2.0          # bow plane faces forward
	bow.add_child(torus)
	bow.position = Vector3(0.3, 0.25, -0.45)
	return bow


# --- the target -----------------------------------------------------------

## The villagers Rama defends: a thousand people clustered around the tower base.
func _build_crowd() -> void:
	var crowd := Node3D.new()
	crowd.name = "Crowd"
	crowd.set_script(CrowdScript)
	crowd.set("total", CROWD_SIZE)
	crowd.connect("population_changed", _on_people_changed)
	crowd.connect("depleted", _on_people_lost)
	add_child(crowd)
	_crowd = crowd
	_people_total = CROWD_SIZE


## Spawn the three monsters (200 / 400 / 800 HP). Each marches in from the horizon
## and mauls the crowd; Rama must hunt them all down to save the people.
func _build_monsters() -> void:
	_monsters.clear()
	for i in MONSTERS.size():
		var spec: Array = MONSTERS[i]
		var m := StaticBody3D.new()
		m.name = "Monster%d" % i
		m.set_script(GiantTargetScript)
		m.set("max_health", spec[0])
		m.set("health", spec[0])
		if spec.size() > 3:
			m.set("small", spec[3])
		m.set("crowd", _crowd)
		m.position = spec[2]
		m.scale = Vector3.ONE * float(spec[1])
		m.connect("died", _on_monster_died)
		m.connect("attacked_tower", _on_tower_attacked)   # only fires once all villagers are dead
		add_child(m)
		_monsters.append(m)
	_monsters_alive = _monsters.size()
	# Tell the villagers whom to charge + shoot at.
	if _crowd and is_instance_valid(_crowd):
		_crowd.set("targets", _monsters)
	_giant = _monsters[0] if not _monsters.is_empty() else null   # legacy debug ref
	# Name the boss "GiantTarget" too so the old auto-shoot debug path still resolves.
	if _monsters.size() >= 3:
		_monsters[2].name = "GiantTarget"


## A monster fell. When the last one dies, the people are saved — victory.
func _on_monster_died() -> void:
	_monsters_alive = maxi(0, _monsters_alive - 1)
	if _monsters_alive > 0:
		return
	# All monsters dead — the villagers they were defending erupt in celebration.
	if _crowd and is_instance_valid(_crowd):
		_crowd.call("celebrate")
	# `died` now fires only after the monster's topple fully completes, so the last monster
	# is already flat on the ground here. Hold for 4 seconds on it lying fallen, then cut to
	# the Rama close-up.
	await get_tree().create_timer(4.0).timeout
	_victory_sequence()


## Victory: swing to a close shot of Rama's face, his bow bursts into divine flame,
## and he ASCENDS (elevation) before the win screen lands. The fire + rise sell the
## "the avatar is risen" beat the player earned by saving the villagers.
func _victory_sequence() -> void:
	# The story takes the controls; no more aiming/scoping.
	if _aim and is_instance_valid(_aim):
		_aim.set_process(false)
		_aim.set_physics_process(false)
		_aim.rotation = Vector3.ZERO                       # face -Z so the close-up frames cleanly
		var pn: Node = _aim.get("pitch_node")
		if pn:
			(pn as Node3D).rotation = Vector3.ZERO
	if _tower and is_instance_valid(_tower):
		_tower.set_physics_process(false)
	# Fully drop the scope so the player SEES the victory shot even when the killing
	# arrow lands while scoped in. ScopeCamera._process otherwise re-grabs `current`
	# every frame (or hands it back to the gameplay cam) and steals the close-up, and
	# the scope overlay (keyed off InputRouter.scope) would stay drawn over it. Stop
	# the scope cam processing and force the scope state + overlay off for good.
	InputRouter.set("touch_scope", false)
	InputRouter.set("scope", false)
	InputRouter.set("enabled", false)        # story has the controls now; no stray E re-scopes
	if _scope_cam and is_instance_valid(_scope_cam):
		_scope_cam.set_process(false)
		_scope_cam.current = false

	# Where Rama's face sits (model is ARCHER_TARGET_HEIGHT tall, feet at the holder).
	var feet: Vector3 = _archer_body.global_position if (_archer_body and is_instance_valid(_archer_body)) else Vector3(0, 25, 0)
	var face := feet + Vector3(0, ARCHER_TARGET_HEIGHT * 0.82, 0)

	# Close-up camera in FRONT of Rama (he faces -Z), tight on his face.
	var cam := Camera3D.new()
	cam.fov = 36.0
	add_child(cam)
	cam.global_position = face + Vector3(1.1, 0.35, -4.4)
	cam.look_at(face, Vector3.UP)
	cam.current = true

	# Close-up beat over Rama's face: swell the triumphant war-horn + drums fanfare over
	# the reveal, and duck the gameplay BGM under it so the win music carries the moment.
	Audio.call("play_victory_fanfare")
	Audio.call("set_music_enabled", false)

	# The bow bursts into divine flame (parented to the bow grip so it tracks Rama).
	var fire := _make_bow_fire()
	var fire_host: Node3D = _bow_tip if (_bow_tip and is_instance_valid(_bow_tip)) else _archer_body
	if fire_host and is_instance_valid(fire_host):
		fire_host.add_child(fire)

	# Warm flame light on the face, riding with Rama so it stays lit as he rises.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.62, 0.22)
	glow.light_energy = 9.0
	glow.omni_range = 14.0
	if _archer_body and is_instance_valid(_archer_body):
		_archer_body.add_child(glow)
		glow.position = Vector3(0, ARCHER_TARGET_HEIGHT * 0.7, -1.6)
	else:
		add_child(glow)
		glow.global_position = face + Vector3(0, 0, -1.6)

	# Flicker the flame light so it dances like real fire instead of a steady lamp.
	var flick := create_tween()
	flick.set_loops()
	flick.tween_property(glow, "light_energy", 11.0, 0.09).set_trans(Tween.TRANS_SINE)
	flick.tween_property(glow, "light_energy", 7.0, 0.13).set_trans(Tween.TRANS_SINE)
	flick.tween_property(glow, "light_energy", 9.5, 0.07).set_trans(Tween.TRANS_SINE)

	# Crank bloom so the fire blazes, then ELEVATION: Rama ascends and the camera
	# cranes up with him for the rising hero shot.
	if _env:
		var bt := create_tween()
		bt.tween_property(_env, "glow_intensity", 0.22, 1.2)
	if _archer_body and is_instance_valid(_archer_body):
		var rise := create_tween()
		rise.set_parallel(true)
		rise.tween_property(_archer_body, "position:y", _archer_body.position.y + 4.5, 2.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		rise.tween_property(cam, "global_position", cam.global_position + Vector3(0, 4.7, 0.7), 2.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(2.8).timeout
	if _win_screen:
		_win_screen.call("show_victory")
		Audio.call("stop_victory_fanfare")   # music ends the moment the win card appears


## A column of divine flame for Rama's bow: additive, billboarded particles licking
## upward ALONG the bow grip. Tuned to read as real fire, not glowing boxes — each
## particle is a soft round flame puff that grows then tapers, turbulence makes the
## tongues flicker, and the whole thing hugs the bow as a thin vertical sheet.
func _make_bow_fire() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 200
	p.lifetime = 0.85
	p.local_coords = false
	p.one_shot = false

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 10.0                              # narrow so the flame stays a tongue, not a ball
	pm.gravity = Vector3(0, 6.0, 0)              # flames rise
	pm.initial_velocity_min = 1.4
	pm.initial_velocity_max = 3.0
	# Thin, tall emitter that traces the bow limb (vertical sheet, not a fat sphere).
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.12, 0.75, 0.06)
	# Each particle grows from a spark then tapers to nothing — flame-tongue shape.
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var scurve := Curve.new()
	scurve.add_point(Vector2(0.0, 0.25))
	scurve.add_point(Vector2(0.2, 1.0))
	scurve.add_point(Vector2(1.0, 0.0))
	var sctex := CurveTexture.new()
	sctex.curve = scurve
	pm.scale_curve = sctex
	# Turbulence = flicker/lick so the fire never looks like a static smear.
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.6
	pm.turbulence_noise_scale = 2.2
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.45
	var grad := Gradient.new()
	grad.add_point(0.0, Color(1.0, 0.97, 0.7, 1.0))   # white-hot core
	grad.add_point(0.35, Color(1.0, 0.6, 0.16, 0.95))  # orange body
	grad.add_point(0.7, Color(0.95, 0.28, 0.04, 0.7))  # deep red
	grad.add_point(1.0, Color(0.5, 0.06, 0.0, 0.0))    # fades to smoke
	var gtex := GradientTexture1D.new()
	gtex.gradient = grad
	pm.color_ramp = gtex
	p.process_material = pm

	# Soft RADIAL alpha so each particle is a round flame puff, not a hard square.
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	var puff := GradientTexture2D.new()
	puff.gradient = soft
	puff.width = 128
	puff.height = 128
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)                  # radius reaches the edge

	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = puff
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 6.0
	quad.material = mat
	p.draw_pass_1 = quad
	p.emitting = true
	return p


## Update the on-screen villager count as the monsters cut the crowd down.
func _on_people_changed(alive: int, total: int) -> void:
	if _tower_bar:
		var frac := (float(alive) / float(total)) if total > 0 else 0.0
		_tower_bar.call("setup", Color(0.45, 0.8, 0.45), "%d / %d" % [alive, total], frac)


## Every villager has fallen. This is NOT an instant loss anymore: the monsters now
## turn on the tower itself. Flip the top bar over to RAMA'S TOWER health — the game is
## lost only if the monsters then batter the tower down (see _on_tower_attacked).
func _on_people_lost() -> void:
	if _tower_label:
		_tower_label.text = "RAMA'S TOWER"
	if _tower_bar:
		var frac := _tower_health / TOWER_MAX_HEALTH
		_tower_bar.call("setup", Color(0.85, 0.7, 0.25), "%d / %d" % [int(_tower_health), int(TOWER_MAX_HEALTH)], frac)


## The giant struck the tower: drain its health, and on empty, begin the defeat.
func _on_tower_attacked(dmg: float) -> void:
	if _lost:
		return
	_tower_health = maxf(0.0, _tower_health - dmg)
	if _tower_bar:
		var frac := _tower_health / TOWER_MAX_HEALTH
		_tower_bar.call("setup", Color(0.85, 0.7, 0.25), "%d / %d" % [int(_tower_health), int(TOWER_MAX_HEALTH)], frac)
	# A quick shake of the whole tower on each hit.
	if _tower and is_instance_valid(_tower):
		var st := create_tween()
		st.tween_property(_tower, "rotation:z", 0.05, 0.05)
		st.tween_property(_tower, "rotation:z", -0.05, 0.08)
		st.tween_property(_tower, "rotation:z", 0.0, 0.08)
	if _tower_health <= 0.0:
		_lose_sequence()


## Defeat: the tower collapses, Hanuman swoops in, catches Rama, and flies him
## away to safety, then GAME OVER appears.
func _lose_sequence() -> void:
	if _lost:
		return
	_lost = true

	# Stop the player aiming/moving; the story takes over.
	if _aim:
		_aim.set_process(false)
		_aim.set_physics_process(false)
	if _tower and is_instance_valid(_tower):
		_tower.set_physics_process(false)

	# Hanuman flies in from the right, low, toward Rama atop the tower.
	var ram_pos := _archer_body.global_position if (_archer_body and is_instance_valid(_archer_body)) else Vector3(0, 25, 0)
	var hanuman := _build_hanuman()
	add_child(hanuman)
	var spawn := ram_pos + Vector3(60, -10, 30)
	hanuman.global_position = spawn
	_face_flight(hanuman, ram_pos - spawn)

	var approach := create_tween()
	approach.tween_property(hanuman, "global_position", ram_pos + Vector3(5.0, 1.0, 7.0), 1.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)   # stop a little farther BACK from the tower (was 2.5,0.5,2.5 — too close)
	await approach.finished

	# Rama mounts Hanuman: parent him to a scale-compensating seat on Hanuman's
	# back (so Rama keeps his own size despite Hanuman's 6x scale), then slide him
	# onto the seat. Preserve world pose at the moment of reparenting.
	if _archer_body and is_instance_valid(_archer_body):
		var seat := Node3D.new()
		seat.scale = Vector3.ONE / HANUMAN_SCALE   # cancel Hanuman's scale
		seat.position = Vector3(0, 1.0, -0.3)       # Hanuman-local seat (tweak in iteration)
		hanuman.add_child(seat)
		var gt := _archer_body.global_transform
		_archer_body.get_parent().remove_child(_archer_body)
		seat.add_child(_archer_body)
		_archer_body.global_transform = gt
		var mount := create_tween()
		mount.tween_property(_archer_body, "position", Vector3.ZERO, 0.5)

	# The emptied tower collapses (the monkey mountain sinks and topples).
	if _tower and is_instance_valid(_tower):
		var cone := _tower.get_node_or_null("MonkeyCone")
		var collapse := create_tween()
		collapse.set_parallel(true)
		if cone:
			collapse.tween_property(cone, "position:y", -20.0, 1.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			collapse.tween_property(cone, "rotation:z", 0.7, 1.6)

	await get_tree().create_timer(0.4).timeout

	# Hanuman bears Rama up and away into the distance.
	var away := ram_pos + Vector3(-140, 70, -90)
	_face_flight(hanuman, away - hanuman.global_position)
	var flee := create_tween()
	flee.tween_property(hanuman, "global_position", away, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await get_tree().create_timer(1.6).timeout
	if _game_over:
		_game_over.call("show_game_over")


## The real detailed Lord Hanuman model (same asset the intro cinematic flies),
## scaled up for the rescue.
func _build_hanuman() -> Node3D:
	var h := HanumanScene.instantiate()
	h.scale = Vector3.ONE * HANUMAN_SCALE
	return h


## Orient Hanuman so he faces (and leans into) his flight direction, matching the
## intro cinematic's convention (+Z is forward, then a forward lean).
func _face_flight(hanuman: Node3D, dir: Vector3) -> void:
	if dir.length() < 0.001:
		return
	hanuman.look_at(hanuman.global_position - dir.normalized(), Vector3.UP)
	hanuman.rotate_object_local(Vector3.RIGHT, deg_to_rad(HANUMAN_LEAN))


# --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud_layer = layer

	# Full game HUD overlay (portrait, bars, compass, quests, hotbar, controls).
	var hud := Control.new()
	hud.set_script(HudScript)
	hud.set("aim_node", _aim)
	layer.add_child(hud)

	# Aim reticle: projects the muzzle's actual aim ray onto the screen so the
	# player sees exactly where the (straight-flying) arrow will land.
	var reticle := ReticleScript.new()
	reticle.set("muzzle", _muzzle)
	layer.add_child(reticle)

	# Sniper-scope overlay (zoom framing); shows only while the scope is active.
	layer.add_child(ScopeOverlayScript.new())

	# Villagers-alive bar, top-center (drains as the monsters cut the crowd down). Once
	# the crowd is wiped it is relabelled RAMA'S TOWER and tracks the tower's health.
	_tower_label = Label.new()
	_tower_label.text = "VILLAGERS"
	_tower_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_tower_label.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.0))
	_tower_label.add_theme_constant_override("outline_size", 6)
	_tower_label.add_theme_font_size_override("font_size", 16)
	_tower_label.position = Vector2(get_viewport().size.x * 0.5 - 130, 54)
	layer.add_child(_tower_label)

	_tower_bar = StatBarScript.new()
	_tower_bar.size = Vector2(260, 20)
	_tower_bar.position = Vector2(get_viewport().size.x * 0.5 - 130, 74)
	layer.add_child(_tower_bar)
	_tower_bar.call("setup", Color(0.45, 0.8, 0.45), "%d / %d" % [_people_total, _people_total], 1.0)

	# Victory overlay, hidden until the Giant dies (drawn above the HUD).
	_win_screen = WinScreenScript.new()
	layer.add_child(_win_screen)

	# Defeat overlay, hidden until the tower collapses (drawn above the HUD).
	_game_over = GameOverScreenScript.new()
	layer.add_child(_game_over)
