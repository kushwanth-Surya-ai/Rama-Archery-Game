extends Control
## Opening title card: "RAMAYANA WAR ZONE". A Varanasi-at-dusk welcome screen —
## a sunset sky over the Ganga (sunset_sky-styled shader backdrop), temple/ghat
## silhouettes, and a slow drift of floating aarti diyas — fronted by the game
## title and a glowing "Play Now" button. Emits `play_pressed` once the player
## commits (button click or Enter/Space), after a short fade-out. Built fully in
## code to match the rest of the project (see WinScreen.gd).

signal play_pressed

const HORIZON := 0.60                          # must match welcome_bg.gdshader

const GOLD := Color(0.97, 0.82, 0.42)
const EMBER := Color(1.0, 0.55, 0.22)
const TEXT := Color(0.95, 0.9, 0.82)
const DIM := Color(0.78, 0.7, 0.6)

const WelcomeBgShader := preload("res://assets/shaders/welcome_bg.gdshader")

var _started := false
var _play_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # swallow gameplay input behind the card

	_build_backdrop()
	add_child(ArtLayer.new())                  # silhouettes + diyas, on top of the sky
	_build_content()

	# Fill the viewport explicitly: a top-level Control under a CanvasLayer/Window
	# doesn't always inherit a non-zero size from anchors alone, which would
	# collapse the full-rect children.
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)

	# Soft fade-in of the whole card.
	modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(self, "modulate:a", 1.0, 0.8)


func _fit_to_viewport() -> void:
	var vp := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = vp


func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = WelcomeBgShader
	mat.set_shader_parameter("horizon", HORIZON)
	mat.set_shader_parameter("sun_pos", Vector2(0.68, 0.5))
	bg.material = mat
	add_child(bg)


func _build_content() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)

	# Kicker
	var kicker := _label("T H E   R A M A Y A N A   S A G A", 24, GOLD)
	kicker.modulate = Color(1, 1, 1, 0.9)
	box.add_child(kicker)

	# Title — RAMAYANA (large, glowing gold)
	var title := _label("RAMAYANA", 120, GOLD)
	title.add_theme_color_override("font_outline_color", Color(0.16, 0.06, 0.0))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_shadow_color", Color(1.0, 0.62, 0.22, 0.5))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 30)
	box.add_child(title)

	# Subtitle banner — WAR ZONE between two rules
	var banner := HBoxContainer.new()
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_theme_constant_override("separation", 22)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(_rule())
	var sub := _label("W A R   Z O N E", 46, EMBER)
	sub.add_theme_color_override("font_outline_color", Color(0.18, 0.05, 0.0))
	sub.add_theme_constant_override("outline_size", 8)
	banner.add_child(sub)
	banner.add_child(_rule())
	box.add_child(banner)

	# Tagline
	var tag := _label("Stand atop the Vanara tower above the ghats of Varanasi —\nloose the divine arrow and break the demon's siege.", 22, TEXT)
	tag.add_theme_color_override("font_outline_color", Color(0.08, 0.03, 0.0, 0.9))
	tag.add_theme_constant_override("outline_size", 6)
	tag.modulate = Color(1, 1, 1, 0.96)
	box.add_child(_spacer(18))
	box.add_child(tag)

	# Play Now
	box.add_child(_spacer(26))
	_play_btn = _make_play_button()
	var wrap := CenterContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_play_btn)
	box.add_child(wrap)

	# Footer hint
	var hint := _label("▶   click  PLAY NOW   ·   or press  ENTER  to begin", 18, DIM)
	box.add_child(_spacer(14))
	box.add_child(hint)


func _make_play_button() -> Button:
	var btn := Button.new()
	btn.text = "PLAY NOW"
	btn.custom_minimum_size = Vector2(300, 74)
	btn.add_theme_font_size_override("font_size", 32)
	btn.add_theme_color_override("font_color", Color(0.16, 0.08, 0.02))
	btn.add_theme_color_override("font_hover_color", Color(0.1, 0.05, 0.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.1, 0.05, 0.0))

	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD
	sb.border_color = Color(1.0, 0.95, 0.78)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(1.0, 0.6, 0.2, 0.55)
	sb.shadow_size = 22
	btn.add_theme_stylebox_override("normal", sb)

	var hover := sb.duplicate()
	hover.bg_color = Color(1.0, 0.9, 0.55)
	hover.shadow_size = 30
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", hover)

	btn.pressed.connect(_on_play)

	# Gentle pulse so the button reads as the call to action.
	var pulse := create_tween().set_loops()
	pulse.tween_property(btn, "modulate", Color(1.12, 1.08, 1.0), 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0), 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return btn


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(0.97, 0.82, 0.42, 0.55)
	r.custom_minimum_size = Vector2(120, 2)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # stay a thin rule, not a block
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _input(event: InputEvent) -> void:
	if _started:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			_on_play()
			get_viewport().set_input_as_handled()


func _on_play() -> void:
	if _started:
		return
	_started = true
	if _play_btn:
		_play_btn.disabled = true
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.5)
	t.tween_callback(func() -> void: play_pressed.emit())


# ---------------------------------------------------------------------------
# Backdrop art drawn over the sky shader: ghat/temple silhouettes, the river
# shore, drifting aarti diyas (floating lamps) and a few rising embers.
# ---------------------------------------------------------------------------
class ArtLayer extends Control:
	const HORIZON := 0.60
	const SIL := Color(0.045, 0.03, 0.05)        # near-black temple silhouette
	const SIL_RIM := Color(0.55, 0.24, 0.12)     # warm backlit rim on the skyline
	const GLOW := Color(1.0, 0.66, 0.26)
	const FLAME := Color(1.0, 0.82, 0.42)
	const CORE := Color(1.0, 0.97, 0.82)

	var _t := 0.0
	var _diyas: Array = []
	var _embers: Array = []
	var _temples: Array = []
	var _rng := RandomNumberGenerator.new()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		_rng.seed = 770626

		# Temple/spire skyline along the far shore: x (0..1), width, height (frac of screen).
		_temples = [
			{"x": 0.12, "w": 0.07, "h": 0.16},
			{"x": 0.20, "w": 0.05, "h": 0.11},
			{"x": 0.30, "w": 0.045, "h": 0.085},
			{"x": 0.40, "w": 0.10, "h": 0.22},   # tall central temple
			{"x": 0.55, "w": 0.05, "h": 0.10},
			{"x": 0.66, "w": 0.085, "h": 0.18},
			{"x": 0.78, "w": 0.05, "h": 0.12},
			{"x": 0.88, "w": 0.06, "h": 0.14},
		]

		for i in 16:
			_diyas.append({
				"x": _rng.randf(),
				"depth": _rng.randf_range(0.05, 0.42),   # 0 shore .. 1 near bottom
				"spd": _rng.randf_range(0.006, 0.02),
				"ph": _rng.randf() * TAU,
				"sz": _rng.randf_range(0.75, 1.6),
			})
		for i in 36:
			_embers.append({
				"x": _rng.randf(),
				"y": _rng.randf() * HORIZON,
				"spd": _rng.randf_range(0.01, 0.035),
				"ph": _rng.randf() * TAU,
				"sz": _rng.randf_range(1.0, 2.6),
			})

	func _process(delta: float) -> void:
		_t += delta
		for d in _diyas:
			d.x += d.spd * delta
			if d.x > 1.06:
				d.x -= 1.12
		for e in _embers:
			e.y -= e.spd * delta
			if e.y < -0.02:
				e.y = HORIZON
				e.x = _rng.randf()
		queue_redraw()

	func _draw() -> void:
		var s := size
		var hy := HORIZON * s.y
		_draw_embers(s, hy)
		_draw_skyline(s, hy)
		_draw_diyas(s, hy)

	func _draw_skyline(s: Vector2, hy: float) -> void:
		# Dark shore band seating everything and hiding the shader seam.
		draw_rect(Rect2(0, hy - 1.0, s.x, 6.0), SIL)
		for tp in _temples:
			_draw_temple(tp.x * s.x, hy, tp.w * s.x, tp.h * s.y)
		# Ghat steps stepping down to the water on the left foreground.
		for i in 5:
			var w := s.x * (0.30 - i * 0.03)
			var y := hy + i * 5.0
			draw_rect(Rect2(0, y, w, 5.0), SIL.lerp(Color(0.02, 0.015, 0.03), 0.4))

	func _draw_temple(cx: float, by: float, w: float, h: float) -> void:
		var hw := w * 0.5
		# Curved shikhara silhouette.
		var pts := PackedVector2Array([
			Vector2(cx - hw, by),
			Vector2(cx - hw * 0.7, by - h * 0.5),
			Vector2(cx - hw * 0.24, by - h * 0.85),
			Vector2(cx, by - h),
			Vector2(cx + hw * 0.24, by - h * 0.85),
			Vector2(cx + hw * 0.7, by - h * 0.5),
			Vector2(cx + hw, by),
		])
		draw_colored_polygon(pts, SIL)
		# Warm backlit rim catching the sunset.
		draw_polyline(pts, SIL_RIM, 1.5, true)
		# Kalasha finial + a faint glow at the tip.
		draw_circle(Vector2(cx, by - h - 3.0), 2.5, SIL_RIM)
		draw_circle(Vector2(cx, by - h - 3.0), 7.0, Color(1.0, 0.6, 0.25, 0.12))

	func _draw_diyas(s: Vector2, hy: float) -> void:
		var river_h := s.y - hy
		for d in _diyas:
			var dx: float = d.x
			var depth: float = d.depth
			var ph: float = d.ph
			var sz: float = d.sz
			var px := dx * s.x
			var bob := sin(_t * 1.6 + ph) * 2.0
			var py := hy + depth * river_h * 0.7 + bob + 6.0
			var flick := 0.85 + 0.15 * sin(_t * 9.0 + ph)
			var r := (5.0 + depth * 10.0) * sz           # nearer diyas (deeper) read bigger
			# Reflection streak on the water below the diya.
			draw_line(Vector2(px, py + r * 0.5), Vector2(px, py + r * 2.6),
				Color(GLOW.r, GLOW.g, GLOW.b, 0.18 * flick), 2.0)
			# Layered warm glow.
			draw_circle(Vector2(px, py), r * 2.6, Color(GLOW.r, GLOW.g, GLOW.b, 0.10 * flick))
			draw_circle(Vector2(px, py), r * 1.5, Color(GLOW.r, GLOW.g, GLOW.b, 0.20 * flick))
			draw_circle(Vector2(px, py), r * 0.9, Color(FLAME.r, FLAME.g, FLAME.b, 0.55 * flick))
			# Bright core + little flame tip.
			draw_circle(Vector2(px, py), r * 0.42, Color(CORE.r, CORE.g, CORE.b, flick))
			var flame := PackedVector2Array([
				Vector2(px - r * 0.22, py - r * 0.1),
				Vector2(px, py - r * (0.9 + 0.2 * sin(_t * 11.0 + ph))),
				Vector2(px + r * 0.22, py - r * 0.1),
			])
			draw_colored_polygon(flame, Color(FLAME.r, FLAME.g, FLAME.b, 0.85 * flick))

	func _draw_embers(s: Vector2, hy: float) -> void:
		for e in _embers:
			var ex: float = e.x
			var ey: float = e.y
			var ph: float = e.ph
			var esz: float = e.sz
			var px := ex * s.x
			var py := ey * s.y
			var tw := 0.4 + 0.6 * (0.5 + 0.5 * sin(_t * 4.0 + ph))
			var fade := clampf(ey / HORIZON, 0.0, 1.0)   # brighter near the ghats, fading upward
			draw_circle(Vector2(px, py), esz, Color(1.0, 0.66, 0.3, 0.5 * tw * fade))
