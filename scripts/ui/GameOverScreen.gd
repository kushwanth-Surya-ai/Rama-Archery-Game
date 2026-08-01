extends Control
## Defeat overlay. Hidden until Rama's tower collapses and Hanuman carries him
## away, then fades in a dimmed backdrop with a "GAME OVER" card and a "Try
## Again" button that reloads the scene. Mirrors WinScreen.gd (red theme).

const RED := Color(0.92, 0.32, 0.22)
const TEXT := Color(0.95, 0.92, 0.85)

const CARD_SIZE := Vector2(560, 360)

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
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_card = PanelContainer.new()
	_card.size = CARD_SIZE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.04, 0.03, 0.93)
	sb.border_color = RED
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
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", RED)
	title.add_theme_color_override("font_outline_color", Color(0.2, 0.04, 0.0))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_font_size_override("font_size", 84)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "The tower fell. Hanuman bore Rama to safety."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", TEXT)
	subtitle.add_theme_font_size_override("font_size", 24)
	box.add_child(subtitle)

	var btn := Button.new()
	btn.text = "Try Again"
	btn.custom_minimum_size = Vector2(240, 64)
	btn.add_theme_font_size_override("font_size", 28)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.20, 0.07, 0.05, 0.95)
	bsb.border_color = RED
	bsb.set_border_width_all(2)
	bsb.set_corner_radius_all(6)
	bsb.content_margin_left = 18
	bsb.content_margin_right = 18
	bsb.content_margin_top = 10
	bsb.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", bsb)
	var bsb_hover := bsb.duplicate()
	bsb_hover.bg_color = Color(0.30, 0.11, 0.07, 0.98)
	btn.add_theme_stylebox_override("hover", bsb_hover)
	btn.add_theme_stylebox_override("pressed", bsb_hover)
	btn.add_theme_color_override("font_color", RED)
	btn.pressed.connect(_on_try_again)

	var btn_wrap := CenterContainer.new()
	btn_wrap.add_child(btn)
	box.add_child(btn_wrap)

	_card.modulate = Color(1, 1, 1, 0)


func _layout() -> void:
	if _card == null:
		return
	var vp := get_viewport_rect().size
	_card.position = (vp - CARD_SIZE) * 0.5
	_card.size = CARD_SIZE


## Reveal the overlay. Call after the rescue flight begins.
func show_game_over() -> void:
	if visible:
		return
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_dim, "color:a", 0.6, 0.6)
	t.tween_property(_card, "modulate:a", 1.0, 0.6).set_delay(0.15)


func _on_try_again() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
