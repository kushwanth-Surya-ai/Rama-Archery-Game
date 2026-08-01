extends Control
## Full game HUD overlay matching the reference: portrait + stat bars, compass,
## pause button, item hotbar, movement pad and action buttons.
## Built in code. Nodes are created in build, then positioned in _layout() from
## the viewport size (re-run on resize) so corner elements never drift off-screen.

const StatBarScript := preload("res://scripts/ui/StatBar.gd")
const CompassScript := preload("res://scripts/ui/Compass.gd")
const IconButtonScript := preload("res://scripts/ui/IconButton.gd")
const JoystickScript := preload("res://scripts/ui/VirtualJoystick.gd")

const GOLD := Color(0.92, 0.74, 0.36)
const TEXT := Color(0.92, 0.88, 0.8)

var aim_node: Node3D

var _compass: Control
var _joystick: Control          # on-screen movement pad (bottom-left) — moves Rama on touch
var _pause: Control
var _restart: Control
var _shoot: Control
var _scope: Control
var _scope_fire: Control      # big FIRE button shown on the right only while scoped
var _scope_off: Control       # close (X) button to drop the scope, shown while scoped
var _pause_label: Label
var _sound: Control            # sound on/off (mute) toggle, top-right

var _paused := false
var _muted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _build() -> void:
	# Compass
	_compass = CompassScript.new()
	_compass.set("aim_node", aim_node)
	_compass.size = Vector2(440, 30)
	add_child(_compass)

	# Movement pad (bottom-left): drag the knob to move Rama on touch devices.
	_joystick = JoystickScript.new()
	add_child(_joystick)

	# Pause + restart
	_pause = _icon("pause", true, 24.0)
	_pause.set("on_press", Callable(self, "_toggle_pause"))
	add_child(_pause)

	_restart = _icon("restart", true, 24.0)
	_restart.set("on_press", Callable(self, "_restart_game"))
	add_child(_restart)

	# Sound on/off — mutes the whole game (BGM + SFX) via the Master bus.
	_sound = _icon("sound", true, 24.0)
	_sound.set("on_press", Callable(self, "_toggle_sound"))
	add_child(_sound)

	# Action cluster
	_shoot = _icon("arrow", true, 32.0)
	_shoot.set("on_press", func(): InputRouter.touch_shoot = true)
	_shoot.set("on_release", func(): InputRouter.touch_shoot = false)
	add_child(_shoot)
	# Scope button (next to shoot): TAP to toggle the bow scope onto the monsters.
	# While scoped, a big FIRE button appears on the right to loose arrows.
	_scope = _icon("scope", true, 32.0)
	_scope.set("on_press", func(): InputRouter.touch_scope = not InputRouter.touch_scope)
	add_child(_scope)

	# Dedicated FIRE button for scoped shooting — large, on the right, hidden until
	# the scope is engaged (toggled by _process from InputRouter.scope).
	_scope_fire = _icon("arrow", true, 46.0)
	_scope_fire.set("on_press", func(): InputRouter.touch_shoot = true)
	_scope_fire.set("on_release", func(): InputRouter.touch_shoot = false)
	_scope_fire.visible = false
	_scope_fire.z_index = 70          # above the scope vignette (z 60)
	_scope_fire.z_as_relative = false
	add_child(_scope_fire)

	# SCOPE OFF button (X): drops the scope, shown on the right only while scoped.
	_scope_off = _icon("close", true, 26.0)
	_scope_off.set("on_press", func(): InputRouter.touch_scope = false)
	_scope_off.visible = false
	_scope_off.z_index = 70
	_scope_off.z_as_relative = false
	add_child(_scope_off)

	# Pause overlay text
	_pause_label = Label.new()
	_pause_label.text = "PAUSED"
	_pause_label.add_theme_color_override("font_color", GOLD)
	_pause_label.add_theme_font_size_override("font_size", 48)
	_pause_label.visible = false
	add_child(_pause_label)


## Show the big FIRE button only while the scope is engaged. If the scope drops
## while the button is held, clear the shoot intent so firing can't get stuck on.
func _process(_delta: float) -> void:
	if _scope_fire == null:
		return
	var on: bool = InputRouter.scope
	if on != _scope_fire.visible:
		_scope_fire.visible = on
		if _scope_off:
			_scope_off.visible = on
		if not on:
			InputRouter.touch_shoot = false


## Position everything from the current viewport size.
func _layout() -> void:
	var vp := get_viewport_rect().size
	var vw := vp.x
	var vh := vp.y

	_compass.position = Vector2(vw * 0.5 - 220, 16)
	# Movement pad: bottom-left, clear of the action buttons on the right.
	# (2*RADIUS+36 = 208 tall; use the literal so layout doesn't depend on _ready order.)
	_joystick.position = Vector2(40, vh - 208 - 40)
	_pause.position = Vector2(vw - 66, 16)
	_restart.position = Vector2(vw - 120, 16)   # just left of pause
	_sound.position = Vector2(vw - 174, 16)     # just left of restart

	_shoot.position = Vector2(vw - 246, vh - 200)
	_scope.position = Vector2(vw - 348, vh - 196)   # left of the shoot button
	# Big FIRE button: right edge, vertically centred so it's easy to reach while scoped.
	_scope_fire.position = Vector2(vw - 120, vh * 0.5 - 46)
	# SCOPE OFF (X): just above the FIRE button on the right edge.
	_scope_off.position = Vector2(vw - 100, vh * 0.5 - 150)

	_pause_label.position = Vector2(vw * 0.5 - 90, vh * 0.5 - 30)


# --- builders -------------------------------------------------------------

func _icon(name: String, interactive: bool, radius: float, badge := "") -> Control:
	var b: Control = IconButtonScript.new()
	b.set("icon_name", name)
	b.set("interactive", interactive)
	b.set("radius", radius)
	if badge != "":
		b.set("badge", badge)
	return b


func _toggle_sound() -> void:
	_muted = not _muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _muted)
	_sound.set("icon_name", "mute" if _muted else "sound")
	_sound.queue_redraw()


func _toggle_pause() -> void:
	_paused = not _paused
	get_tree().paused = _paused
	_pause_label.visible = _paused


## Restart the whole game from the beginning (replays the Hanuman intro).
func _restart_game() -> void:
	get_tree().paused = false
	_paused = false
	_pause_label.visible = false
	InputRouter.set("enabled", true)
	get_tree().reload_current_scene()
