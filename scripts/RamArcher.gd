extends Node3D
## Rigged Lord Ram archer body, built on the CC0 KayKit "Adventurers" Barbarian
## GLB (a muscular, bare-chested warrior — the closest free rigged+animated match
## for Ram). It is a real skinned skeleton with real archery animation clips, so
## the bow draw/aim/loose actually MOVE, unlike a static statue.
##
## It implements the same duck-typed contract ArcherAim drives:
##   set_charge(ratio)  -> hold the aim/draw pose while charging
##   release()          -> play the shoot/loose clip once
##   set_pitch(pitch)   -> lean the body to the aim pitch
## and exposes `bow_tip` (a Marker3D) for the arrow spawn origin.
##
## Ram identity on top of the generic body: a soft blue skin tint, a gold mukut
## (crown) parented to the head bone, and a gold bow parented to the bow hand.
##
## EVERYTHING placement-related is a tunable const up top — because this was
## authored without a running editor, expect to nudge SCALE / FACING / the bow &
## crown offsets once in Godot to line them up perfectly.

# --- tunables (adjust in the editor once you can see it) -------------------
const MODEL_PATH := "res://assets/rigged/Barbarian.glb"
const BODY_SCALE := 2.7                       # tall, powerful presence on the summit
const FACING_DEG := 180.0                     # spin so the model faces -Z (the giant)
const FEET_Y := 0.4                           # lift feet onto the summit blobs
const PITCH_LEAN := 0.45                      # how much of the aim pitch the body leans
const RAM_TINT := Color(0.62, 0.72, 1.0)      # soft blue multiply -> shyam complexion

# Bone names confirmed by parsing the GLB (41-joint rig).
const BOW_BONE := "handslot.l"                # forward (bow) hand
const HEAD_BONE := "head"

# Bow placement in the bow-hand bone's local space (tune these first in-editor).
const BOW_OFFSET := Vector3(0.0, 0.05, 0.0)
const BOW_ROT_DEG := Vector3(0.0, 0.0, 0.0)
# Crown placement in the head bone's local space.
const CROWN_OFFSET := Vector3(0.0, 0.18, 0.0)

# Animation clip names confirmed inside Barbarian.glb.
const CLIP_IDLE := "Idle"
const CLIP_AIM := "2H_Ranged_Aiming"
const CLIP_SHOOT := "2H_Ranged_Shoot"
const BLEND := 0.18                           # crossfade time between clips

var bow_tip: Node3D                           # arrow spawn origin (read by Main)

var _model: Node3D
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _shooting := false
var _aiming := false


func _ready() -> void:
	scale = Vector3.ONE * BODY_SCALE
	rotation.y = deg_to_rad(FACING_DEG)
	position = Vector3(0, FEET_Y, 0)

	# load() (not preload) so a missing/unimported model degrades gracefully
	# instead of breaking the whole script at parse time.
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		push_warning("RamArcher: could not load %s — open the editor so Godot imports it." % MODEL_PATH)
		bow_tip = _fallback_tip()
		return
	_model = scene.instantiate()
	add_child(_model)

	_anim = _find(_model, "AnimationPlayer") as AnimationPlayer
	_skel = _find(_model, "Skeleton3D") as Skeleton3D

	_tint_ram()
	_attach_crown()
	_attach_bow()           # also creates bow_tip on the bow hand
	if bow_tip == null:
		bow_tip = _fallback_tip()

	if _anim:
		_force_loop(CLIP_IDLE, true)
		_force_loop(CLIP_AIM, true)
		_force_loop(CLIP_SHOOT, false)
		if not _anim.animation_finished.is_connected(_on_anim_finished):
			_anim.animation_finished.connect(_on_anim_finished)
		_play(CLIP_IDLE)


# --- contract ArcherAim drives --------------------------------------------

func set_charge(ratio: float) -> void:
	if _anim == null or _shooting:
		return
	if ratio > 0.02:
		if not _aiming:
			_aiming = true
			_play(CLIP_AIM)
	else:
		if _aiming:
			_aiming = false
			_play(CLIP_IDLE)


func release() -> void:
	if _anim == null:
		return
	if not _anim.has_animation(CLIP_SHOOT):
		return
	_shooting = true
	_aiming = false
	_play(CLIP_SHOOT)


func set_pitch(pitch: float) -> void:
	# Lean the whole body into the aim. (Per-bone spine bending would be nicer
	# but needs a SkeletonModifier; a gentle root lean reads fine here.)
	if _model:
		_model.rotation.x = -pitch * PITCH_LEAN


# --- internals ------------------------------------------------------------

func _on_anim_finished(name: StringName) -> void:
	if name == CLIP_SHOOT:
		_shooting = false
		_play(CLIP_IDLE)


func _play(clip: String) -> void:
	if _anim and _anim.has_animation(clip):
		_anim.play(clip, BLEND)


func _force_loop(clip: String, loop: bool) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	var a := _anim.get_animation(clip)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE


## Tint every surface toward the shyam (blue) complexion without losing the
## baked texture detail — albedo_color multiplies the albedo_texture in Godot.
func _tint_ram() -> void:
	for mi in _all_meshes(_model):
		var mesh := mi as MeshInstance3D
		if mesh == null:
			continue
		var n := mesh.get_surface_override_material_count()
		for i in n:
			var m := mesh.get_active_material(i)
			if m is StandardMaterial3D:
				var d := (m as StandardMaterial3D).duplicate()
				d.albedo_color = RAM_TINT
				mesh.set_surface_override_material(i, d)


func _attach_crown() -> void:
	if _skel == null:
		return
	var bi := _skel.find_bone(HEAD_BONE)
	if bi < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = HEAD_BONE
	_skel.add_child(ba)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.92, 0.72, 0.20)
	gold.metallic = 0.9
	gold.roughness = 0.3
	# band
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.12
	bm.bottom_radius = 0.13
	bm.height = 0.08
	band.mesh = bm
	band.material_override = gold
	band.position = CROWN_OFFSET
	ba.add_child(band)
	# finial spike
	var fin := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.0
	fm.bottom_radius = 0.07
	fm.height = 0.16
	fin.mesh = fm
	fin.material_override = gold
	fin.position = CROWN_OFFSET + Vector3(0, 0.12, 0)
	ba.add_child(fin)


func _attach_bow() -> void:
	if _skel == null:
		return
	var bi := _skel.find_bone(BOW_BONE)
	if bi < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = BOW_BONE
	_skel.add_child(ba)

	var holder := Node3D.new()
	holder.position = BOW_OFFSET
	holder.rotation = Vector3(deg_to_rad(BOW_ROT_DEG.x), deg_to_rad(BOW_ROT_DEG.y), deg_to_rad(BOW_ROT_DEG.z))
	ba.add_child(holder)

	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.92, 0.72, 0.20)
	gold.metallic = 0.9
	gold.roughness = 0.3
	var string_mat := StandardMaterial3D.new()
	string_mat.albedo_color = Color(0.92, 0.88, 0.72)

	# Gold bow stave: a shallow C of short segments in the vertical plane.
	var R := 0.55
	var segs := 8
	var prev := Vector3.ZERO
	var top := Vector3.ZERO
	var bot := Vector3.ZERO
	for i in range(segs + 1):
		var t := float(i) / segs
		var ang := lerpf(deg_to_rad(-70.0), deg_to_rad(70.0), t)
		var p := Vector3(-cos(ang) * R + R, sin(ang) * R, 0.0)   # bow bows away in -X
		if i == 0:
			bot = p
		elif i == segs:
			top = p
		else:
			pass
		if i > 0:
			_segment(holder, gold, prev, p, 0.03)
		prev = p

	# Bowstring straight between the tips.
	_segment(holder, string_mat, top, bot, 0.008)

	# Arrow rest / spawn origin at the grip.
	bow_tip = Marker3D.new()
	bow_tip.name = "BowTip"
	bow_tip.position = (top + bot) * 0.5
	holder.add_child(bow_tip)


## A capsule segment between two local points.
func _segment(parent: Node3D, mat: Material, a: Vector3, b: Vector3, radius: float) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.0001:
		return
	var m := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(length, radius * 2.0)
	m.mesh = cm
	m.material_override = mat
	var yax := dir / length
	var xax := Vector3.RIGHT
	if absf(yax.dot(xax)) > 0.95:
		xax = Vector3.FORWARD
	var zax := xax.cross(yax).normalized()
	xax = yax.cross(zax).normalized()
	m.transform = Transform3D(Basis(xax, yax, zax), (a + b) * 0.5)
	parent.add_child(m)


func _fallback_tip() -> Node3D:
	var t := Marker3D.new()
	t.name = "BowTip"
	t.position = Vector3(0.2, 1.2, -0.4)
	add_child(t)
	return t


func _all_meshes(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_all_meshes(c))
	return out


func _find(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
