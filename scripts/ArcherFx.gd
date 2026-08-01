extends Node3D
## Draw / loose motion for the STATIC (non-rigged) Lord Ram model. The mesh has
## no skeleton, so it can't move a finger on its own — instead we fake the shot
## on the whole upper body: while the player charges, Ram winds BACK (drawing the
## string); the instant the arrow looses, he snaps forward and settles. Lives on
## the archer holder and is driven by ArcherAim via the duck-typed contract:
##   set_charge(ratio) — 0..1 draw amount, called every frame while charging
##   set_pitch(pitch)  — aim pitch (rad, +up), leans the body to the shot
##   release()         — fire the one-shot forward "loose" kick
##
## It animates a child pivot (the model) so the holder's own origin/bow-tip stay
## put; everything is rotation-only, so the model's scale/seating are untouched.

const DRAW_LEAN := 0.13        # rad the torso winds back at full draw
const LOOSE_KICK := 0.24       # rad of forward snap at the instant of release
const PITCH_LEAN := 0.12       # how much of the aim pitch the body leans into
const DRAW_EASE := 10.0        # how fast the body follows the draw amount
const LOOSE_DECAY := 9.0       # how fast the loose kick settles back

var _model: Node3D             # the visual to lean (rotated about its pivot)
var _base_rot := Vector3.ZERO
var _charge := 0.0             # smoothed draw amount (0..1)
var _charge_target := 0.0
var _pitch := 0.0
var _loose := 0.0              # transient 1->0 kick fired on release


## Called once by Main right after the model is parented in.
func bind(model: Node3D) -> void:
	_model = model
	if _model:
		_base_rot = _model.rotation


func set_charge(ratio: float) -> void:
	_charge_target = clampf(ratio, 0.0, 1.0)


func set_pitch(pitch: float) -> void:
	_pitch = pitch


func release() -> void:
	_loose = 1.0
	_charge_target = 0.0


func _process(delta: float) -> void:
	if _model == null:
		return
	# ease the draw toward its target, decay the loose kick
	_charge = lerpf(_charge, _charge_target, clampf(delta * DRAW_EASE, 0.0, 1.0))
	if _loose > 0.0:
		_loose = maxf(_loose - delta * LOOSE_DECAY, 0.0)
	# +x leans the torso back (draw); the loose drives it sharply forward (-x).
	var lean_x := DRAW_LEAN * _charge - LOOSE_KICK * _loose - PITCH_LEAN * _pitch
	_model.rotation = _base_rot + Vector3(lean_x, 0.0, 0.0)
