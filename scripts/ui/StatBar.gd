extends Control
## A single labelled stat bar (health / mana / stamina) in the fantasy HUD style.

var fill_color := Color(0.8, 0.1, 0.1)
var value := 1.0          # 0..1
var label_text := ""


func setup(col: Color, txt: String, frac := 1.0) -> void:
	fill_color = col
	label_text = txt
	value = frac
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# Track
	draw_rect(r, Color(0.02, 0.02, 0.02, 0.7))
	# Fill (with a subtle darker bottom for depth)
	var fw := size.x * clampf(value, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(fw, size.y)), fill_color)
	draw_rect(Rect2(Vector2(0, size.y * 0.55), Vector2(fw, size.y * 0.45)), fill_color.darkened(0.25))
	# Border
	draw_rect(r, Color(0.5, 0.42, 0.22, 0.9), false, 1.5)
	# Centered text
	var f := ThemeDB.fallback_font
	var fs := 13
	var ts := f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := Vector2((size.x - ts.x) * 0.5, size.y * 0.5 + ts.y * 0.5 - 3)
	draw_string(f, pos + Vector2(1, 1), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
	draw_string(f, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.96, 0.93, 0.85))
