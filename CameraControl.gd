extends Spatial

export var speed = 1.0

# Intern variables.
var dir = Vector3(0.0, 0.0, 0.0)

var camera
var camera_holder

# May need to adjust depending on mouse sensitivity
const MOUSE_SENSITIVITY = 0.10
const MAX_SLOPE_ANGLE = 40      # Steepest angle we can climb


func _ready():
	camera = $CameraMount/Camera
	camera_holder = $CameraMount
	
	set_physics_process(true)

	# Keep the mouse in the current window
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	set_process_input(true)

func _physics_process(delta):
	# Intended direction of movement
	var dir = Vector3()
	# Global camera transform
	var cam_xform = camera.get_global_transform()

	# Check the directional input and
	# get the direction orientated to the camera in the global coords
	# NB: The camera's Z axis faces backwards to the player
	if Input.is_action_pressed("forward"):
		dir += -cam_xform.basis.z.normalized()
	if Input.is_action_pressed("backward"):
		dir += cam_xform.basis.z.normalized()
	if Input.is_action_pressed("left"):
		dir += -cam_xform.basis.x.normalized()
	if Input.is_action_pressed("right"):
		dir += cam_xform.basis.x.normalized()
	
	dir.y = 0
	dir = dir.normalized()

	move_and_slide(dir, Vector3(0,1,0), 0.05, 4, deg2rad(MAX_SLOPE_ANGLE))

	dir = Vector3()

	if Input.is_action_pressed("down"):
		dir.y -= 1.0
	if Input.is_action_pressed("up"):
		dir.y += 1.0
	
	translate(dir * speed * delta)


func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if event is InputEventMouseMotion && Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Rotate camera holder on the X plane given changes to the Y mouse position (Vertical)
		camera_holder.rotate_x(deg2rad(event.relative.y * MOUSE_SENSITIVITY * -1))
		# Rotate camera on the Y plane given changes to the X mouse position (Horizontal)
		self.rotate_y(deg2rad(event.relative.x * MOUSE_SENSITIVITY * -1))

		# Clamp the vertical look to +- 70 because we don't do back flips or tumbles
		var camera_rot = camera_holder.rotation_degrees
		camera_rot.x = clamp(camera_rot.x, -70, 70)
		camera_holder.rotation_degrees = camera_rot