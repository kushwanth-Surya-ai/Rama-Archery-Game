extends SceneTree
## Drives the defeat sequence: loads Main, drains the tower health, lets the
## collapse + Hanuman rescue play, and screenshots mid-flight to verify no
## runtime errors and that Hanuman carries Rama.
func _init():
	var ps = load("res://scenes/Main.tscn")
	var main = ps.instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	# Drain the tower to trigger _lose_sequence().
	for i in 5:
		await create_timer(0.25).timeout
		if main.has_method("_on_tower_attacked"):
			main._on_tower_attacked(30.0)
	print("LOSE TEST: tower drained, sequence running")
	# Let the rescue choreography play, capture mid-flight.
	await create_timer(3.2).timeout
	await RenderingServer.frame_post_draw
	var img = get_root().get_texture().get_image()
	img.save_png("/tmp/lose_test.png")
	print("LOSE TEST: saved /tmp/lose_test.png")
	await create_timer(2.5).timeout
	print("LOSE TEST DONE")
	quit()
