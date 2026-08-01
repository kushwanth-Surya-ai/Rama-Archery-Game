extends Camera3D
## First-person scope camera. Mounted on AimPitch, so it looks straight down the
## aim direction (the muzzle's -Z, where the arrow flies). It becomes the active
## camera ONLY while the scope is engaged (InputRouter.scope), showing what is in
## FRONT of Rama (the giant/target) instead of the third-person view of Rama.
## When the scope drops, control is handed back to the gameplay camera.

var game_cam: Camera3D            # the third-person gameplay camera to restore


func _process(_delta: float) -> void:
	if InputRouter.scope:
		if not current:
			current = true
	elif current:
		# We were scoping and just stopped — hand the view back to gameplay.
		if game_cam:
			game_cam.current = true
