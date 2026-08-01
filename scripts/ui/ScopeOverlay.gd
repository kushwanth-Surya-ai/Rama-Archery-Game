extends Control
## Bow-sight overlay. Drawn full-screen ONLY while the aim scope is active
## (InputRouter.scope): darkens the screen outside a central circular lens, then
## draws a compound-bow pin sight — a round pin-guard housing, a stack of glowing
## fiber-optic pins on a faint vertical guide, and a bubble level — so the zoomed
## view reads as looking through an archer's sight, NOT a rifle scope.
## Aiming/shooting is unchanged — the existing cursor reticle still marks the shot.

const VIGNETTE := Color(0.0, 0.0, 0.0, 0.93)
const RING := Color(0.04, 0.03, 0.02, 1.0)
const HOUSING := Color(0.5, 0.4, 0.2, 0.7)   # inner metallic highlight of the pin guard
const GUIDE := Color(0.85, 0.8, 0.55, 0.32)  # faint central fiber the pins hang on
# Fiber-optic sight pins, top (near range) to bottom (far range).
const PINS := [
	Color(0.30, 1.0, 0.35, 1.0),   # green
	Color(1.0, 0.25, 0.25, 1.0),   # red
	Color(1.0, 0.85, 0.15, 1.0),   # yellow
	Color(1.0, 0.55, 0.10, 1.0),   # orange
]
const PIN_OFFSETS := [-0.10, 0.04, 0.17, 0.30]   # fraction of lens radius, stacked downward

var _on := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 60   # above the reticle (z 50) so the lens framing sits on top


func _process(_delta: float) -> void:
	var want := InputRouter.scope
	if want != _on:
		_on = want
		queue_redraw()


func _draw() -> void:
	if not _on:
		return
	var vp := get_viewport_rect().size
	var c := vp * 0.5
	var r: float = min(vp.x, vp.y) * 0.42      # lens radius

	# Darken everything OUTSIDE the lens with an annulus of triangles fanning from
	# the lens edge (radius r) out past the screen corners (radius big).
	var segs := 96
	var big: float = vp.length()
	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var quad := PackedVector2Array([
			c + d0 * r, c + d1 * r, c + d1 * big, c + d0 * big])
		draw_colored_polygon(quad, VIGNETTE)

	# Round pin-guard housing (thick rim) + thin inner highlight.
	draw_arc(c, r, 0.0, TAU, segs, RING, 14.0, true)
	draw_arc(c, r - 7.0, 0.0, TAU, segs, HOUSING, 1.5, true)

	# Faint vertical fiber the pins hang on — NO rifle crosshair, no mil-dots.
	draw_line(c + Vector2(0, -r + 16), c + Vector2(0, r - 16), GUIDE, 1.0)

	# Stacked fiber-optic sight pins: a short arm + a glowing dot on the guide,
	# top (near) to bottom (far) — the signature compound-bow sight picture.
	for i in range(PINS.size()):
		var col: Color = PINS[i]
		var p := c + Vector2(0, PIN_OFFSETS[i] * r)
		draw_line(p + Vector2(-14, 0), p + Vector2(14, 0), Color(col.r, col.g, col.b, 0.5), 1.0)
		draw_circle(p, 4.5, Color(col.r, col.g, col.b, 0.28))   # soft halo
		draw_circle(p, 2.2, col)                                 # bright core
		draw_circle(p, 0.9, Color(1, 1, 1, 0.9))                 # hot centre

	# Bubble level near the bottom of the housing — a cue unique to bow sights.
	var lb := c + Vector2(0, r * 0.62)
	draw_line(lb + Vector2(-16, 0), lb + Vector2(16, 0), HOUSING, 1.0)
	draw_arc(lb, 6.0, 0.0, TAU, 24, HOUSING, 1.0, true)
	draw_circle(lb, 2.5, Color(0.3, 1.0, 0.5, 0.85))   # centred bubble
