extends Control
## Victory overlay. Hidden until the Giant dies, then fades in a dimmed backdrop
## with a centered card holding a "YOU WIN" banner and a "Play Again" button
## that reloads the scene. Centering is done in _layout() from the viewport size
## (re-run on resize) so the card never drifts, matching the HUD's approach.

const GOLD := Color(0.95, 0.8, 0.4)
const TEXT := Color(0.95, 0.92, 0.85)

const CARD_SIZE := Vector2(680, 380)

var _dim: ColorRect
var _card: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow gameplay input
	add_child(_dim)

	# Centered card.
	_card = PanelContainer.new()
	_card.size = CARD_SIZE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.04, 0.99)   # opaque so the bright victory cinematic can't wash out the text
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 36
	sb.content_margin_bottom = 36
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	_card.add_theme_stylebox_override("panel", sb)
	add_child(_card)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	_card.add_child(box)

	var title := Label.new()
	title.text = "VILLAGE RESCUED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.0))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_font_size_override("font_size", 60)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "The demons are slain — Rama has saved\nthe villagers. Victory!"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", TEXT)
	subtitle.add_theme_font_size_override("font_size", 24)
	box.add_child(subtitle)

	var btn := Button.new()
	btn.text = "Play Again"
	btn.custom_minimum_size = Vector2(240, 64)
	btn.add_theme_font_size_override("font_size", 28)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.18, 0.13, 0.06, 0.95)
	bsb.border_color = GOLD
	bsb.set_border_width_all(2)
	bsb.set_corner_radius_all(6)
	bsb.content_margin_left = 18
	bsb.content_margin_right = 18
	bsb.content_margin_top = 10
	bsb.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", bsb)
	var bsb_hover := bsb.duplicate()
	bsb_hover.bg_color = Color(0.28, 0.2, 0.09, 0.98)
	btn.add_theme_stylebox_override("hover", bsb_hover)
	btn.add_theme_stylebox_override("pressed", bsb_hover)
	btn.add_theme_color_override("font_color", GOLD)
	btn.pressed.connect(_on_play_again)

	var btn_wrap := CenterContainer.new()
	btn_wrap.add_child(btn)
	box.add_child(btn_wrap)

	# Start hidden; faded in by show_victory().
	_card.modulate = Color(1, 1, 1, 0)


## Center the card on the current viewport.
func _layout() -> void:
	if _card == null:
		return
	var vp := get_viewport_rect().size
	_card.position = (vp - CARD_SIZE) * 0.5
	_card.size = CARD_SIZE


## Reveal the overlay. Call after the Giant's death animation begins.
func show_victory() -> void:
	if visible:
		return
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_dim, "color:a", 0.72, 0.6)
	t.tween_property(_card, "modulate:a", 1.0, 0.6).set_delay(0.15)


func _on_play_again() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
