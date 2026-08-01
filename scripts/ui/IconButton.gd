extends Control
## Circular HUD button with a vector-drawn icon. Used for the action cluster,
## the pause button, the portrait, and the ammo indicator. Set `interactive`
## false for purely decorative ones.

var icon_name := "arrow"
var interactive := true
var radius := 34.0
var badge := ""                  # small number badge under the icon
var accent := Color(0.85, 0.7, 0.4)
var on_press := Callable()
var on_release := Callable()

var _down := false


func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			# On touch devices a single tap emits BOTH an InputEventScreenTouch and
			# an emulated InputEventMouseButton. Without this guard the paired events
			# fired on_press twice — harmless for set-true buttons, but it made the
			# scope's toggle (`not touch_scope`) flip on then instantly off, so the
			# scope never engaged on mobile. Ignore the duplicate while already down.
			if _down:
				return
			_down = true
			queue_redraw()
			if on_press.is_valid():
				on_press.call()
		else:
			if not _down:
				return
			_down = false
			queue_redraw()
			if on_release.is_valid():
				on_release.call()


func _draw() -> void:
	var c := size * 0.5
	var bg := Color(0.05, 0.04, 0.03, 0.55)
	if _down:
		bg = Color(0.95, 0.72, 0.32, 0.4)
	draw_circle(c, radius, bg)
	draw_arc(c, radius, 0.0, TAU, 44, accent.lerp(Color.WHITE, 0.1), 2.0, true)
	_draw_icon(icon_name, c, radius * 0.6, Color(0.96, 0.93, 0.86))

	if badge != "":
		var f := ThemeDB.fallback_font
		var bc := c + Vector2(0, radius * 0.92)
		draw_circle(bc, 12, Color(0.05, 0.04, 0.03, 0.9))
		draw_arc(bc, 12, 0.0, TAU, 20, accent, 1.5, true)
		var ts := f.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		draw_string(f, bc + Vector2(-ts.x * 0.5, 5), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.96, 0.9, 0.8))


func _draw_icon(n: String, c: Vector2, s: float, col: Color) -> void:
	match n:
		"arrow":
			var a := c + Vector2(-s, s) * 0.75
			var b := c + Vector2(s, -s) * 0.75
			draw_line(a, b, col, 3.0)
			draw_line(b, b + Vector2(-s * 0.55, 0), col, 3.0)
			draw_line(b, b + Vector2(0, s * 0.55), col, 3.0)
		"sword":
			draw_line(c + Vector2(0, -s), c + Vector2(0, s * 0.45), col, 3.0)
			draw_line(c + Vector2(-s * 0.55, s * 0.25), c + Vector2(s * 0.55, s * 0.25), col, 3.0)
			draw_line(c + Vector2(0, s * 0.45), c + Vector2(0, s * 0.85), col, 4.0)
		"run", "dash":
			var n_ch := 2 if n == "run" else 3
			for i in range(n_ch):
				var ox := -s * 0.4 + i * s * 0.45
				draw_line(c + Vector2(ox - s * 0.2, -s * 0.6), c + Vector2(ox + s * 0.2, 0), col, 3.0)
				draw_line(c + Vector2(ox + s * 0.2, 0), c + Vector2(ox - s * 0.2, s * 0.6), col, 3.0)
		"coil":
			draw_arc(c, s * 0.7, -PI * 0.5, PI, 18, col, 2.5)
			draw_arc(c, s * 0.38, PI * 0.5, PI * 2.0, 18, col, 2.5)
		"pause":
			draw_rect(Rect2(c + Vector2(-s * 0.45, -s * 0.7), Vector2(s * 0.3, s * 1.4)), col)
			draw_rect(Rect2(c + Vector2(s * 0.15, -s * 0.7), Vector2(s * 0.3, s * 1.4)), col)
		"restart":
			# circular refresh arrow (gap at top-right with an arrowhead)
			draw_arc(c, s * 0.7, -PI * 0.35, PI * 1.5, 28, col, 3.0)
			var ang := -PI * 0.35
			var tip := c + Vector2(cos(ang), sin(ang)) * (s * 0.7)
			draw_line(tip, tip + Vector2(-s * 0.18, -s * 0.32), col, 3.0)
			draw_line(tip, tip + Vector2(s * 0.30, -s * 0.12), col, 3.0)
		"bow":
			draw_arc(c + Vector2(-s * 0.15, 0), s, -PI / 2.2, PI / 2.2, 18, col, 2.5)
			var top := c + Vector2(-s * 0.15, 0) + Vector2(cos(-PI / 2.2), sin(-PI / 2.2)) * s
			var bot := c + Vector2(-s * 0.15, 0) + Vector2(cos(PI / 2.2), sin(PI / 2.2)) * s
			draw_line(top, bot, col, 1.5)
			draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), col, 2.0)
		"scope":
			draw_arc(c, s * 0.7, 0.0, TAU, 28, col, 2.5)
			draw_line(c + Vector2(-s, 0), c + Vector2(-s * 0.35, 0), col, 2.0)
			draw_line(c + Vector2(s * 0.35, 0), c + Vector2(s, 0), col, 2.0)
			draw_line(c + Vector2(0, -s), c + Vector2(0, -s * 0.35), col, 2.0)
			draw_line(c + Vector2(0, s * 0.35), c + Vector2(0, s), col, 2.0)
			draw_circle(c, 2.0, col)
		"close":
			draw_line(c + Vector2(-s * 0.6, -s * 0.6), c + Vector2(s * 0.6, s * 0.6), col, 3.0)
			draw_line(c + Vector2(s * 0.6, -s * 0.6), c + Vector2(-s * 0.6, s * 0.6), col, 3.0)
		"sound", "mute":
			# speaker body (box + cone), then either sound-waves or a mute cross
			var spk := PackedVector2Array([
				c + Vector2(-s * 0.6, -s * 0.25),
				c + Vector2(-s * 0.25, -s * 0.25),
				c + Vector2(0.05, -s * 0.6),
				c + Vector2(0.05, s * 0.6),
				c + Vector2(-s * 0.25, s * 0.25),
				c + Vector2(-s * 0.6, s * 0.25)])
			draw_colored_polygon(spk, col)
			if n == "sound":
				draw_arc(c + Vector2(s * 0.05, 0), s * 0.55, -PI * 0.33, PI * 0.33, 14, col, 2.0)
				draw_arc(c + Vector2(s * 0.05, 0), s * 0.85, -PI * 0.33, PI * 0.33, 14, col, 2.0)
			else:
				var x0 := c + Vector2(s * 0.35, -s * 0.35)
				draw_line(x0, x0 + Vector2(s * 0.55, s * 0.7), col, 2.5)
				draw_line(x0 + Vector2(s * 0.55, 0), x0 + Vector2(0, s * 0.7), col, 2.5)
		"portrait":
			draw_circle(c + Vector2(0, -s * 0.25), s * 0.5, col)
			var body := PackedVector2Array([
				c + Vector2(-s * 0.75, s),
				c + Vector2(-s * 0.5, s * 0.35),
				c + Vector2(s * 0.5, s * 0.35),
				c + Vector2(s * 0.75, s)])
			draw_colored_polygon(body, col)
		_:
			draw_circle(c, s * 0.4, col)
