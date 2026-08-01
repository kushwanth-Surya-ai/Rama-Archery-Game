extends Node
## Single source of truth for player intent. Merges keyboard/mouse and the
## on-screen controls into one API. Registered as an autoload.
##
## Two control modes (toggle with T):
##  - POINTER mode (default): cursor visible, NO mouse capture. Play entirely
##    with the mouse — drag the d-pad to move, tap the on-screen buttons to
##    shoot/sprint/dodge, and DRAG ON THE OPEN 3D AREA to look around. Keyboard
##    WASD also works. This needs no focus/capture tricks, so it always works.
##  - MOUSELOOK mode: classic FPS — cursor captured, mouse turns the view,
##    left-click shoots, WASD moves.

signal mode_changed(touch_mode: bool)

# --- merged intent (read these from gameplay scripts) ---
var move_vector := Vector2.ZERO          # x = strafe (+right), y = forward (+fwd), len <= 1
var sprint := false
var dodge_pressed := false               # true for the frame a dodge is requested
var shoot_held := false
var shoot_just_pressed := false
var shoot_just_released := false
var scope := false                       # true while the aim scope (zoom) is active
var bow_drawn := false                    # set by ArcherAim while the bow is drawn

# --- on-screen control contributions ---
var touch_move := Vector2.ZERO
var touch_sprint := false
var touch_dodge := false                 # one-shot request, auto-cleared
var touch_shoot := false
var touch_scope := false                 # on-screen scope button (hold to zoom)

var touch_mode := true                   # true = POINTER mode (default)
var enabled := true                      # false during the intro cinematic (suppresses all intent)

var _look_accum := Vector2.ZERO
var scope_look_accum := Vector2.ZERO      # touch drag delta used to PAN the aim while scoped
var _prev_shoot := false
var _shoot_via_button := false            # this shot came from a FIRE/shoot button (bypass drag guard)

# Drag-to-turn (pointer mode): hold LEFT and move to orbit the camera; a quick
# tap (press+release with little movement) shoots instead.
const DRAG_THRESH := 8.0          # pixels of motion before a hold becomes a "turn"
var orbit_accum := Vector2.ZERO   # drag delta the camera consumes to turn the view
var _lmb := false
var _drag := 0.0
var _was_drag := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_actions()
	# Default to POINTER mode. Cursor HIDDEN (the on-screen reticle is the
	# pointer); the mouse freely aims the archer and left-click shoots.
	touch_mode = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _setup_actions() -> void:
	_add_key("move_forward", KEY_W)
	_add_key("move_back", KEY_DOWN)   # S is now the shoot key; back-step moves to Down-arrow
	_add_key("move_left", KEY_A)
	_add_key("move_right", KEY_D)
	_add_key("sprint", KEY_SHIFT)
	_add_key("dodge", KEY_CTRL)
	_add_mouse_btn("shoot", MOUSE_BUTTON_LEFT)
	_add_key("shoot_key", KEY_S)      # keyboard fire: S looses arrows in both modes


func _add_key(action: String, code: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var e := InputEventKey.new()
	e.physical_keycode = code
	InputMap.action_add_event(action, e)


func _add_mouse_btn(action: String, btn: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var e := InputEventMouseButton.new()
	e.button_index = btn
	InputMap.action_add_event(action, e)


func set_touch_mode(on: bool) -> void:
	touch_mode = on
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if on else Input.MOUSE_MODE_CAPTURED
	mode_changed.emit(on)


func _input(event: InputEvent) -> void:
	# T toggles between pointer mode and classic mouse-look.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		set_touch_mode(not touch_mode)
		return

	# E toggles the bow scope on/off (same as the on-screen scope button).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		touch_scope = not touch_scope
		return

	if touch_mode:
		return   # pointer-mode aiming is handled in _unhandled_input (below)

	# --- MOUSELOOK mode ---
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_accum += event.relative.limit_length(120.0)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Click the game to (re)capture the cursor for continuous mouse-look.
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# POINTER mode: free mouse aims (cursor). Hold LEFT and DRAG to turn the
	# camera (3D). A quick tap shoots. Runs only on events the HUD didn't consume,
	# so dragging on the d-pad/buttons never turns the view.
	if not touch_mode:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_lmb = true
			_drag = 0.0
			_was_drag = false
		else:
			_lmb = false
	elif event is InputEventMouseMotion and _lmb:
		var r: Vector2 = event.relative
		_drag += r.length()
		if _drag > DRAG_THRESH:
			_was_drag = true
			orbit_accum += r.limit_length(120.0)   # feed the camera turn
	elif event is InputEventScreenDrag:
		orbit_accum += event.relative.limit_length(120.0)
		# While scoped, a drag on the open area PANS the aim (relative), so the
		# scope can be pointed on touch devices (there is no mouse cursor to aim).
		if scope:
			scope_look_accum += event.relative.limit_length(120.0)


func _process(_delta: float) -> void:
	if not enabled:
		# Intro cinematic in control: zero all intent and drain accumulators.
		move_vector = Vector2.ZERO
		sprint = false
		dodge_pressed = false
		shoot_held = false
		shoot_just_pressed = false
		shoot_just_released = false
		_look_accum = Vector2.ZERO
		orbit_accum = Vector2.ZERO
		scope = false
		bow_drawn = false
		return

	if Input.is_action_just_pressed("ui_cancel"):
		# Esc frees the cursor in mouse-look mode.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var kv := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	move_vector = kv + touch_move
	if move_vector.length() > 1.0:
		move_vector = move_vector.normalized()

	sprint = Input.is_action_pressed("sprint") or touch_sprint
	dodge_pressed = Input.is_action_just_pressed("dodge") or touch_dodge
	touch_dodge = false
	# Scope (bow zoom): engaged ONLY by the dedicated on-screen scope button (held),
	# used together with the bow to sight the monster. It is deliberately NOT tied
	# to `bow_drawn` — auto-scoping on every shoot-tap slammed the first-person view
	# into the monkey cone (the "tap -> monkeys fill the screen" glitch).
	scope = touch_scope

	# Shoot when LEFT is held WITHOUT dragging (a drag is a camera turn, not a
	# shot). Mouselook mode keeps plain LMB-shoot. On-screen button also shoots.
	var pointer_shoot := (_lmb and not _was_drag) if touch_mode else Input.is_action_pressed("shoot")
	var button_shoot := touch_shoot or Input.is_action_pressed("shoot_key")
	var shoot := pointer_shoot or button_shoot
	if shoot and button_shoot:
		_shoot_via_button = true      # a dedicated FIRE/shoot button drove this shot
	shoot_just_pressed = shoot and not _prev_shoot
	# Don't fire the OPEN-AREA pointer if its press turned into a drag-turn (the turn
	# consumed it). But the dedicated FIRE/shoot buttons must ALWAYS fire — even while
	# a scope aim-drag has set _was_drag — so a button shot bypasses the drag guard.
	shoot_just_released = (not shoot) and _prev_shoot and (_shoot_via_button or not _was_drag)
	shoot_held = shoot
	_prev_shoot = shoot
	if not shoot:
		_shoot_via_button = false


## Returns accumulated look delta and resets it. Aim consumes this each frame.
func consume_look() -> Vector2:
	var l := _look_accum
	_look_accum = Vector2.ZERO
	return l


## Returns accumulated drag-to-turn delta and resets it. The camera consumes it.
func consume_orbit() -> Vector2:
	var o := orbit_accum
	orbit_accum = Vector2.ZERO
	return o


## Returns accumulated scope-pan drag delta and resets it. ArcherAim consumes it
## while scoped on touch devices to move the aim.
func consume_scope_look() -> Vector2:
	var s := scope_look_accum
	scope_look_accum = Vector2.ZERO
	return s
