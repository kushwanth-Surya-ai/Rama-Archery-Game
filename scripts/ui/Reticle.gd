extends Control
## Aim reticle. Sits exactly at the mouse cursor (move the mouse -> the pointer
## moves) and the archer aims wherever it points. Turns gold + draws a lock ring
## when the cursor is over something hittable (ground / the giant).

var muzzle: Node3D   # unused (kept for wiring compatibility)

var _screen_pos := Vector2.ZERO
var _visible := false
var _locked := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(48, 48)
	z_index = 50


func _physics_process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_visible = false
		queue_redraw()
		return

	_screen_pos = get_viewport().get_mouse_position()
	_visible = true

	# locked if the camera ray through the cursor hits the world/target layer (1)
	var ro := cam.project_ray_origin(_screen_pos)
	var rn := cam.project_ray_normal(_screen_pos)
	var space := cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ro, ro + rn * 2000.0, 1)
	_locked = space.intersect_ray(query).has("position")

	queue_redraw()


func _draw() -> void:
	if not _visible or InputRouter.scope:
		return   # while scoped, the scope overlay's own crosshair is used instead
	var c := _screen_pos
	var col := Color(1.0, 0.82, 0.28, 1.0) if _locked else Color(1, 1, 1, 0.95)
	var outline := Color(0, 0, 0, 0.7)
	var r := 16.0
	var gap := 6.0
	var th := 2.5
	# dark outline first (offset thicker) so the reticle reads on bright sky too
	_ticks(c, r, gap, outline, th + 2.0)
	_ticks(c, r, gap, col, th)
	draw_circle(c, 3.4, outline)
	draw_circle(c, 2.0, col)
	if _locked:
		draw_arc(c, r + 4.0, 0.0, TAU, 32, outline, 3.0)
		draw_arc(c, r + 4.0, 0.0, TAU, 32, col, 1.6)


func _ticks(c: Vector2, r: float, gap: float, col: Color, th: float) -> void:
	draw_line(c + Vector2(-r, 0), c + Vector2(-gap, 0), col, th)
	draw_line(c + Vector2(gap, 0), c + Vector2(r, 0), col, th)
	draw_line(c + Vector2(0, -r), c + Vector2(0, -gap), col, th)
	draw_line(c + Vector2(0, gap), c + Vector2(0, r), col, th)
