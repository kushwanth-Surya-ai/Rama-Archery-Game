extends Control
## One slot in the bottom item hotbar: framed icon + optional count.

var icon_name := "arrow"
var count := 0
var selected := false


func setup(n: String, c: int, sel := false) -> void:
	icon_name = n
	count = c
	selected = sel
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.06, 0.05, 0.04, 0.75))
	var border := Color(0.5, 0.4, 0.2, 0.85)
	var bw := 2.0
	if selected:
		border = Color(0.97, 0.8, 0.36, 1.0)
		bw = 3.0
	draw_rect(r, border, false, bw)

	_draw_icon(icon_name, size * 0.5, minf(size.x, size.y) * 0.3, Color(0.92, 0.88, 0.78))

	if count > 0:
		var f := ThemeDB.fallback_font
		var t := str(count)
		var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
		var p := Vector2(size.x - ts.x - 5, size.y - 5)
		draw_string(f, p + Vector2(1, 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.8))
		draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.96, 0.9, 0.8))


func _draw_icon(n: String, c: Vector2, s: float, col: Color) -> void:
	match n:
		"arrow":
			var a := c + Vector2(-s, s) * 0.8
			var b := c + Vector2(s, -s) * 0.8
			draw_line(a, b, col, 2.5)
			draw_line(b, b + Vector2(-s * 0.5, 0), col, 2.5)
			draw_line(b, b + Vector2(0, s * 0.5), col, 2.5)
		"sword":
			draw_line(c + Vector2(0, -s), c + Vector2(0, s * 0.5), col, 2.5)
			draw_line(c + Vector2(-s * 0.5, s * 0.2), c + Vector2(s * 0.5, s * 0.2), col, 2.5)
		"potion":
			draw_rect(Rect2(c + Vector2(-s * 0.18, -s * 0.7), Vector2(s * 0.36, s * 0.35)), col.darkened(0.2))
			var body := Color(0.9, 0.6, 0.2)
			draw_rect(Rect2(c + Vector2(-s * 0.45, -s * 0.35), Vector2(s * 0.9, s * 1.05)), body)
			draw_rect(Rect2(c + Vector2(-s * 0.45, -s * 0.35), Vector2(s * 0.9, s * 1.05)), col, false, 1.5)
		"bolas":
			draw_circle(c + Vector2(-s * 0.5, s * 0.4), s * 0.22, col)
			draw_circle(c + Vector2(s * 0.5, s * 0.4), s * 0.22, col)
			draw_line(c + Vector2(-s * 0.5, s * 0.4), c, col, 2.0)
			draw_line(c + Vector2(s * 0.5, s * 0.4), c, col, 2.0)
		"meat":
			var poly := PackedVector2Array()
			for i in range(12):
				var ang := TAU * i / 12.0
				poly.append(c + Vector2(cos(ang) * s * 0.7, sin(ang) * s * 0.5))
			draw_colored_polygon(poly, Color(0.7, 0.35, 0.3))
			draw_line(c + Vector2(s * 0.4, -s * 0.3), c + Vector2(s * 0.8, -s * 0.6), col, 3.0)
		_:
			draw_circle(c, s * 0.4, col)
