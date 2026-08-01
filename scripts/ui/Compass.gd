extends Control
## Top compass strip. Scrolls cardinal directions based on the archer's yaw.

const DIRS := [["N", 0.0], ["NE", 45.0], ["E", 90.0], ["SE", 135.0],
	["S", 180.0], ["SW", 225.0], ["W", 270.0], ["NW", 315.0]]
const SPAN := 170.0       # degrees visible across the full width

var aim_node: Node3D


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var f := ThemeDB.fallback_font

	var heading := 0.0
	if aim_node:
		heading = wrapf(rad_to_deg(-aim_node.rotation.y), 0.0, 360.0)

	draw_line(Vector2(0, h * 0.55), Vector2(w, h * 0.55), Color(0.8, 0.7, 0.4, 0.25), 1.0)

	for d in DIRS:
		var rel := wrapf(d[1] - heading, -180.0, 180.0)
		if absf(rel) <= SPAN * 0.5:
			var x := w * 0.5 + rel / (SPAN * 0.5) * (w * 0.5)
			var label: String = d[0]
			var major := label.length() == 1
			var fs := 17 if major else 13
			var col := Color(0.97, 0.92, 0.82) if major else Color(0.78, 0.7, 0.52)
			var ts := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(f, Vector2(x - ts.x * 0.5, h * 0.55 + ts.y * 0.5 - 3), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			draw_line(Vector2(x, h * 0.55 + 7), Vector2(x, h * 0.55 + 11), Color(0.8, 0.7, 0.4, 0.5), 1.0)

	# Center pointer diamond
	var cx := w * 0.5
	var pts := PackedVector2Array([
		Vector2(cx, 0), Vector2(cx + 5, 7), Vector2(cx, 14), Vector2(cx - 5, 7)])
	draw_colored_polygon(pts, Color(0.96, 0.78, 0.35))
