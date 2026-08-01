extends Control
## On-screen movement pad (d-pad style ring + knob), matching the reference HUD.
## Outputs a normalised Vector2 into InputRouter.touch_move. Handles touch+mouse.

const RADIUS := 86.0
const KNOB := 40.0

var _knob_pos := Vector2.ZERO
var _active := false


func _ready() -> void:
	custom_minimum_size = Vector2(2 * RADIUS + 36, 2 * RADIUS + 36)
	size = custom_minimum_size


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, RADIUS, Color(0.05, 0.04, 0.03, 0.5))
	draw_arc(c, RADIUS, 0.0, TAU, 56, Color(0.8, 0.7, 0.4, 0.6), 2.5, true)

	var arrow_col := Color(0.85, 0.78, 0.6, 0.85)
	var off := RADIUS - 16.0
	_tri(c + Vector2(0, -off), 0.0, arrow_col)
	_tri(c + Vector2(0, off), PI, arrow_col)
	_tri(c + Vector2(-off, 0), -PI * 0.5, arrow_col)
	_tri(c + Vector2(off, 0), PI * 0.5, arrow_col)

	draw_circle(c + _knob_pos, KNOB, Color(0.1, 0.09, 0.08, 0.9))
	draw_arc(c + _knob_pos, KNOB, 0.0, TAU, 28, Color(0.82, 0.7, 0.4, 0.8), 2.0, true)


func _tri(center: Vector2, ang: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for p in [Vector2(0, -9), Vector2(-6, 5), Vector2(6, 5)]:
		pts.append(center + p.rotated(ang))
	draw_colored_polygon(pts, col)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_active = true
			_update(event.position)
		else:
			_active = false
			_knob_pos = Vector2.ZERO
			InputRouter.touch_move = Vector2.ZERO
			queue_redraw()
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _active:
		_update(event.position)


func _update(pos: Vector2) -> void:
	var c := size * 0.5
	var v := pos - c
	if v.length() > RADIUS:
		v = v.normalized() * RADIUS
	_knob_pos = v
	var nrm := v / RADIUS
	InputRouter.touch_move = Vector2(nrm.x, -nrm.y)   # screen +y is down -> forward is -y
	queue_redraw()
